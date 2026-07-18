from __future__ import annotations

import hashlib
import json
import logging
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from td_change_monitor.audit import EventGroup, group_events_by_table
from td_change_monitor.change_id import build_change_id
from td_change_monitor.clients.local_git import FileChange
from td_change_monitor.config import Settings, TargetTablesConfig
from td_change_monitor.diff import (
    diff_created,
    diff_deleted,
    diff_snapshots,
    snapshot_from_mapping,
    snapshot_to_json_bytes,
)
from td_change_monitor.errors import (
    ChangeMonitorError,
    ExternalApiError,
    UnresolvedAuditEventsError,
)
from td_change_monitor.models import (
    AuditEvent,
    ChangeKind,
    DetectedChange,
    EventType,
    RunSummary,
    SchemaDiff,
    TableSnapshot,
)
from td_change_monitor.rendering import (
    render_diff_markdown,
    render_issue_description,
    render_issue_summary,
)
from td_change_monitor.time_window import TimeWindow, build_optional_time_window

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class _RunState:
    last_successful_run_at: datetime
    audit_query_from: datetime
    audit_query_to: datetime
    processed_audit_event_ids: dict[str, datetime]
    processed_aggregated_change_ids: dict[str, datetime]
    backlog_issues: dict[str, str]
    table_ids: dict[str, str]


class TreasureDataClientProtocol(Protocol):
    async def fetch_audit_events(self, window: TimeWindow) -> list[AuditEvent]: ...

    async def fetch_table_snapshot(self, database: str, table: str) -> TableSnapshot: ...


class RepositoryProtocol(Protocol):
    async def prepare(self, *, push_pending: bool) -> None: ...

    async def read_text(self, path: str) -> str | None: ...

    async def commit_files(self, *, changes: list[FileChange], message: str) -> str: ...


class BacklogClientProtocol(Protocol):
    async def ensure_issue(self, *, change_id: str, summary: str, description: str) -> str: ...


