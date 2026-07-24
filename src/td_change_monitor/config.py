from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Annotated, Any

import yaml
from pydantic import AliasChoices, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

from td_change_monitor.audit import AuditColumnConfig

_SQL_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_TD_RESOURCE_NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
_QUALIFIED_TABLE_RE = re.compile(r"^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$")


class MonitorStatus(StrEnum):
    """棚卸し結果に基づくリソースの監視状態を表す。"""

    MONITOR = "monitor"
    EVIDENCE_ONLY = "evidence_only"
    EXCLUDE = "exclude"
    NEEDS_REVIEW = "needs_review"


class Settings(BaseSettings):
    """環境変数と.envから読み込むバッチ全体の設定を保持する。"""
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    app_env: str = "local"
    log_level: str = "INFO"
    display_timezone: str = "Asia/Tokyo"
    audit_log_lag_minutes: int = 10
    audit_log_overlap_minutes: int = 30
    max_changed_tables_per_run: int = 250
    processed_id_retention_days: int = Field(default=7, ge=1)
    local_log_retention_days: int = Field(default=30, ge=1)
    max_generated_file_size_mb: int = Field(default=5, ge=1)
    workflow_archive_max_total_size_mb: int = Field(default=100, ge=1)

    http_connect_timeout_seconds: float = 10
    http_read_timeout_seconds: float = 60
    http_max_retries: int = 3

    td_api_base_url: str
    td_workflow_api_base_url: str = "https://api-workflow.treasuredata.co.jp"
    td_console_api_base_url: str = "https://console.treasuredata.co.jp"
    td_api_key: SecretStr
    td_query_engine: str = "presto"
    td_audit_database: str = "td_audit_log"
    td_audit_table: str = "access"
    td_audit_id_column: str = "id"
    td_audit_time_column: str = "time"
    td_audit_event_column: str = "event_name"
    td_audit_event_result_column: str = "event_result"
    td_audit_resource_name_column: str = "resource_name"
    td_audit_resource_id_column: str = "resource_id"
    td_audit_request_path_column: str = "requested_path_info"
    td_audit_request_http_verb_column: str = "requested_http_verb"
    td_audit_user_column: str = "user_email"
    td_audit_source_user_column: str = "source_user_email"
    td_audit_attribute_column: str = "attribute_name"
    td_audit_old_value_column: str = "old_value"
    td_audit_new_value_column: str = "new_value"
    td_audit_target_resource_name_column: str = "target_resource_name"
    td_audit_time_unit: str = "epoch_seconds"

    git_repository_path: Path = Path(".")
    git_remote_name: str = "origin"
    git_branch: str = Field(
        default="main",
        validation_alias=AliasChoices("GIT_BRANCH", "GITHUB_BRANCH"),
    )
    git_executable: str = "git"
    git_committer_name: str = Field(
        default="TD Change Monitor",
        validation_alias=AliasChoices("GIT_COMMITTER_NAME", "GITHUB_COMMITTER_NAME"),
    )
    git_committer_email: str = Field(
        default="td-change-monitor@example.com",
        validation_alias=AliasChoices("GIT_COMMITTER_EMAIL", "GITHUB_COMMITTER_EMAIL"),
    )
    github_repository_url: str = ""
    github_owner: str | None = None
    github_repo: str | None = None

    backlog_base_url: str
    backlog_api_key: SecretStr
    backlog_project_id: int
    backlog_issue_type_id: int
    backlog_priority_id: int
    backlog_assignee_id: int | None = None
    backlog_category_ids: Annotated[list[int], NoDecode] = Field(default_factory=list)

    @field_validator("backlog_category_ids", mode="before")
    @classmethod
    def _parse_category_ids(cls, value: object) -> object:
        """BacklogカテゴリIDのカンマ区切り文字列を整数タプルへ変換する。

        引数:
            value: 環境変数または既に解析済みの設定値。
        戻り値:
            文字列なら整数タプル、それ以外なら元の値。
        """
        if value is None or value == "":
            return []
        if isinstance(value, str):
            return [int(item.strip()) for item in value.split(",") if item.strip()]
        return value

    @field_validator("backlog_assignee_id", mode="before")
    @classmethod
    def _parse_optional_int(cls, value: object) -> object:
        """空文字の任意整数設定をNoneへ変換する。

        引数:
            value: 環境変数から得た設定値。
        戻り値:
            空文字ならNone、それ以外なら元の値。
        """
        if value == "":
            return None
        return value

    @model_validator(mode="after")
    def _build_legacy_github_repository_url(self) -> Settings:
        """旧設定値がある場合にBacklog差分リンク用URLを補完する。

        引数:
            なし。
        戻り値:
            URL補完後の同じSettingsインスタンス。
        """
        if not self.github_repository_url and self.github_owner and self.github_repo:
            self.github_repository_url = (
                f"https://github.com/{self.github_owner}/{self.github_repo}"
            )
        if not self.github_repository_url:
            raise ValueError("GITHUB_REPOSITORY_URL is required")
        return self

    @property
    def audit_columns(self) -> AuditColumnConfig:
        """Audit Log解析用の列名設定をまとめて返す。

        引数:
            なし。
        戻り値:
            Settings内の列名と時刻単位から作ったAuditColumnConfig。
        """
        return AuditColumnConfig(
            id_column=self.td_audit_id_column,
            time_column=self.td_audit_time_column,
            event_column=self.td_audit_event_column,
            event_result_column=self.td_audit_event_result_column,
            resource_name_column=self.td_audit_resource_name_column,
            resource_id_column=self.td_audit_resource_id_column,
            request_path_column=self.td_audit_request_path_column,
            request_http_verb_column=self.td_audit_request_http_verb_column,
            user_column=self.td_audit_user_column,
            source_user_column=self.td_audit_source_user_column,
            attribute_column=self.td_audit_attribute_column,
            old_value_column=self.td_audit_old_value_column,
            new_value_column=self.td_audit_new_value_column,
            target_resource_name_column=self.td_audit_target_resource_name_column,
            time_unit=self.td_audit_time_unit,
        )


