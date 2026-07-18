from __future__ import annotations

import re
from collections import defaultdict
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from td_change_monitor.models import AuditEvent, EventType

_QUALIFIED_NAME_RE = re.compile(r"(?P<database>[A-Za-z0-9_]+)\.(?P<table>[A-Za-z0-9_]+)")
_PATH_TABLE_RE = re.compile(
    r"/(?:v\d+/)?(?:table|tables)/(?:[^/]+/)*(?P<database>[A-Za-z0-9_]+)/"
    r"(?P<table>[A-Za-z0-9_]+)"
)
_RENAME_PATH_RE = re.compile(
    r"/(?:v\d+/)?table/rename/(?P<database>[A-Za-z0-9_]+)/"
    r"(?P<old_table>[A-Za-z0-9_]+)/(?P<new_table>[A-Za-z0-9_]+)"
)


@dataclass(frozen=True)
class AuditColumnConfig:
    id_column: str
    time_column: str
    event_column: str
    event_result_column: str
    resource_name_column: str
    resource_id_column: str
    request_path_column: str
    request_http_verb_column: str
    user_column: str
    source_user_column: str
    attribute_column: str
    old_value_column: str
    new_value_column: str
    target_resource_name_column: str
    time_unit: str = "epoch_seconds"


@dataclass(frozen=True)
class EventGroup:
    database: str
    table: str
    events: tuple[AuditEvent, ...]
    previous_table: str | None = None

    @property
    def table_names(self) -> tuple[str, ...]:
        names: list[str] = []
        for event in self.events:
            for name in (event.previous_table, event.table):
                if name is not None and name not in names:
                    names.append(name)
        return tuple(names)

    @property
    def event_types(self) -> tuple[EventType, ...]:
        return tuple(event.event_type for event in self.events)


def parse_event_type(value: object) -> EventType | None:
    if not isinstance(value, str):
        return None
    try:
        event_type = EventType(value)
    except ValueError:
        return None
    if event_type == EventType.TABLE_IMPORT_CREATE:
        return None
    return event_type


def parse_audit_time(value: object, *, unit: str) -> datetime:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)
    if isinstance(value, int | float):
        return datetime.fromtimestamp(value, tz=UTC)
    if isinstance(value, str):
        if unit == "epoch_seconds":
            return datetime.fromtimestamp(float(value), tz=UTC)
        normalized = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC)
    raise ValueError(f"unsupported audit time value: {value!r}")


def extract_table_identity(
    raw: Mapping[str, Any],
    columns: AuditColumnConfig,
) -> tuple[str, str] | None:
    rename = extract_rename_identity(raw, columns)
    if rename is not None:
        return rename[0], rename[2]

    direct_database = raw.get("database")
    direct_table = raw.get("table")
    if isinstance(direct_database, str) and isinstance(direct_table, str):
        return direct_database, direct_table

    for key in (columns.resource_name_column, "resource_name", "table_name"):
        value = raw.get(key)
        if isinstance(value, str):
            match = _QUALIFIED_NAME_RE.search(value)
            if match:
                return match.group("database"), match.group("table")

    for key in (columns.request_path_column, "requested_path_info", "path"):
        value = raw.get(key)
        if isinstance(value, str):
            match = _PATH_TABLE_RE.search(value)
            if match:
                return match.group("database"), match.group("table")

    for key in (columns.old_value_column, columns.new_value_column, "old_value", "new_value"):
        value = raw.get(key)
        if isinstance(value, str):
            match = _QUALIFIED_NAME_RE.search(value)
            if match:
                return match.group("database"), match.group("table")

    return None


def extract_rename_identity(
    raw: Mapping[str, Any],
    columns: AuditColumnConfig,
) -> tuple[str, str, str] | None:
    attribute_name = raw.get(columns.attribute_column)
    if attribute_name != "name":
        return None
    for key in (columns.request_path_column, "requested_path_info", "path"):
        value = raw.get(key)
        if isinstance(value, str):
            match = _RENAME_PATH_RE.search(value)
            if match:
                return (
                    match.group("database"),
                    match.group("old_table"),
                    match.group("new_table"),
                )
    old_value = raw.get(columns.old_value_column)
    new_value = raw.get(columns.new_value_column)
    resource_name = raw.get(columns.resource_name_column)
    if isinstance(old_value, str) and isinstance(new_value, str) and isinstance(resource_name, str):
        match = _QUALIFIED_NAME_RE.search(resource_name)
        if match:
            return match.group("database"), old_value, new_value
    return None


