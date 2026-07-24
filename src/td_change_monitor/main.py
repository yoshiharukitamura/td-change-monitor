from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path

from td_change_monitor.clients.backlog import BacklogClient
from td_change_monitor.clients.local_git import LocalGitRepositoryClient
from td_change_monitor.clients.treasure_data import TreasureDataClient
from td_change_monitor.clients.treasure_data_saved_query import (
    TreasureDataSavedQueryClient,
)
from td_change_monitor.clients.treasure_data_workflow import TreasureDataWorkflowClient
from td_change_monitor.config import (
    Settings,
    load_resource_targets_config,
    load_target_tables_config,
)
from td_change_monitor.errors import ChangeMonitorError
from td_change_monitor.resource_monitor import AdditionalResourceMonitor
from td_change_monitor.service import ChangeMonitorService
from td_change_monitor.target_import import (
    build_resource_targets_from_workbook,
    write_resource_targets,
)


async def run_application(
    *,
    dry_run: bool = False,
    bootstrap: bool = False,
    bootstrap_state_end_at: datetime | None = None,
) -> dict[str, object]:
    """設定と各外部クライアントを生成し、1回の監視処理を実行する。

    引数:
        dry_run: Backlog・Git・stateへ書き込まず判定だけ行うかどうか。
        bootstrap: 現在schemaと初期stateを作る初回実行かどうか。
        bootstrap_state_end_at: bootstrap時にstateへ保存する監視開始UTC時刻。
    戻り値:
        実行IDと処理件数を含む実行結果辞書。
    """
    settings = Settings()  # type: ignore[call-arg]
    _configure_logging(settings.log_level)
    target_tables = load_target_tables_config()
    resource_targets = load_resource_targets_config()
    treasure_data = TreasureDataClient(settings)
    workflow = TreasureDataWorkflowClient(settings)
    saved_query = TreasureDataSavedQueryClient(settings)
    repository = LocalGitRepositoryClient(settings)
    backlog = BacklogClient(settings)
    resource_monitor = AdditionalResourceMonitor(
        settings=settings,
        targets=resource_targets,
        workflow=workflow,
        saved_query=saved_query,
        repository=repository,
    )
    service = ChangeMonitorService(
        settings=settings,
        target_tables=target_tables,
        treasure_data=treasure_data,
        repository=repository,
        backlog=backlog,
        resource_monitor=resource_monitor,
    )
    try:
        return await service.run(
            dry_run=dry_run,
            bootstrap=bootstrap,
            bootstrap_state_end_at=bootstrap_state_end_at,
        )
    finally:
        await treasure_data.aclose()
        await workflow.aclose()
        await saved_query.aclose()
        await backlog.aclose()


async def import_resource_targets(
    *,
    workbook_path: Path,
    output_path: Path = Path("config/resource_targets.yml"),
) -> dict[str, int]:
    """棚卸しExcelを実APIの安定IDと照合して対象マスターを生成する。

    引数:
        workbook_path: 3つの対象シートを持つ棚卸しExcel。
        output_path: 生成するGit管理用YAML。
    戻り値:
        Workflow・登録クエリの照合件数要約。
    """
    settings = Settings()  # type: ignore[call-arg]
    _configure_logging(settings.log_level)
    workflow = TreasureDataWorkflowClient(settings)
    saved_query = TreasureDataSavedQueryClient(settings)
    try:
        config, summary = await build_resource_targets_from_workbook(
            workbook_path,
            workflow_client=workflow,
            saved_query_client=saved_query,
        )
        write_resource_targets(output_path, config)
        return summary.as_dict()
    finally:
        await workflow.aclose()
        await saved_query.aclose()


async def _run(
    *,
    dry_run: bool,
    bootstrap: bool,
    bootstrap_state_end_at: datetime | None,
) -> int:
    """アプリケーションを実行し、例外をCLI終了コードへ変換する。

    引数:
        dry_run: 書き込みを無効にするかどうか。
        bootstrap: 初回snapshot作成を行うかどうか。
        bootstrap_state_end_at: 初回stateの監視開始時刻。
    戻り値:
        成功なら0、想定内外の失敗なら1。
    """
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


async def _run_target_import(
    *,
    workbook_path: Path,
    output_path: Path,
) -> int:
    """対象マスター生成を実行し、例外をCLI終了コードへ変換する。

    引数:
        workbook_path: 入力する棚卸しExcel。
        output_path: 生成する対象マスターYAML。
    戻り値:
        成功なら0、失敗なら1。
    """
    _configure_logging("INFO")
    try:
        summary = await import_resource_targets(
            workbook_path=workbook_path,
            output_path=output_path,
        )
    except Exception as exc:
        logging.getLogger(__name__).error(
            "td_change_monitor_target_import_failed",
            extra={"error": str(exc), "exc_type": type(exc).__name__},
        )
        return 1
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


def cli() -> None:
    """CLI引数を解析して非同期バッチを起動する。

    引数:
        なし。引数はコマンドラインから読み取る。
    戻り値:
        なし。処理終了時にSystemExitを送出する。
    """
    parser = argparse.ArgumentParser(description="Treasure Data change monitor")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--bootstrap", action="store_true")
    parser.add_argument(
        "--import-targets-from",
        type=Path,
        help="inventory xlsx used to generate config/resource_targets.yml",
    )
    parser.add_argument(
        "--resource-targets-output",
        type=Path,
        default=Path("config/resource_targets.yml"),
        help="output YAML path for --import-targets-from",
    )
    parser.add_argument(
        "--bootstrap-state-end-at",
        type=_parse_datetime,
        help="ISO timestamp to write state/state.json during bootstrap",
    )
    args = parser.parse_args()
    if args.import_targets_from is not None:
        if args.dry_run or args.bootstrap or args.bootstrap_state_end_at is not None:
            parser.error("--import-targets-from cannot be combined with run options")
        raise SystemExit(
            asyncio.run(
                _run_target_import(
                    workbook_path=args.import_targets_from,
                    output_path=args.resource_targets_output,
                )
            )
        )
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
    """JSON構造化ログを標準出力へ設定する。

    引数:
        level: INFO、DEBUGなどのログレベル文字列。
    戻り値:
        なし。
    """
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
    """CLIのISO日時文字列をタイムゾーン付きUTCへ変換する。

    引数:
        value: Z表記またはUTC offset付きISO日時文字列。
    戻り値:
        UTCへ正規化したdatetime。
    """
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected ISO datetime") from exc
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("expected timezone-aware ISO datetime")
    return parsed.astimezone(UTC)


class _JsonFormatter(logging.Formatter):
    """実行ログを1行JSON形式へ整形する。"""

    def format(self, record: logging.LogRecord) -> str:
        """LogRecordを1行JSON文字列へ変換する。

        引数:
            record: Python loggingが生成したログレコード。
        戻り値:
            level、message、loggerと許可属性を含むJSON文字列。
        """
        payload: dict[str, object] = {
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        for key in (
            "summary",
            "dry_run_change",
            "workflow_archive_inventory",
            "error",
            "exc_type",
        ):
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)


if __name__ == "__main__":
    cli()
