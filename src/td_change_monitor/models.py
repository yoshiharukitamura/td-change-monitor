from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any


class EventType(StrEnum):
    TABLE_CREATE = "table_create"
    TABLE_MODIFY = "table_modify"
    TABLE_DELETE = "table_delete"
    TABLE_CHANGE_DATABASE = "table_change_database"
    TABLE_SWAP = "table_swap"
    TABLE_IMPORT_CREATE = "table_import_create"


class ChangeKind(StrEnum):
    SCHEMA_CHANGE = "schema_change"
    TABLE_DELETE = "table_delete"
    TABLE_RENAME = "table_rename"
    TABLE_RENAME_SCHEMA_CHANGE = "table_rename_schema_change"
    TABLE_RECREATE = "table_recreate"
    TABLE_RECREATE_SCHEMA_CHANGE = "table_recreate_schema_change"
    AUDIT_ONLY = "audit_only"


@dataclass(frozen=True)
class ColumnDefinition:
    name: str
    type: str
    alias: str | None = None
    description: str | None = None
    position: int = 0


@dataclass(frozen=True)
class TableSnapshot:
    database: str
    table: str
    columns: tuple[ColumnDefinition, ...]
    table_id: str | None = None


@dataclass(frozen=True)
class AuditEvent:
    event_id: str
    event_type: EventType
    occurred_at: datetime
    database: str | None
    table: str | None
    previous_table: str | None
    actor: str | None
    source_actor: str | None
    resource_id: str | None
    event_result: str | None
    requested_http_verb: str | None
    requested_path_info: str | None
    attribute_name: str | None
    old_value: str | None
    new_value: str | None
    target_resource_name: str | None
    raw: dict[str, Any]


@dataclass(frozen=True)
class SchemaDiff:
    added: tuple[ColumnDefinition, ...]
    removed: tuple[ColumnDefinition, ...]
    type_changed: tuple[tuple[str, str, str], ...]
    alias_changed: tuple[tuple[str, str | None, str | None], ...] = ()
    description_changed: tuple[tuple[str, str | None, str | None], ...] = ()
    order_changed: tuple[tuple[str, int, int], ...] = ()

    @property
    def has_changes(self) -> bool:
        return bool(
            self.added
            or self.removed
            or self.type_changed
            or self.alias_changed
            or self.description_changed
            or self.order_changed
        )

    @property
    def has_important_changes(self) -> bool:
        return bool(self.added or self.removed or self.type_changed)


@dataclass(frozen=True)
class DetectedChange:
    database: str
    table: str
    previous_table: str | None
    event_types: tuple[EventType, ...]
    events: tuple[AuditEvent, ...]
    before: TableSnapshot | None
    after: TableSnapshot | None
    diff: SchemaDiff
    change_kind: ChangeKind
    change_id: str
    diff_path: str
    github_diff_url: str
    should_create_issue: bool
    table_id_changed: bool = False

    @property
    def qualified_name(self) -> str:
        return f"{self.database}.{self.table}"


@dataclass(frozen=True)
class RunSummary:
    run_id: str
    dry_run: bool
    bootstrap: bool
    target_count: int
    diff_count: int
    issue_count: int
    planned_file_count: int
    commit_sha: str | None = None

    def as_dict(self) -> dict[str, object]:
        return {
            "run_id": self.run_id,
            "dry_run": self.dry_run,
            "bootstrap": self.bootstrap,
            "target_count": self.target_count,
            "diff_count": self.diff_count,
            "issue_count": self.issue_count,
            "planned_file_count": self.planned_file_count,
            "commit_sha": self.commit_sha,
        }