@dataclass(frozen=True)
class TargetTablesConfig:
    """監視対象table、除外パターン、bootstrap対象を保持する。"""
    monitored_tables: tuple[tuple[str, str], ...]
    exclude_table_patterns: tuple[str, ...]
    bootstrap_tables: tuple[str, ...]

    def includes(self, database: str, table: str) -> bool:
        """指定tableが許可リストに含まれ、除外対象でないかを判定する。

        引数:
            database: 判定するdatabase名。
            table: 判定するtable名。
        戻り値:
            監視対象ならTrue。
        """
        qualified = f"{database}.{table}"
        monitored = {f"{db}.{name}" for db, name in self.monitored_tables}
        if qualified not in monitored:
            return False
        return not any(re.search(pattern, table) for pattern in self.exclude_table_patterns)

    def includes_any(self, database: str, *tables: str | None) -> bool:
        """rename前後名のいずれかが監視対象かを判定する。

        引数:
            database: 判定するdatabase名。
            tables: 判定候補のtable名列。Noneは無視する。
        戻り値:
            1件以上が監視対象ならTrue。
        """
        return any(table is not None and self.includes(database, table) for table in tables)

    def bootstrap_targets(self) -> tuple[tuple[str, str], ...]:
        """初回snapshotを取得するtable一覧を返す。

        引数:
            なし。
        戻り値:
            bootstrap専用指定があればその一覧、なければ監視対象一覧。
        """
        tables = self.bootstrap_tables or tuple(
            f"{database}.{table}" for database, table in self.monitored_tables
        )
        return tuple(_split_qualified_table(item) for item in tables)


@dataclass(frozen=True)
class WorkflowProjectTarget:
    """Workflowプロジェクトの安定IDと棚卸し対象を保持する。"""

    project_name: str
    project_id: str | None
    target_workflows: tuple[str, ...]
    target_schedule_ids: tuple[str, ...]
    monitor_status: MonitorStatus

    @property
    def is_active(self) -> bool:
        """日次バッチで現在状態を取得する対象かを返す。

        引数:
            なし。
        戻り値:
            monitorまたはevidence_onlyでproject IDが確定していればTrue。
        """
        return (
            self.monitor_status
            in {MonitorStatus.MONITOR, MonitorStatus.EVIDENCE_ONLY}
            and self.project_id is not None
        )


