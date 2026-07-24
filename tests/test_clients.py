from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from pathlib import Path

import httpx
import pytest
import respx
from conftest import make_settings

from td_change_monitor.clients.backlog import BacklogClient
from td_change_monitor.clients.treasure_data import TreasureDataClient
from td_change_monitor.clients.treasure_data_saved_query import (
    TreasureDataSavedQueryClient,
)
from td_change_monitor.clients.treasure_data_workflow import TreasureDataWorkflowClient
from td_change_monitor.errors import ExternalApiError
from td_change_monitor.models import EventType
from td_change_monitor.time_window import TimeWindow

FIXTURES = Path(__file__).parent / "fixtures"


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
def test_treasure_data_parses_json_lines_array_job_result() -> None:
    async def scenario() -> None:
        settings = make_settings(http_max_retries=1)
        respx.post("https://api.td.test/v3/job/issue/presto/audit_db").mock(
            return_value=httpx.Response(200, json={"job_id": "job-jsonl"})
        )
        respx.get("https://api.td.test/v3/job/status/job-jsonl").mock(
            return_value=httpx.Response(200, json={"status": "success"})
        )
        row = [
            "audit-jsonl-1",
            1783900800,
            "table_modify",
            "success",
            "db.table",
            "table-1",
            "/v3/table/update-schema/db/table",
            "POST",
            "operator@example.com",
            None,
            "schema",
            '[["id","long"]]',
            '[["id","long"],["name","string"]]',
            None,
        ]
        second_row = row.copy()
        second_row[0] = "audit-jsonl-2"
        second_row[1] += 1
        respx.get("https://api.td.test/v3/job/result/job-jsonl").mock(
            return_value=httpx.Response(
                200,
                content=(
                    json.dumps(row) + "\n" + json.dumps(second_row) + "\n"
                ).encode(),
                headers={"content-type": "application/json"},
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

        assert len(events) == 2
        assert events[0].event_id == "audit-jsonl-1"
        assert events[0].resource_id == "table-1"
        assert events[0].actor == "operator@example.com"
        assert events[1].event_id == "audit-jsonl-2"
        assert events[0].old_value == '[["id","long"]]'

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


@respx.mock
def test_workflow_client_fetches_confirmed_workflow_page() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "workflows_by_project_response.json").read_text(encoding="utf-8")
        )
        route = respx.get("https://api-workflow.td.test/api/workflows").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            workflows = await client.fetch_workflow_page_by_project_name(
                "cdp_audience_1016484"
            )
        finally:
            await client.aclose()

        assert route.called
        request = route.calls.last.request
        assert request.url.params["last_id"] == "0"
        assert request.url.params["count"] == "3"
        assert request.url.params["order"] == "asc"
        assert request.url.params["name_pattern"] == "cdp_audience_1016484"
        assert request.url.params["search_project_name"] == "true"
        assert len(workflows) == 3
        assert workflows[0].workflow_id == "15997382"
        assert workflows[0].workflow_name == "predictive_scoring"
        assert workflows[0].project.project_id == "1519759"
        assert workflows[0].project.project_name == "cdp_audience_1016484"
        assert workflows[0].revision == "abae650d-0ed0-414c-8cce-5ad24528e06c"
        assert workflows[0].timezone == "UTC"

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_fetches_confirmed_project_detail() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "workflow_project_response.json").read_text(encoding="utf-8")
        )
        route = respx.get("https://api-workflow.td.test/api/projects/1519759").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            project = await client.fetch_project("1519759")
        finally:
            await client.aclose()

        assert route.called
        assert project.project_id == "1519759"
        assert project.project_name == "cdp_audience_1016484"
        assert project.revision == "abae650d-0ed0-414c-8cce-5ad24528e06c"
        assert project.archive_md5 == "i2w3Mbzsslg5OG6BC4VNwg=="
        assert project.archive_type == "s3"

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_fetches_confirmed_project_archive() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        route = respx.get(
            "https://api-workflow.td.test/api/projects/1519759/archive"
        ).mock(
            return_value=httpx.Response(
                200,
                content=b"confirmed-gzip-response",
                headers={"content-type": "application/gzip"},
            )
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            archive = await client.fetch_project_archive(
                "1519759",
                "abae650d-0ed0-414c-8cce-5ad24528e06c",
            )
        finally:
            await client.aclose()

        assert route.called
        request = route.calls.last.request
        assert request.url.params["revision"] == (
            "abae650d-0ed0-414c-8cce-5ad24528e06c"
        )
        assert request.url.params["direct_download"] == "false"
        assert request.headers["accept"] == "application/gzip"
        assert archive == b"confirmed-gzip-response"

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_fetches_confirmed_schedule_detail() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "workflow_schedule_response.json").read_text(encoding="utf-8")
        )
        route = respx.get("https://api-workflow.td.test/api/schedules/261426").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            schedule = await client.fetch_schedule("261426")
        finally:
            await client.aclose()

        assert route.called
        assert schedule.schedule_id == "261426"
        assert schedule.project.project_id == "1346232"
        assert schedule.project.project_name == "_integration_datamart"
        assert schedule.workflow.workflow_id == "15949212"
        assert schedule.workflow.workflow_name == "_cron_0700__monday_update"
        assert schedule.enabled is True

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_normalizes_confirmed_disabled_schedule() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "workflow_schedule_disabled_response.json").read_text(
                encoding="utf-8"
            )
        )
        respx.get("https://api-workflow.td.test/api/schedules/40405").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            schedule = await client.fetch_schedule("40405")
        finally:
            await client.aclose()

        assert schedule.schedule_id == "40405"
        assert schedule.project.project_id == "551683"
        assert schedule.workflow.workflow_id == "3752110"
        assert schedule.enabled is False

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_ignores_dynamic_schedule_timestamps() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        first_payload = json.loads(
            (FIXTURES / "workflow_schedule_response.json").read_text(encoding="utf-8")
        )
        second_payload = {
            **first_payload,
            "nextRunTime": "2099-01-01T00:00:00Z",
            "nextScheduleTime": "2099-01-01T09:00:00+09:00",
        }
        route = respx.get(
            "https://api-workflow.td.test/api/schedules/261426"
        ).mock(
            side_effect=[
                httpx.Response(200, json=first_payload),
                httpx.Response(200, json=second_payload),
            ]
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            first = await client.fetch_schedule("261426")
            second = await client.fetch_schedule("261426")
        finally:
            await client.aclose()

        assert route.call_count == 2
        assert first == second

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_fetches_confirmed_project_schedule_page() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "workflow_project_schedules_response.json").read_text(
                encoding="utf-8"
            )
        )
        route = respx.get(
            "https://api-workflow.td.test/api/projects/1346232/schedules"
        ).mock(return_value=httpx.Response(200, json=payload))
        client = TreasureDataWorkflowClient(settings)
        try:
            schedules = await client.fetch_project_schedule_page("1346232")
        finally:
            await client.aclose()

        assert route.called
        assert route.calls.last.request.url.params["last_id"] == "0"
        assert [schedule.schedule_id for schedule in schedules] == [
            "261426",
            "381148",
            "418913",
        ]
        assert all(schedule.project.project_id == "1346232" for schedule in schedules)
        assert schedules[2].workflow.workflow_id == "15949220"
        assert schedules[2].workflow.workflow_name == "_cron_0600__daily_update"
        assert all(schedule.enabled for schedule in schedules)

    asyncio.run(scenario())


