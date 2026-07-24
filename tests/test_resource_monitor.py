from __future__ import annotations

import asyncio
import io
import json
import logging
import tarfile
from datetime import UTC, datetime
from pathlib import Path

import pytest
from conftest import make_settings

from td_change_monitor.config import (
    MonitorStatus,
    ResourceTargetsConfig,
    SavedQueryTarget,
    WorkflowProjectTarget,
)
from td_change_monitor.models import (
    SavedQueryDatabaseReference,
    SavedQueryDetail,
    SavedQueryOwnerReference,
    WorkflowProjectDetail,
    WorkflowProjectReference,
    WorkflowReference,
    WorkflowScheduleDetail,
)
from td_change_monitor.resource_monitor import AdditionalResourceMonitor, ResourceRunPlan
from td_change_monitor.saved_query_diff import (
    saved_query_snapshot_to_json_bytes,
    snapshot_from_saved_query,
)
from td_change_monitor.workflow_archive import (
    snapshot_from_workflow_archive,
    workflow_snapshot_to_files,
)
from td_change_monitor.workflow_schedule import (
    build_workflow_project_schedule_snapshot,
    workflow_schedule_snapshot_to_bytes,
)


def build_archive(files: dict[str, bytes]) -> bytes:
    """テスト用gzip TARを作る。"""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for path, content in files.items():
            info = tarfile.TarInfo(path)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


def project_detail() -> WorkflowProjectDetail:
    """テスト用Workflow project詳細を作る。"""
    return WorkflowProjectDetail(
        project_id="100",
        project_name="project_a",
        revision="revision-1",
        archive_md5="md5-1",
        archive_type="s3",
    )


def schedule_detail(*, enabled: bool) -> WorkflowScheduleDetail:
    """テスト用schedule API状態を作る。"""
    return WorkflowScheduleDetail(
        schedule_id="200",
        project=WorkflowProjectReference(
            project_id="100",
            project_name="project_a",
        ),
        workflow=WorkflowReference(
            workflow_id="10",
            workflow_name="main",
        ),
        enabled=enabled,
    )


def query_detail(*, sql: str = "SELECT 1") -> SavedQueryDetail:
    """テスト用登録クエリ詳細を作る。"""
    return SavedQueryDetail(
        query_id="300",
        query_name="query_a",
        database=SavedQueryDatabaseReference(
            database_id="1",
            database_name="db",
        ),
        owner=SavedQueryOwnerReference(
            owner_id="2",
            owner_name="User",
        ),
        engine_type="trino",
        engine_version="stable",
        connector_config=None,
        cron=None,
        timezone="UTC",
        delay=0,
        priority=0,
        retry_limit=0,
        description=None,
        draft=False,
        query_string=sql,
    )


class FakeWorkflow:
    """Workflow project・archive・scheduleを返すテスト用API。"""

    def __init__(self, *, enabled: bool = True) -> None:
        self.enabled = enabled
        self.archive = build_archive(
            {
                "main.dig": (
                    b"timezone: Asia/Tokyo\n"
                    b"schedule:\n"
                    b"  daily>: 07:00:00\n"
                    b"+task:\n"
                    b"  echo>: ok\n"
                )
            }
        )
        self.archive_fetches = 0

    async def fetch_project(self, project_id: str) -> WorkflowProjectDetail:
        assert project_id == "100"
        return project_detail()

    async def fetch_project_archive(self, project_id: str, revision: str) -> bytes:
        assert (project_id, revision) == ("100", "revision-1")
        self.archive_fetches += 1
        return self.archive

    async def fetch_project_schedules(
        self,
        project_id: str,
    ) -> tuple[WorkflowScheduleDetail, ...]:
        assert project_id == "100"
        return (schedule_detail(enabled=self.enabled),)


class FakeSavedQuery:
    """登録クエリ詳細または削除状態を返すテスト用API。"""

    def __init__(self, detail: SavedQueryDetail | None) -> None:
        self.detail = detail

    async def fetch_query_if_exists(
        self,
        query_id: str,
    ) -> SavedQueryDetail | None:
        assert query_id == "300"
        return self.detail


class FakeRepository:
    """前回snapshot文字列を返すテスト用repository。"""

    def __init__(self, texts: dict[str, str] | None = None) -> None:
        self.texts = texts or {}

    async def read_text(self, path: str) -> str | None:
        return self.texts.get(path)


def targets(
    *,
    query_status: MonitorStatus = MonitorStatus.MONITOR,
) -> ResourceTargetsConfig:
    """Workflowと登録クエリ各1件の対象マスターを作る。"""
    return ResourceTargetsConfig(
        workflow_projects=(
            WorkflowProjectTarget(
                project_name="project_a",
                project_id="100",
                target_workflows=("main",),
                target_schedule_ids=("200",),
                monitor_status=MonitorStatus.MONITOR,
            ),
        ),
        saved_queries=(
            SavedQueryTarget(
                query_id="300",
                query_name="query_a",
                database="db",
                owner="User",
                monitor_status=query_status,
            ),
        ),
    )


