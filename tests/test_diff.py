from td_change_monitor.diff import (
    diff_snapshots,
    schema_columns_from_raw,
    snapshot_from_mapping,
    snapshot_hash,
)
from td_change_monitor.models import ColumnDefinition, TableSnapshot


def snapshot(*columns: tuple[str, str]) -> TableSnapshot:
    return TableSnapshot(
        database="db",
        table="table",
        columns=tuple(ColumnDefinition(name=name, type=type_) for name, type_ in columns),
    )


def test_detects_added_removed_and_type_changed_columns() -> None:
    before = snapshot(("id", "long"), ("removed_col", "string"), ("amount", "long"))
    after = snapshot(("id", "long"), ("added_col", "string"), ("amount", "double"))

    result = diff_snapshots(before, after)

    assert [(item.name, item.type) for item in result.added] == [("added_col", "string")]
    assert [(item.name, item.type) for item in result.removed] == [("removed_col", "string")]
    assert result.type_changed == (("amount", "long", "double"),)
    assert result.has_changes


def test_snapshot_hash_ignores_volatile_metadata() -> None:
    left = snapshot_from_mapping(
        {
            "database": "db",
            "table": "table",
            "row_count": 10,
            "columns": [{"name": "id", "type": "long"}],
        }
    )
    right = snapshot_from_mapping(
        {
            "database": "db",
            "table": "table",
            "updated_at": "2026-07-13T00:00:00Z",
            "columns": [{"name": "id", "type": "LONG"}],
        }
    )

    assert snapshot_hash(left) == snapshot_hash(right)


def test_schema_json_string_and_2_3_4_item_columns_are_normalized() -> None:
    columns = schema_columns_from_raw(
        '[["id","long"],["name","string","表示名"],["memo","string","メモ","説明"]]'
    )

    normalized = [
        (item.name, item.type, item.alias, item.description, item.position) for item in columns
    ]
    assert normalized == [
        ("id", "long", None, None, 0),
        ("name", "string", "表示名", None, 1),
        ("memo", "string", "メモ", "説明", 2),
    ]


def test_detects_alias_description_and_order_changes_separately() -> None:
    before = TableSnapshot(
        database="db",
        table="table",
        columns=tuple(
            schema_columns_from_raw(
                [["id", "long", "ID", "old"], ["name", "string", "Name", "same"]]
            )
        ),
    )
    after = TableSnapshot(
        database="db",
        table="table",
        columns=tuple(
            schema_columns_from_raw(
                [["name", "string", "Name", "same"], ["id", "long", "ID2", "new"]]
            )
        ),
    )

    result = diff_snapshots(before, after)

    assert result.alias_changed == (("id", "ID", "ID2"),)
    assert result.description_changed == (("id", "old", "new"),)
    assert result.order_changed == (("id", 0, 1), ("name", 1, 0))
    assert result.has_changes
    assert not result.has_important_changes