@dataclass(frozen=True)
class SavedQueryTarget:
    """登録クエリの安定IDと初回照合情報を保持する。"""

    query_id: str | None
    query_name: str
    database: str
    owner: str
    monitor_status: MonitorStatus

    @property
    def is_active(self) -> bool:
        """日次バッチで現在状態を取得する対象かを返す。

        引数:
            なし。
        戻り値:
            monitorまたはevidence_onlyでQuery IDが確定していればTrue。
        """
        return (
            self.monitor_status
            in {MonitorStatus.MONITOR, MonitorStatus.EVIDENCE_ONLY}
            and self.query_id is not None
        )


@dataclass(frozen=True)
class ResourceTargetsConfig:
    """Workflowプロジェクトと登録クエリの監視対象マスターを保持する。"""

    workflow_projects: tuple[WorkflowProjectTarget, ...]
    saved_queries: tuple[SavedQueryTarget, ...]

    def active_workflow_projects(self) -> tuple[WorkflowProjectTarget, ...]:
        """日次処理対象のWorkflowプロジェクトを返す。

        引数:
            なし。
        戻り値:
            project IDが確定したmonitor・evidence_only対象。
        """
        return tuple(target for target in self.workflow_projects if target.is_active)

    def active_saved_queries(self) -> tuple[SavedQueryTarget, ...]:
        """日次処理対象の登録クエリを返す。

        引数:
            なし。
        戻り値:
            Query IDが確定したmonitor・evidence_only対象。
        """
        return tuple(target for target in self.saved_queries if target.is_active)


def load_target_tables_config(path: str | Path = "config/target_tables.yml") -> TargetTablesConfig:
    """YAMLファイルから監視対象設定を読み込み検証する。

    引数:
        path: 対象table設定YAMLのパス。
    戻り値:
        重複除去・形式検証済みTargetTablesConfig。
    """
    config_path = Path(path)
    payload = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if not isinstance(payload, dict):
        raise ValueError("target table config must be a mapping")

    include = _mapping(payload.get("include"))
    exclude = _mapping(payload.get("exclude"))
    bootstrap = _mapping(payload.get("bootstrap"))

    monitored_tables = _monitored_tables(payload.get("monitored_tables"))
    include_tables = _string_tuple(include.get("tables"))
    if not monitored_tables and include_tables:
        monitored_tables = tuple(_split_qualified_table(item) for item in include_tables)
    exclude_patterns = _string_tuple(exclude.get("table_patterns"))
    bootstrap_tables = _string_tuple(bootstrap.get("tables"))

    for database, table in monitored_tables:
        validate_td_resource_name(database)
        validate_td_resource_name(table)
    for table in bootstrap_tables:
        validate_qualified_table(table)
    for pattern in exclude_patterns:
        re.compile(pattern)

    return TargetTablesConfig(
        monitored_tables=monitored_tables,
        exclude_table_patterns=exclude_patterns,
        bootstrap_tables=bootstrap_tables,
    )


def load_resource_targets_config(
    path: str | Path = "config/resource_targets.yml",
) -> ResourceTargetsConfig:
    """YAMLからWorkflowと登録クエリの監視対象マスターを読み込む。

    引数:
        path: Git管理する追加リソース対象マスターのパス。
    戻り値:
        ID重複とstatus整合性を検証したResourceTargetsConfig。
    """
    config_path = Path(path)
    if not config_path.exists():
        return ResourceTargetsConfig(workflow_projects=(), saved_queries=())
    payload = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if not isinstance(payload, dict):
        raise ValueError("resource target config must be a mapping")

    workflow_projects = _workflow_project_targets(payload.get("workflow_projects"))
    saved_queries = _saved_query_targets(payload.get("saved_queries"))
    _validate_unique_optional_ids(
        (target.project_id for target in workflow_projects),
        "Workflow project ID",
    )
    _validate_unique_optional_ids(
        (target.query_id for target in saved_queries),
        "saved query ID",
    )
    return ResourceTargetsConfig(
        workflow_projects=workflow_projects,
        saved_queries=saved_queries,
    )


