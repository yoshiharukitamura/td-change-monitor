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
    def __init__(
        self,
        settings: Settings,
        *,
        client: httpx.AsyncClient | None = None,
        poll_interval_seconds: float = 1,
        max_poll_attempts: int = 120,
    ) -> None:
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
        query = self._build_audit_query(window)
        job_id = await self._issue_query(query)
        await self._wait_for_job(job_id)
        records = await self._fetch_job_result(job_id)
        return events_from_records(records, self._settings.audit_columns)

    async def fetch_table_snapshot(self, database: str, table: str) -> TableSnapshot:
        validate_td_resource_name(database)
        validate_td_resource_name(table)
        response = await self._http.request("GET", f"table/show/{database}/{table}")
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD table response")
        return _snapshot_from_td_payload(payload, database=database, table=table)

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    def _build_audit_query(self, window: TimeWindow) -> str:
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
    if unit == "epoch_seconds":
        return str(int(value.timestamp()))
    return f"'{value.isoformat()}'"


def _records_from_td_result(
    payload: object,
    *,
    expected_columns: list[str] | None = None,
) -> list[Mapping[str, Any]]:
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
    rows: list[object] = []
    try:
        for line in text.splitlines():
            if line.strip():
                rows.append(json.loads(line))
    except json.JSONDecodeError as exc:
        raise ExternalApiError("invalid TD job result JSON lines") from exc
    return rows


def _audit_result_columns(settings: Settings) -> list[str]:
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
    if not isinstance(value, Mapping):
        raise ExternalApiError("expected mapping record")
    return value


def _row_to_mapping(columns: list[str], row: object) -> Mapping[str, Any]:
    if not isinstance(row, list):
        raise ExternalApiError("expected row list")
    return dict(zip(columns, row, strict=False))
