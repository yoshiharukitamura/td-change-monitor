from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any


class EventType(StrEnum):
    """監視対象として扱うTD Auditイベント種別を表す。"""
    TABLE_CREATE = "table_create"
    TABLE_MODIFY = "table_modify"
    TABLE_DELETE = "table_delete"
    TABLE_CHANGE_DATABASE = "table_change_database"
    TABLE_SWAP = "table_swap"
    TABLE_IMPORT_CREATE = "table_import_create"


class ChangeKind(StrEnum):
    """複数イベントとNet Diffから決定する最終変更種別を表す。"""
    SCHEMA_CHANGE = "schema_change"
    TABLE_DELETE = "table_delete"
    TABLE_RENAME = "table_rename"
    TABLE_RENAME_SCHEMA_CHANGE = "table_rename_schema_change"
    TABLE_RECREATE = "table_recreate"
    TABLE_RECREATE_SCHEMA_CHANGE = "table_recreate_schema_change"
    AUDIT_ONLY = "audit_only"


@dataclass(frozen=True)
class ColumnDefinition:
    """比較に必要な1カラム分の正規化済み定義を保持する。"""
    name: str
    type: str
    alias: str | None = None
    description: str | None = None
    position: int = 0


@dataclass(frozen=True)
class TableSnapshot:
    """特定時点のtable IDとschemaを保持する。"""
    database: str
    table: str
    columns: tuple[ColumnDefinition, ...]
    table_id: str | None = None


@dataclass(frozen=True)
class WorkflowProjectReference:
    """Workflow一覧に含まれる所属プロジェクトのIDと名前を保持する。"""
    project_id: str
    project_name: str


@dataclass(frozen=True)
class WorkflowDefinitionSummary:
    """Workflow一覧から監視対象の照合に必要な項目だけを保持する。"""
    workflow_id: str
    workflow_name: str
    project: WorkflowProjectReference
    revision: str
    timezone: str


@dataclass(frozen=True)
class WorkflowProjectDetail:
    """Workflowプロジェクトの変更判定に必要な現在情報を保持する。"""
    project_id: str
    project_name: str
    revision: str
    archive_md5: str
    archive_type: str


@dataclass(frozen=True)
class WorkflowReference:
    """schedule一覧・詳細に含まれるWorkflowのIDと名前を保持する。"""
    workflow_id: str
    workflow_name: str


@dataclass(frozen=True)
class WorkflowScheduleDetail:
    """Workflow scheduleの固定識別情報と有効状態を保持する。"""
    schedule_id: str
    project: WorkflowProjectReference
    workflow: WorkflowReference
    enabled: bool


class WorkflowScheduleChangeKind(StrEnum):
    """Workflow scheduleの変更種別を表す。"""

    ADDED = "added"
    DELETED = "deleted"
    MODIFIED = "modified"


@dataclass(frozen=True)
class WorkflowScheduleSnapshot:
    """schedule APIとdig定義から作った比較用の固定状態を保持する。"""

    schedule_id: str
    workflow_id: str
    workflow_name: str
    enabled: bool
    schedule_type: str
    schedule_value: str
    timezone: str
    definition_path: str


@dataclass(frozen=True)
class WorkflowProjectScheduleSnapshot:
    """Workflowプロジェクトに所属するscheduleの正規化済み状態を保持する。"""

    project_id: str
    project_name: str
    schedules: tuple[WorkflowScheduleSnapshot, ...]


@dataclass(frozen=True)
class WorkflowScheduleChange:
    """schedule 1件の追加・削除・設定変更を保持する。"""

    kind: WorkflowScheduleChangeKind
    schedule_id: str
    changed_fields: tuple[str, ...]
    before: WorkflowScheduleSnapshot | None
    after: WorkflowScheduleSnapshot | None


class WorkflowFileChangeKind(StrEnum):
    """Workflow監視ファイルの変更種別を表す。"""

    ADDED = "added"
    DELETED = "deleted"
    MODIFIED = "modified"
    RENAMED = "renamed"


