from __future__ import annotations

import difflib
from datetime import datetime, timedelta, timezone

from td_change_monitor.models import (
    SavedQueryDetectedChange,
    SavedQuerySnapshot,
    WorkflowDetectedChange,
    WorkflowFileChange,
    WorkflowFileChangeKind,
    WorkflowFileSnapshot,
    WorkflowProjectSnapshot,
    WorkflowScheduleChange,
    WorkflowScheduleSnapshot,
)

_ISSUE_DIFF_LINE_LIMIT = 300


def render_workflow_diff_markdown(
    change: WorkflowDetectedChange,
    *,
    window_start: datetime,
    window_end: datetime,
) -> str:
    """Workflowプロジェクトのファイル・schedule最終差分をMarkdown化する。

    引数:
        change: project IDへ集約したWorkflow変更。
        window_start: 今回監視期間のUTC開始。
        window_end: 今回監視期間のUTC終了。
    戻り値:
        Gitへ保存する省略なしの差分Markdown。
    """
    lines = _workflow_overview_lines(change, window_start, window_end)
    lines.extend(["", "## Workflow files", ""])
    if change.change_kind == "deleted":
        lines.append("- Project deleted")
    elif change.diff is None or not change.diff.file_changes:
        lines.append("- No file changes")
    else:
        for file_change in change.diff.file_changes:
            lines.extend(_workflow_file_change_lines(change, file_change))
    lines.extend(["", "## Schedules", ""])
    if change.diff is None or not change.diff.schedule_changes:
        lines.append("- No schedule changes")
    else:
        for schedule_change in change.diff.schedule_changes:
            lines.extend(_workflow_schedule_change_lines(schedule_change))
    lines.append("")
    return "\n".join(lines)


def render_workflow_issue_summary(change: WorkflowDetectedChange) -> str:
    """Workflow変更のBacklog件名を作る。

    引数:
        change: 課題化するWorkflow project変更。
    戻り値:
        project名と変更件数を含む件名。
    """
    file_count = len(change.diff.file_changes) if change.diff is not None else 0
    schedule_count = len(change.diff.schedule_changes) if change.diff is not None else 0
    return (
        f"【TD Workflow変更】{change.project_name}"
        f"(ファイル{file_count}件・schedule{schedule_count}件)"
        f" [chg:{change.change_id[:8]}]"
    )


def render_workflow_issue_description(
    change: WorkflowDetectedChange,
    *,
    run_id: str,
    window_start: datetime,
    window_end: datetime,
    display_timezone: str,
) -> str:
    """Workflow変更を人が確認しやすいBacklog本文へ整形する。

    引数:
        change: 課題化するWorkflow project変更。
        run_id: 今回の日次バッチ実行ID。
        window_start: 今回監視期間のUTC開始。
        window_end: 今回監視期間のUTC終了。
        display_timezone: 人向け表示timezone。現在はAsia/Tokyoだけを許可する。
    戻り値:
        project単位にファイルとscheduleをまとめた課題本文。
    """
    display_start, display_end = _display_window(
        window_start,
        window_end,
        display_timezone,
    )
    before_revision = change.before.revision if change.before is not None else "なし"
    after_revision = change.after.revision if change.after is not None else "削除済み"
    lines = [
        "Treasure DataのWorkflowプロジェクトで変更を検知しました。",
        "",
        "■ 検知内容",
        f"- プロジェクト: {change.project_name}",
        f"- Project ID: {change.project_id}",
        f"- 検知期間 (JST): {display_start} - {display_end}",
        f"- 変更前revision: {before_revision}",
        f"- 現在revision: {after_revision}",
        "- 変更したユーザー: Audit Logから取得できません",
        "",
        "■ 最終的な変更",
        "",
        "● Workflow・SQLファイル",
    ]
    if change.change_kind == "deleted":
        lines.append("- プロジェクトが削除されています。")
    elif change.diff is None or not change.diff.file_changes:
        lines.append("- ファイル変更なし")
    else:
        lines.extend(
            f"- {_workflow_file_change_label(item)}"
            for item in change.diff.file_changes
        )
    lines.extend(["", "● スケジュール変更"])
    if change.diff is None or not change.diff.schedule_changes:
        lines.append("- schedule変更なし")
    else:
        lines.extend(
            line
            for item in change.diff.schedule_changes
            for line in _workflow_schedule_change_lines(item)
        )
    lines.extend(
        [
            "",
            "■ 確認事項",
            "- 実行順序への影響を確認してください。",
            "- 参照・出力テーブルへの影響を確認してください。",
            "- SQL処理内容への影響を確認してください。",
            "- 実行スケジュールへの影響を確認してください。",
            "",
            "■ 関連情報",
            f"- GitHub差分: {change.github_diff_url}",
            f"- run_id: {run_id}",
            f"- aggregated_change_id: {change.change_id}",
            f"- Project ID: {change.project_id}",
            "- 対象Audit Log ID: 取得対象外",
            "",
            "この課題はTD Change Monitorにより自動作成されました。",
        ]
    )
    return "\n".join(lines)