def previous_texts(workflow: FakeWorkflow, extraction_root: Path) -> dict[str, str]:
    """現在APIと同じ内容の前回Workflow・query基準状態を作る。"""
    project, _ = snapshot_from_workflow_archive(
        workflow.archive,
        project_detail(),
        extraction_root=extraction_root,
        max_file_size_bytes=1024 * 1024,
        max_total_size_bytes=2 * 1024 * 1024,
    )
    project_files = workflow_snapshot_to_files(project)
    schedule = build_workflow_project_schedule_snapshot(
        project,
        (schedule_detail(enabled=True),),
    )
    texts = {
        f"workflows/current/project_a/{path}": content.decode("utf-8")
        for path, content in project_files.items()
    }
    texts["workflow_schedules/current/project_a.json"] = (
        workflow_schedule_snapshot_to_bytes(schedule).decode("utf-8")
    )
    texts["saved_queries/current/300.json"] = saved_query_snapshot_to_json_bytes(
        snapshot_from_saved_query(query_detail())
    ).decode("utf-8")
    return texts


def monitor(
    *,
    workflow: FakeWorkflow,
    saved_query: FakeSavedQuery,
    repository: FakeRepository,
    resource_targets: ResourceTargetsConfig | None = None,
) -> AdditionalResourceMonitor:
    """テスト用依存で追加リソース監視を作る。"""
    return AdditionalResourceMonitor(
        settings=make_settings(git_repository_path="."),
        targets=resource_targets or targets(),
        workflow=workflow,
        saved_query=saved_query,
        repository=repository,
    )


def run_plan(
    resource_monitor: AdditionalResourceMonitor,
    *,
    bootstrap: bool,
) -> ResourceRunPlan:
    """時刻固定で追加リソース計画を実行する。"""
    return asyncio.run(
        resource_monitor.plan(
            at=datetime(2026, 7, 24, 0, 0, tzinfo=UTC),
            window_start=datetime(2026, 7, 23, 0, 0, tzinfo=UTC),
            window_end=datetime(2026, 7, 24, 0, 0, tzinfo=UTC),
            bootstrap=bootstrap,
            workflow_project_names={},
        )
    )


def test_bootstrap_writes_current_snapshots_without_diff_or_issue(
    caplog: pytest.LogCaptureFixture,
) -> None:
    workflow = FakeWorkflow()
    caplog.set_level(logging.INFO)

    plan = run_plan(
        monitor(
            workflow=workflow,
            saved_query=FakeSavedQuery(query_detail()),
            repository=FakeRepository(),
        ),
        bootstrap=True,
    )

    assert plan.target_count == 2
    assert plan.diff_count == 0
    assert plan.baseline_count == 2
    paths = {change.path for change in plan.file_changes}
    assert "workflows/current/project_a/.workflow_state.json" in paths
    assert "workflow_schedules/current/project_a.json" in paths
    assert "saved_queries/current/300.json" in paths
    assert not any(path.startswith("diffs/") for path in paths)
    inventory_record = next(
        record
        for record in caplog.records
        if record.message == "td_change_monitor_workflow_archive_inventory"
    )
    assert inventory_record.workflow_archive_inventory["extension_counts"] == {
        ".dig": 1
    }


def test_daily_plan_aggregates_schedule_and_query_changes(tmp_path: Path) -> None:
    workflow = FakeWorkflow(enabled=False)
    repository = FakeRepository(previous_texts(workflow, tmp_path / "extract"))

    plan = run_plan(
        monitor(
            workflow=workflow,
            saved_query=FakeSavedQuery(query_detail(sql="SELECT 2")),
            repository=repository,
        ),
        bootstrap=False,
    )

    assert plan.diff_count == 2
    assert len(plan.workflow_changes) == 1
    assert len(plan.workflow_changes[0].diff.schedule_changes) == 1
    assert plan.workflow_changes[0].should_create_issue
    assert len(plan.saved_query_changes) == 1
    assert plan.saved_query_changes[0].diff.sql_changed
    paths = {change.path for change in plan.file_changes}
    assert any(path.startswith("diffs/workflows/") for path in paths)
    assert any(path.startswith("diffs/saved_queries/") for path in paths)
    assert workflow.archive_fetches == 0


def test_saved_query_deletion_removes_current_and_evidence_only_skips_issue(
    tmp_path: Path,
) -> None:
    workflow = FakeWorkflow()
    repository = FakeRepository(previous_texts(workflow, tmp_path / "extract"))

    plan = run_plan(
        monitor(
            workflow=workflow,
            saved_query=FakeSavedQuery(None),
            repository=repository,
            resource_targets=targets(query_status=MonitorStatus.EVIDENCE_ONLY),
        ),
        bootstrap=False,
    )

    assert len(plan.saved_query_changes) == 1
    assert plan.saved_query_changes[0].diff.deleted
    assert not plan.saved_query_changes[0].should_create_issue
    files = {change.path: change.content for change in plan.file_changes}
    assert files["saved_queries/current/300.json"] is None
    diff_content = next(
        content
        for path, content in files.items()
        if path.startswith("diffs/saved_queries/")
    )
    assert diff_content is not None
    assert json.loads(
        saved_query_snapshot_to_json_bytes(
            snapshot_from_saved_query(query_detail())
        )
    )["query_id"] == "300"