def audit_event_from_record(
    raw: Mapping[str, Any],
    columns: AuditColumnConfig,
) -> AuditEvent | None:
    event_type = parse_event_type(raw.get(columns.event_column))
    if event_type is None:
        return None

    event_id = raw.get(columns.id_column)
    if not isinstance(event_id, str | int):
        raise ValueError("audit log record did not include id")

    identity = extract_table_identity(raw, columns)
    rename = extract_rename_identity(raw, columns)
    occurred_at = parse_audit_time(raw.get(columns.time_column), unit=columns.time_unit)
    return AuditEvent(
        event_id=str(event_id),
        event_type=event_type,
        occurred_at=occurred_at,
        database=identity[0] if identity else None,
        table=identity[1] if identity else None,
        previous_table=rename[1] if rename else None,
        actor=_string_or_none(raw.get(columns.user_column)),
        source_actor=_string_or_none(raw.get(columns.source_user_column)),
        resource_id=_string_or_none(raw.get(columns.resource_id_column)),
        event_result=_string_or_none(raw.get(columns.event_result_column)),
        requested_http_verb=_string_or_none(raw.get(columns.request_http_verb_column)),
        requested_path_info=_string_or_none(raw.get(columns.request_path_column)),
        attribute_name=_string_or_none(raw.get(columns.attribute_column)),
        old_value=_string_or_none(raw.get(columns.old_value_column)),
        new_value=_string_or_none(raw.get(columns.new_value_column)),
        target_resource_name=_string_or_none(raw.get(columns.target_resource_name_column)),
        raw=dict(raw),
    )


def events_from_records(
    records: Iterable[Mapping[str, Any]],
    columns: AuditColumnConfig,
) -> list[AuditEvent]:
    events: list[AuditEvent] = []
    seen_ids: set[str] = set()
    for record in records:
        event = audit_event_from_record(record, columns)
        if event is not None and event.event_id not in seen_ids:
            seen_ids.add(event.event_id)
            events.append(event)
    return events


def group_events_by_table(
    events: Iterable[AuditEvent],
) -> tuple[tuple[EventGroup, ...], tuple[AuditEvent, ...]]:
    resolved: list[AuditEvent] = []
    unresolved: list[AuditEvent] = []
    for event in events:
        if event.database is None or event.table is None:
            unresolved.append(event)
            continue
        resolved.append(event)

    parents = list(range(len(resolved)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parents[right_root] = left_root

    key_owners: dict[str, int] = {}
    for index, event in enumerate(resolved):
        for key in _logical_event_keys(event):
            owner = key_owners.get(key)
            if owner is None:
                key_owners[key] = index
            else:
                union(index, owner)

    grouped: dict[int, list[AuditEvent]] = defaultdict(list)
    for index, event in enumerate(resolved):
        grouped[find(index)].append(event)

    groups = tuple(
        sorted(
            (_event_group(items) for items in grouped.values()),
            key=lambda group: (group.database, group.table),
        )
    )
    return groups, tuple(unresolved)


def _logical_event_keys(event: AuditEvent) -> tuple[str, ...]:
    assert event.database is not None
    assert event.table is not None
    keys = [f"name:{event.database}.{event.table}"]
    if event.previous_table:
        keys.append(f"name:{event.database}.{event.previous_table}")
    if event.resource_id:
        keys.append(f"resource:{event.resource_id}")
    return tuple(keys)


def _event_group(events: list[AuditEvent]) -> EventGroup:
    ordered = tuple(sorted(events, key=lambda item: (item.occurred_at, item.event_id)))
    final_event = ordered[-1]
    assert final_event.database is not None
    assert final_event.table is not None
    rename_events = [
        event
        for event in ordered
        if event.previous_table is not None and event.previous_table != event.table
    ]
    previous_table = rename_events[0].previous_table if rename_events else None
    final_table = final_event.table
    if rename_events:
        last_rename = rename_events[-1]
        assert last_rename.table is not None
        final_table = last_rename.table
        events_after_rename = [
            event for event in ordered if event.occurred_at > last_rename.occurred_at
        ]
        if events_after_rename:
            assert events_after_rename[-1].table is not None
            final_table = events_after_rename[-1].table
    return EventGroup(
        database=final_event.database,
        table=final_table,
        events=ordered,
        previous_table=previous_table,
    )


def _string_or_none(value: object) -> str | None:
    return value if isinstance(value, str) and value else None
