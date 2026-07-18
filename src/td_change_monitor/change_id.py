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
    parts = [
        database,
        table,
        ",".join(sorted(audit_event_ids)),
        change_kind.value,
        snapshot_hash(before),
        snapshot_hash(after),
    ]
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()
