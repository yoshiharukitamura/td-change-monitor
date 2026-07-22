from __future__ import annotations

import asyncio
import json
from collections.abc import Mapping
from datetime import datetime
from typing import Any

import httpx

from td_change_monitor.audit import events_from_records
from td_change_monitor.clients.http import RetryingHttpClient, build_timeout
from td_change_monitor.config import (
    Settings,
    validate_sql_identifier,
    validate_td_resource_name,
)
from td_change_monitor.diff import schema_columns_from_raw
from td_change_monitor.errors import ExternalApiError
from td_change_monitor.models import AuditEvent, EventType, TableSnapshot
from td_change_monitor.time_window import TimeWindow


class TreasureDataClient:
    """TD Query APIとTable APIから監視に必要な情報だけを取得する。"""

    def __init__(
        self,
        settings: Settings,
        *,
        client: httpx.AsyncClient | None = None,
        poll_interval_seconds: float = 1,
        max_poll_attempts: int = 120,
    ) -> None:
        """認証済みTD用HTTPクライアントを初期化する。

        引数:
            settings: TD接続先、認証、Audit列設定を含む設定。
            client: テストなどで注入するhttpxクライアント。
            poll_interval_seconds: Query Job状態を確認する間隔秒数。
        戻り値:
            なし。
        """
        self._settings = settings
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=settings.td_api_base_url.rstrip("/"),
            timeout=build_timeout(
                settings.http_connect_timeout_seconds,
                settings.http_read_timeout_seconds,
            ),
            headers={"Authorization": f"TD1 {settings.td_api_key.get_secret_value()}"},
        )
        self._http = RetryingHttpClient(self._client, max_retries=settings.http_max_retries)
        self._poll_interval_seconds = poll_interval_seconds
        self._max_poll_attempts = max_poll_attempts

    async def fetch_audit_events(self, window: TimeWindow) -> list[AuditEvent]:
        """指定時間範囲のAuditイベントをQuery Job経由で取得する。

        引数:
            window: 半開区間で指定するAudit検索範囲。
        戻り値:
            重複除去・型変換済みAuditEvent一覧。
        """
        query = self._build_audit_query(window)
        job_id = await self._issue_query(query)
        await self._wait_for_job(job_id)
        records = await self._fetch_job_result(job_id)
        return events_from_records(records, self._settings.audit_columns)

    async def fetch_table_snapshot(self, database: str, table: str) -> TableSnapshot:
        """Table APIから指定tableの現在IDとschemaを取得する。

        引数:
            database: 取得対象のdatabase名。
            table: 取得対象のtable名。
        戻り値:
            正規化した現在のTableSnapshot。
        """
        validate_td_resource_name(database)
        validate_td_resource_name(table)
        response = await self._http.request("GET", f"table/show/{database}/{table}")
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD table response")
        return _snapshot_from_td_payload(payload, database=database, table=table)

    async def aclose(self) -> None:
        """内部で生成したHTTP接続を閉じる。

        引数:
            なし。
        戻り値:
            なし。
        """
        if self._owns_client:
            await self._client.aclose()

    def _build_audit_query(self, window: TimeWindow) -> str:
        """Audit Logから必要列だけを取得するPresto SQLを組み立てる。

        引数:
            window: SQLのWHERE句へ設定する半開時間範囲。
        戻り値:
            識別子検証済みのSELECT文。
        """
        columns = self._settings.audit_columns
        identifiers = [
            self._settings.td_audit_database,
            self._settings.td_audit_table,
            columns.id_column,
            columns.time_column,
            columns.event_column,
            columns.event_result_column,
            columns.resource_name_column,
            columns.resource_id_column,
            columns.request_path_column,
            columns.request_http_verb_column,
            columns.user_column,
            columns.source_user_column,
            columns.attribute_column,
            columns.old_value_column,
            columns.new_value_column,
            columns.target_resource_name_column,
        ]
        for identifier in identifiers:
            validate_sql_identifier(identifier)

        event_values = ", ".join(
            f"'{event.value}'"
            for event in (
                EventType.TABLE_CREATE,
                EventType.TABLE_MODIFY,
                EventType.TABLE_DELETE,
                EventType.TABLE_IMPORT_CREATE,
            )
        )
        start_value = _sql_time_literal(window.start, columns.time_unit)
        end_value = _sql_time_literal(window.end, columns.time_unit)
        select_columns = ", ".join(identifiers[2:])
        return (
            f"SELECT {select_columns} "
            f"FROM {self._settings.td_audit_database}.{self._settings.td_audit_table} "
            f"WHERE {columns.time_column} >= {start_value} "
            f"AND {columns.time_column} < {end_value} "
            f"AND {columns.event_column} IN ({event_values}) "
            f"ORDER BY {columns.time_column} ASC"
        )

    async def _issue_query(self, query: str) -> str:
        """TD Query APIへSQLを発行してJob IDを取得する。

        引数:
            query: 実行するPresto SQL。
        戻り値:
            TDが発行したJob ID。
        """
        validate_sql_identifier(self._settings.td_query_engine)
        validate_sql_identifier(self._settings.td_audit_database)
        response = await self._http.request(
            "POST",
            f"job/issue/{self._settings.td_query_engine}/{self._settings.td_audit_database}",
            data={"query": query},
        )
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD job issue response")
        job_id = payload.get("job_id") or payload.get("jobId") or payload.get("id")
        if not isinstance(job_id, str | int):
            raise ExternalApiError("TD job issue response did not include job_id")
        return str(job_id)

    async def _wait_for_job(self, job_id: str) -> None:
        """Query Jobが成功または失敗状態になるまで待機する。

        引数:
            job_id: 状態確認するTD Job ID。
        戻り値:
            なし。成功時に戻り、失敗時は例外を送出する。
        """
        for _ in range(self._max_poll_attempts):
            response = await self._http.request("GET", f"job/status/{job_id}")
            payload = response.json()
            if not isinstance(payload, Mapping):
                raise ExternalApiError("invalid TD job status response")
            status = str(payload.get("status", "")).lower()
            if status in {"success", "finished"}:
                return
            if status in {"error", "failed", "killed"}:
                raise ExternalApiError(f"TD job {job_id} failed with status {status}")
            await asyncio.sleep(self._poll_interval_seconds)
        raise ExternalApiError(f"TD job {job_id} did not finish before poll limit", transient=True)

    async def _fetch_job_result(self, job_id: str) -> list[Mapping[str, Any]]:
        """Query Job結果を列名付きレコード一覧へ変換する。

        引数:
            job_id: 結果取得するTD Job ID。
        戻り値:
            JSON配列またはJSON Linesを解析したレコード一覧。
        """
        response = await self._http.request(
            "GET",
            f"job/result/{job_id}",
            params={"format": "json"},
        )
        try:
            payload = response.json()
        except json.JSONDecodeError:
            payload = _json_lines_from_td_result(response.text)
        return _records_from_td_result(
            payload,
            expected_columns=_audit_result_columns(self._settings),
        )


