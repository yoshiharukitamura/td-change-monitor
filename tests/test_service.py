from __future__ import annotations

import asyncio
import json
import logging
from datetime import UTC, datetime

import pytest
from conftest import make_settings

from td_change_monitor.clients.local_git import FileChange
from td_change_monitor.config import TargetTablesConfig
from td_change_monitor.errors import (
    ChangeMonitorError,
    ExternalApiError,
    UnresolvedAuditEventsError,
)
from td_change_monitor.models import (
    AuditEvent,
    ColumnDefinition,
    EventType,
    SavedQueryDetectedChange,
    SavedQueryDiff,
    SavedQuerySnapshot,
    TableSnapshot,
)
from td_change_monitor.resource_monitor import ResourceRunPlan
from td_change_monitor.service import (
    ChangeMonitorService,
    ResourceMonitorProtocol,
)
from td_change_monitor.time_window import TimeWindow

STATE_PATH = "state/state.json"
SCHEMA_PATH = "schemas/current/db/table.json"
STATE_AT = "2026-07-13T00:00:00+00:00"


def snapshot(
    *columns: tuple[str, str],
    table: str = "table",
    table_id: str | None = "table-1",
) -> TableSnapshot:
    return TableSnapshot(
        database="db",
        table=table,
        columns=tuple(
            ColumnDefinition(name=name, type=type_, position=index)
            for index, (name, type_) in enumerate(columns)
        ),
        table_id=table_id,
    )


def snapshot_text(
    *columns: tuple[str, str], table: str = "table", table_id: str = "table-1"
) -> str:
    return json.dumps(
        {
            "database": "db",
            "table": table,
            "table_id": table_id,
            "columns": [
                {"name": name, "type": type_, "position": index}
                for index, (name, type_) in enumerate(columns)
            ],
        }
    )


def event(
    event_type: EventType,
    *,
    event_id: str = "audit-1",
    database: str | None = "db",
    table: str | None = "table",
    previous_table: str | None = None,
    resource_id: str | None = "table-1",
    attribute_name: str | None = "schema",
    old_value: str | None = None,
    new_value: str | None = None,
    actor: str | None = "operator@example.com",
    occurred_at: datetime | None = None,
) -> AuditEvent:
    return AuditEvent(
        event_id=event_id,
        event_type=event_type,
        occurred_at=occurred_at or datetime(2026, 7, 13, 0, 30, tzinfo=UTC),
        database=database,
        table=table,
        previous_table=previous_table,
        actor=actor,
        source_actor=None,
        resource_id=resource_id,
        event_result="success",
        requested_http_verb="POST",
        requested_path_info=None,
        attribute_name=attribute_name,
        old_value=old_value,
        new_value=new_value,
        target_resource_name=None,
        raw={"must_not_be_saved": "raw API response"},
    )


def state_text(
    *,
    audit_query_to: str = STATE_AT,
    processed_ids: dict[str, str] | None = None,
    processed_change_ids: dict[str, str] | None = None,
) -> str:
    return json.dumps(
        {
            "version": 2,
            "last_successful_run_at": audit_query_to,
            "audit_query_from": audit_query_to,
            "audit_query_to": audit_query_to,
            "processed_audit_event_ids": processed_ids or {},
            "processed_aggregated_change_ids": processed_change_ids or {},
            "backlog_issues": {},
            "table_ids": {"db.table": "table-1"},
        }
    )


class FakeTreasureData:
    def __init__(
        self,
        *,
        events: list[AuditEvent] | None = None,
        snapshots: dict[tuple[str, str], TableSnapshot] | None = None,
    ) -> None:
        self.events = events or []
        self.snapshots = snapshots or {}
        self.fetches: list[tuple[str, str]] = []
        self.audit_windows: list[TimeWindow] = []

    async def fetch_audit_events(self, window: TimeWindow) -> list[AuditEvent]:
        self.audit_windows.append(window)
        return self.events

    async def fetch_table_snapshot(self, database: str, table: str) -> TableSnapshot:
        self.fetches.append((database, table))
        try:
            return self.snapshots[(database, table)]
        except KeyError as exc:
            raise ExternalApiError("not found", status_code=404) from exc


class FakeRepository:
    def __init__(self, texts: dict[str, str] | None = None) -> None:
        self.texts = texts or {}
        self.commits: list[list[FileChange]] = []
        self.prepare_calls: list[bool] = []

    async def prepare(self, *, push_pending: bool) -> None:
        self.prepare_calls.append(push_pending)

    async def read_text(self, path: str) -> str | None:
        return self.texts.get(path)

    async def commit_files(self, *, changes: list[FileChange], message: str) -> str:
        assert message
        self.commits.append(changes)
        return "commit-sha"


