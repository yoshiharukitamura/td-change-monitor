from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any

from td_change_monitor.models import (
    SavedQueryDetail,
    SavedQueryDiff,
    SavedQuerySnapshot,
)

_SETTING_FIELDS = (
    "query_name",
    "database_id",
    "database_name",
    "engine_type",
    "engine_version",
    "connector_type",
    "connector_config_hash",
    "cron",
    "timezone",
    "delay",
    "priority",
    "retry_limit",
)


def snapshot_from_saved_query(detail: SavedQueryDetail) -> SavedQuerySnapshot:
    """API詳細を秘密値を含まないGit保存用snapshotへ変換する。

    引数:
        detail: 登録クエリ詳細APIから正規化した現在状態。
    戻り値:
        SQL、監視設定、出力設定hashだけを持つsnapshot。
    """
    connector_type = _connector_type(detail.connector_config)
    connector_config_hash = _connector_config_hash(detail.connector_config)
    return SavedQuerySnapshot(
        query_id=detail.query_id,
        query_name=detail.query_name,
        query_string=_normalize_query_string(detail.query_string),
        database_id=detail.database.database_id,
        database_name=detail.database.database_name,
        engine_type=detail.engine_type,
        engine_version=detail.engine_version,
        connector_type=connector_type,
        connector_config_hash=connector_config_hash,
        cron=detail.cron,
        timezone=detail.timezone,
        delay=detail.delay,
        priority=detail.priority,
        retry_limit=detail.retry_limit,
    )


def diff_saved_queries(
    before: SavedQuerySnapshot,
    after: SavedQuerySnapshot | None,
) -> SavedQueryDiff:
    """同じQuery IDの前回状態と現在状態から最終差分を作る。

    引数:
        before: Gitに保存された前回snapshot。
        after: APIから作った現在snapshot。削除時はNone。
    戻り値:
        SQL変更、設定変更項目、削除状態を持つ差分。
    """
    if after is None:
        return SavedQueryDiff(
            query_id=before.query_id,
            sql_changed=False,
            changed_fields=(),
            deleted=True,
        )
    if before.query_id != after.query_id:
        raise ValueError("saved query snapshots must have the same query_id")

    sql_changed = before.query_string != after.query_string
    changed_fields = tuple(
        field
        for field in _SETTING_FIELDS
        if getattr(before, field) != getattr(after, field)
    )
    return SavedQueryDiff(
        query_id=before.query_id,
        sql_changed=sql_changed,
        changed_fields=changed_fields,
        deleted=False,
    )


def saved_query_snapshot_hash(snapshot: SavedQuerySnapshot | None) -> str:
    """登録クエリsnapshotの決定的なSHA-256を返す。

    引数:
        snapshot: hash対象。削除後など存在しない場合はNone。
    戻り値:
        Git保存形式のSHA-256。Noneなら固定文字列。
    """
    if snapshot is None:
        return "none"
    return hashlib.sha256(saved_query_snapshot_to_json_bytes(snapshot)).hexdigest()


def saved_query_snapshot_to_dict(
    snapshot: SavedQuerySnapshot,
) -> dict[str, object]:
    """登録クエリsnapshotをGit保存可能な辞書へ変換する。

    引数:
        snapshot: 変換対象の正規化済みsnapshot。
    戻り値:
        API生データと出力設定値を含まない辞書。
    """
    return {
        "query_id": snapshot.query_id,
        "query_name": snapshot.query_name,
        "query_string": _normalize_query_string(snapshot.query_string),
        "database": {
            "id": snapshot.database_id,
            "name": snapshot.database_name,
        },
        "engine": {
            "type": snapshot.engine_type,
            "version": snapshot.engine_version,
        },
        "output_settings": {
            "connector_type": snapshot.connector_type,
            "config_sha256": snapshot.connector_config_hash,
        },
        "schedule": {
            "cron": snapshot.cron,
            "timezone": snapshot.timezone,
            "delay": snapshot.delay,
            "priority": snapshot.priority,
            "retry_limit": snapshot.retry_limit,
        },
    }


