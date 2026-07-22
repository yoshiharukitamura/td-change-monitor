from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any

from td_change_monitor.models import ColumnDefinition, SchemaDiff, TableSnapshot


def normalize_snapshot(snapshot: TableSnapshot) -> TableSnapshot:
    """schema比較が安定するよう型名・空文字・位置を正規化する。

    引数:
        snapshot: TDまたはGitから読み込んだtable snapshot。
    戻り値:
        比較用に正規化した新しいTableSnapshot。
    """
    """Return a stable representation used for hashing and comparison."""
    columns = tuple(
        ColumnDefinition(
            name=column.name.strip(),
            type=column.type.strip().lower(),
            alias=_blank_to_none(column.alias.strip() if column.alias is not None else None),
            description=_blank_to_none(
                column.description.strip() if column.description is not None else None
            ),
            position=index,
        )
        for index, column in enumerate(snapshot.columns)
    )
    return TableSnapshot(
        database=snapshot.database.strip(),
        table=snapshot.table.strip(),
        columns=columns,
        table_id=snapshot.table_id,
    )


def diff_snapshots(before: TableSnapshot, after: TableSnapshot) -> SchemaDiff:
    """変更前後のschemaを比較して項目別のNet Diffを作る。

    引数:
        before: Gitに保存された変更前snapshot。
        after: Table APIから取得した現在snapshot。
    戻り値:
        追加・削除・型・alias・説明・順序の差分。
    """
    before_columns = normalize_snapshot(before).columns
    after_columns = normalize_snapshot(after).columns
    before_map = {column.name: column for column in before_columns}
    after_map = {column.name: column for column in after_columns}

    added = tuple(after_map[name] for name in after_map.keys() - before_map.keys())
    removed = tuple(before_map[name] for name in before_map.keys() - after_map.keys())
    type_changed = tuple(
        (name, before_map[name].type, after_map[name].type)
        for name in before_map.keys() & after_map.keys()
        if before_map[name].type != after_map[name].type
    )
    alias_changed = tuple(
        (name, before_map[name].alias, after_map[name].alias)
        for name in before_map.keys() & after_map.keys()
        if before_map[name].alias != after_map[name].alias
    )
    description_changed = tuple(
        (name, before_map[name].description, after_map[name].description)
        for name in before_map.keys() & after_map.keys()
        if before_map[name].description != after_map[name].description
    )
    order_changed = tuple(
        (name, before_map[name].position, after_map[name].position)
        for name in before_map.keys() & after_map.keys()
        if before_map[name].position != after_map[name].position
    )

    return SchemaDiff(
        added=tuple(sorted(added, key=lambda item: item.name)),
        removed=tuple(sorted(removed, key=lambda item: item.name)),
        type_changed=tuple(sorted(type_changed, key=lambda item: item[0])),
        alias_changed=tuple(sorted(alias_changed, key=lambda item: item[0])),
        description_changed=tuple(sorted(description_changed, key=lambda item: item[0])),
        order_changed=tuple(sorted(order_changed, key=lambda item: item[0])),
    )


def diff_created(after: TableSnapshot) -> SchemaDiff:
    """新規作成tableの全カラムを追加差分として返す。

    引数:
        after: 新規作成後のsnapshot。
    戻り値:
        全カラムがaddedに入ったSchemaDiff。
    """
    normalized = normalize_snapshot(after)
    return SchemaDiff(added=normalized.columns, removed=(), type_changed=())


def diff_deleted(before: TableSnapshot | None) -> SchemaDiff:
    """削除tableの全カラムを削除差分として返す。

    引数:
        before: 削除前snapshot。存在しない場合はNone。
    戻り値:
        全カラムがremovedに入ったSchemaDiff。
    """
    if before is None:
        return SchemaDiff(added=(), removed=(), type_changed=())
    normalized = normalize_snapshot(before)
    return SchemaDiff(added=(), removed=normalized.columns, type_changed=())