def validate_sql_identifier(identifier: str) -> str:
    """SQLへ埋め込む識別子が安全な英数字とアンダースコアだけか検証する。

    引数:
        identifier: 検証対象の列名または識別子。
    戻り値:
        検証に成功した元の文字列。
    """
    if not _SQL_IDENTIFIER_RE.fullmatch(identifier):
        raise ValueError(f"invalid SQL identifier: {identifier!r}")
    return identifier


def validate_td_resource_name(name: str) -> str:
    """TDのdatabaseまたはtable名として許可する形式か検証する。

    引数:
        name: 検証対象のresource名。
    戻り値:
        検証に成功した元の文字列。
    """
    if not _TD_RESOURCE_NAME_RE.fullmatch(name):
        raise ValueError(f"invalid TD resource name: {name!r}")
    return name


def validate_qualified_table(value: str) -> str:
    """`database.table`形式の完全修飾名を検証する。

    引数:
        value: 検証対象の完全修飾table名。
    戻り値:
        検証に成功した元の文字列。
    """
    if not _QUALIFIED_TABLE_RE.fullmatch(value):
        raise ValueError(f"invalid qualified table: {value!r}")
    database, table = value.split(".", 1)
    validate_td_resource_name(database)
    validate_td_resource_name(table)
    return value


def _mapping(value: object) -> dict[str, Any]:
    """YAML値を文字列キーの辞書として検証する。

    引数:
        value: YAMLから読み込んだ任意値。
    戻り値:
        Noneなら空辞書、Mappingなら通常の辞書。
    """
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("expected mapping")
    return value


