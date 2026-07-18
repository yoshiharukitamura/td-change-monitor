from __future__ import annotations

from datetime import datetime, timedelta, timezone, tzinfo

from td_change_monitor.models import AuditEvent, DetectedChange, SchemaDiff


def render_diff_markdown(
    change: DetectedChange,
    *,
    window_start: datetime,
    window_end: datetime,
) -> str:
    lines = [
        f"# TD table change: {change.qualified_name}",
        "",
        f"- aggregated_change_id: `{change.change_id}`",
        f"- change_kind: `{change.change_kind.value}`",
        f"- window: `{window_start.isoformat()}` - `{window_end.isoformat()}`",
        f"- events: {', '.join(event.value for event in change.event_types)}",
        f"- should_create_issue: `{change.should_create_issue}`",
        "",
        "## Events",
        "",
        *_event_lines(change.events),
        "",
        "## Schema diff",
        "",
        *_diff_lines(change.diff),
        "",
    ]
    return "\n".join(lines)


def render_issue_summary(change: DetectedChange) -> str:
    return (
        f"【TD変更検知】{_change_kind_label(change.change_kind.value)}: "
        f"{change.qualified_name} "
        f"[chg:{change.change_id[:8]}]"
    )


def render_issue_description(
    change: DetectedChange,
    *,
    window_start: datetime,
    window_end: datetime,
    display_timezone: str,
) -> str:
    if display_timezone != "Asia/Tokyo":
        raise ValueError(f"unsupported display timezone: {display_timezone}")
    display_tz = timezone(timedelta(hours=9), name="JST")
    lines = [
        "Treasure Dataの監視対象テーブルで、確認が必要な変更を検知しました。",
        "",
        "■ 概要",
        f"- 対象テーブル: {change.qualified_name}",
        *_previous_table_lines(change),
        f"- 検知内容: {_change_kind_label(change.change_kind.value)}",
        f"- 操作者メールアドレス: {_actor_summary(change.events)}",
        f"- 変更件数: {_change_count_summary(change.diff)}",
        "- 検知期間 (JST): "
        f"{_display_datetime(window_start, display_tz)} - "
        f"{_display_datetime(window_end, display_tz)}",
        "",
        "■ 検知された操作",
        *_operation_lines(change.events, display_timezone=display_tz),
        "",
        "■ 変更内容",
        *_diff_lines(change.diff),
        "",
        "■ 確認してほしいこと",
        "- この変更が意図したものか確認してください。",
        "- このテーブルを参照するクエリ、ワークフロー、ダッシュボードへの影響を確認してください。",
        "- 確認結果や必要な対応を、この課題へ記録してください。",
        "",
        "■ 証跡",
        f"- GitHub差分: {change.github_diff_url}",
        f"- aggregated_change_id (重複防止用): {change.change_id}",
        "- Audit Log:",
        *_event_lines(change.events, display_timezone=display_tz),
        "",
        "この課題はTD Change Monitorにより自動作成されました。",
    ]
    return "\n".join(lines)


def _event_lines(
    events: tuple[AuditEvent, ...],
    *,
    display_timezone: tzinfo | None = None,
) -> list[str]:
    if not events:
        return ["- なし"]
    return [
        f"- [{event.event_id}] "
        f"{_event_datetime(event.occurred_at, display_timezone)} "
        f"{event.event_type.value}"
        f"{f' attribute={event.attribute_name}' if event.attribute_name else ''}"
        f"{f' by {_event_actor(event)}' if _event_actor(event) else ''}"
        for event in events
    ]


def _operation_lines(
    events: tuple[AuditEvent, ...],
    *,
    display_timezone: tzinfo,
) -> list[str]:
    return [
        f"- {_display_datetime(event.occurred_at, display_timezone)}: "
        f"{_operation_label(event)}"
        f"{f' (操作者: {_event_actor(event)})' if _event_actor(event) else ''}"
        for event in events
    ] or ["- なし"]


