from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime

from td_change_monitor.models import (
    AuditEvent,
    ChangeKind,
    ColumnDefinition,
    DetectedChange,
    EventType,
    SchemaDiff,
)
from td_change_monitor.rendering import render_issue_description, render_issue_summary


def detected_change() -> DetectedChange:
    event = AuditEvent(
        event_id="audit-1",
        event_type=EventType.TABLE_MODIFY,
        occurred_at=datetime(2026, 7, 18, 1, 30, tzinfo=UTC),
        database="db",
        table="orders",
        previous_table=None,
        actor="operator@example.com",
        source_actor=None,
        resource_id="123",
        event_result="success",
        requested_http_verb="POST",
        requested_path_info="/v3/table/update-schema/db/orders",
        attribute_name="schema",
        old_value=None,
        new_value=None,
        target_resource_name=None,
        raw={},
    )
    return DetectedChange(
        database="db",
        table="orders",
        previous_table=None,
        event_types=(EventType.TABLE_MODIFY,),
        events=(event,),
        before=None,
        after=None,
        diff=SchemaDiff(
            added=(ColumnDefinition(name="customer_rank", type="string"),),
            removed=(),
            type_changed=(("amount", "long", "double"),),
        ),
        change_kind=ChangeKind.SCHEMA_CHANGE,
        change_id="a81d9e47" + "0" * 56,
        diff_path="diffs/example.md",
        github_diff_url="https://github.example/diffs/example.md",
        should_create_issue=True,
    )


def test_issue_summary_uses_human_readable_change_kind() -> None:
    assert render_issue_summary(detected_change()) == (
        "【TD変更検知】スキーマ変更: db.orders [chg:a81d9e47]"
    )


def test_issue_description_prioritizes_summary_and_uses_jst() -> None:
    description = render_issue_description(
        detected_change(),
        window_start=datetime(2026, 7, 18, 0, 0, tzinfo=UTC),
        window_end=datetime(2026, 7, 18, 2, 0, tzinfo=UTC),
        display_timezone="Asia/Tokyo",
    )

    assert "- 検知内容: スキーマ変更" in description
    assert "- 操作者メールアドレス: operator@example.com" in description
    assert "- 変更件数: 追加 1件 / 削除 0件 / 型変更 1件" in description
    assert "2026-07-18 09:00:00 JST - 2026-07-18 11:00:00 JST" in description
    assert "### 追加されたカラム" in description
    assert "### 型が変更されたカラム" in description
    assert "■ 確認してほしいこと" in description
    assert "2026-07-18 10:30:00 JST table_modify" in description
    assert "change_id (重複防止用)" in description


def test_issue_description_uses_source_actor_and_handles_missing_actor() -> None:
    change = detected_change()
    source_only_event = replace(
        change.events[0],
        actor=None,
        source_actor="source@example.com",
    )
    change = replace(change, events=(source_only_event,))

    description = render_issue_description(
        change,
        window_start=datetime(2026, 7, 18, 0, 0, tzinfo=UTC),
        window_end=datetime(2026, 7, 18, 2, 0, tzinfo=UTC),
        display_timezone="Asia/Tokyo",
    )

    assert "- 操作者メールアドレス: source@example.com" in description

    unknown_actor_change = replace(
        change,
        events=(replace(source_only_event, source_actor=None),),
    )
    unknown_description = render_issue_description(
        unknown_actor_change,
        window_start=datetime(2026, 7, 18, 0, 0, tzinfo=UTC),
        window_end=datetime(2026, 7, 18, 2, 0, tzinfo=UTC),
        display_timezone="Asia/Tokyo",
    )
    assert "- 操作者メールアドレス: 不明 (Audit Logに記録なし)" in unknown_description
