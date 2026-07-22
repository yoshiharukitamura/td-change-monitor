from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Any

import yaml
from pydantic import AliasChoices, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

from td_change_monitor.audit import AuditColumnConfig

_SQL_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_TD_RESOURCE_NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
_QUALIFIED_TABLE_RE = re.compile(r"^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$")


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

    http_connect_timeout_seconds: float = 10
    http_read_timeout_seconds: float = 60
    http_max_retries: int = 3

    td_api_base_url: str
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