class FakeBacklog:
    def __init__(self) -> None:
        self.issues: list[str] = []
        self.requests: list[dict[str, str]] = []

    async def ensure_issue(self, *, change_id: str, summary: str, description: str) -> str:
        self.issues.append(change_id)
        self.requests.append({"summary": summary, "description": description})
        return "PRJ-1"


class FakeResourceMonitor:
    """固定の追加リソース計画を返すサービス統合テスト用monitor。"""

    def __init__(self, plan: ResourceRunPlan) -> None:
        self.plan_result = plan

    async def plan(
        self,
        *,
        at: datetime,
        window_start: datetime,
        window_end: datetime,
        bootstrap: bool,
        workflow_project_names: dict[str, str],
    ) -> ResourceRunPlan:
        assert at.tzinfo is not None
        assert window_start < window_end
        assert not bootstrap
        assert workflow_project_names == {}
        return self.plan_result


def service(
    *,
    td: FakeTreasureData,
    repository: FakeRepository,
    backlog: FakeBacklog,
    target_tables: TargetTablesConfig | None = None,
    resource_monitor: ResourceMonitorProtocol | None = None,
    **settings_overrides: object,
) -> ChangeMonitorService:
    return ChangeMonitorService(
        settings=make_settings(**settings_overrides),
        target_tables=target_tables or TargetTablesConfig((("db", "table"),), (), ()),
        treasure_data=td,
        repository=repository,
        backlog=backlog,
        resource_monitor=resource_monitor,
        now_provider=lambda: datetime(2026, 7, 13, 1, 10, tzinfo=UTC),
    )


def committed_map(repository: FakeRepository) -> dict[str, FileChange]:
    assert len(repository.commits) == 1
    return {change.path: change for change in repository.commits[0]}


def audit_payload(repository: FakeRepository) -> dict[str, object]:
    item = next(
        change for change in repository.commits[0] if change.path.startswith("audit_events/")
    )
    assert item.content is not None
    payload = json.loads(item.content)
    assert isinstance(payload, dict)
    return payload


def saved_query_snapshot(sql: str) -> SavedQuerySnapshot:
    """サービス統合テスト用の登録クエリsnapshotを作る。"""
    return SavedQuerySnapshot(
        query_id="300",
        query_name="query_a",
        query_string=sql,
        database_id="1",
        database_name="db",
        engine_type="trino",
        engine_version="stable",
        connector_type=None,
        connector_config_hash=None,
        cron=None,
        timezone="UTC",
        delay=0,
        priority=0,
        retry_limit=0,
    )


def test_additional_resource_issue_and_files_share_one_commit() -> None:
    before = saved_query_snapshot("SELECT 1")
    after = saved_query_snapshot("SELECT 2")
    query_change = SavedQueryDetectedChange(
        query_id="300",
        query_name="query_a",
        before=before,
        after=after,
        diff=SavedQueryDiff(
            query_id="300",
            sql_changed=True,
            changed_fields=(),
            deleted=False,
        ),
        change_id="query-change-id",
        diff_path="diffs/saved_queries/2026/07/13/300_query-change-id.md",
        github_diff_url=(
            "https://github.example/repository/blob/main/"
            "diffs/saved_queries/2026/07/13/300_query-change-id.md"
        ),
        should_create_issue=True,
    )
    resource_plan = ResourceRunPlan(
        target_count=1,
        workflow_changes=(),
        saved_query_changes=(query_change,),
        file_changes=(
            FileChange(
                "saved_queries/current/300.json",
                b'{"query_id":"300"}',
            ),
            FileChange(query_change.diff_path, b"# diff"),
        ),
        workflow_project_names={},
        baseline_count=0,
    )
    repository = FakeRepository({STATE_PATH: state_text()})
    backlog = FakeBacklog()

    summary = asyncio.run(
        service(
            td=FakeTreasureData(),
            repository=repository,
            backlog=backlog,
            target_tables=TargetTablesConfig((), (), ()),
            resource_monitor=FakeResourceMonitor(resource_plan),
        ).run()
    )

    files = committed_map(repository)
    assert summary["target_count"] == 1
    assert summary["diff_count"] == 1
    assert summary["issue_count"] == 1
    assert backlog.issues == ["query-change-id"]
    assert "- run_id:" in backlog.requests[0]["description"]
    assert "- 対象Audit Log ID: 取得対象外" in backlog.requests[0]["description"]
    assert "saved_queries/current/300.json" in files
    assert query_change.diff_path in files
    assert STATE_PATH in files
    assert json.loads(files[STATE_PATH].content or b"{}")["version"] == 3