def _string_tuple(value: object) -> tuple[str, ...]:
    """YAMLの文字列配列をタプルへ変換する。

    引数:
        value: YAMLから読み込んだ配列またはNone。
    戻り値:
        検証済み文字列タプル。
    """
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ValueError("expected list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise ValueError("expected string list item")
        if item:
            result.append(item)
    return tuple(result)


def _split_qualified_table(value: str) -> tuple[str, str]:
    """完全修飾table名をdatabase名とtable名へ分割する。

    引数:
        value: `database.table`形式の文字列。
    戻り値:
        database名とtable名のタプル。
    """
    validate_qualified_table(value)
    database, table = value.split(".", 1)
    return database, table


def _monitored_tables(value: object) -> tuple[tuple[str, str], ...]:
    """YAMLの監視対象定義をdatabase・tableのタプル列へ変換する。

    引数:
        value: 文字列形式または辞書形式を含むYAML配列。
    戻り値:
        重複除去前の検証済みtable識別子列。
    """
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ValueError("monitored_tables must be a list")
    tables: list[tuple[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            raise ValueError("monitored_tables items must be mappings")
        database = item.get("database")
        table = item.get("table")
        if not isinstance(database, str) or not isinstance(table, str):
            raise ValueError("monitored_tables items require database and table")
        validate_td_resource_name(database)
        validate_td_resource_name(table)
        tables.append((database, table))
    return tuple(tables)


def _workflow_project_targets(value: object) -> tuple[WorkflowProjectTarget, ...]:
    """YAMLのWorkflowプロジェクト対象を型付き設定へ変換する。

    引数:
        value: `workflow_projects`配列またはNone。
    戻り値:
        statusとID整合性を検証したWorkflowProjectTarget列。
    """
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ValueError("workflow_projects must be a list")
    targets: list[WorkflowProjectTarget] = []
    for item in value:
        if not isinstance(item, dict):
            raise ValueError("workflow_projects items must be mappings")
        project_name = _required_config_string(item, "project_name")
        project_id = _optional_digit_id(item.get("project_id"), "project_id")
        status = _monitor_status(item.get("monitor_status"))
        _validate_resolved_status(project_id, status, "Workflow project")
        workflows = _config_string_tuple(item.get("target_workflows"))
        schedule_ids = _config_string_tuple(item.get("target_schedule_ids"))
        if any(not schedule_id.isdigit() for schedule_id in schedule_ids):
            raise ValueError("target_schedule_ids must contain digits only")
        targets.append(
            WorkflowProjectTarget(
                project_name=project_name,
                project_id=project_id,
                target_workflows=tuple(sorted(set(workflows))),
                target_schedule_ids=tuple(
                    sorted(set(schedule_ids), key=lambda item: (len(item), item))
                ),
                monitor_status=status,
            )
        )
    return tuple(sorted(targets, key=lambda item: item.project_name))


def _saved_query_targets(value: object) -> tuple[SavedQueryTarget, ...]:
    """YAMLの登録クエリ対象を型付き設定へ変換する。

    引数:
        value: `saved_queries`配列またはNone。
    戻り値:
        statusとID整合性を検証したSavedQueryTarget列。
    """
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ValueError("saved_queries must be a list")
    targets: list[SavedQueryTarget] = []
    for item in value:
        if not isinstance(item, dict):
            raise ValueError("saved_queries items must be mappings")
        query_id = _optional_digit_id(item.get("query_id"), "query_id")
        status = _monitor_status(item.get("monitor_status"))
        _validate_resolved_status(query_id, status, "saved query")
        targets.append(
            SavedQueryTarget(
                query_id=query_id,
                query_name=_required_config_string(
                    item,
                    "query_name",
                    preserve_whitespace=True,
                ),
                database=_required_config_string(item, "database"),
                owner=_required_config_string(item, "owner"),
                monitor_status=status,
            )
        )
    return tuple(
        sorted(
            targets,
            key=lambda item: (
                item.query_id is None,
                len(item.query_id or ""),
                item.query_id or "",
                item.query_name,
            ),
        )
    )


def _required_config_string(
    payload: dict[str, Any],
    key: str,
    *,
    preserve_whitespace: bool = False,
) -> str:
    """設定mappingの必須文字列を取得する。

    引数:
        payload: YAMLの1対象を表すmapping。
        key: 取得する項目名。
        preserve_whitespace: 登録クエリ名の先頭空白を保持するかどうか。
    戻り値:
        空でない文字列。
    """
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return value if preserve_whitespace else value.strip()


def _optional_digit_id(value: object, key: str) -> str | None:
    """任意IDを数字文字列またはNoneへ正規化する。

    引数:
        value: YAMLのID値。
        key: エラー表示用の項目名。
    戻り値:
        数字だけの文字列。nullまたは空文字ならNone。
    """
    if value is None or value == "":
        return None
    if isinstance(value, bool) or not isinstance(value, str | int):
        raise ValueError(f"{key} must be a digit string or null")
    normalized = str(value)
    if not normalized.isdigit():
        raise ValueError(f"{key} must contain digits only")
    return normalized


def _monitor_status(value: object) -> MonitorStatus:
    """YAMLのmonitor_statusを列挙値へ変換する。

    引数:
        value: status文字列。
    戻り値:
        対応するMonitorStatus。
    """
    if not isinstance(value, str):
        raise ValueError("monitor_status must be a string")
    try:
        return MonitorStatus(value)
    except ValueError as exc:
        raise ValueError(f"unsupported monitor_status: {value}") from exc


def _validate_resolved_status(
    resource_id: str | None,
    status: MonitorStatus,
    resource_name: str,
) -> None:
    """ID未確定の対象が監視状態へ入ることを拒否する。

    引数:
        resource_id: 安定IDまたはNone。
        status: 対象のmonitor_status。
        resource_name: エラー表示用のリソース種別。
    戻り値:
        なし。
    """
    if resource_id is None and status in {
        MonitorStatus.MONITOR,
        MonitorStatus.EVIDENCE_ONLY,
    }:
        raise ValueError(f"{resource_name} without ID must use needs_review or exclude")


def _config_string_tuple(value: object) -> tuple[str, ...]:
    """設定内の任意文字列配列を空要素なしのタプルへ変換する。

    引数:
        value: YAML配列またはNone。
    戻り値:
        前後空白を除いた文字列タプル。
    """
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ValueError("expected string list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise ValueError("expected non-empty string list item")
        result.append(item.strip())
    return tuple(result)


def _validate_unique_optional_ids(
    values: Iterable[str | None],
    label: str,
) -> None:
    """Noneを除く安定IDに重複がないことを確認する。

    引数:
        values: ID列を反復できる値。
        label: エラー表示用のID種別。
    戻り値:
        なし。
    """
    seen: set[str] = set()
    for value in values:
        if value is None:
            continue
        if value in seen:
            raise ValueError(f"duplicate {label}: {value}")
        seen.add(value)
