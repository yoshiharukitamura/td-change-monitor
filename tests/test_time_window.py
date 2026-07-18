from datetime import UTC, datetime

import pytest

from td_change_monitor.time_window import build_optional_time_window, build_time_window


def test_builds_half_open_window_with_lag() -> None:
    last_end = datetime(2026, 7, 12, 23, 50, tzinfo=UTC)
    now = datetime(2026, 7, 13, 0, 10, tzinfo=UTC)

    window = build_time_window(
        last_successful_end_at=last_end,
        now=now,
        lag_minutes=10,
    )

    assert window.start == datetime(2026, 7, 12, 23, 50, tzinfo=UTC)
    assert window.end == datetime(2026, 7, 13, 0, 0, tzinfo=UTC)


def test_optional_window_returns_none_when_lag_window_is_not_ready() -> None:
    window = build_optional_time_window(
        last_successful_end_at=datetime(2026, 7, 13, 1, 5, tzinfo=UTC),
        now=datetime(2026, 7, 13, 1, 10, tzinfo=UTC),
        lag_minutes=10,
    )

    assert window is None


def test_strict_window_rejects_empty_or_negative_window() -> None:
    with pytest.raises(ValueError, match="start must be earlier"):
        build_time_window(
            last_successful_end_at=datetime(2026, 7, 13, 1, 5, tzinfo=UTC),
            now=datetime(2026, 7, 13, 1, 10, tzinfo=UTC),
            lag_minutes=10,
        )
