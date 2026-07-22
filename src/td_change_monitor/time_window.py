from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta


@dataclass(frozen=True)
class TimeWindow:
    """Audit Logを検索するUTC時間範囲を表す。"""

    start: datetime
    end: datetime

    def __post_init__(self) -> None:
        """時間範囲がタイムゾーン付きかつ開始より終了が後であることを検証する。

        引数:
            なし。
        戻り値:
            なし。
        """
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
    """前回終了時刻から取得遅延を考慮した必須の検索範囲を作る。

    引数:
        last_successful_end_at: 前回正常終了時に処理済みとした終端時刻。
        now: 今回実行の基準時刻。
        lag_minutes: TD側の反映待ちとして現在時刻から差し引く分数。
    戻り値:
        UTCへ正規化した検索範囲。
    """
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
    """検索可能な時間がある場合だけAudit Log検索範囲を作る。

    引数:
        last_successful_end_at: 前回正常終了時に処理済みとした終端時刻。
        now: 今回実行の基準時刻。
        lag_minutes: TD側の反映待ちとして現在時刻から差し引く分数。
    戻り値:
        開始が終了より前なら検索範囲、それ以外ならNone。
    """
    if last_successful_end_at.tzinfo is None or now.tzinfo is None:
        raise ValueError("datetimes must be timezone-aware")
    if lag_minutes < 0:
        raise ValueError("lag_minutes must be non-negative")

    start = last_successful_end_at.astimezone(UTC)
    end = (now - timedelta(minutes=lag_minutes)).astimezone(UTC)
    if start >= end:
        return None
    return TimeWindow(start=start, end=end)
