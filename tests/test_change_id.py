from __future__ import annotations

from td_change_monitor.change_id import build_change_id
from td_change_monitor.models import ChangeKind, ColumnDefinition, TableSnapshot


def snapshot(*columns: tuple[str, str]) -> TableSnapshot:
    return TableSnapshot(
        database="db",
        table="table",
        columns=tuple(ColumnDefinition(name=name, type=type_) for name, type_ in columns),
    )


def test_change_id_is_deterministic_and_event_order_independent() -> None:
    kwargs = {
        "database": "db",
        "table": "table",
        "change_kind": ChangeKind.SCHEMA_CHANGE,
        "before": snapshot(("id", "long")),
        "after": snapshot(("id", "long"), ("name", "string")),
    }

    left = build_change_id(
        audit_event_ids=["audit-2", "audit-1"],
        **kwargs,
    )
    right = build_change_id(
        audit_event_ids=["audit-1", "audit-2"],
        **kwargs,
    )

    assert left == right
