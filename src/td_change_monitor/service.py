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
    """state/state.jsonから復元した再実行制御情報を保持する。"""
    last_successful_run_at: datetime
    audit_query_from: datetime
    audit_query_to: datetime
    processed_audit_event_ids: dict[str, datetime]
    processed_aggregated_change_ids: dict[str, datetime]
    backlog_issues: dict[str, str]
    table_ids: dict[str, str]


class TreasureDataClientProtocol(Protocol):
    """Serviceが必要とするTDクライアントの契約を表す。"""

    async def fetch_audit_events(self, window: TimeWindow) -> list[AuditEvent]:
        """引数の時間範囲からAuditイベント一覧を取得して返す。"""
        ...

    async def fetch_table_snapshot(self, database: str, table: str) -> TableSnapshot:
        """引数のdatabaseとtableから現在snapshotを取得して返す。"""
        ...


class RepositoryProtocol(Protocol):
    """Serviceが必要とするローカルGit repositoryの契約を表す。"""

    async def prepare(self, *, push_pending: bool) -> None:
        """引数に従ってrepositoryを同期し、戻り値は返さない。"""
        ...

    async def read_text(self, path: str) -> str | None:
        """引数の相対パスを読み、内容またはNoneを返す。"""
        ...

    async def commit_files(self, *, changes: list[FileChange], message: str) -> str:
        """引数の変更を1commitでpushし、commit SHAを返す。"""
        ...


class BacklogClientProtocol(Protocol):
    """Serviceが必要とするBacklogクライアントの契約を表す。"""

    async def ensure_issue(self, *, change_id: str, summary: str, description: str) -> str:
        """引数の変更IDで課題を保証し、課題キーを返す。"""
        ...