class ChangeMonitorService:
    def __init__(
        self,
        *,
        settings: Settings,
        target_tables: TargetTablesConfig,
        treasure_data: TreasureDataClientProtocol,
        repository: RepositoryProtocol,
        backlog: BacklogClientProtocol,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._settings = settings
        self._target_tables = target_tables
        self._td = treasure_data
        self._repository = repository
        self._backlog = backlog
        self._now_provider = now_provider or (lambda: datetime.now(UTC))

    async def run(
        self,
        *,
        dry_run: bool = False,
        bootstrap: bool = False,
        bootstrap_state_end_at: datetime | None = None,
    ) -> dict[str, object]:
        run_id = uuid.uuid4().hex
        await self._repository.prepare(push_pending=not dry_run)
        if bootstrap:
            summary = await self._run_bootstrap(
                run_id=run_id,
                dry_run=dry_run,
                state_end_at=bootstrap_state_end_at,
            )
        elif bootstrap_state_end_at is not None:
            raise ChangeMonitorError("--bootstrap-state-end-at can only be used with --bootstrap")
        else:
            summary = await self._run_normal(run_id=run_id, dry_run=dry_run)
        logger.info("td_change_monitor_run_complete", extra={"summary": summary.as_dict()})
        return summary.as_dict()

    async def _run_normal(self, *, run_id: str, dry_run: bool) -> RunSummary:
        state = await self._read_state()
        now = self._now_provider()
        window = build_optional_time_window(
            last_successful_end_at=state.audit_query_to,
            now=now,
            lag_minutes=self._settings.audit_log_lag_minutes,
        )
        if window is None:
            return RunSummary(
                run_id=run_id,
                dry_run=dry_run,
                bootstrap=False,
                target_count=0,
                diff_count=0,
                issue_count=0,
                planned_file_count=0,
            )

        fetch_window = TimeWindow(
            start=window.start - timedelta(minutes=self._settings.audit_log_overlap_minutes),
            end=window.end,
        )

        fetched_events = await self._td.fetch_audit_events(fetch_window)
        events = [
            event
            for event in fetched_events
            if event.event_id not in state.processed_audit_event_ids
        ]
        groups, unresolved = group_events_by_table(events)
        if unresolved:
            raise UnresolvedAuditEventsError(len(unresolved))

        target_groups = tuple(
            group
            for group in groups
            if self._target_tables.includes_any(group.database, *group.table_names)
        )
        if len(target_groups) > self._settings.max_changed_tables_per_run:
            raise ChangeMonitorError(
                "changed table count exceeds MAX_CHANGED_TABLES_PER_RUN: "
                f"{len(target_groups)} > {self._settings.max_changed_tables_per_run}"
            )

        changes = [
            change
            for group in target_groups
            if (change := await self._build_detected_change(group=group)) is not None
        ]
        processed_audit_event_ids = dict(state.processed_audit_event_ids)
        processed_audit_event_ids.update({event.event_id: event.occurred_at for event in events})
        processed_aggregated_change_ids = dict(state.processed_aggregated_change_ids)
        processed_aggregated_change_ids.update(
            {change.change_id: group_time(change.events) for change in changes}
        )
        backlog_issues = dict(state.backlog_issues)
        table_ids = _updated_table_ids(state.table_ids, changes)

        if dry_run:
            planned_files = self._build_run_file_changes(
                run_id=run_id,
                window=fetch_window,
                changes=changes,
                processed_audit_event_ids=processed_audit_event_ids,
                processed_aggregated_change_ids=processed_aggregated_change_ids,
                backlog_issues=backlog_issues,
                table_ids=table_ids,
                last_successful_run_at=now,
                audit_query_to=window.end,
            )
            return RunSummary(
                run_id=run_id,
                dry_run=True,
                bootstrap=False,
                target_count=len(target_groups),
                diff_count=len(changes),
                issue_count=sum(1 for change in changes if change.should_create_issue),
                planned_file_count=len(planned_files),
            )

        issue_count = 0
        for change in changes:
            if not change.should_create_issue:
                continue
            if change.change_id in backlog_issues:
                continue
            issue_key = await self._backlog.ensure_issue(
                change_id=change.change_id,
                summary=render_issue_summary(change),
                description=render_issue_description(
                    change,
                    window_start=window.start,
                    window_end=window.end,
                    display_timezone=self._settings.display_timezone,
                ),
            )
            backlog_issues[change.change_id] = issue_key
            issue_count += 1

        planned_files = self._build_run_file_changes(
            run_id=run_id,
            window=fetch_window,
            changes=changes,
            processed_audit_event_ids=processed_audit_event_ids,
            processed_aggregated_change_ids=processed_aggregated_change_ids,
            backlog_issues=backlog_issues,
            table_ids=table_ids,
            last_successful_run_at=now,
            audit_query_to=window.end,
        )
        commit_sha = await self._repository.commit_files(
            changes=planned_files,
            message=f"Record TD changes for {window.end.isoformat()}",
        )
        return RunSummary(
            run_id=run_id,
            dry_run=False,
            bootstrap=False,
            target_count=len(target_groups),
            diff_count=len(changes),
            issue_count=issue_count,
            planned_file_count=len(planned_files),
            commit_sha=commit_sha,
        )

    async def _run_bootstrap(
        self,
        *,
        run_id: str,
        dry_run: bool,
        state_end_at: datetime | None,
    ) -> RunSummary:
        targets = self._target_tables.bootstrap_targets()
        if not targets:
            raise ChangeMonitorError(
                "bootstrap requires explicit tables in config/target_tables.yml"
            )

        changes: list[FileChange] = []
        bootstrap_table_ids: dict[str, str] = {}
        for database, table in targets:
            snapshot = await self._td.fetch_table_snapshot(database, table)
            if snapshot.table_id:
                bootstrap_table_ids[f"{database}.{table}"] = snapshot.table_id
            changes.append(
                FileChange(
                    path=_schema_path(database, table),
                    content=snapshot_to_json_bytes(snapshot),
                )
            )

        if state_end_at is not None:
            if state_end_at.tzinfo is None:
                raise ChangeMonitorError("--bootstrap-state-end-at must include a timezone")
            state_at = state_end_at.astimezone(UTC)
            changes.append(
                FileChange(
                    path="state/state.json",
                    content=_json_bytes(
                        {
                            "version": 2,
                            "last_successful_run_at": self._now_provider()
                            .astimezone(UTC)
                            .isoformat(),
                            "audit_query_from": state_at.isoformat(),
                            "audit_query_to": state_at.isoformat(),
                            "processed_audit_event_ids": {},
                            "processed_aggregated_change_ids": {},
                            "backlog_issues": {},
                            "table_ids": bootstrap_table_ids,
                        }
                    ),
                )
            )

        if dry_run:
            commit_sha = None
        else:
            commit_sha = await self._repository.commit_files(
                changes=changes,
                message=f"Bootstrap TD schema snapshots {run_id}",
            )

        return RunSummary(
            run_id=run_id,
            dry_run=dry_run,
            bootstrap=True,
            target_count=len(targets),
            diff_count=0,
            issue_count=0,
            planned_file_count=len(changes),
            commit_sha=commit_sha,
        )

    async def _build_detected_change(
        self,
        *,
        group: EventGroup,
    ) -> DetectedChange | None:
        before_table = group.previous_table or group.table
        before = await self._read_snapshot(_schema_path(group.database, before_table))
        event_types = group.event_types
        event_type_set = set(event_types)
        after = await self._fetch_snapshot_or_none(group.database, group.table)
        if after is None:
            diff = diff_deleted(before)
        elif before is None:
            diff = diff_created(after)
        else:
            diff = diff_snapshots(before, after)

        table_id_changed = _table_id_changed(before, after, group.events)
        change_kind = _change_kind(
            event_type_set=event_type_set,
            diff=diff,
            table_id_changed=table_id_changed,
            is_rename=group.previous_table is not None and group.previous_table != group.table,
            after_exists=after is not None,
        )
        if not _should_record_change(change_kind, diff):
            return None
        should_issue = _should_issue(change_kind, diff)

        change_id = build_change_id(
            database=group.database,
            table=group.table,
            audit_event_ids=(event.event_id for event in group.events),
            change_kind=change_kind,
            before=before,
            after=after,
        )
        diff_path = _diff_path(group.events[-1].occurred_at, group.database, group.table, change_id)
        return DetectedChange(
            database=group.database,
            table=group.table,
            previous_table=group.previous_table,
            event_types=event_types,
            events=group.events,
            before=before,
            after=after,
            diff=diff,
            change_kind=change_kind,
            change_id=change_id,
            diff_path=diff_path,
            github_diff_url=self._github_blob_url(diff_path),
            should_create_issue=should_issue,
            table_id_changed=table_id_changed,
        )

    def _build_run_file_changes(
        self,
        *,
        run_id: str,
        window: TimeWindow,
        changes: list[DetectedChange],
        processed_audit_event_ids: dict[str, datetime],
        processed_aggregated_change_ids: dict[str, datetime],
        backlog_issues: dict[str, str],
        table_ids: dict[str, str],
        last_successful_run_at: datetime,
        audit_query_to: datetime,
    ) -> list[FileChange]:
        files: dict[str, bytes | None] = {}
        git_file_change_count = _git_file_change_count(changes)
        backlog_issue_count = sum(1 for change in changes if change.should_create_issue)
        for change in changes:
            files[change.diff_path] = render_diff_markdown(
                change,
                window_start=window.start,
                window_end=window.end,
            ).encode("utf-8")
            audit_events_path = _audit_events_path(
                change.events[-1].occurred_at,
                change.database,
                change.table,
                change.change_id,
            )
            files[audit_events_path] = _json_bytes(
                {
                    "aggregated_change_id": change.change_id,
                    "database": change.database,
                    "table": change.table,
                    "previous_table": change.previous_table,
                    "change_kind": change.change_kind.value,
                    "backlog_issue_key": backlog_issues.get(change.change_id),
                    "run": {
                        "run_id": run_id,
                        "audit_query_from": window.start.isoformat(),
                        "audit_query_to": window.end.isoformat(),
                        "changed_table_count": len(changes),
                        "backlog_issue_count": backlog_issue_count,
                        "git_file_change_count": git_file_change_count,
                    },
                    "net_diff": _diff_dict(change.diff),
                    "events": [_audit_event_dict(event) for event in change.events],
                }
            )
            if change.after is not None:
                files[_schema_path(change.database, change.table)] = snapshot_to_json_bytes(
                    change.after
                )
                if change.previous_table is not None and change.previous_table != change.table:
                    files[_schema_path(change.database, change.previous_table)] = None
            elif change.before is not None:
                files[_schema_path(change.database, change.table)] = None
                if change.previous_table is not None and change.previous_table != change.table:
                    files[_schema_path(change.database, change.previous_table)] = None

        cutoff = audit_query_to - timedelta(days=self._settings.processed_id_retention_days)
        retained_audit_ids = _prune_timestamp_map(processed_audit_event_ids, cutoff)
        retained_change_ids = _prune_timestamp_map(processed_aggregated_change_ids, cutoff)
        retained_backlog_issues = {
            change_id: issue_key
            for change_id, issue_key in backlog_issues.items()
            if change_id in retained_change_ids
        }
        files["state/state.json"] = _json_bytes(
            {
                "version": 2,
                "last_successful_run_at": last_successful_run_at.astimezone(UTC).isoformat(),
                "audit_query_from": window.start.isoformat(),
                "audit_query_to": audit_query_to.isoformat(),
                "processed_audit_event_ids": {
                    event_id: occurred_at.isoformat()
                    for event_id, occurred_at in sorted(retained_audit_ids.items())
                },
                "processed_aggregated_change_ids": {
                    change_id: occurred_at.isoformat()
                    for change_id, occurred_at in sorted(retained_change_ids.items())
                },
                "backlog_issues": retained_backlog_issues,
                "table_ids": table_ids,
            }
        )
        return [FileChange(path=path, content=content) for path, content in sorted(files.items())]

    async def _read_state(self) -> _RunState:
        text = await self._repository.read_text("state/state.json")
        if text is None:
            raise ChangeMonitorError(
                "state/state.json is missing; run bootstrap with --bootstrap-state-end-at"
            )
        payload = json.loads(text)
        if not isinstance(payload, Mapping):
            raise ChangeMonitorError("state/state.json must be a JSON object")
        audit_query_to = _state_datetime(payload, "audit_query_to")
        return _RunState(
            last_successful_run_at=_state_datetime(payload, "last_successful_run_at"),
            audit_query_from=_state_datetime(payload, "audit_query_from"),
            audit_query_to=audit_query_to,
            processed_audit_event_ids=_state_timestamp_map(payload, "processed_audit_event_ids"),
            processed_aggregated_change_ids=_state_timestamp_map(
                payload, "processed_aggregated_change_ids"
            ),
            backlog_issues=_state_string_map(payload, "backlog_issues"),
            table_ids=_state_string_map(payload, "table_ids"),
        )

    async def _read_snapshot(self, path: str) -> TableSnapshot | None:
        text = await self._repository.read_text(path)
        if text is None:
            return None
        payload = json.loads(text)
        if not isinstance(payload, Mapping):
            raise ChangeMonitorError(f"snapshot {path} must be a JSON object")
        return snapshot_from_mapping(payload)

    async def _fetch_snapshot_or_none(self, database: str, table: str) -> TableSnapshot | None:
        try:
            return await self._td.fetch_table_snapshot(database, table)
        except ExternalApiError as exc:
            if exc.status_code == 404:
                return None
            raise

    def _github_blob_url(self, path: str) -> str:
        return (
            f"{self._settings.github_repository_url.rstrip('/')}"
            f"/blob/{self._settings.git_branch}/{path}"
        )


def _should_issue(change_kind: ChangeKind, diff: SchemaDiff) -> bool:
    if change_kind in {
        ChangeKind.TABLE_DELETE,
        ChangeKind.TABLE_RENAME,
        ChangeKind.TABLE_RENAME_SCHEMA_CHANGE,
        ChangeKind.TABLE_RECREATE_SCHEMA_CHANGE,
    }:
        return True
    if change_kind == ChangeKind.SCHEMA_CHANGE:
        return diff.has_important_changes
    return False


def _should_record_change(change_kind: ChangeKind, diff: SchemaDiff) -> bool:
    if change_kind == ChangeKind.AUDIT_ONLY:
        return False
    if change_kind == ChangeKind.SCHEMA_CHANGE:
        return bool(
            diff.added
            or diff.removed
            or diff.type_changed
            or diff.alias_changed
            or diff.order_changed
        )
    return True


def _change_kind(
    *,
    event_type_set: set[EventType],
    diff: SchemaDiff,
    table_id_changed: bool,
    is_rename: bool,
    after_exists: bool,
) -> ChangeKind:
    if not after_exists:
        return ChangeKind.TABLE_DELETE
    if is_rename and diff.has_important_changes:
        return ChangeKind.TABLE_RENAME_SCHEMA_CHANGE
    if is_rename:
        return ChangeKind.TABLE_RENAME
    if table_id_changed and diff.has_important_changes:
        return ChangeKind.TABLE_RECREATE_SCHEMA_CHANGE
    if table_id_changed:
        return ChangeKind.TABLE_RECREATE
    if diff.has_changes:
        return ChangeKind.SCHEMA_CHANGE
    if EventType.TABLE_DELETE in event_type_set or EventType.TABLE_CREATE in event_type_set:
        return ChangeKind.TABLE_RECREATE
    return ChangeKind.AUDIT_ONLY


def _table_id_changed(
    before: TableSnapshot | None,
    after: TableSnapshot | None,
    events: tuple[AuditEvent, ...],
) -> bool:
    if before is not None and after is not None and before.table_id and after.table_id:
        return before.table_id != after.table_id
    resource_ids = {event.resource_id for event in events if event.resource_id}
    event_types = {event.event_type for event in events}
    return (
        EventType.TABLE_DELETE in event_types
        and EventType.TABLE_CREATE in event_types
        and len(resource_ids) > 1
    )


def _schema_path(database: str, table: str) -> str:
    return f"schemas/current/{database}/{table}.json"


def _diff_path(at: datetime, database: str, table: str, change_id: str) -> str:
    return f"diffs/{at:%Y/%m/%d}/{database}.{table}_{change_id}.md"


def _audit_events_path(at: datetime, database: str, table: str, change_id: str) -> str:
    return f"audit_events/{at:%Y/%m/%d}/{database}.{table}_{change_id}.json"


def _json_bytes(payload: Mapping[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8")


def _audit_event_dict(event: AuditEvent) -> dict[str, object]:
    payload: dict[str, object | None] = {
        "id": event.event_id,
        "time": event.occurred_at.isoformat(),
        "event_name": event.event_type.value,
        "event_result": event.event_result,
        "resource_id": event.resource_id,
        "database": event.database,
        "table": event.table,
        "previous_table": event.previous_table,
        "requested_http_verb": event.requested_http_verb,
        "requested_path_info": event.requested_path_info,
        "attribute_name": event.attribute_name,
        "user_email": event.actor,
        "source_user_email": event.source_actor,
        "target_resource_name": event.target_resource_name,
    }
    if event.attribute_name == "schema":
        payload["old_value_sha256"] = _text_hash(event.old_value)
        payload["new_value_sha256"] = _text_hash(event.new_value)
    else:
        payload["old_value"] = event.old_value
        payload["new_value"] = event.new_value
    return {key: value for key, value in payload.items() if value is not None}


def _diff_dict(diff: SchemaDiff) -> dict[str, object]:
    return {
        "added_columns": [column.name for column in diff.added],
        "removed_columns": [column.name for column in diff.removed],
        "type_changes": [
            {"name": name, "before": before, "after": after}
            for name, before, after in diff.type_changed
        ],
        "alias_changes": [
            {"name": name, "before": before, "after": after}
            for name, before, after in diff.alias_changed
        ],
        "description_changes": [
            {"name": name, "before": before, "after": after}
            for name, before, after in diff.description_changed
        ],
        "order_changes": [
            {"name": name, "before": before, "after": after}
            for name, before, after in diff.order_changed
        ],
    }


def group_time(events: tuple[AuditEvent, ...]) -> datetime:
    return max(event.occurred_at for event in events)


def _git_file_change_count(changes: list[DetectedChange]) -> int:
    paths = {"state/state.json"}
    for change in changes:
        paths.add(change.diff_path)
        paths.add(
            _audit_events_path(
                change.events[-1].occurred_at,
                change.database,
                change.table,
                change.change_id,
            )
        )
        paths.add(_schema_path(change.database, change.table))
        if change.previous_table is not None and change.previous_table != change.table:
            paths.add(_schema_path(change.database, change.previous_table))
    return len(paths)


def _updated_table_ids(
    current: dict[str, str],
    changes: list[DetectedChange],
) -> dict[str, str]:
    result = dict(current)
    for change in changes:
        current_key = f"{change.database}.{change.table}"
        if change.previous_table and change.previous_table != change.table:
            result.pop(f"{change.database}.{change.previous_table}", None)
        if change.after is None:
            result.pop(current_key, None)
        elif change.after.table_id:
            result[current_key] = change.after.table_id
    return result


def _prune_timestamp_map(
    values: dict[str, datetime],
    cutoff: datetime,
) -> dict[str, datetime]:
    return {key: value for key, value in values.items() if value >= cutoff}


def _state_datetime(payload: Mapping[str, Any], key: str) -> datetime:
    value = payload.get(key)
    if not isinstance(value, str):
        raise ChangeMonitorError(f"state field {key} must be an ISO timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _state_timestamp_map(payload: Mapping[str, Any], key: str) -> dict[str, datetime]:
    value = payload.get(key, {})
    if not isinstance(value, Mapping):
        raise ChangeMonitorError(f"state field {key} must be an object")
    result: dict[str, datetime] = {}
    for item_id, occurred_at in value.items():
        if not isinstance(item_id, str) or not isinstance(occurred_at, str):
            raise ChangeMonitorError(f"state field {key} must map strings to timestamps")
        parsed = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        result[item_id] = parsed.astimezone(UTC)
    return result


def _state_string_map(payload: Mapping[str, Any], key: str) -> dict[str, str]:
    value = payload.get(key, {})
    if not isinstance(value, Mapping):
        raise ChangeMonitorError(f"state field {key} must be an object")
    if not all(
        isinstance(item_key, str) and isinstance(item, str) for item_key, item in value.items()
    ):
        raise ChangeMonitorError(f"state field {key} must map strings to strings")
    return {str(item_key): str(item) for item_key, item in value.items()}


def _text_hash(value: str | None) -> str | None:
    if value is None:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