def saved_query_snapshot_from_mapping(
    payload: Mapping[str, Any],
) -> SavedQuerySnapshot:
    """Git上のJSON辞書から登録クエリsnapshotを復元する。

    引数:
        payload: snapshot JSONを解析したマッピング。
    戻り値:
        型と必須項目を検証したSavedQuerySnapshot。
    """
    database = _required_mapping(payload, "database")
    engine = _required_mapping(payload, "engine")
    output_settings = _required_mapping(payload, "output_settings")
    schedule = _required_mapping(payload, "schedule")
    return SavedQuerySnapshot(
        query_id=_required_string(payload, "query_id"),
        query_name=_required_string(payload, "query_name", preserve_whitespace=True),
        query_string=_normalize_query_string(
            _required_string(payload, "query_string", preserve_whitespace=True)
        ),
        database_id=_required_string(database, "id"),
        database_name=_required_string(database, "name"),
        engine_type=_required_string(engine, "type"),
        engine_version=_required_string(engine, "version"),
        connector_type=_optional_string(output_settings, "connector_type"),
        connector_config_hash=_optional_hash(output_settings, "config_sha256"),
        cron=_optional_string(schedule, "cron"),
        timezone=_required_string(schedule, "timezone"),
        delay=_required_integer(schedule, "delay"),
        priority=_required_integer(schedule, "priority"),
        retry_limit=_required_integer(schedule, "retry_limit"),
    )


def saved_query_snapshot_to_json_bytes(snapshot: SavedQuerySnapshot) -> bytes:
    """登録クエリsnapshotを整形済みUTF-8 JSONへ変換する。

    引数:
        snapshot: Gitへ保存する正規化済みsnapshot。
    戻り値:
        キー順が安定したJSONバイト列。
    """
    payload = json.dumps(
        saved_query_snapshot_to_dict(snapshot),
        ensure_ascii=False,
        sort_keys=True,
        indent=2,
    )
    return payload.encode("utf-8")


def _connector_config_hash(config: Mapping[str, Any] | None) -> str | None:
    """出力設定値を保存せず変更検知用SHA-256へ変換する。

    引数:
        config: APIが返したconnectorConfig。未設定ならNone。
    戻り値:
        canonical JSONのSHA-256。未設定ならNone。
    """
    if config is None:
        return None
    encoded = json.dumps(
        config,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _connector_type(config: Mapping[str, Any] | None) -> str | None:
    """確認済み構造から秘密値を含まないconnector種別だけを取得する。

    引数:
        config: APIが返したconnectorConfig。未設定ならNone。
    戻り値:
        connector.type文字列。取得できなければNone。
    """
    if config is None:
        return None
    connector = config.get("connector")
    if not isinstance(connector, Mapping):
        return None
    value = connector.get("type")
    return value if isinstance(value, str) and value.strip() else None


def _normalize_query_string(query: str) -> str:
    """SQL本文の改行コードだけをLFへ統一する。

    引数:
        query: APIまたはGitから得たSQL本文。
    戻り値:
        SQLの空白やコメントを変えず、改行だけを統一した文字列。
    """
    return query.replace("\r\n", "\n").replace("\r", "\n")


def _required_mapping(
    payload: Mapping[str, Any],
    key: str,
) -> Mapping[str, Any]:
    """必須項目をJSONオブジェクトとして取得する。

    引数:
        payload: 対象項目を含むマッピング。
        key: 取得する項目名。
    戻り値:
        検証済みの子マッピング。
    """
    value = payload.get(key)
    if not isinstance(value, Mapping):
        raise ValueError(f"saved query snapshot did not include {key}")
    return value


def _required_string(
    payload: Mapping[str, Any],
    key: str,
    *,
    preserve_whitespace: bool = False,
) -> str:
    """必須項目を空でない文字列として取得する。

    引数:
        payload: 対象項目を含むマッピング。
        key: 取得する項目名。
        preserve_whitespace: 先頭末尾空白を保持するかどうか。
    戻り値:
        検証済み文字列。
    """
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"saved query snapshot did not include {key}")
    return value if preserve_whitespace else value.strip()


def _optional_string(
    payload: Mapping[str, Any],
    key: str,
) -> str | None:
    """任意項目を文字列またはNoneとして取得する。

    引数:
        payload: 対象項目を含むマッピング。
        key: 取得する項目名。
    戻り値:
        文字列またはNone。
    """
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"saved query snapshot {key} was invalid")
    return value


def _optional_hash(
    payload: Mapping[str, Any],
    key: str,
) -> str | None:
    """任意SHA-256項目を64桁16進文字列として取得する。

    引数:
        payload: 対象項目を含むマッピング。
        key: 取得するhash項目名。
    戻り値:
        検証済みhash文字列またはNone。
    """
    value = _optional_string(payload, key)
    if value is None:
        return None
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise ValueError(f"saved query snapshot {key} was invalid")
    return value


def _required_integer(payload: Mapping[str, Any], key: str) -> int:
    """必須項目をboolではない整数として取得する。

    引数:
        payload: 対象項目を含むマッピング。
        key: 取得する項目名。
    戻り値:
        検証済み整数。
    """
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"saved query snapshot {key} was invalid")
    return value
