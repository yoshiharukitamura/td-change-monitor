from __future__ import annotations

from collections import defaultdict
from pathlib import PurePosixPath

from td_change_monitor.models import (
    WorkflowFileChange,
    WorkflowFileChangeKind,
    WorkflowFileSnapshot,
    WorkflowProjectDiff,
    WorkflowProjectScheduleSnapshot,
    WorkflowProjectSnapshot,
)
from td_change_monitor.workflow_schedule import diff_workflow_schedule_snapshots


def diff_workflow_projects(
    before: WorkflowProjectSnapshot,
    after: WorkflowProjectSnapshot,
    *,
    before_schedules: WorkflowProjectScheduleSnapshot | None = None,
    after_schedules: WorkflowProjectScheduleSnapshot | None = None,
) -> WorkflowProjectDiff:
    """同じproject IDの前回・現在snapshotから最終ファイル差分を作る。

    引数:
        before: Gitに保存された前回project snapshot。
        after: archiveから作った現在project snapshot。
        before_schedules: Gitに保存されていた前回schedule状態。
        after_schedules: schedule APIと現在digから作ったschedule状態。
    戻り値:
        project名変更と追加・削除・変更・renameを集約した差分。
    """
    if before.project_id != after.project_id:
        raise ValueError("Workflow snapshots must have the same project_id")
    if (before_schedules is None) != (after_schedules is None):
        raise ValueError("Both Workflow schedule snapshots must be provided")
    if (
        before_schedules is not None
        and after_schedules is not None
        and (
            before_schedules.project_id != before.project_id
            or after_schedules.project_id != after.project_id
        )
    ):
        raise ValueError(
            "Workflow file and schedule snapshots must have the same project_id"
        )

    before_by_path = {file.path: file for file in before.files}
    after_by_path = {file.path: file for file in after.files}
    common_paths = before_by_path.keys() & after_by_path.keys()
    removed_paths = set(before_by_path.keys() - after_by_path.keys())
    added_paths = set(after_by_path.keys() - before_by_path.keys())

    changes: list[WorkflowFileChange] = []
    changes.extend(
        _detect_exact_renames(
            before_by_path,
            after_by_path,
            removed_paths,
            added_paths,
        )
    )
    for path in sorted(common_paths):
        before_file = before_by_path[path]
        after_file = after_by_path[path]
        if before_file.content_hash == after_file.content_hash:
            continue
        changes.append(
            WorkflowFileChange(
                kind=WorkflowFileChangeKind.MODIFIED,
                before_path=path,
                after_path=path,
                notification_required=_is_substantive_modification(
                    before_file,
                    after_file,
                ),
            )
        )
    changes.extend(
        WorkflowFileChange(
            kind=WorkflowFileChangeKind.ADDED,
            before_path=None,
            after_path=path,
            notification_required=True,
        )
        for path in sorted(added_paths)
    )
    changes.extend(
        WorkflowFileChange(
            kind=WorkflowFileChangeKind.DELETED,
            before_path=path,
            after_path=None,
            notification_required=True,
        )
        for path in sorted(removed_paths)
    )

    return WorkflowProjectDiff(
        project_id=before.project_id,
        project_name_changed=before.project_name != after.project_name,
        file_changes=tuple(changes),
        schedule_changes=(
            diff_workflow_schedule_snapshots(before_schedules, after_schedules)
            if before_schedules is not None and after_schedules is not None
            else ()
        ),
    )


def _detect_exact_renames(
    before_by_path: dict[str, WorkflowFileSnapshot],
    after_by_path: dict[str, WorkflowFileSnapshot],
    removed_paths: set[str],
    added_paths: set[str],
) -> tuple[WorkflowFileChange, ...]:
    """同一content hashの削除・追加ペアを決定的にrenameへ変換する。

    引数:
        before_by_path: 前回ファイルのpath索引。
        after_by_path: 現在ファイルのpath索引。
        removed_paths: 前回だけに存在するpath集合。
        added_paths: 現在だけに存在するpath集合。
    戻り値:
        path順に対応付けたrename差分。
    """
    removed_by_hash: defaultdict[str, list[str]] = defaultdict(list)
    added_by_hash: defaultdict[str, list[str]] = defaultdict(list)
    for path in removed_paths:
        removed_by_hash[before_by_path[path].content_hash].append(path)
    for path in added_paths:
        added_by_hash[after_by_path[path].content_hash].append(path)

    renames: list[WorkflowFileChange] = []
    for content_hash in sorted(removed_by_hash.keys() & added_by_hash.keys()):
        old_paths = sorted(removed_by_hash[content_hash])
        new_paths = sorted(added_by_hash[content_hash])
        for old_path, new_path in zip(old_paths, new_paths, strict=False):
            removed_paths.remove(old_path)
            added_paths.remove(new_path)
            renames.append(
                WorkflowFileChange(
                    kind=WorkflowFileChangeKind.RENAMED,
                    before_path=old_path,
                    after_path=new_path,
                    notification_required=True,
                )
            )
    return tuple(
        sorted(
            renames,
            key=lambda item: (item.before_path or "", item.after_path or ""),
        )
    )


def _is_substantive_modification(
    before: WorkflowFileSnapshot,
    after: WorkflowFileSnapshot,
) -> bool:
    """空白・改行・コメントだけではない内容変更かを判定する。

    引数:
        before: 変更前ファイル。
        after: 変更後ファイル。
    戻り値:
        Backlog通知対象の実質変更ならTrue。
    """
    if _without_whitespace(before.content) == _without_whitespace(after.content):
        return False
    suffix = PurePosixPath(before.path).suffix.lower()
    before_without_comments = _strip_comments(before.content, suffix)
    after_without_comments = _strip_comments(after.content, suffix)
    return _without_whitespace(before_without_comments) != _without_whitespace(
        after_without_comments
    )


def _without_whitespace(content: str) -> str:
    """比較用にUnicode空白をすべて除去する。

    引数:
        content: 比較対象テキスト。
    戻り値:
        空白を除いた文字列。
    """
    return "".join(content.split())


def _strip_comments(content: str, suffix: str) -> str:
    """引用符内を保持しながらSQLまたはdigコメントを除去する。

    引数:
        content: 比較対象テキスト。
        suffix: `.sql`または`.dig`。
    戻り値:
        コメントだけを空白へ置換した決定的比較用文字列。
    """
    output: list[str] = []
    index = 0
    quote: str | None = None
    line_comment = False
    block_comment = False
    while index < len(content):
        character = content[index]
        next_character = content[index + 1] if index + 1 < len(content) else ""

        if line_comment:
            if character == "\n":
                line_comment = False
                output.append(character)
            index += 1
            continue
        if block_comment:
            if character == "*" and next_character == "/":
                block_comment = False
                output.append(" ")
                index += 2
            else:
                if character == "\n":
                    output.append(character)
                index += 1
            continue
        if quote is not None:
            output.append(character)
            if character == "\\" and next_character:
                output.append(next_character)
                index += 2
                continue
            if character == quote:
                if next_character == quote:
                    output.append(next_character)
                    index += 2
                    continue
                quote = None
            index += 1
            continue

        if character in ("'", '"'):
            quote = character
            output.append(character)
            index += 1
            continue
        if suffix == ".sql" and character == "-" and next_character == "-":
            line_comment = True
            output.append(" ")
            index += 2
            continue
        if suffix == ".sql" and character == "/" and next_character == "*":
            block_comment = True
            output.append(" ")
            index += 2
            continue
        if suffix == ".dig" and character == "#":
            line_comment = True
            output.append(" ")
            index += 1
            continue

        output.append(character)
        index += 1
    return "".join(output)