def test_no_schema_change_writes_only_state_and_no_daily_run_file() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"))}
    )
    td = FakeTreasureData(
        events=[event(EventType.TABLE_MODIFY)],
        snapshots={("db", "table"): snapshot(("id", "LONG"))},
    )

    summary = asyncio.run(service(td=td, repository=repository, backlog=FakeBacklog()).run())

    assert summary["diff_count"] == 0
    assert set(committed_map(repository)) == {STATE_PATH}
    assert not any(path.startswith("runs/") for path in committed_map(repository))


def test_include_v_only_change_does_not_create_artifact_or_issue() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"))}
    )
    td = FakeTreasureData(
        events=[event(EventType.TABLE_MODIFY, attribute_name="include_v")],
        snapshots={("db", "table"): snapshot(("id", "long"))},
    )
    backlog = FakeBacklog()

    summary = asyncio.run(service(td=td, repository=repository, backlog=backlog).run())

    assert summary["diff_count"] == 0
    assert backlog.issues == []
    assert set(committed_map(repository)) == {STATE_PATH}


def test_schema_change_saves_current_diff_and_minimal_related_audit_only() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"))}
    )
    related = event(
        EventType.TABLE_MODIFY,
        old_value='[["id","long"]]',
        new_value='[["id","long"],["name","string"]]',
    )
    unrelated = event(
        EventType.TABLE_MODIFY,
        event_id="other-event",
        database="other_db",
        table="other_table",
        resource_id="other-id",
    )
    td = FakeTreasureData(
        events=[related, unrelated],
        snapshots={("db", "table"): snapshot(("id", "long"), ("name", "string"))},
    )
    backlog = FakeBacklog()

    summary = asyncio.run(service(td=td, repository=repository, backlog=backlog).run())

    files = committed_map(repository)
    assert summary["issue_count"] == 1
    assert SCHEMA_PATH in files
    assert len([path for path in files if path.startswith("diffs/")]) == 1
    assert len([path for path in files if path.startswith("audit_events/")]) == 1
    assert not any(path.startswith(("runs/", "net_diffs/", "schemas_deleted/")) for path in files)
    payload = audit_payload(repository)
    assert [item["id"] for item in payload["events"]] == ["audit-1"]
    serialized = json.dumps(payload)
    assert "must_not_be_saved" not in serialized
    assert '[[\\"id\\",\\"long\\"]]' not in serialized
    assert "old_value_sha256" in serialized
    assert "new_value_sha256" in serialized
    assert "td-secret" not in serialized
    assert "backlog-secret" not in serialized
    run = payload["run"]
    assert run["changed_table_count"] == 1
    assert run["backlog_issue_count"] == 1
    assert run["git_file_change_count"] == len(files)


def test_table_delete_removes_only_current_schema_and_keeps_change_artifacts() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"))}
    )
    td = FakeTreasureData(events=[event(EventType.TABLE_DELETE)])
    backlog = FakeBacklog()

    summary = asyncio.run(service(td=td, repository=repository, backlog=backlog).run())

    files = committed_map(repository)
    assert summary["issue_count"] == 1
    assert files[SCHEMA_PATH].content is None
    assert any(path.startswith("diffs/") for path in files)
    assert audit_payload(repository)["change_kind"] == "table_delete"


def test_table_recreate_same_schema_records_audit_without_issue() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"), table_id="old-id")}
    )
    td = FakeTreasureData(
        events=[
            event(EventType.TABLE_DELETE, event_id="delete-1", resource_id="old-id"),
            event(EventType.TABLE_CREATE, event_id="create-1", resource_id="new-id"),
        ],
        snapshots={("db", "table"): snapshot(("id", "long"), table_id="new-id")},
    )
    backlog = FakeBacklog()

    summary = asyncio.run(service(td=td, repository=repository, backlog=backlog).run())

    assert summary["diff_count"] == 1
    assert summary["issue_count"] == 0
    assert audit_payload(repository)["change_kind"] == "table_recreate"


def test_temporary_table_rename_uses_existing_target_as_previous_state() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"), table_id="old-id")}
    )
    td = FakeTreasureData(
        events=[
            event(
                EventType.TABLE_MODIFY,
                event_id="rename-temp",
                table="table",
                previous_table="tmp_table",
                resource_id="new-id",
                attribute_name="name",
                old_value="tmp_table",
                new_value="table",
            )
        ],
        snapshots={
            ("db", "table"): snapshot(("id", "long"), table_id="new-id")
        },
    )
    backlog = FakeBacklog()

    summary = asyncio.run(service(td=td, repository=repository, backlog=backlog).run())

    assert summary["diff_count"] == 1
    assert summary["issue_count"] == 0
    assert backlog.issues == []
    payload = audit_payload(repository)
    assert payload["change_kind"] == "table_recreate"
    assert payload["previous_table"] is None
    assert payload["net_diff"]["added_columns"] == []