@respx.mock
def test_workflow_client_fetches_project_schedules_until_empty_page() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_workflow_api_base_url="https://api-workflow.td.test",
            http_max_retries=1,
        )
        first_page = json.loads(
            (FIXTURES / "workflow_project_schedules_response.json").read_text(
                encoding="utf-8"
            )
        )
        empty_page = json.loads(
            (FIXTURES / "workflow_project_schedules_empty_response.json").read_text(
                encoding="utf-8"
            )
        )
        route = respx.get(
            "https://api-workflow.td.test/api/projects/1346232/schedules"
        ).mock(
            side_effect=[
                httpx.Response(200, json=first_page),
                httpx.Response(200, json=empty_page),
            ]
        )
        client = TreasureDataWorkflowClient(settings)
        try:
            schedules = await client.fetch_project_schedules("1346232")
        finally:
            await client.aclose()

        assert route.call_count == 2
        assert route.calls[0].request.url.params["last_id"] == "0"
        assert route.calls[1].request.url.params["last_id"] == "418913"
        assert [schedule.schedule_id for schedule in schedules] == [
            "261426",
            "381148",
            "418913",
        ]

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_fetches_confirmed_query_detail() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "saved_query_detail_response.json").read_text(encoding="utf-8")
        )
        route = respx.get("https://console.td.test/v4/queries/1001").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataSavedQueryClient(settings)
        try:
            query = await client.fetch_query("1001")
        finally:
            await client.aclose()

        assert route.called
        request = route.calls.last.request
        assert request.headers["authorization"] == "TD1 td-secret"
        assert request.headers["accept"] == "application/json"
        assert request.headers["id-format"] == "string"
        assert request.headers["key-format"] == "camelCase"
        assert "cookie" not in request.headers
        assert query.query_id == "1001"
        assert query.query_name == " sample_saved_query"
        assert query.query_string == "SELECT 1"
        assert query.database.database_id == "3001"
        assert query.database.database_name == "sample_database"
        assert query.owner.owner_id == "2001"
        assert query.owner.owner_name == "Sample User"
        assert query.engine_type == "trino"
        assert query.engine_version == "stable"
        assert query.connector_config is None
        assert query.cron is None
        assert query.timezone == "UTC"
        assert query.delay == 0
        assert query.priority == 0
        assert query.retry_limit == 0
        assert query.description is None
        assert query.draft is False

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_rejects_truncated_query_string() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "saved_query_detail_response.json").read_text(encoding="utf-8")
        )
        payload["isQueryStringTruncated"] = True
        respx.get("https://console.td.test/v4/queries/1001").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataSavedQueryClient(settings)
        try:
            with pytest.raises(ExternalApiError, match="truncated SQL"):
                await client.fetch_query("1001")
        finally:
            await client.aclose()

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_accepts_connector_config_object() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "saved_query_detail_response.json").read_text(encoding="utf-8")
        )
        payload["connectorConfig"] = {
            "id": "4001",
            "connector": {
                "id": "5001",
                "name": "sample_connector",
                "type": "sample_type",
            },
        }
        respx.get("https://console.td.test/v4/queries/1001").mock(
            return_value=httpx.Response(200, json=payload)
        )
        client = TreasureDataSavedQueryClient(settings)
        try:
            query = await client.fetch_query("1001")
        finally:
            await client.aclose()

        assert query.connector_config == {
            "id": "4001",
            "connector": {
                "id": "5001",
                "name": "sample_connector",
                "type": "sample_type",
            },
        }

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_returns_none_for_confirmed_not_found_response() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "saved_query_not_found_response.json").read_text(
                encoding="utf-8"
            )
        )
        route = respx.get("https://console.td.test/v4/queries/999999999").mock(
            return_value=httpx.Response(404, json=payload)
        )
        client = TreasureDataSavedQueryClient(settings)
        try:
            query = await client.fetch_query_if_exists("999999999")
        finally:
            await client.aclose()

        assert route.called
        assert query is None

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_fetches_confirmed_paginated_query_list() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        first_page = json.loads(
            (FIXTURES / "saved_query_paginated_index_page1.json").read_text(
                encoding="utf-8"
            )
        )
        second_page = json.loads(
            (FIXTURES / "saved_query_paginated_index_page2.json").read_text(
                encoding="utf-8"
            )
        )
        route = respx.get(
            "https://console.td.test/v4/queries/paginated_index"
        ).mock(
            side_effect=[
                httpx.Response(200, json=first_page),
                httpx.Response(200, json=second_page),
            ]
        )
        client = TreasureDataSavedQueryClient(settings)
        try:
            queries = await client.fetch_queries()
        finally:
            await client.aclose()

        assert route.call_count == 2
        first_request = route.calls[0].request
        second_request = route.calls[1].request
        assert first_request.url.params["minimalConnectorConfig"] == "true"
        assert second_request.url.params["anchor_column"] == "name"
        assert second_request.url.params["anchor_id"] == "1002"
        assert second_request.url.params["anchor_value"] == "sample_query_2"
        assert second_request.url.params["locale"] == "en"
        assert second_request.url.params["page_size"] == "2"
        assert second_request.url.params["sort_direction"] == "asc"
        assert "cookie" not in first_request.headers
        assert "cookie" not in second_request.headers
        assert [query.query_id for query in queries] == ["1001", "1002", "1003"]
        assert queries[0].database.database_name == "sample_database"
        assert queries[1].cron == "0 0 * * *"
        assert queries[2].draft is True

    asyncio.run(scenario())