@dataclass(frozen=True)
class WorkflowFileSnapshot:
    """Workflow archive内の監視対象テキストファイルを保持する。"""
    path: str
    content: str
    content_hash: str


@dataclass(frozen=True)
class WorkflowProjectSnapshot:
    """Workflow projectの識別情報と監視対象ファイルを保持する。"""
    project_id: str
    project_name: str
    revision: str
    archive_md5: str
    files: tuple[WorkflowFileSnapshot, ...]


@dataclass(frozen=True)
class WorkflowArchiveInventory:
    """archiveに含まれる拡張子別件数と確認用ファイル例を保持する。"""
    extension_counts: tuple[tuple[str, int], ...]
    examples: tuple[tuple[str, tuple[str, ...]], ...]


@dataclass(frozen=True)
class WorkflowSnapshotLoadResult:
    """Workflow snapshot取得結果とarchive取得有無を保持する。"""
    snapshot: WorkflowProjectSnapshot
    archive_fetched: bool
    inventory: WorkflowArchiveInventory | None


@dataclass(frozen=True)
class WorkflowFileChange:
    """Workflowファイル1件の変更種別と通知要否を保持する。"""
    kind: WorkflowFileChangeKind
    before_path: str | None
    after_path: str | None
    notification_required: bool


@dataclass(frozen=True)
class WorkflowProjectDiff:
    """Workflow project単位に集約したファイル差分を保持する。"""
    project_id: str
    project_name_changed: bool
    file_changes: tuple[WorkflowFileChange, ...]
    schedule_changes: tuple[WorkflowScheduleChange, ...] = ()

    @property
    def has_changes(self) -> bool:
        """project名または監視対象ファイルに差分があるかを返す。

        引数:
            なし。
        戻り値:
            Git証跡対象の差分が1件以上あればTrue。
        """
        return (
            self.project_name_changed
            or bool(self.file_changes)
            or bool(self.schedule_changes)
        )

    @property
    def should_create_issue(self) -> bool:
        """Backlog通知対象となる実質変更があるかを返す。

        引数:
            なし。
        戻り値:
            project名変更または通知対象ファイル差分があればTrue。
        """
        return (
            self.project_name_changed
            or bool(self.schedule_changes)
            or any(change.notification_required for change in self.file_changes)
        )


@dataclass(frozen=True)
class WorkflowDetectedChange:
    """1 Workflowプロジェクトへ集約した日次変更と成果物情報を保持する。"""

    project_id: str
    project_name: str
    before: WorkflowProjectSnapshot | None
    after: WorkflowProjectSnapshot | None
    before_schedules: WorkflowProjectScheduleSnapshot | None
    after_schedules: WorkflowProjectScheduleSnapshot | None
    diff: WorkflowProjectDiff | None
    change_kind: str
    change_id: str
    diff_path: str
    github_diff_url: str
    should_create_issue: bool


@dataclass(frozen=True)
class SavedQueryDatabaseReference:
    """登録クエリが実行対象とするdatabaseのIDと名前を保持する。"""
    database_id: str
    database_name: str


@dataclass(frozen=True)
class SavedQueryOwnerReference:
    """登録クエリ所有者のIDと表示名を保持する。"""
    owner_id: str
    owner_name: str


@dataclass(frozen=True)
class SavedQuerySummary:
    """登録クエリ一覧から取得できる識別情報と設定を保持する。"""
    query_id: str
    query_name: str
    database: SavedQueryDatabaseReference
    owner: SavedQueryOwnerReference
    engine_type: str
    engine_version: str
    connector_config: Mapping[str, Any] | None
    cron: str | None
    timezone: str
    delay: int
    priority: int
    retry_limit: int
    description: str | None
    draft: bool


@dataclass(frozen=True)
class SavedQueryDetail(SavedQuerySummary):
    """登録クエリの変更判定に必要な現在状態とSQL本文を保持する。"""
    query_string: str


