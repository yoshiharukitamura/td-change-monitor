from __future__ import annotations

from datetime import UTC, datetime

from td_change_monitor.audit import AuditColumnConfig, events_from_records, group_events_by_table
from td_change_monitor.models import EventType


def columns() -> AuditColumnConfig:
    return AuditColumnConfig(
        id_column="id",
        time_column="time",
        event_column="event_name",
        event_result_column="event_result",
        resource_name_column="resource_name",
        resource_id_column="resource_id",
        request_path_column="requested_path_info",
        request_http_verb_column="requested_http_verb",
        user_column="user_email",
        source_user_column="source_user_email",
        attribute_column="attribute_name",
        old_value_column="old_value",
        new_value_column="new_value",
        target_resource_name_column="target_resource_name",
    )


def test_parses_target_event_and_extracts_table_from_resource_name() -> None:
    events = events_from_records(
        [
            {
                "id": "audit-1",
                "event_name": "table_modify",
                "time": 1783900800,
                "resource_name": "sample_database.sample_table",
                "resource_id": "12345",
                "requested_path_info": "/v3/table/update-schema/sample_database/sample_table",
                "user_email": "masked@example.com",
            }
        ],
        columns(),
    )

    assert len(events) == 1
    assert events[0].event_type == EventType.TABLE_MODIFY
    assert events[0].database == "sample_database"
    assert events[0].table == "sample_table"
    assert events[0].occurred_at == datetime(2026, 7, 13, 0, 0, tzinfo=UTC)


def test_parses_table_name_starting_with_digit() -> None:
    events = events_from_records(
        [
            {
                "id": "audit-numeric-table",
                "event_name": "table_modify",
                "time": 1783900800,
                "resource_name": "l2_emberpoint_output.0426_analytical_grade",
            }
        ],
        columns(),
    )

    assert len(events) == 1
    assert events[0].database == "l2_emberpoint_output"
    assert events[0].table == "0426_analytical_grade"


def test_excludes_table_import_create() -> None:
    events = events_from_records(
        [
            {
                "id": "audit-import-1",
                "event_name": "table_import_create",
                "time": 1783900800,
                "resource_name": "db.table",
            }
        ],
        columns(),
    )

    assert events == []


def test_parses_table_rename_from_requested_path() -> None:
    events = events_from_records(
        [
            {
                "id": "audit-rename-1",
                "event_name": "table_modify",
                "time": 1783900800,
                "resource_name": "db.old_table",
                "attribute_name": "name",
                "old_value": "old_table",
                "new_value": "new_table",
                "requested_path_info": "/v3/table/rename/db/old_table/new_table",
            }
        ],
        columns(),
    )

    assert len(events) == 1
    assert events[0].database == "db"
    assert events[0].previous_table == "old_table"
    assert events[0].table == "new_table"


def test_groups_multiple_events_for_same_table_and_keeps_unresolved() -> None:
    events = events_from_records(
        [
            {"id": "1", "event_name": "table_create", "time": 1, "resource_name": "db.table"},
            {"id": "2", "event_name": "table_modify", "time": 2, "resource_name": "db.table"},
            {"id": "3", "event_name": "table_swap", "time": 3, "resource_name": "unparseable"},
        ],
        columns(),
    )

    groups, unresolved = group_events_by_table(events)

    assert len(groups) == 1
    assert groups[0].database == "db"
    assert groups[0].table == "table"
    assert groups[0].event_types == (EventType.TABLE_CREATE, EventType.TABLE_MODIFY)
    assert len(unresolved) == 1


def test_groups_events_across_rename_as_one_logical_table() -> None:
    events = events_from_records(
        [
            {
                "id": "modify-old",
                "event_name": "table_modify",
                "time": 1,
                "resource_name": "db.old_table",
                "resource_id": "table-1",
                "attribute_name": "schema",
            },
            {
                "id": "rename",
                "event_name": "table_modify",
                "time": 2,
                "resource_name": "db.old_table",
                "resource_id": "table-1",
                "attribute_name": "name",
                "old_value": "old_table",
                "new_value": "new_table",
                "requested_path_info": "/v3/table/rename/db/old_table/new_table",
            },
            {
                "id": "delete-new",
                "event_name": "table_delete",
                "time": 3,
                "resource_name": "db.new_table",
                "resource_id": "table-1",
            },
        ],
        columns(),
    )

    groups, unresolved = group_events_by_table(events)

    assert unresolved == ()
    assert len(groups) == 1
    assert groups[0].database == "db"
    assert groups[0].table == "new_table"
    assert groups[0].previous_table == "old_table"
    assert groups[0].table_names == ("old_table", "new_table")
    assert [item.event_id for item in groups[0].events] == [
        "modify-old",
        "rename",
        "delete-new",
    ]


def test_deduplicates_by_audit_log_id() -> None:
    events = events_from_records(
        [
            {"id": "1", "event_name": "table_modify", "time": 1, "resource_name": "db.table"},
            {"id": "1", "event_name": "table_modify", "time": 1, "resource_name": "db.table"},
        ],
        columns(),
    )

    assert len(events) == 1