def _operation_label(event: AuditEvent) -> str:
    if event.previous_table and event.table and event.previous_table != event.table:
        return f"テーブル名を `{event.previous_table}` から `{event.table}` へ変更"
    if event.event_type.value == "table_create":
        return "テーブルを作成"
    if event.event_type.value == "table_delete":
        return "テーブルを削除"
    if event.event_type.value == "table_modify" and event.attribute_name == "schema":
        return "テーブルのスキーマを変更"
    if event.event_type.value == "table_modify":
        attribute = event.attribute_name or "詳細不明"
        return f"テーブル属性 `{attribute}` を変更"
    return event.event_type.value


def _diff_lines(diff: SchemaDiff) -> list[str]:
    lines: list[str] = []
    if diff.added:
        lines.append("### 追加されたカラム")
        lines.extend(f"- `{item.name}`: `{item.type}`" for item in diff.added)
    if diff.removed:
        lines.append("### 削除されたカラム")
        lines.extend(f"- `{item.name}`: `{item.type}`" for item in diff.removed)
    if diff.type_changed:
        lines.append("### 型が変更されたカラム")
        lines.extend(
            f"- `{name}`: `{before}` -> `{after}`" for name, before, after in diff.type_changed
        )
    if diff.alias_changed:
        lines.append("### 別名が変更されたカラム")
        lines.extend(
            f"- `{name}`: `{_optional_value(before)}` -> `{_optional_value(after)}`"
            for name, before, after in diff.alias_changed
        )
    if diff.description_changed:
        lines.append("### 説明が変更されたカラム")
        lines.extend(
            f"- `{name}`: `{_optional_value(before)}` -> `{_optional_value(after)}`"
            for name, before, after in diff.description_changed
        )
    if diff.order_changed:
        lines.append("### 並び順が変更されたカラム")
        lines.extend(
            f"- `{name}`: `{before}` -> `{after}`" for name, before, after in diff.order_changed
        )
    if not lines:
        lines.append("- スキーマ実差分なし")
    return lines


def _change_kind_label(change_kind: str) -> str:
    return {
        "schema_change": "スキーマ変更",
        "table_delete": "テーブル削除",
        "table_rename": "テーブル名変更",
        "table_rename_schema_change": "テーブル名変更・スキーマ変更",
        "table_recreate": "テーブル再作成",
        "table_recreate_schema_change": "テーブル再作成・スキーマ変更",
        "audit_only": "操作記録のみ",
    }.get(change_kind, change_kind)


def _change_count_summary(diff: SchemaDiff) -> str:
    return " / ".join(
        (
            f"追加 {len(diff.added)}件",
            f"削除 {len(diff.removed)}件",
            f"型変更 {len(diff.type_changed)}件",
        )
    )


def _actor_summary(events: tuple[AuditEvent, ...]) -> str:
    actor_values: set[str] = set()
    for event in events:
        actor = event.actor or event.source_actor
        if actor:
            actor_values.add(actor)
    actors = sorted(actor_values)
    return ", ".join(actors) if actors else "不明 (Audit Logに記録なし)"


def _event_actor(event: AuditEvent) -> str | None:
    return event.actor or event.source_actor


def _previous_table_lines(change: DetectedChange) -> list[str]:
    if change.previous_table is None or change.previous_table == change.table:
        return []
    return [f"- 変更前テーブル名: {change.database}.{change.previous_table}"]


def _display_datetime(value: datetime, display_timezone: tzinfo) -> str:
    return value.astimezone(display_timezone).strftime("%Y-%m-%d %H:%M:%S %Z")


def _event_datetime(value: datetime, display_timezone: tzinfo | None) -> str:
    return _display_datetime(value, display_timezone) if display_timezone else value.isoformat()


def _optional_value(value: str | None) -> str:
    return value if value is not None else "未設定"