def render_saved_query_diff_markdown(
    change: SavedQueryDetectedChange,
    *,
    window_start: datetime,
    window_end: datetime,
) -> str:
    """登録クエリのSQLと固定設定の最終差分をMarkdown化する。

    引数:
        change: Query IDへ集約した登録クエリ変更。
        window_start: 今回監視期間のUTC開始。
        window_end: 今回監視期間のUTC終了。
    戻り値:
        Gitへ保存するSQL行差分と設定差分Markdown。
    """
    lines = [
        f"# TD saved query change: {change.query_name}",
        "",
        f"- Query ID: `{change.query_id}`",
        f"- aggregated_change_id: `{change.change_id}`",
        f"- window: `{window_start.isoformat()}` - `{window_end.isoformat()}`",
        f"- deleted: `{change.diff.deleted}`",
        "",
        "## SQL",
        "",
        "```diff",
        *_saved_query_sql_diff(change.before, change.after),
        "```",
        "",
        "## Settings",
        "",
        *_saved_query_setting_lines(change),
        "",
    ]
    return "\n".join(lines)


def render_saved_query_issue_summary(change: SavedQueryDetectedChange) -> str:
    """登録クエリ変更のBacklog件名を作る。

    引数:
        change: 課題化する登録クエリ変更。
    戻り値:
        クエリ名と短縮変更IDを含む件名。
    """
    return f"【TD登録クエリ変更】{change.query_name} [chg:{change.change_id[:8]}]"


def render_saved_query_issue_description(
    change: SavedQueryDetectedChange,
    *,
    run_id: str,
    window_start: datetime,
    window_end: datetime,
    display_timezone: str,
) -> str:
    """登録クエリ変更を人が確認しやすいBacklog本文へ整形する。

    引数:
        change: 課題化する登録クエリ変更。
        run_id: 今回の日次バッチ実行ID。
        window_start: 今回監視期間のUTC開始。
        window_end: 今回監視期間のUTC終了。
        display_timezone: 人向け表示timezone。現在はAsia/Tokyoだけを許可する。
    戻り値:
        SQL行差分、設定差分、確認事項を持つ課題本文。
    """
    display_start, display_end = _display_window(
        window_start,
        window_end,
        display_timezone,
    )
    current = change.after or change.before
    sql_diff = _saved_query_sql_diff(change.before, change.after)
    visible_sql_diff = sql_diff[:_ISSUE_DIFF_LINE_LIMIT]
    lines = [
        "Treasure Dataの登録クエリで変更を検知しました。",
        "",
        "■ 検知内容",
        f"- Query ID: {change.query_id}",
        f"- クエリ名: {change.query_name}",
        f"- データベース: {current.database_name}",
        f"- エンジン: {current.engine_type} / {current.engine_version}",
        f"- 検知期間 (JST): {display_start} - {display_end}",
        "- 操作者: Audit Logから取得できません",
        "",
        "■ 最終的な変更",
        "",
        "● SQL本文",
        "{code:diff}",
        *visible_sql_diff,
        "{code}",
    ]
    if len(sql_diff) > len(visible_sql_diff):
        lines.append(
            f"- SQL差分は{len(sql_diff)}行あるため先頭"
            f"{_ISSUE_DIFF_LINE_LIMIT}行だけ表示しています。全差分はGitHubを確認してください。"
        )
    lines.extend(["", "● 設定変更", *_saved_query_setting_lines(change)])
    lines.extend(
        [
            "",
            "■ 確認事項",
            "- 参照テーブルへの影響を確認してください。",
            "- 出力先への影響を確認してください。",
            "- 集計条件への影響を確認してください。",
            "- Databricks移行対象への影響を確認してください。",
            "",
            "■ 関連情報",
            f"- GitHub差分: {change.github_diff_url}",
            f"- run_id: {run_id}",
            f"- aggregated_change_id: {change.change_id}",
            f"- Query ID: {change.query_id}",
            "- 対象Audit Log ID: 取得対象外",
            "",
            "この課題はTD Change Monitorにより自動作成されました。",
        ]
    )
    return "\n".join(lines)


def _workflow_overview_lines(
    change: WorkflowDetectedChange,
    window_start: datetime,
    window_end: datetime,
) -> list[str]:
    """Workflow差分Markdownの共通header行を作る。"""
    return [
        f"# TD Workflow change: {change.project_name}",
        "",
        f"- Project ID: `{change.project_id}`",
        f"- aggregated_change_id: `{change.change_id}`",
        f"- change_kind: `{change.change_kind}`",
        f"- window: `{window_start.isoformat()}` - `{window_end.isoformat()}`",
    ]