@respx.mock
def test_saved_query_list_skips_items_without_database() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        payload = json.loads(
            (FIXTURES / "saved_query_paginated_index_page1.json").read_text(
                encoding="utf-8"
            )
        )
        unidentifiable = dict(payload["queries"][0])
        unidentifiable["id"] = "9999"
        unidentifiable["database"] = None
        payload["queries"].append(unidentifiable)
        route = respx.get(
            "https://console.td.test/v4/queries/paginated_index"
        ).mock(return_value=httpx.Response(200, json=payload))
        client = TreasureDataSavedQueryClient(settings)
        try:
            page = await client.fetch_query_page()
        finally:
            await client.aclose()

        assert route.called
        assert [query.query_id for query in page.queries] == ["1001", "1002"]

    asyncio.run(scenario())


@respx.mock
def test_saved_query_client_rejects_external_next_page() -> None:
    async def scenario() -> None:
        settings = make_settings(
            td_console_api_base_url="https://console.td.test",
            http_max_retries=1,
        )
        first_page = json.loads(
            (FIXTURES / "saved_query_paginated_index_page1.json").read_text(
                encoding="utf-8"
            )
        )
        first_page["pagination"]["nextPage"] = (
            "https://untrusted.test/v4/queries/paginated_index"
        )
        route = respx.get(
            "https://console.td.test/v4/queries/paginated_index"
        ).mock(return_value=httpx.Response(200, json=first_page))
        client = TreasureDataSavedQueryClient(settings)
        try:
            with pytest.raises(ExternalApiError, match="nextPage was invalid"):
                await client.fetch_queries()
        finally:
            await client.aclose()

        assert route.call_count == 1

    asyncio.run(scenario())
