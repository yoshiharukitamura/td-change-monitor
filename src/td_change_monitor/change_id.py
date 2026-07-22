from __future__ import annotations

import hashlib
from collections.abc import Iterable

from td_change_monitor.diff import snapshot_hash
from td_change_monitor.models import ChangeKind, TableSnapshot


def build_change_id(
    *,
    database: str,
    table: str,
    audit_event_ids: Iterable[str],
    change_kind: ChangeKind,
    before: TableSnapshot | None,
    after: TableSnapshot | None,
) -> str:
    """同じ論理変更で常に同じ値になる集約変更IDを作る。

    引数:
        database: 対象database名。
        table: 最終的な対象table名。
        audit_event_ids: 集約したAuditイベントID。
        change_kind: 最終的に判定した変更種別。
        before: 変更前snapshot。存在しない場合はNone。
        after: 変更後snapshot。削除された場合はNone。
    戻り値:
        入力要素を正規化して生成したSHA-256文字列。
    """
    parts = [
        database,
        table,
        ",".join(sorted(audit_event_ids)),
        change_kind.value,
        snapshot_hash(before),
        snapshot_hash(after),
    ]
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()
