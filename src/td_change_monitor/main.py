from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from datetime import UTC, datetime

from td_change_monitor.clients.backlog import BacklogClient
from td_change_monitor.clients.local_git import LocalGitRepositoryClient
from td_change_monitor.clients.treasure_data import TreasureDataClient
from td_change_monitor.config import Settings, load_target_tables_config
from td_change_monitor.errors import ChangeMonitorError
from td_change_monitor.service import ChangeMonitorService


async def run_application(
    *,
    dry_run: bool = False,
    bootstrap: bool = False,
    bootstrap_state_end_at: datetime | None = None,
) -> dict[str, object]:
    settings = Settings()  # type: ignore[call-arg]
    _configure_logging(settings.log_level)
    target_tables = load_target_tables_config()
    treasure_data = TreasureDataClient(settings)
    repository = LocalGitRepositoryClient(settings)
    backlog = BacklogClient(settings)
    service = ChangeMonitorService(
        settings=settings,
        target_tables=target_tables,
        treasure_data=treasure_data,
        repository=repository,
        backlog=backlog,
    )
    try:
        return await service.run(
            dry_run=dry_run,
            bootstrap=bootstrap,
            bootstrap_state_end_at=bootstrap_state_end_at,
        )
    finally:
        await treasure_data.aclose()
        await backlog.aclose()


async def _run(
    *,
    dry_run: bool,
    bootstrap: bool,
    bootstrap_state_end_at: datetime | None,
) -> int:
    _configure_logging("INFO")
    try:
        summary = await run_application(
            dry_run=dry_run,
            bootstrap=bootstrap,
            bootstrap_state_end_at=bootstrap_state_end_at,
        )
    except ChangeMonitorError as exc:
        logging.getLogger(__name__).error(
            "td_change_monitor_run_failed",
            extra={"error": str(exc), "exc_type": type(exc).__name__},
        )
        return 1
    except Exception as exc:
        logging.getLogger(__name__).error(
            "td_change_monitor_run_failed",
            extra={"error": str(exc), "exc_type": type(exc).__name__},
        )
        return 1

    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


def cli() -> None:
    parser = argparse.ArgumentParser(description="Treasure Data change monitor")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--bootstrap", action="store_true")
    parser.add_argument(
        "--bootstrap-state-end-at",
        type=_parse_datetime,
        help="ISO timestamp to write state/state.json during bootstrap",
    )
    args = parser.parse_args()
    raise SystemExit(
        asyncio.run(
            _run(
                dry_run=args.dry_run,
                bootstrap=args.bootstrap,
                bootstrap_state_end_at=args.bootstrap_state_end_at,
            )
        )
    )


def _configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        handlers=[handler],
        force=True,
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


def _parse_datetime(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected ISO datetime") from exc
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("expected timezone-aware ISO datetime")
    return parsed.astimezone(UTC)


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        for key in ("summary", "error", "exc_type"):
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)


if __name__ == "__main__":
    cli()