def _sql_time_literal(value: datetime, unit: str) -> str:
    """Audit時刻列の単位に合わせてSQLリテラルを作る。

    引数:
        value: SQLへ埋め込むタイムゾーン付き時刻。
        unit: epoch_secondsまたはISO時刻指定。
    戻り値:
        数値epoch秒または引用符付きISO文字列。
    """
    if unit == "epoch_seconds":
        return str(int(value.timestamp()))
    return f"'{value.isoformat()}'"


def _records_from_td_result(
    payload: object,
    *,
    expected_columns: list[str] | None = None,
) -> list[Mapping[str, Any]]:
    """TD Job結果の複数JSON形式を辞書レコードへ統一する。

    引数:
        payload: JSON解析後のJob結果。
        expected_columns: 配列行へ対応付ける列名一覧。
    戻り値:
        列名をキーに持つレコード一覧。
    """
    if isinstance(payload, list):
        if all(isinstance(item, Mapping) for item in payload):
            return [_ensure_mapping(item) for item in payload]
        if expected_columns is not None:
            if len(payload) == len(expected_columns) and not any(
                isinstance(item, (list, Mapping)) for item in payload
            ):
                return [_row_to_mapping(expected_columns, payload)]
            return [_row_to_mapping(expected_columns, row) for row in payload]
    if isinstance(payload, Mapping):
        rows = payload.get("rows") or payload.get("results")
        if isinstance(rows, list):
            if rows and all(isinstance(item, Mapping) for item in rows):
                return [_ensure_mapping(item) for item in rows]
            columns = payload.get("columns")
            if isinstance(columns, list):
                names = [str(column) for column in columns]
                return [_row_to_mapping(names, row) for row in rows]
    raise ExternalApiError("invalid TD job result response")


