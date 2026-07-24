from __future__ import annotations

import hashlib
from dataclasses import replace

import pytest

from td_change_monitor.models import (
    WorkflowFileSnapshot,
    WorkflowProjectReference,
    WorkflowProjectScheduleSnapshot,
    WorkflowProjectSnapshot,
    WorkflowReference,
    WorkflowScheduleChangeKind,
    WorkflowScheduleDetail,
    WorkflowScheduleSnapshot,
)
from td_change_monitor.workflow_schedule import (
    WorkflowScheduleDefinitionError,
    build_workflow_project_schedule_snapshot,
    diff_workflow_schedule_snapshots,
    parse_workflow_schedule_definition,
    workflow_schedule_snapshot_from_bytes,
    workflow_schedule_snapshot_to_bytes,
)


def workflow_file(path: str, content: str) -> WorkflowFileSnapshot:
    """テスト用Workflowファイルを実装と同じhash規則で作る。"""
    return WorkflowFileSnapshot(
        path=path,
        content=content,
        content_hash=hashlib.sha256(content.encode("utf-8")).hexdigest(),
    )


def project_snapshot(*files: WorkflowFileSnapshot) -> WorkflowProjectSnapshot:
    """テスト用Workflowプロジェクト状態を作る。"""
    return WorkflowProjectSnapshot(
        project_id="1001",
        project_name="sample_project",
        revision="revision-1",
        archive_md5="archive-md5-1",
        files=files,
    )


def schedule_detail(
    schedule_id: str,
    workflow_name: str,
    *,
    workflow_id: str | None = None,
    enabled: bool = True,
) -> WorkflowScheduleDetail:
    """確認済みschedule APIモデルと同じ形のテストデータを作る。"""
    return WorkflowScheduleDetail(
        schedule_id=schedule_id,
        project=WorkflowProjectReference(
            project_id="1001",
            project_name="sample_project",
        ),
        workflow=WorkflowReference(
            workflow_id=workflow_id or f"workflow-{schedule_id}",
            workflow_name=workflow_name,
        ),
        enabled=enabled,
    )


def normalized_schedule(
    schedule_id: str,
    *,
    workflow_id: str | None = None,
    workflow_name: str | None = None,
    enabled: bool = True,
    schedule_type: str = "daily",
    schedule_value: str = "07:00:00",
    timezone: str = "Asia/Tokyo",
    definition_path: str | None = None,
) -> WorkflowScheduleSnapshot:
    """差分テスト用の正規化済みscheduleを作る。"""
    name = workflow_name or f"workflow_{schedule_id}"
    return WorkflowScheduleSnapshot(
        schedule_id=schedule_id,
        workflow_id=workflow_id or f"workflow-{schedule_id}",
        workflow_name=name,
        enabled=enabled,
        schedule_type=schedule_type,
        schedule_value=schedule_value,
        timezone=timezone,
        definition_path=definition_path or f"{name}.dig",
    )


def schedule_project(
    *schedules: WorkflowScheduleSnapshot,
) -> WorkflowProjectScheduleSnapshot:
    """差分テスト用のプロジェクトschedule状態を作る。"""
    return WorkflowProjectScheduleSnapshot(
        project_id="1001",
        project_name="sample_project",
        schedules=schedules,
    )


@pytest.mark.parametrize(
    ("directive", "expected_type", "expected_value"),
    [
        ("hourly>: 30:00", "hourly", "30:00"),
        ("daily>: 07:00:00", "daily", "07:00:00"),
        ("weekly>: Sun,09:00:00", "weekly", "Sun,09:00:00"),
        ("monthly>: 1,09:00:00", "monthly", "1,09:00:00"),
        ("minutes_interval>: 30", "minutes_interval", "30"),
        ("cron>: '42 4 1 * *'", "cron", "42 4 1 * *"),
    ],
)
def test_parses_confirmed_digdag_schedule_directives(
    directive: str,
    expected_type: str,
    expected_value: str,
) -> None:
    file = workflow_file(
        "main.dig",
        f"timezone: Asia/Tokyo # display timezone\nschedule:\n  {directive}\n+task:\n"
        "  echo>: ok\n",
    )

    result = parse_workflow_schedule_definition(file)

    assert result == (expected_type, expected_value, "Asia/Tokyo")


def test_schedule_parser_defaults_timezone_to_utc_and_keeps_hash_in_quotes() -> None:
    file = workflow_file(
        "main.dig",
        'schedule:\n  cron>: "0 1 * * * # fixed"\n',
    )

    result = parse_workflow_schedule_definition(file)

    assert result == ("cron", "0 1 * * * # fixed", "UTC")


