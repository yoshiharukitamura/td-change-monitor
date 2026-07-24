from __future__ import annotations

import hashlib

from td_change_monitor.models import (
    WorkflowFileChangeKind,
    WorkflowFileSnapshot,
    WorkflowProjectScheduleSnapshot,
    WorkflowProjectSnapshot,
    WorkflowScheduleSnapshot,
)
from td_change_monitor.workflow_diff import diff_workflow_projects


def workflow_file(path: str, content: str) -> WorkflowFileSnapshot:
    return WorkflowFileSnapshot(
        path=path,
        content=content,
        content_hash=hashlib.sha256(content.encode("utf-8")).hexdigest(),
    )


def snapshot(
    *files: WorkflowFileSnapshot,
    name: str = "sample_project",
) -> WorkflowProjectSnapshot:
    return WorkflowProjectSnapshot(
        project_id="1001",
        project_name=name,
        revision="revision",
        archive_md5="archive-md5",
        files=files,
    )


def test_detects_added_deleted_modified_and_exact_rename() -> None:
    before = snapshot(
        workflow_file("comment.sql", "SELECT 1 -- old comment\n"),
        workflow_file("deleted.sql", "SELECT 0\n"),
        workflow_file("modified.sql", "SELECT 1\n"),
        workflow_file("old_name.sql", "SELECT 10\n"),
        workflow_file("whitespace.dig", "+task:\n  echo>: ok\n"),
    )
    after = snapshot(
        workflow_file("added.sql", "SELECT 20\n"),
        workflow_file("comment.sql", "SELECT 1 -- new comment\n"),
        workflow_file("modified.sql", "SELECT 2\n"),
        workflow_file("new_name.sql", "SELECT 10\n"),
        workflow_file("whitespace.dig", "+task:  \n\n  echo>:    ok\n"),
    )

    result = diff_workflow_projects(before, after)

    assert [
        (
            change.kind,
            change.before_path,
            change.after_path,
            change.notification_required,
        )
        for change in result.file_changes
    ] == [
        (
            WorkflowFileChangeKind.RENAMED,
            "old_name.sql",
            "new_name.sql",
            True,
        ),
        (
            WorkflowFileChangeKind.MODIFIED,
            "comment.sql",
            "comment.sql",
            False,
        ),
        (
            WorkflowFileChangeKind.MODIFIED,
            "modified.sql",
            "modified.sql",
            True,
        ),
        (
            WorkflowFileChangeKind.MODIFIED,
            "whitespace.dig",
            "whitespace.dig",
            False,
        ),
        (
            WorkflowFileChangeKind.ADDED,
            None,
            "added.sql",
            True,
        ),
        (
            WorkflowFileChangeKind.DELETED,
            "deleted.sql",
            None,
            True,
        ),
    ]
    assert result.has_changes
    assert result.should_create_issue


def test_comment_and_whitespace_only_changes_keep_git_evidence_without_issue() -> None:
    before = snapshot(
        workflow_file("main.sql", "SELECT 1 -- old\n"),
        workflow_file("main.dig", "+task:\n  echo>: ok # old\n"),
    )
    after = snapshot(
        workflow_file("main.sql", "\nSELECT 1 -- new\n"),
        workflow_file("main.dig", "+task:  \n  echo>: ok # new\n"),
    )

    result = diff_workflow_projects(before, after)

    assert result.has_changes
    assert not result.should_create_issue
    assert all(not change.notification_required for change in result.file_changes)


def test_comment_markers_inside_sql_string_are_substantive() -> None:
    before = snapshot(workflow_file("main.sql", "SELECT '-- old'\n"))
    after = snapshot(workflow_file("main.sql", "SELECT '-- new'\n"))

    result = diff_workflow_projects(before, after)

    assert result.should_create_issue


def test_project_rename_is_notification_change() -> None:
    file = workflow_file("main.sql", "SELECT 1\n")
    before = snapshot(file, name="old_project")
    after = snapshot(file, name="new_project")

    result = diff_workflow_projects(before, after)

    assert result.project_name_changed
    assert result.has_changes
    assert result.should_create_issue


def test_schedule_change_is_aggregated_into_one_workflow_project_diff() -> None:
    file = workflow_file(
        "main.dig",
        "timezone: Asia/Tokyo\nschedule:\n  daily>: 07:00:00\n",
    )
    before_schedule = WorkflowProjectScheduleSnapshot(
        project_id="1001",
        project_name="sample_project",
        schedules=(
            WorkflowScheduleSnapshot(
                schedule_id="10",
                workflow_id="200",
                workflow_name="main",
                enabled=True,
                schedule_type="daily",
                schedule_value="07:00:00",
                timezone="Asia/Tokyo",
                definition_path="main.dig",
            ),
        ),
    )
    after_schedule = WorkflowProjectScheduleSnapshot(
        project_id="1001",
        project_name="sample_project",
        schedules=(
            WorkflowScheduleSnapshot(
                schedule_id="10",
                workflow_id="200",
                workflow_name="main",
                enabled=False,
                schedule_type="daily",
                schedule_value="07:00:00",
                timezone="Asia/Tokyo",
                definition_path="main.dig",
            ),
        ),
    )

    result = diff_workflow_projects(
        snapshot(file),
        snapshot(file),
        before_schedules=before_schedule,
        after_schedules=after_schedule,
    )

    assert result.file_changes == ()
    assert len(result.schedule_changes) == 1
    assert result.schedule_changes[0].changed_fields == ("enabled",)
    assert result.has_changes
    assert result.should_create_issue
