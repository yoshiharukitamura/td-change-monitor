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


def build_resource_change_id(
    *,
    resource_type: str,
    stable_resource_id: str,
    event_ids: Iterable[str],
    before_hash: str,
    after_hash: str,
    change_kind: str,
) -> str:
    """table以外のリソースに共通する集約変更IDを作る。

    引数:
        resource_type: workflowやsaved_queryなどのリソース種別。
        stable_resource_id: project IDやQuery IDなどの安定ID。
        event_ids: 集約した検知イベントID。
        before_hash: 前回の正規化済み状態hash。
        after_hash: 現在の正規化済み状態hash。
        change_kind: 最終的に判定した変更種別。
    戻り値:
        入力順に依存しないSHA-256文字列。
    """
    parts = [
        resource_type.strip(),
        stable_resource_id.strip(),
        ",".join(sorted(set(event_ids))),
        before_hash,
        after_hash,
        change_kind.strip(),
    ]
    if not all(parts[index] for index in (0, 1, 3, 4, 5)):
        raise ValueError("resource change ID inputs must not be blank")
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()
