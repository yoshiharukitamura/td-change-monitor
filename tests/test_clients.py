from __future__ import annotations

import asyncio
from datetime import UTC, datetime

import httpx
import pytest
import respx
from conftest import make_settings

from td_change_monitor.clients.backlog import BacklogClient
from td_change_monitor.clients.treasure_data import TreasureDataClient
from td_change_monitor.errors import ExternalApiError
from td_change_monitor.models import EventType
from td_change_monitor.time_window import TimeWindow


@respx.mock
def test_backlog_uses_existing_issue_when_change_id_is_found() -> None:
    async def scenario() -> None:
        settings = make_settings()
        list_route = respx.get("https://space.backlog.test/api/v2/issues").mock(
            return_value=httpx.Response(200, json=[{"issueKey": "PRJ-1"}])
        )
        create_route = respx.post("https://space.backlog.test/api/v2/issues").mock(
            return_value=httpx.Response(201, json={"issueKey": "PRJ-2"})
        )
        client = BacklogClient(settings)
        try:
            key = await client.ensure_issue(
                change_id="change-1",
                summary="summary",
                description="description change-1",
            )
        finally:
            await client.aclose()

        assert key == "PRJ-1"
        assert list_route.call_count == 1
        assert create_route.call_count == 0

    asyncio.run(scenario())


@respx.mock
def test_backlog_error_message_does_not_include_api_key() -> None:
    async def scenario() -> None:
        settings = make_settings()
        respx.get("https://space.backlog.test/api/v2/issues").mock(
            return_value=httpx.Response(500, json={"message": "temporary failure"})
        )
        client = BacklogClient(settings)
        try:
            with pytest.raises(ExternalApiError) as exc_info:
                await client.ensure_issue(
                    change_id="change-1",
                    summary="summary",
                    description="description change-1",
                )
        finally:
            await client.aclose()

        message = str(exc_info.value)
        assert "backlog-secret" not in message
        assert "apiKey" not in message

    asyncio.run(scenario())


@respx.mock
def test_treasure_data_fetches_audit_events_through_query_job() -> None:
    async def scenario() -> None:
        settings = make_settings(http_max_retries=1)
        respx.post("https://api.td.test/v3/job/issue/presto/audit_db").mock(
            return_value=httpx.Response(200, json={"job_id": "job-1"})
        )
        respx.get("https://api.td.test/v3/job/status/job-1").mock(
            return_value=httpx.Response(200, json={"status": "success"})
        )
        respx.get("https://api.td.test/v3/job/result/job-1").mock(
            return_value=httpx.Response(
                200,
                json=[
                    {
                        "id": "audit-1",
                        "event_name": "table_modify",
                        "time": 1783900800,
                        "resource_name": "db.table",
                    }
                ],
            )
        )
        client = TreasureDataClient(settings, poll_interval_seconds=0)
        try:
            events = await client.fetch_audit_events(
                TimeWindow(
                    start=datetime(2026, 7, 13, 0, 0, tzinfo=UTC),
                    end=datetime(2026, 7, 13, 1, 0, tzinfo=UTC),
                )
            )
        finally:
            await client.aclose()

        assert len(events) == 1
        assert events[0].event_type == EventType.TABLE_MODIFY
        assert events[0].database == "db"
        assert events[0].table == "table"

    asyncio.run(scenario())


@respx.mock
def test_treasure_data_table_show_parses_schema_json_string() -> None:
    async def scenario() -> None:
        settings = make_settings(http_max_retries=1)
        respx.get("https://api.td.test/v3/table/show/db/table").mock(
            return_value=httpx.Response(
                200,
                json={
                    "id": "table-1",
                    "schema": (
                        '[["customer_id","string","customer_id"],'
                        '["uriage1","double","uriage1","売上"]]'
                    ),
                },
            )
        )
        client = TreasureDataClient(settings)
        try:
            snapshot = await client.fetch_table_snapshot("db", "table")
        finally:
            await client.aclose()

        assert snapshot.table_id == "table-1"
        assert [(c.name, c.type, c.alias, c.description, c.position) for c in snapshot.columns] == [
            ("customer_id", "string", "customer_id", None, 0),
            ("uriage1", "double", "uriage1", "売上", 1),
        ]

    asyncio.run(scenario())


@respx.mock
def test_treasure_data_table_show_accepts_table_name_starting_with_digit() -> None:
    async def scenario() -> None:
        settings = make_settings(http_max_retries=1)
        route = respx.get(
            "https://api.td.test/v3/table/show/l2_emberpoint_output/0426_analytical_grade"
        ).mock(return_value=httpx.Response(200, json={"id": 42, "schema": "[]"}))
        client = TreasureDataClient(settings)
        try:
            snapshot = await client.fetch_table_snapshot(
                "l2_emberpoint_output", "0426_analytical_grade"
            )
        finally:
            await client.aclose()

        assert route.called
        assert snapshot.table_id == "42"

    asyncio.run(scenario())