def test_modify_rename_delete_creates_one_issue_and_one_grouped_audit_file() -> None:
    old_path = "schemas/current/db/old_table.json"
    repository = FakeRepository(
        {STATE_PATH: state_text(), old_path: snapshot_text(("id", "long"), table="old_table")}
    )
    td = FakeTreasureData(
        events=[
            event(
                EventType.TABLE_MODIFY,
                event_id="modify-old",
                table="old_table",
                occurred_at=datetime(2026, 7, 13, 0, 10, tzinfo=UTC),
            ),
            event(
                EventType.TABLE_MODIFY,
                event_id="rename",
                table="new_table",
                previous_table="old_table",
                attribute_name="name",
                old_value="old_table",
                new_value="new_table",
                occurred_at=datetime(2026, 7, 13, 0, 20, tzinfo=UTC),
            ),
            event(
                EventType.TABLE_DELETE,
                event_id="delete-new",
                table="new_table",
                attribute_name=None,
                occurred_at=datetime(2026, 7, 13, 0, 30, tzinfo=UTC),
            ),
        ]
    )
    backlog = FakeBacklog()
    targets = TargetTablesConfig((("db", "old_table"),), (), ())

    summary = asyncio.run(
        service(td=td, repository=repository, backlog=backlog, target_tables=targets).run()
    )

    files = committed_map(repository)
    assert summary["target_count"] == 1
    assert summary["issue_count"] == 1
    assert len(backlog.requests) == 1
    assert len([path for path in files if path.startswith("audit_events/")]) == 1
    payload = audit_payload(repository)
    assert payload["change_kind"] == "table_delete"
    assert [item["id"] for item in payload["events"]] == [
        "modify-old",
        "rename",
        "delete-new",
    ]
    assert files[old_path].content is None
    assert files["schemas/current/db/new_table.json"].content is None
    assert "operator@example.com" in backlog.requests[0]["description"]


def test_rename_and_schema_change_create_one_combined_issue() -> None:
    old_path = "schemas/current/db/old_table.json"
    repository = FakeRepository(
        {STATE_PATH: state_text(), old_path: snapshot_text(("id", "long"), table="old_table")}
    )
    td = FakeTreasureData(
        events=[
            event(
                EventType.TABLE_MODIFY,
                event_id="rename",
                table="new_table",
                previous_table="old_table",
                attribute_name="name",
                old_value="old_table",
                new_value="new_table",
            ),
            event(EventType.TABLE_MODIFY, event_id="modify-new", table="new_table"),
        ],
        snapshots={
            ("db", "new_table"): snapshot(("id", "long"), ("name", "string"), table="new_table")
        },
    )
    backlog = FakeBacklog()

    summary = asyncio.run(
        service(
            td=td,
            repository=repository,
            backlog=backlog,
            target_tables=TargetTablesConfig((("db", "old_table"),), (), ()),
        ).run()
    )

    assert summary["issue_count"] == 1
    assert audit_payload(repository)["change_kind"] == "table_rename_schema_change"
    assert len(backlog.requests) == 1


def test_processed_id_is_skipped_and_retention_is_bounded() -> None:
    old = "2026-06-01T00:00:00+00:00"
    repository = FakeRepository(
        {
            STATE_PATH: state_text(
                processed_ids={"audit-1": STATE_AT, "expired": old},
                processed_change_ids={"expired-change": old},
            ),
            SCHEMA_PATH: snapshot_text(("id", "long")),
        }
    )
    td = FakeTreasureData(events=[event(EventType.TABLE_MODIFY, event_id="audit-1")])

    summary = asyncio.run(service(td=td, repository=repository, backlog=FakeBacklog()).run())

    assert summary["diff_count"] == 0
    state_change = committed_map(repository)[STATE_PATH]
    assert state_change.content is not None
    payload = json.loads(state_change.content)
    assert "expired" not in payload["processed_audit_event_ids"]
    assert "expired-change" not in payload["processed_aggregated_change_ids"]
    assert "audit-1" in payload["processed_audit_event_ids"]
    assert td.audit_windows[0].start.isoformat() == "2026-07-12T23:30:00+00:00"


