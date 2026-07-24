from __future__ import annotations

import json

from td_change_monitor.models import (
    SavedQueryDatabaseReference,
    SavedQueryDetail,
    SavedQueryOwnerReference,
)
from td_change_monitor.saved_query_diff import (
    diff_saved_queries,
    saved_query_snapshot_from_mapping,
    saved_query_snapshot_hash,
    saved_query_snapshot_to_json_bytes,
    snapshot_from_saved_query,
)


def query_detail(**overrides: object) -> SavedQueryDetail:
    values: dict[str, object] = {
        "query_id": "1001",
        "query_name": "daily_summary",
        "query_string": "SELECT 1\r\n",
        "database": SavedQueryDatabaseReference(
            database_id="3001",
            database_name="analytics",
        ),
        "owner": SavedQueryOwnerReference(
            owner_id="2001",
            owner_name="Sample User",
        ),
        "engine_type": "trino",
        "engine_version": "stable",
        "connector_config": None,
        "cron": None,
        "timezone": "UTC",
        "delay": 0,
        "priority": 0,
        "retry_limit": 0,
        "description": None,
        "draft": False,
    }
    values.update(overrides)
    return SavedQueryDetail(**values)  # type: ignore[arg-type]


def test_snapshot_keeps_only_hash_and_type_from_connector_config() -> None:
    detail = query_detail(
        connector_config={
            "id": "4001",
            "connector": {
                "id": "5001",
                "name": "private_destination",
                "type": "google_sheets",
            },
            "password": "do-not-store",
            "write_mode": "append",
        }
    )

    snapshot = snapshot_from_saved_query(detail)
    encoded = saved_query_snapshot_to_json_bytes(snapshot)

    assert snapshot.connector_type == "google_sheets"
    assert snapshot.connector_config_hash is not None
    assert b"do-not-store" not in encoded
    assert b"private_destination" not in encoded
    assert b"password" not in encoded
    assert b"write_mode" not in encoded


def test_detects_sql_name_database_engine_output_and_schedule_changes() -> None:
    before = snapshot_from_saved_query(query_detail())
    after = snapshot_from_saved_query(
        query_detail(
            query_name="daily_summary_renamed",
            query_string="SELECT 2\n",
            database=SavedQueryDatabaseReference(
                database_id="3002",
                database_name="analytics_new",
            ),
            engine_type="presto",
            engine_version="legacy",
            connector_config={
                "connector": {
                    "type": "s3",
                },
                "write_mode": "replace",
            },
            cron="0 0 * * *",
            timezone="Asia/Tokyo",
            delay=60,
            priority=1,
            retry_limit=2,
        )
    )

    result = diff_saved_queries(before, after)

    assert result.query_id == "1001"
    assert result.sql_changed
    assert result.changed_fields == (
        "query_name",
        "database_id",
        "database_name",
        "engine_type",
        "engine_version",
        "connector_type",
        "connector_config_hash",
        "cron",
        "timezone",
        "delay",
        "priority",
        "retry_limit",
    )
    assert not result.deleted
    assert result.has_changes


def test_query_rename_keeps_same_query_id() -> None:
    before = snapshot_from_saved_query(query_detail(query_name="old_name"))
    after = snapshot_from_saved_query(query_detail(query_name="new_name"))

    result = diff_saved_queries(before, after)

    assert result.query_id == "1001"
    assert result.changed_fields == ("query_name",)


def test_deleted_query_is_detected_from_missing_current_state() -> None:
    before = snapshot_from_saved_query(query_detail())

    result = diff_saved_queries(before, None)

    assert result.deleted
    assert result.has_changes
    assert not result.sql_changed
    assert result.changed_fields == ()


def test_snapshot_round_trip_is_stable_and_excludes_runtime_fields() -> None:
    snapshot = snapshot_from_saved_query(query_detail())
    encoded = saved_query_snapshot_to_json_bytes(snapshot)
    payload = json.loads(encoded)
    restored = saved_query_snapshot_from_mapping(payload)

    assert restored == snapshot
    assert saved_query_snapshot_hash(restored) == saved_query_snapshot_hash(snapshot)
    assert "lastJob" not in payload
    assert "nextRunAt" not in payload
    assert "permissions" not in payload
    assert "owner" not in payload