class ChangeMonitorService:
    """Audit取得からBacklog・Git反映までの業務フローを統括する。"""

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
        """設定と外部依存を受け取り監視サービスを初期化する。

        引数:
            settings: 時刻、上限、接続先などの全体設定。
            target_tables: 監視対象tableの許可リスト。
            treasure_data: Auditと現在schemaを取得するクライアント。
            repository: state・snapshot読取とGit書き込みを行うクライアント。
            backlog: 重複防止付き課題作成クライアント。
            now_provider: テスト時に現在時刻を固定する任意関数。
        戻り値:
            なし。
        """
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
        """実行モードに応じてbootstrapまたは通常監視を1回実行する。

        引数:
            dry_run: 外部への書き込みを行わず判定だけ実施するかどうか。
            bootstrap: 初回snapshot作成モードかどうか。
            bootstrap_state_end_at: 初回stateへ設定する監視開始時刻。
        戻り値:
            RunSummaryをJSON化可能な辞書へ変換した実行結果。
        """
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
        """stateの続きから日次Auditを処理し、必要な成果物を反映する。

        引数:
            run_id: 今回実行を識別する一意なID。
            dry_run: Backlog・Git・stateへの書き込みを無効にするかどうか。
        戻り値:
            対象数、差分数、課題数、予定ファイル数を含むRunSummary。
        """
        # stateの終端とlagから今回処理可能な範囲を求め、未確定時間は次回へ残す。
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

        # overlap分を再取得した後、state内のAudit IDで処理済みイベントを除外する。
        fetched_events = await self._td.fetch_audit_events(fetch_window)
        events = [
            event
            for event in fetched_events
            if event.event_id not in state.processed_audit_event_ids
        ]
        groups, unresolved = group_events_by_table(events)
        # 1件でもtableを特定できない場合は取りこぼしを避けるためstateを進めない。
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
        # ここでは次のstate内容をメモリ上だけで作り、Backlogとpush成功まで確定しない。
        processed_audit_event_ids = dict(state.processed_audit_event_ids)
        processed_audit_event_ids.update({event.event_id: event.occurred_at for event in events})
        processed_aggregated_change_ids = dict(state.processed_aggregated_change_ids)
        processed_aggregated_change_ids.update(
            {change.change_id: group_time(change.events) for change in changes}
        )
        backlog_issues = dict(state.backlog_issues)
        table_ids = _updated_table_ids(state.table_ids, changes)

        if dry_run:
            # dry-runでは判定根拠をログへ出すが、課題作成とrepository書き込みは行わない。
            for change in changes:
                logger.info(
                    "td_change_monitor_dry_run_change",
                    extra={"dry_run_change": _dry_run_change_dict(change)},
                )
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
        # 同一change_idの課題キーがstateにあればBacklog APIを呼ばず重複作成を防ぐ。
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
        """監視対象全tableの現在schemaと任意の初期stateを作る。

        引数:
            run_id: 今回実行を識別する一意なID。
            dry_run: Gitへ書き込まず予定だけ返すかどうか。
            state_end_at: 初回stateへ保存する監視開始時刻。
        戻り値:
            bootstrap対象数と予定ファイル数を含むRunSummary。
        """
        targets = self._target_tables.bootstrap_targets()
        if not targets:
            raise ChangeMonitorError(
                "bootstrap requires explicit tables in config/target_tables.yml"
            )

        changes: list[FileChange] = []
        bootstrap_table_ids: dict[str, str] = {}
        missing_targets: list[str] = []
        for database, table in targets:
            try:
                snapshot = await self._td.fetch_table_snapshot(database, table)
            except ExternalApiError as exc:
                if exc.status_code == 404:
                    missing_targets.append(f"{database}.{table}")
                    continue
                raise
            if snapshot.table_id:
                bootstrap_table_ids[f"{database}.{table}"] = snapshot.table_id
            changes.append(
                FileChange(
                    path=_schema_path(database, table),
                    content=snapshot_to_json_bytes(snapshot),
                )
            )

        if missing_targets:
            raise ChangeMonitorError(
                "bootstrap target tables were not found in Treasure Data: "
                f"count={len(missing_targets)}; tables={','.join(missing_targets)}"
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
        """1論理テーブルの前回状態と現在状態から最終変更を判定する。

        引数:
            group: resource IDとrename前後名で集約済みのEventGroup。
        戻り値:
            Git証跡を残す変更ならDetectedChange、実差分がなければNone。
        """
        is_rename = group.previous_table is not None and group.previous_table != group.table
        before_table = group.previous_table or group.table
        before = await self._read_snapshot(_schema_path(group.database, before_table))
        effective_previous_table = group.previous_table
        if is_rename and before is None:
            # 一時tableを本tableへ置換する定常処理では旧一時名のsnapshotがない。
            # この場合は既存の本table snapshotを変更前状態として誤rename通知を防ぐ。
            current_name_before = await self._read_snapshot(
                _schema_path(group.database, group.table)
            )
            if current_name_before is not None:
                before = current_name_before
                is_rename = False
                effective_previous_table = None
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
            is_rename=is_rename,
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
            previous_table=effective_previous_table,
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
        """検出変更と次stateからGitへ反映するファイル変更一覧を作る。

        引数:
            run_id: 今回実行のID。
            window: 今回取得したAudit検索範囲。
            changes: Git証跡を残す検出変更一覧。
            processed_audit_event_ids: 更新後の処理済みAudit ID対応表。
            processed_aggregated_change_ids: 更新後の処理済み変更ID対応表。
            backlog_issues: 更新後の変更IDとBacklog課題キー対応表。
            table_ids: 更新後のtable完全修飾名とTD ID対応表。
            last_successful_run_at: 今回の正常終了候補時刻。
            audit_query_to: 今回処理済みとするAudit終端時刻。
        戻り値:
            schema、diff、Audit証跡、stateのFileChange一覧。
        """
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
        """単一stateファイルを読み込み、型付き実行状態へ変換する。

        引数:
            なし。
        戻り値:
            UTC時刻と各対応表を持つ_RunState。
        """
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
        """Git作業ツリーから前回snapshotを読み込む。

        引数:
            path: repositoryルート基準のsnapshot相対パス。
        戻り値:
            復元したTableSnapshot。ファイルがなければNone。
        """
        text = await self._repository.read_text(path)
        if text is None:
            return None
        payload = json.loads(text)
        if not isinstance(payload, Mapping):
            raise ChangeMonitorError(f"snapshot {path} must be a JSON object")
        return snapshot_from_mapping(payload)

    async def _fetch_snapshot_or_none(self, database: str, table: str) -> TableSnapshot | None:
        """現在snapshotを取得し、Table APIの404だけを削除状態へ変換する。

        引数:
            database: 取得対象database名。
            table: 取得対象table名。
        戻り値:
            現在のTableSnapshot。404ならNone。
        """
        try:
            return await self._td.fetch_table_snapshot(database, table)
        except ExternalApiError as exc:
            if exc.status_code == 404:
                return None
            raise

    def _github_blob_url(self, path: str) -> str:
        """GitHub上の成果物をBacklogから参照するblob URLを作る。

        引数:
            path: repository内の成果物相対パス。
        戻り値:
            設定repository URLとbranchを連結したURL。
        """
        return (
            f"{self._settings.github_repository_url.rstrip('/')}"
            f"/blob/{self._settings.git_branch}/{path}"
        )


def _should_issue(change_kind: ChangeKind, diff: SchemaDiff) -> bool:
    """変更種別と重要schema差分からBacklog課題が必要か判定する。

    引数:
        change_kind: 論理テーブルの最終変更種別。
        diff: 前回状態と現在状態のNet Diff。
    戻り値:
        課題作成対象ならTrue。
    """
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
    """変更をGit証跡として記録する必要があるか判定する。

    引数:
        change_kind: 論理テーブルの最終変更種別。
        diff: 前回状態と現在状態のNet Diff。
    戻り値:
        diff・Audit成果物を残す変更ならTrue。
    """
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
    """イベント、Net Diff、table ID、存在状態から最終変更種別を決める。

    引数:
        event_type_set: 集約イベントに含まれる操作種別集合。
        diff: 前回状態と現在状態のschema差分。
        table_id_changed: TDの物理table IDが変わったかどうか。
        is_rename: 監視対象の論理名が変わったかどうか。
        after_exists: 現在もtableが存在するかどうか。
    戻り値:
        優先順位に従って決定したChangeKind。
    """
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
    """snapshot IDまたはdelete/createイベントから物理table再作成を判定する。

    引数:
        before: 変更前snapshot。
        after: 変更後snapshot。
        events: 判定対象の集約Auditイベント列。
    戻り値:
        異なる物理tableへ置き換わったと判断できればTrue。
    """
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
    """現在schemaを保存するrepository相対パスを作る。

    引数:
        database: 対象database名。
        table: 対象table名。
    戻り値:
        `schemas/current/{database}/{table}.json`形式のパス。
    """
    return f"schemas/current/{database}/{table}.json"


def _diff_path(at: datetime, database: str, table: str, change_id: str) -> str:
    """人向け差分Markdownのrepository相対パスを作る。

    引数:
        at: 最終イベントのUTC時刻。
        database: 対象database名。
        table: 対象table名。
        change_id: 集約変更ID。
    戻り値:
        UTC日付で階層化したdiffパス。
    """
    return f"diffs/{at:%Y/%m/%d}/{database}.{table}_{change_id}.md"


def _audit_events_path(at: datetime, database: str, table: str, change_id: str) -> str:
    """最小Audit証跡JSONのrepository相対パスを作る。

    引数:
        at: 最終イベントのUTC時刻。
        database: 対象database名。
        table: 対象table名。
        change_id: 集約変更ID。
    戻り値:
        UTC日付で階層化したAudit証跡パス。
    """
    return f"audit_events/{at:%Y/%m/%d}/{database}.{table}_{change_id}.json"


def _json_bytes(payload: Mapping[str, Any]) -> bytes:
    """辞書を決定的な整形済みUTF-8 JSONへ変換する。

    引数:
        payload: JSON保存するマッピング。
    戻り値:
        キー順を固定したJSONバイト列。
    """
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8")


def _audit_event_dict(event: AuditEvent) -> dict[str, object]:
    """Auditイベントを保存用の証跡辞書へ変換する。

    引数:
        event: 証跡へ保存するAuditイベント。
    戻り値:
        None項目を除去し、schema値をhash化した辞書。
    """
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
    """SchemaDiffをAudit成果物へ保存できる辞書へ変換する。

    引数:
        diff: 変換対象のschema差分。
    戻り値:
        項目別のカラム名と変更前後値を持つ辞書。
    """
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


def _dry_run_change_dict(change: DetectedChange) -> dict[str, object]:
    """dry-run検証用に変更判定の要点だけをログ辞書へ変換する。

    引数:
        change: ログへ出す検出変更。
    戻り値:
        table名、種別、課題候補、差分列名を含む辞書。
    """
    return {
        "database": change.database,
        "table": change.table,
        "previous_table": change.previous_table,
        "change_kind": change.change_kind.value,
        "backlog_candidate": change.should_create_issue,
        "table_id_changed": change.table_id_changed,
        "change_id": change.change_id,
        "audit_event_count": len(change.events),
        "event_types": [event_type.value for event_type in change.event_types],
        "added_columns": [column.name for column in change.diff.added],
        "removed_columns": [column.name for column in change.diff.removed],
        "type_changes": [
            {"column": name, "before": before, "after": after}
            for name, before, after in change.diff.type_changed
        ],
        "alias_changed_columns": [name for name, _, _ in change.diff.alias_changed],
        "description_changed_columns": [
            name for name, _, _ in change.diff.description_changed
        ],
        "order_changed_columns": [name for name, _, _ in change.diff.order_changed],
    }


def group_time(events: tuple[AuditEvent, ...]) -> datetime:
    """集約イベント集合の最終発生時刻を返す。

    引数:
        events: 1件以上のAuditイベント列。
    戻り値:
        occurred_atが最も新しいdatetime。
    """
    return max(event.occurred_at for event in events)


def _git_file_change_count(changes: list[DetectedChange]) -> int:
    """今回stage対象となる一意なファイルパス数を見積もる。

    引数:
        changes: Git証跡を残す検出変更一覧。
    戻り値:
        stateを含む一意な生成・削除対象パス数。
    """
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
    """検出変更を反映した最新table ID対応表を作る。

    引数:
        current: stateに保存されている現在のID対応表。
        changes: 今回検出した変更一覧。
    戻り値:
        rename・削除・再作成を反映した新しい対応表。
    """
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
    """保持期限より古い処理済みIDを対応表から除去する。

    引数:
        values: IDと発生UTC時刻の対応表。
        cutoff: 保持対象とする最古時刻。
    戻り値:
        cutoff以降の項目だけを持つ新しい辞書。
    """
    return {key: value for key, value in values.items() if value >= cutoff}


def _state_datetime(payload: Mapping[str, Any], key: str) -> datetime:
    """stateの指定項目をタイムゾーン付きUTCへ変換する。

    引数:
        payload: state JSONを解析したマッピング。
        key: 取得する時刻項目名。
    戻り値:
        UTCへ正規化したdatetime。
    """
    value = payload.get(key)
    if not isinstance(value, str):
        raise ChangeMonitorError(f"state field {key} must be an ISO timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _state_timestamp_map(payload: Mapping[str, Any], key: str) -> dict[str, datetime]:
    """stateのID・時刻対応表を型検証して復元する。

    引数:
        payload: state JSONを解析したマッピング。
        key: 取得する対応表の項目名。
    戻り値:
        文字列IDとUTC datetimeの辞書。
    """
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
    """stateの文字列対応表を型検証して復元する。

    引数:
        payload: state JSONを解析したマッピング。
        key: 取得する対応表の項目名。
    戻り値:
        文字列キーと文字列値の辞書。
    """
    value = payload.get(key, {})
    if not isinstance(value, Mapping):
        raise ChangeMonitorError(f"state field {key} must be an object")
    if not all(
        isinstance(item_key, str) and isinstance(item, str) for item_key, item in value.items()
    ):
        raise ChangeMonitorError(f"state field {key} must map strings to strings")
    return {str(item_key): str(item) for item_key, item in value.items()}


def _text_hash(value: str | None) -> str | None:
    """保存禁止のschema本文をSHA-256へ置き換える。

    引数:
        value: hash化する文字列。値がなければNone。
    戻り値:
        SHA-256文字列。入力がNoneならNone。
    """
    if value is None:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