@dataclass(frozen=True)
class SavedQueryPage:
    """登録クエリ一覧の1ページと次ページ情報を保持する。"""
    queries: tuple[SavedQuerySummary, ...]
    total_count: int
    has_next_page: bool
    next_page: str | None


@dataclass(frozen=True)
class SavedQuerySnapshot:
    """Gitへ保存できる登録クエリの正規化済み状態を保持する。"""
    query_id: str
    query_name: str
    query_string: str
    database_id: str
    database_name: str
    engine_type: str
    engine_version: str
    connector_type: str | None
    connector_config_hash: str | None
    cron: str | None
    timezone: str
    delay: int
    priority: int
    retry_limit: int


@dataclass(frozen=True)
class SavedQueryDiff:
    """登録クエリのSQL・設定・削除に関する最終差分を保持する。"""
    query_id: str
    sql_changed: bool
    changed_fields: tuple[str, ...]
    deleted: bool

    @property
    def has_changes(self) -> bool:
        """登録クエリに通知・証跡対象の差分があるかを返す。

        引数:
            なし。
        戻り値:
            SQL、設定、削除のいずれかに差分があればTrue。
        """
        return self.sql_changed or bool(self.changed_fields) or self.deleted


@dataclass(frozen=True)
class SavedQueryDetectedChange:
    """1 Query IDへ集約した日次変更と成果物情報を保持する。"""

    query_id: str
    query_name: str
    before: SavedQuerySnapshot
    after: SavedQuerySnapshot | None
    diff: SavedQueryDiff
    change_id: str
    diff_path: str
    github_diff_url: str
    should_create_issue: bool


@dataclass(frozen=True)
class AuditEvent:
    """TD Audit Logの1レコードを安全な型へ変換したイベントを保持する。"""
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
    """変更前後のschemaから検出した差分を分類して保持する。"""
    added: tuple[ColumnDefinition, ...]
    removed: tuple[ColumnDefinition, ...]
    type_changed: tuple[tuple[str, str, str], ...]
    alias_changed: tuple[tuple[str, str | None, str | None], ...] = ()
    description_changed: tuple[tuple[str, str | None, str | None], ...] = ()
    order_changed: tuple[tuple[str, int, int], ...] = ()

    @property
    def has_changes(self) -> bool:
        """いずれかのschema差分があるかを返す。

        引数:
            なし。
        戻り値:
            差分が1件以上あればTrue。
        """
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
        """Backlog通知対象となる重要なschema差分があるかを返す。

        引数:
            なし。
        戻り値:
            カラム追加・削除・型変更のいずれかがあればTrue。
        """
        return bool(self.added or self.removed or self.type_changed)


@dataclass(frozen=True)
class DetectedChange:
    """1論理テーブルに集約した最終変更判定と成果物情報を保持する。"""
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
        """database名とtable名を連結した完全修飾名を返す。

        引数:
            なし。
        戻り値:
            `database.table`形式の文字列。
        """
        return f"{self.database}.{self.table}"


@dataclass(frozen=True)
class RunSummary:
    """1回のバッチ実行結果を件数中心に保持する。"""
    run_id: str
    dry_run: bool
    bootstrap: bool
    target_count: int
    diff_count: int
    issue_count: int
    planned_file_count: int
    baseline_count: int = 0
    commit_sha: str | None = None

    def as_dict(self) -> dict[str, object]:
        """実行結果をJSON出力可能な辞書へ変換する。

        引数:
            なし。
        戻り値:
            CLI出力と構造化ログに使用する辞書。
        """
        return {
            "run_id": self.run_id,
            "dry_run": self.dry_run,
            "bootstrap": self.bootstrap,
            "target_count": self.target_count,
            "diff_count": self.diff_count,
            "issue_count": self.issue_count,
            "planned_file_count": self.planned_file_count,
            "baseline_count": self.baseline_count,
            "commit_sha": self.commit_sha,
        }