def test_unresolved_event_fails_before_state_commit() -> None:
    repository = FakeRepository({STATE_PATH: state_text()})
    td = FakeTreasureData(events=[event(EventType.TABLE_SWAP, database=None, table=None)])

    with pytest.raises(UnresolvedAuditEventsError):
        asyncio.run(service(td=td, repository=repository, backlog=FakeBacklog()).run())

    assert repository.commits == []


def test_no_ready_time_window_is_noop_without_commit() -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(audit_query_to="2026-07-13T01:05:00+00:00")}
    )
    td = FakeTreasureData(events=[event(EventType.TABLE_MODIFY)])

    summary = asyncio.run(service(td=td, repository=repository, backlog=FakeBacklog()).run())

    assert summary["planned_file_count"] == 0
    assert td.audit_windows == []
    assert repository.commits == []


def test_dry_run_does_not_write_repository_or_backlog(
    caplog: pytest.LogCaptureFixture,
) -> None:
    repository = FakeRepository(
        {STATE_PATH: state_text(), SCHEMA_PATH: snapshot_text(("id", "long"))}
    )
    td = FakeTreasureData(
        events=[event(EventType.TABLE_MODIFY)],
        snapshots={("db", "table"): snapshot(("id", "long"), ("name", "string"))},
    )
    backlog = FakeBacklog()

    with caplog.at_level(logging.INFO, logger="td_change_monitor.service"):
        summary = asyncio.run(
            service(td=td, repository=repository, backlog=backlog).run(dry_run=True)
        )

    assert summary["diff_count"] == 1
    assert repository.prepare_calls == [False]
    assert repository.commits == []
    assert backlog.issues == []
    change_records = [
        record
        for record in caplog.records
        if record.message == "td_change_monitor_dry_run_change"
    ]
    assert len(change_records) == 1
    dry_run_change = dict(change_records[0].dry_run_change)
    change_id = dry_run_change.pop("change_id")
    assert isinstance(change_id, str)
    assert len(change_id) == 64
    assert dry_run_change == {
        "database": "db",
        "table": "table",
        "previous_table": None,
        "change_kind": "schema_change",
        "backlog_candidate": True,
        "table_id_changed": False,
        "audit_event_count": 1,
        "event_types": ["table_modify"],
        "added_columns": ["name"],
        "removed_columns": [],
        "type_changes": [],
        "alias_changed_columns": [],
        "description_changed_columns": [],
        "order_changed_columns": [],
    }


def test_bootstrap_overwrites_only_current_snapshot_without_daily_schema() -> None:
    repository = FakeRepository()
    td = FakeTreasureData(snapshots={("db", "table"): snapshot(("id", "long"))})
    targets = TargetTablesConfig((("db", "table"),), (), ("db.table",))

    summary = asyncio.run(
        service(td=td, repository=repository, backlog=FakeBacklog(), target_tables=targets).run(
            bootstrap=True
        )
    )

    assert summary["bootstrap"] is True
    assert summary["baseline_count"] == 1
    assert set(committed_map(repository)) == {SCHEMA_PATH}


def test_bootstrap_can_write_single_initial_state() -> None:
    repository = FakeRepository()
    td = FakeTreasureData(snapshots={("db", "table"): snapshot(("id", "long"))})
    targets = TargetTablesConfig((("db", "table"),), (), ("db.table",))

    asyncio.run(
        service(td=td, repository=repository, backlog=FakeBacklog(), target_tables=targets).run(
            bootstrap=True,
            bootstrap_state_end_at=datetime(2026, 7, 13, 0, 0, tzinfo=UTC),
        )
    )

    state_change = committed_map(repository)[STATE_PATH]
    assert state_change.content is not None
    payload = json.loads(state_change.content)
    assert payload["audit_query_to"] == STATE_AT
    assert payload["processed_audit_event_ids"] == {}
    assert payload["table_ids"] == {"db.table": "table-1"}


def test_bootstrap_reports_all_missing_targets_without_commit() -> None:
    repository = FakeRepository()
    td = FakeTreasureData(
        snapshots={("db", "table"): snapshot(("id", "long"))}
    )
    targets = TargetTablesConfig(
        (("db", "table"), ("db", "missing_one"), ("db", "missing_two")),
        (),
        (),
    )

    with pytest.raises(
        ChangeMonitorError,
        match=r"count=2; tables=db\.missing_one,db\.missing_two",
    ):
        asyncio.run(
            service(
                td=td,
                repository=repository,
                backlog=FakeBacklog(),
                target_tables=targets,
            ).run(bootstrap=True)
        )

    assert td.fetches == [
        ("db", "table"),
        ("db", "missing_one"),
        ("db", "missing_two"),
    ]
    assert repository.commits == []