def snapshot_hash(snapshot: TableSnapshot | None) -> str:
    """snapshotの内容を決定的なSHA-256へ変換する。

    引数:
        snapshot: hash対象。存在しない状態はNone。
    戻り値:
        正規化したsnapshotのSHA-256。Noneなら固定文字列。
    """
    if snapshot is None:
        return "none"

    normalized = normalize_snapshot(snapshot)
    payload = {
        "database": normalized.database,
        "table": normalized.table,
        "table_id": normalized.table_id,
        "columns": [_column_to_dict(c) for c in normalized.columns],
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def snapshot_to_dict(snapshot: TableSnapshot) -> dict[str, object]:
    """snapshotをGit保存用の辞書へ変換する。

    引数:
        snapshot: 変換対象のtable snapshot。
    戻り値:
        database、table、table ID、columnsを持つ辞書。
    """
    normalized = normalize_snapshot(snapshot)
    return {
        "database": normalized.database,
        "table": normalized.table,
        "table_id": normalized.table_id,
        "columns": [_column_to_dict(column) for column in normalized.columns],
    }


def snapshot_from_mapping(payload: Mapping[str, Any]) -> TableSnapshot:
    """Git上のJSON辞書からTableSnapshotを復元する。

    引数:
        payload: snapshot JSONを解析したマッピング。
    戻り値:
        型と値を検証して構築したTableSnapshot。
    """
    database = payload.get("database")
    table = payload.get("table")
    table_id = payload.get("table_id") or payload.get("id")
    columns = payload.get("columns")
    if not isinstance(database, str) or not isinstance(table, str) or not isinstance(columns, list):
        raise ValueError("invalid table snapshot payload")

    parsed_columns = schema_columns_from_raw(columns)

    return normalize_snapshot(
        TableSnapshot(
            database=database,
            table=table,
            columns=tuple(parsed_columns),
            table_id=str(table_id) if table_id is not None else None,
        )
    )


def snapshot_to_json_bytes(snapshot: TableSnapshot) -> bytes:
    """snapshotを整形済みUTF-8 JSONへ変換する。

    引数:
        snapshot: 保存対象のtable snapshot。
    戻り値:
        Git書き込みに使用するJSONバイト列。
    """
    payload = json.dumps(
        snapshot_to_dict(snapshot),
        ensure_ascii=False,
        sort_keys=True,
        indent=2,
    )
    return payload.encode("utf-8")


def schema_columns_from_raw(raw_schema: object) -> list[ColumnDefinition]:
    """TDのschema表現をColumnDefinition一覧へ変換する。

    引数:
        raw_schema: JSON文字列または解析済み配列形式のschema。
    戻り値:
        入力順に位置を付けたカラム定義一覧。
    """
    if isinstance(raw_schema, str):
        try:
            decoded = json.loads(raw_schema)
        except json.JSONDecodeError as exc:
            raise ValueError("schema JSON string could not be decoded") from exc
        return schema_columns_from_raw(decoded)
    if not isinstance(raw_schema, list):
        raise ValueError("schema must be a list or JSON string")

    columns: list[ColumnDefinition] = []
    for position, item in enumerate(raw_schema):
        columns.append(_column_from_raw(item, position=position))
    return columns


def _column_from_raw(item: object, *, position: int) -> ColumnDefinition:
    """TD schema内の1要素を正規化したカラム定義へ変換する。

    引数:
        item: 配列形式または辞書形式のカラム情報。
        position: schema内の0始まり位置。
    戻り値:
        検証済みColumnDefinition。
    """
    if isinstance(item, Mapping):
        name = item.get("name")
        type_ = item.get("type")
        alias = item.get("alias")
        description = item.get("description")
    elif isinstance(item, list | tuple):
        if len(item) < 2:
            raise ValueError("schema column array must contain at least name and type")
        name = item[0]
        type_ = item[1]
        alias = item[2] if len(item) >= 3 else None
        description = item[3] if len(item) >= 4 else None
    else:
        raise ValueError("invalid schema column payload")

    if not isinstance(name, str) or not isinstance(type_, str):
        raise ValueError("schema column name and type must be strings")
    if alias is not None and not isinstance(alias, str):
        alias = str(alias)
    if description is not None and not isinstance(description, str):
        description = str(description)
    return ColumnDefinition(
        name=name,
        type=type_,
        alias=_blank_to_none(alias),
        description=_blank_to_none(description),
        position=position,
    )


def _column_to_dict(column: ColumnDefinition) -> dict[str, object]:
    """カラム定義をJSON保存可能な辞書へ変換する。

    引数:
        column: 変換対象のカラム定義。
    戻り値:
        name、type、positionと任意属性を持つ辞書。
    """
    return {
        "name": column.name,
        "type": column.type,
        "alias": column.alias,
        "description": column.description,
        "position": column.position,
    }


def _blank_to_none(value: str | None) -> str | None:
    """空文字をNoneへ統一する。

    引数:
        value: 正規化対象の文字列またはNone。
    戻り値:
        空でない文字列。空文字またはNoneならNone。
    """
    return value if value else None