def test_schedule_parser_accepts_confirmed_inline_mapping() -> None:
    file = workflow_file(
        "main.dig",
        'timezone: "Asia/Tokyo"\n'
        'schedule: {"daily>": "10:00:00", "skip_on_overtime": true, '
        '"start": "2026-03-11"}\n',
    )

    result = parse_workflow_schedule_definition(file)

    assert result == ("daily", "10:00:00", "Asia/Tokyo")


def test_schedule_parser_rejects_unsupported_inline_operator() -> None:
    file = workflow_file(
        "main.dig",
        'schedule: {"daily>": "10:00:00", "custom>": "value"}\n',
    )

    with pytest.raises(WorkflowScheduleDefinitionError, match="unsupported"):
        parse_workflow_schedule_definition(file)


def test_builds_project_snapshot_by_matching_workflow_name_to_dig() -> None:
    project = project_snapshot(
        workflow_file(
            "daily_job.dig",
            "timezone: Asia/Tokyo\nschedule:\n  daily>: 07:00:00\n",
        ),
        workflow_file(
            "nested/hourly_job.dig",
            "schedule:\n  hourly>: 15:00\n",
        ),
    )

    result = build_workflow_project_schedule_snapshot(
        project,
        (
            schedule_detail("20", "hourly_job", enabled=False),
            schedule_detail("3", "daily_job"),
        ),
    )

    assert [schedule.schedule_id for schedule in result.schedules] == ["3", "20"]
    assert result.schedules[0].schedule_type == "daily"
    assert result.schedules[0].timezone == "Asia/Tokyo"
    assert result.schedules[1].definition_path == "nested/hourly_job.dig"
    assert result.schedules[1].enabled is False


def test_build_rejects_missing_or_ambiguous_workflow_definition() -> None:
    missing_project = project_snapshot(workflow_file("other.dig", "+task:\n"))
    ambiguous_project = project_snapshot(
        workflow_file("one/main.dig", "schedule:\n  daily>: 01:00:00\n"),
        workflow_file("two/main.dig", "schedule:\n  daily>: 02:00:00\n"),
    )

    with pytest.raises(WorkflowScheduleDefinitionError, match="exactly one dig"):
        build_workflow_project_schedule_snapshot(
            missing_project,
            (schedule_detail("1", "main"),),
        )
    with pytest.raises(WorkflowScheduleDefinitionError, match="exactly one dig"):
        build_workflow_project_schedule_snapshot(
            ambiguous_project,
            (schedule_detail("1", "main"),),
        )


def test_build_rejects_schedule_api_item_from_another_project() -> None:
    project = project_snapshot(
        workflow_file("main.dig", "schedule:\n  daily>: 01:00:00\n")
    )
    detail = replace(
        schedule_detail("1", "main"),
        project=WorkflowProjectReference(
            project_id="9999",
            project_name="other_project",
        ),
    )

    with pytest.raises(WorkflowScheduleDefinitionError, match="different project"):
        build_workflow_project_schedule_snapshot(project, (detail,))


def test_detects_added_deleted_and_all_fixed_setting_changes() -> None:
    before = schedule_project(
        normalized_schedule("1"),
        normalized_schedule("2"),
    )
    after = schedule_project(
        normalized_schedule(
            "1",
            workflow_id="new-workflow-id",
            workflow_name="new_workflow",
            enabled=False,
            schedule_type="weekly",
            schedule_value="Mon,08:30:00",
            timezone="UTC",
            definition_path="new_workflow.dig",
        ),
        normalized_schedule("3"),
    )

    changes = diff_workflow_schedule_snapshots(before, after)

    assert [change.kind for change in changes] == [
        WorkflowScheduleChangeKind.MODIFIED,
        WorkflowScheduleChangeKind.DELETED,
        WorkflowScheduleChangeKind.ADDED,
    ]
    assert changes[0].changed_fields == (
        "workflow_id",
        "workflow_name",
        "enabled",
        "schedule_type",
        "schedule_value",
        "timezone",
        "definition_path",
    )
    assert changes[1].before is not None
    assert changes[1].after is None
    assert changes[2].before is None
    assert changes[2].after is not None


def test_schedule_snapshot_json_round_trip_excludes_dynamic_execution_times() -> None:
    snapshot = schedule_project(
        normalized_schedule("20"),
        normalized_schedule("3"),
    )

    content = workflow_schedule_snapshot_to_bytes(snapshot)
    restored = workflow_schedule_snapshot_from_bytes(content)

    assert restored.schedules == (
        normalized_schedule("3"),
        normalized_schedule("20"),
    )
    assert b"nextRunTime" not in content
    assert b"nextScheduleTime" not in content


def test_snapshot_json_rejects_duplicate_schedule_ids() -> None:
    content = workflow_schedule_snapshot_to_bytes(
        schedule_project(
            normalized_schedule("1"),
            normalized_schedule("1"),
        )
    )

    with pytest.raises(ValueError, match="duplicate ID"):
        workflow_schedule_snapshot_from_bytes(content)