def _workflow_file_change_lines(
    change: WorkflowDetectedChange,
    file_change: WorkflowFileChange,
) -> list[str]:
    """Workflowファイル1件の説明と必要な行差分を作る。"""
    lines = [f"### {_workflow_file_change_label(file_change)}", ""]
    if file_change.kind != WorkflowFileChangeKind.MODIFIED:
        return lines
    before_file = _find_workflow_file(change.before, file_change.before_path)
    after_file = _find_workflow_file(change.after, file_change.after_path)
    if before_file is None or after_file is None:
        return [*lines, "- File content was unavailable", ""]
    lines.extend(
        [
            "```diff",
            *difflib.unified_diff(
                before_file.content.splitlines(),
                after_file.content.splitlines(),
                fromfile=before_file.path,
                tofile=after_file.path,
                lineterm="",
            ),
            "```",
            "",
        ]
    )
    return lines


def _workflow_file_change_label(change: WorkflowFileChange) -> str:
    """Workflowファイル変更を日本語の1行表示へ変換する。"""
    if change.kind == WorkflowFileChangeKind.RENAMED:
        return f"名前変更: {change.before_path} -> {change.after_path}"
    path = change.after_path or change.before_path or "unknown"
    labels = {
        WorkflowFileChangeKind.ADDED: "追加",
        WorkflowFileChangeKind.DELETED: "削除",
        WorkflowFileChangeKind.MODIFIED: "内容変更",
    }
    return f"{labels[change.kind]}: {path}"


def _workflow_schedule_change_lines(change: WorkflowScheduleChange) -> list[str]:
    """schedule変更1件を固定設定だけの人向け行へ変換する。"""
    before = _schedule_display(change.before)
    after = _schedule_display(change.after)
    if change.kind.value == "added":
        return [f"- schedule {change.schedule_id} 追加: {after}"]
    if change.kind.value == "deleted":
        return [f"- schedule {change.schedule_id} 削除: {before}"]
    fields = ", ".join(change.changed_fields)
    return [
        f"- schedule {change.schedule_id} 変更項目: {fields}",
        f"  変更前: {before}",
        f"  変更後: {after}",
    ]


def _schedule_display(schedule: WorkflowScheduleSnapshot | None) -> str:
    """schedule snapshotを秘密値なしの1行へ変換する。"""
    if schedule is None:
        return "なし"
    state = "有効" if schedule.enabled else "無効"
    return (
        f"{schedule.workflow_name}, {state}, "
        f"{schedule.schedule_type}={schedule.schedule_value}, {schedule.timezone}"
    )


def _find_workflow_file(
    snapshot: WorkflowProjectSnapshot | None,
    path: str | None,
) -> WorkflowFileSnapshot | None:
    """project snapshotから指定pathのファイルを探す。"""
    if path is None or snapshot is None:
        return None
    return next((file for file in snapshot.files if file.path == path), None)


def _saved_query_sql_diff(
    before: SavedQuerySnapshot,
    after: SavedQuerySnapshot | None,
) -> list[str]:
    """登録クエリSQLのunified diffを行配列で返す。"""
    after_lines = after.query_string.splitlines() if after is not None else []
    return list(
        difflib.unified_diff(
            before.query_string.splitlines(),
            after_lines,
            fromfile=f"query-{before.query_id}-before.sql",
            tofile=f"query-{before.query_id}-after.sql",
            lineterm="",
        )
    ) or ["(SQL本文の変更なし)"]


def _saved_query_setting_lines(change: SavedQueryDetectedChange) -> list[str]:
    """登録クエリ固定設定の変更項目をMarkdown表へ変換する。"""
    if change.diff.deleted:
        return ["- 登録クエリが削除されています。"]
    if not change.diff.changed_fields:
        return ["- 固定設定の変更なし"]
    assert change.after is not None
    lines = ["| 項目 | 変更前 | 変更後 |", "|---|---|---|"]
    for field in change.diff.changed_fields:
        lines.append(
            f"| {field} | {_setting_value(getattr(change.before, field))} "
            f"| {_setting_value(getattr(change.after, field))} |"
        )
    return lines


def _setting_value(value: object) -> str:
    """Markdown表へ入れる固定設定値を改行なし文字列へ変換する。"""
    if value is None:
        return "(なし)"
    return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def _display_window(
    window_start: datetime,
    window_end: datetime,
    display_timezone: str,
) -> tuple[str, str]:
    """UTC監視期間をJSTの人向け時刻へ変換する。"""
    if display_timezone != "Asia/Tokyo":
        raise ValueError(f"unsupported display timezone: {display_timezone}")
    jst = timezone(timedelta(hours=9), name="JST")
    return (
        window_start.astimezone(jst).strftime("%Y-%m-%d %H:%M:%S JST"),
        window_end.astimezone(jst).strftime("%Y-%m-%d %H:%M:%S JST"),
    )