def _json_lines_from_td_result(text: str) -> list[object]:
    """改行区切りJSON形式のTD Job結果を行ごとに解析する。

    引数:
        text: Job result APIのレスポンス本文。
    戻り値:
        空行を除外してJSON解析した行一覧。
    """
    rows: list[object] = []
    try:
        for line in text.splitlines():
            if line.strip():
                rows.append(json.loads(line))
    except json.JSONDecodeError as exc:
        raise ExternalApiError("invalid TD job result JSON lines") from exc
    return rows


def _audit_result_columns(settings: Settings) -> list[str]:
    """Audit SQLのSELECT順と一致する列名一覧を返す。

    引数:
        settings: Audit列名設定を含むSettings。
    戻り値:
        TD配列行を辞書へ変換するための列名一覧。
    """
    columns = settings.audit_columns
    return [
        columns.id_column,
        columns.time_column,
        columns.event_column,
        columns.event_result_column,
        columns.resource_name_column,
        columns.resource_id_column,
        columns.request_path_column,
        columns.request_http_verb_column,
        columns.user_column,
        columns.source_user_column,
        columns.attribute_column,
        columns.old_value_column,
        columns.new_value_column,
        columns.target_resource_name_column,
    ]


def _snapshot_from_td_payload(
    payload: Mapping[str, Any],
    *,
    database: str,
    table: str,
) -> TableSnapshot:
    """Table APIレスポンスから必要なIDとschemaだけをsnapshotへ変換する。

    引数:
        payload: Table APIレスポンスのJSONオブジェクト。
        database: リクエストしたdatabase名。
        table: リクエストしたtable名。
    戻り値:
        カラム定義とtable IDを持つTableSnapshot。
    """
    raw_columns = payload.get("schema") if "schema" in payload else payload.get("columns")
    if raw_columns is None:
        raise ExternalApiError("TD table response did not include columns")
    try:
        columns = schema_columns_from_raw(raw_columns)
    except ValueError as exc:
        raise ExternalApiError(str(exc)) from exc
    table_id = payload.get("id") or payload.get("table_id")
    return TableSnapshot(
        database=database,
        table=table,
        columns=tuple(columns),
        table_id=str(table_id) if table_id is not None else None,
    )


def _ensure_mapping(value: object) -> Mapping[str, Any]:
    """任意値がJSONオブジェクト形式かを検証する。

    引数:
        value: 検証対象の値。
    戻り値:
        Mapping型として確認した値。
    """
    if not isinstance(value, Mapping):
        raise ExternalApiError("expected mapping record")
    return value


def _row_to_mapping(columns: list[str], row: object) -> Mapping[str, Any]:
    """TDの配列行へSELECT列名を対応付ける。

    引数:
        columns: SELECT句と同じ順序の列名一覧。
        row: TD Job結果の1配列行。
    戻り値:
        列名と値を対応付けた辞書。
    """
    if not isinstance(row, list):
        raise ExternalApiError("expected row list")
    return dict(zip(columns, row, strict=False))
