from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta


@dataclass(frozen=True)
class TimeWindow:
    start: datetime
    end: datetime

    def __post_init__(self) -> None:
        if self.start.tzinfo is None or self.end.tzinfo is None:
            raise ValueError("TimeWindow datetimes must be timezone-aware")
        if self.start >= self.end:
            raise ValueError("TimeWindow start must be earlier than end")


def build_time_window(
    *,
    last_successful_end_at: datetime,
    now: datetime,
    lag_minutes: int,
) -> TimeWindow:
    window = build_optional_time_window(
        last_successful_end_at=last_successful_end_at,
        now=now,
        lag_minutes=lag_minutes,
    )
    if window is None:
        raise ValueError("TimeWindow start must be earlier than end")
    return window


def build_optional_time_window(
    *,
    last_successful_end_at: datetime,
    now: datetime,
    lag_minutes: int,
) -> TimeWindow | None:
    if last_successful_end_at.tzinfo is None or now.tzinfo is None:
        raise ValueError("datetimes must be timezone-aware")
    if lag_minutes < 0:
        raise ValueError("lag_minutes must be non-negative")

    start = last_successful_end_at.astimezone(UTC)
    end = (now - timedelta(minutes=lag_minutes)).astimezone(UTC)
    if start >= end:
        return None
    return TimeWindow(start=start, end=end)
