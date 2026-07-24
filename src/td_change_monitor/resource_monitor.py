from __future__ import annotations

import hashlib
import json
import logging
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

from td_change_monitor.change_id import build_resource_change_id
from td_change_monitor.clients.local_git import FileChange
from td_change_monitor.config import (
    MonitorStatus,
    ResourceTargetsConfig,
    SavedQueryTarget,
    Settings,
    WorkflowProjectTarget,
)
from td_change_monitor.errors import ChangeMonitorError, ExternalApiError
from td_change_monitor.models import (
    SavedQueryDetail,
    SavedQueryDetectedChange,
    SavedQuerySnapshot,
    WorkflowDetectedChange,
    WorkflowProjectDetail,
    WorkflowProjectScheduleSnapshot,
    WorkflowProjectSnapshot,
    WorkflowScheduleDetail,
)
from td_change_monitor.resource_rendering import (
    render_saved_query_diff_markdown,
    render_workflow_diff_markdown,
)
from td_change_monitor.saved_query_diff import (
    diff_saved_queries,
    saved_query_snapshot_from_mapping,
    saved_query_snapshot_hash,
    saved_query_snapshot_to_json_bytes,
    snapshot_from_saved_query,
)
from td_change_monitor.workflow_archive import (
    WORKFLOW_METADATA_FILE,
    load_workflow_project_snapshot,
    workflow_project_snapshot_hash,
    workflow_snapshot_from_files,
    workflow_snapshot_to_files,
)
from td_change_monitor.workflow_diff import diff_workflow_projects
from td_change_monitor.workflow_schedule import (
    build_workflow_project_schedule_snapshot,
    workflow_schedule_snapshot_from_bytes,
    workflow_schedule_snapshot_hash,
    workflow_schedule_snapshot_to_bytes,
)

_SAFE_PATH_COMPONENT_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
logger = logging.getLogger(__name__)


class WorkflowMonitorClientProtocol(Protocol):
    """日次Workflow監視に必要なAPIクライアント境界を表す。"""

    async def fetch_project(self, project_id: str) -> WorkflowProjectDetail:
        """project IDの現在識別情報を返す。"""
        ...

    async def fetch_project_archive(self, project_id: str, revision: str) -> bytes:
        """指定revisionのproject archiveを返す。"""
        ...

    async def fetch_project_schedules(
        self,
        project_id: str,
    ) -> tuple[WorkflowScheduleDetail, ...]:
        """projectに所属する現在scheduleを全件返す。"""
        ...


class SavedQueryMonitorClientProtocol(Protocol):
    """日次登録クエリ監視に必要なAPIクライアント境界を表す。"""

    async def fetch_query_if_exists(
        self,
        query_id: str,
    ) -> SavedQueryDetail | None:
        """Query IDの現在詳細を返し、404ならNoneを返す。"""
        ...


class ResourceRepositoryProtocol(Protocol):
    """追加リソースsnapshotの読取りに必要なrepository境界を表す。"""

    async def read_text(self, path: str) -> str | None:
        """生成対象pathのUTF-8内容またはNoneを返す。"""
        ...


@dataclass(frozen=True)
class ResourceRunPlan:
    """追加リソースの日次判定結果とGit反映予定を保持する。"""

    target_count: int
    workflow_changes: tuple[WorkflowDetectedChange, ...]
    saved_query_changes: tuple[SavedQueryDetectedChange, ...]
    file_changes: tuple[FileChange, ...]
    workflow_project_names: dict[str, str]
    baseline_count: int

    @property
    def diff_count(self) -> int:
        """Workflowと登録クエリの変更件数合計を返す。"""
        return len(self.workflow_changes) + len(self.saved_query_changes)


class AdditionalResourceMonitor:
    """Workflow・schedule・登録クエリの現在状態比較を統括する。"""

    def __init__(
        self,
        *,
        settings: Settings,
        targets: ResourceTargetsConfig,
        workflow: WorkflowMonitorClientProtocol,
        saved_query: SavedQueryMonitorClientProtocol,
        repository: ResourceRepositoryProtocol,
    ) -> None:
        """設定、対象、API、repositoryを保持する。

        引数:
            settings: archive上限、Git URL、branchを含む全体設定。
            targets: Git管理された追加リソース対象マスター。
            workflow: 確認済みWorkflow APIクライアント。
            saved_query: 確認済み登録クエリAPIクライアント。
            repository: 前回snapshotを読むローカルGitクライアント。
        戻り値:
            なし。
        """
        self._settings = settings
        self._targets = targets
        self._workflow = workflow
        self._saved_query = saved_query
        self._repository = repository

    async def plan(
        self,
        *,
        at: datetime,
        window_start: datetime,
        window_end: datetime,
        bootstrap: bool,
        workflow_project_names: Mapping[str, str],
    ) -> ResourceRunPlan:
        """全追加対象を比較し、外部書込み前の実行計画をメモリ上に作る。

        引数:
            at: 差分成果物を配置する今回実行時刻。
            window_start: 人向け成果物へ記録する監視期間開始。
            window_end: 人向け成果物へ記録する監視期間終了。
            bootstrap: 初回基準登録として課題・diffを作らないかどうか。
            workflow_project_names: project IDと前回保存名のstate対応表。
        戻り値:
            検出変更、current snapshot、削除、project名state更新を含む計画。
        """
        files: dict[str, bytes | None] = {}
        workflow_changes: list[WorkflowDetectedChange] = []
        saved_query_changes: list[SavedQueryDetectedChange] = []
        project_names = dict(workflow_project_names)
        baseline_count = 0

        for workflow_target in self._targets.active_workflow_projects():
            workflow_result, target_files, baseline, current_name = (
                await self._plan_workflow(
                    workflow_target,
                    at=at,
                    window_start=window_start,
                    window_end=window_end,
                    bootstrap=bootstrap,
                    previous_project_name=project_names.get(
                        _required_id(workflow_target.project_id),
                        workflow_target.project_name,
                    ),
                )
            )
            _merge_files(files, target_files)
            baseline_count += int(baseline)
            if workflow_result is not None:
                workflow_changes.append(workflow_result)
            if current_name is None:
                project_names.pop(_required_id(workflow_target.project_id), None)
            else:
                project_names[_required_id(workflow_target.project_id)] = current_name

        for query_target in self._targets.active_saved_queries():
            query_result, target_files, baseline = await self._plan_saved_query(
                query_target,
                at=at,
                window_start=window_start,
                window_end=window_end,
                bootstrap=bootstrap,
            )
            _merge_files(files, target_files)
            baseline_count += int(baseline)
            if query_result is not None:
                saved_query_changes.append(query_result)

        return ResourceRunPlan(
            target_count=(
                len(self._targets.active_workflow_projects())
                + len(self._targets.active_saved_queries())
            ),
            workflow_changes=tuple(workflow_changes),
            saved_query_changes=tuple(saved_query_changes),
            file_changes=tuple(
                FileChange(path=path, content=content)
                for path, content in sorted(files.items())
            ),
            workflow_project_names=project_names,
            baseline_count=baseline_count,
        )

    async def _plan_workflow(
        self,
        target: WorkflowProjectTarget,
        *,
        at: datetime,
        window_start: datetime,
        window_end: datetime,
        bootstrap: bool,
        previous_project_name: str,
    ) -> tuple[
        WorkflowDetectedChange | None,
        dict[str, bytes | None],
        bool,
        str | None,
    ]:
        """1 Workflowプロジェクトの前回・現在状態を比較する。

        引数:
            target: project IDが確定した対象マスター行。
            at: 差分成果物の日付に使用する時刻。
            window_start: 差分Markdownの監視開始時刻。
            window_end: 差分Markdownの監視終了時刻。
            bootstrap: 初回基準登録かどうか。
            previous_project_name: stateに保存された前回project名。
        戻り値:
            検出変更、current反映ファイル、基準登録有無、現在project名。
        """
        project_id = _required_id(target.project_id)
        previous = await self._read_workflow_snapshot(previous_project_name)
        previous_schedules = await self._read_workflow_schedule_snapshot(
            previous_project_name
        )
        detail = await self._fetch_workflow_project_if_exists(project_id)

        if detail is None:
            if bootstrap:
                raise ChangeMonitorError(
                    f"Workflow bootstrap target was not found: project_id={project_id}"
                )
            if previous is None:
                raise ChangeMonitorError(
                    f"Workflow target project was not found: project_id={project_id}"
                )
            change = _workflow_deleted_change(
                previous,
                previous_schedules,
                at=at,
                github_url=self._github_blob_url,
                should_create_issue=target.monitor_status == MonitorStatus.MONITOR,
            )
            files = _workflow_current_file_changes(
                previous_name=previous_project_name,
                before=previous,
                before_schedules=previous_schedules,
                after=None,
                after_schedules=None,
            )
            files[change.diff_path] = render_workflow_diff_markdown(
                change,
                window_start=window_start,
                window_end=window_end,
            ).encode("utf-8")
            return change, files, False, None

        loaded = await load_workflow_project_snapshot(
            self._workflow,
            detail,
            previous=previous,
            temp_parent=self._settings.git_repository_path / "tmp",
            max_file_size_bytes=self._settings.max_generated_file_size_mb
            * 1024
            * 1024,
            max_total_size_bytes=self._settings.workflow_archive_max_total_size_mb
            * 1024
            * 1024,
        )
        if loaded.inventory is not None:
            logger.info(
                "td_change_monitor_workflow_archive_inventory",
                extra={
                    "workflow_archive_inventory": {
                        "project_id": detail.project_id,
                        "project_name": detail.project_name,
                        "extension_counts": dict(
                            loaded.inventory.extension_counts
                        ),
                        "examples": {
                            extension: list(paths)
                            for extension, paths in loaded.inventory.examples
                        },
                    }
                },
            )
        current = loaded.snapshot
        api_schedules = await self._workflow.fetch_project_schedules(project_id)
        current_schedules = build_workflow_project_schedule_snapshot(
            current,
            api_schedules,
        )

        if previous is None:
            files = _workflow_current_file_changes(
                previous_name=previous_project_name,
                before=None,
                before_schedules=None,
                after=current,
                after_schedules=current_schedules,
            )
            return None, files, True, current.project_name

        if previous_schedules is None:
            diff = diff_workflow_projects(previous, current)
        else:
            diff = diff_workflow_projects(
                previous,
                current,
                before_schedules=previous_schedules,
                after_schedules=current_schedules,
            )
        schedule_baseline_needed = previous_schedules is None
        if bootstrap or not diff.has_changes:
            files = (
                _workflow_current_file_changes(
                    previous_name=previous_project_name,
                    before=previous,
                    before_schedules=previous_schedules,
                    after=current,
                    after_schedules=current_schedules,
                )
                if bootstrap
                or schedule_baseline_needed
                or previous_project_name != current.project_name
                else {}
            )
            return None, files, bootstrap or schedule_baseline_needed, current.project_name

        before_hash = _workflow_combined_hash(previous, previous_schedules)
        after_hash = _workflow_combined_hash(current, current_schedules)
        change_id = build_resource_change_id(
            resource_type="workflow_project",
            stable_resource_id=project_id,
            event_ids=(),
            before_hash=before_hash,
            after_hash=after_hash,
            change_kind="modified",
        )
        diff_path = _workflow_diff_path(at, current.project_name, change_id)
        change = WorkflowDetectedChange(
            project_id=project_id,
            project_name=current.project_name,
            before=previous,
            after=current,
            before_schedules=previous_schedules,
            after_schedules=current_schedules,
            diff=diff,
            change_kind="modified",
            change_id=change_id,
            diff_path=diff_path,
            github_diff_url=self._github_blob_url(diff_path),
            should_create_issue=(
                target.monitor_status == MonitorStatus.MONITOR
                and diff.should_create_issue
            ),
        )
        files = _workflow_current_file_changes(
            previous_name=previous_project_name,
            before=previous,
            before_schedules=previous_schedules,
            after=current,
            after_schedules=current_schedules,
        )
        files[diff_path] = render_workflow_diff_markdown(
            change,
            window_start=window_start,
            window_end=window_end,
        ).encode("utf-8")
        return change, files, False, current.project_name

    async def _plan_saved_query(
        self,
        target: SavedQueryTarget,
        *,
        at: datetime,
        window_start: datetime,
        window_end: datetime,
        bootstrap: bool,
    ) -> tuple[SavedQueryDetectedChange | None, dict[str, bytes | None], bool]:
        """1 Query IDの前回・現在状態を比較する。

        引数:
            target: Query IDが確定した対象マスター行。
            at: 差分成果物の日付に使用する時刻。
            window_start: 差分Markdownの監視開始時刻。
            window_end: 差分Markdownの監視終了時刻。
            bootstrap: 初回基準登録かどうか。
        戻り値:
            検出変更、current反映ファイル、基準登録有無。
        """
        query_id = _required_id(target.query_id)
        path = _saved_query_path(query_id)
        previous = await self._read_saved_query_snapshot(path)
        detail = await self._saved_query.fetch_query_if_exists(query_id)
        current = snapshot_from_saved_query(detail) if detail is not None else None

        if bootstrap and current is None:
            raise ChangeMonitorError(
                f"saved query bootstrap target was not found: query_id={query_id}"
            )
        if previous is None:
            if current is None:
                raise ChangeMonitorError(
                    f"saved query target was not found: query_id={query_id}"
                )
            return None, {path: saved_query_snapshot_to_json_bytes(current)}, True

        diff = diff_saved_queries(previous, current)
        if bootstrap or not diff.has_changes:
            files = (
                {
                    path: (
                        saved_query_snapshot_to_json_bytes(current)
                        if current is not None
                        else None
                    )
                }
                if bootstrap
                else {}
            )
            return None, files, bootstrap

        change_kind = "deleted" if diff.deleted else "modified"
        change_id = build_resource_change_id(
            resource_type="saved_query",
            stable_resource_id=query_id,
            event_ids=(),
            before_hash=saved_query_snapshot_hash(previous),
            after_hash=saved_query_snapshot_hash(current),
            change_kind=change_kind,
        )
        query_name = current.query_name if current is not None else previous.query_name
        diff_path = _saved_query_diff_path(at, query_id, change_id)
        change = SavedQueryDetectedChange(
            query_id=query_id,
            query_name=query_name,
            before=previous,
            after=current,
            diff=diff,
            change_id=change_id,
            diff_path=diff_path,
            github_diff_url=self._github_blob_url(diff_path),
            should_create_issue=target.monitor_status == MonitorStatus.MONITOR,
        )
        files = {
            path: (
                saved_query_snapshot_to_json_bytes(current)
                if current is not None
                else None
            ),
            diff_path: render_saved_query_diff_markdown(
                change,
                window_start=window_start,
                window_end=window_end,
            ).encode("utf-8"),
        }
        return change, files, False

    async def _fetch_workflow_project_if_exists(
        self,
        project_id: str,
    ) -> WorkflowProjectDetail | None:
        """project詳細を取得し、HTTP 404だけを削除状態へ変換する。"""
        try:
            return await self._workflow.fetch_project(project_id)
        except ExternalApiError as exc:
            if exc.status_code == 404:
                return None
            raise

    async def _read_workflow_snapshot(
        self,
        project_name: str,
    ) -> WorkflowProjectSnapshot | None:
        """Git currentディレクトリからWorkflow project snapshotを復元する。"""
        prefix = _workflow_path_prefix(project_name)
        metadata_text = await self._repository.read_text(
            f"{prefix}/{WORKFLOW_METADATA_FILE}"
        )
        if metadata_text is None:
            return None
        try:
            metadata = json.loads(metadata_text)
        except json.JSONDecodeError as exc:
            raise ChangeMonitorError("Workflow snapshot metadata was invalid") from exc
        if not isinstance(metadata, Mapping):
            raise ChangeMonitorError("Workflow snapshot metadata was invalid")
        entries = metadata.get("files")
        if not isinstance(entries, list):
            raise ChangeMonitorError("Workflow snapshot metadata did not include files")

        files: dict[str, bytes] = {
            WORKFLOW_METADATA_FILE: metadata_text.encode("utf-8")
        }
        for entry in entries:
            if not isinstance(entry, Mapping) or not isinstance(entry.get("path"), str):
                raise ChangeMonitorError("Workflow snapshot file metadata was invalid")
            relative_path = str(entry["path"])
            text = await self._repository.read_text(f"{prefix}/{relative_path}")
            if text is None:
                raise ChangeMonitorError("Workflow snapshot file was missing")
            files[relative_path] = text.encode("utf-8")
        try:
            return workflow_snapshot_from_files(files)
        except ValueError as exc:
            raise ChangeMonitorError("Workflow snapshot could not be restored") from exc

    async def _read_workflow_schedule_snapshot(
        self,
        project_name: str,
    ) -> WorkflowProjectScheduleSnapshot | None:
        """Git current JSONからWorkflow schedule snapshotを復元する。"""
        text = await self._repository.read_text(_workflow_schedule_path(project_name))
        if text is None:
            return None
        try:
            return workflow_schedule_snapshot_from_bytes(text.encode("utf-8"))
        except ValueError as exc:
            raise ChangeMonitorError(
                "Workflow schedule snapshot could not be restored"
            ) from exc

    async def _read_saved_query_snapshot(
        self,
        path: str,
    ) -> SavedQuerySnapshot | None:
        """Git current JSONから登録クエリsnapshotを復元する。"""
        text = await self._repository.read_text(path)
        if text is None:
            return None
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ChangeMonitorError("saved query snapshot JSON was invalid") from exc
        if not isinstance(payload, Mapping):
            raise ChangeMonitorError("saved query snapshot JSON was invalid")
        try:
            return saved_query_snapshot_from_mapping(payload)
        except ValueError as exc:
            raise ChangeMonitorError("saved query snapshot could not be restored") from exc

    def _github_blob_url(self, path: str) -> str:
        """生成予定成果物のGitHub blob URLを作る。"""
        return (
            f"{self._settings.github_repository_url.rstrip('/')}"
            f"/blob/{self._settings.git_branch}/{path}"
        )


def _workflow_deleted_change(
    before: WorkflowProjectSnapshot,
    before_schedules: WorkflowProjectScheduleSnapshot | None,
    *,
    at: datetime,
    github_url: Callable[[str], str],
    should_create_issue: bool,
) -> WorkflowDetectedChange:
    """削除済みWorkflow projectの決定的な変更モデルを作る。"""
    before_hash = _workflow_combined_hash(before, before_schedules)
    change_id = build_resource_change_id(
        resource_type="workflow_project",
        stable_resource_id=before.project_id,
        event_ids=(),
        before_hash=before_hash,
        after_hash="none",
        change_kind="deleted",
    )
    diff_path = _workflow_diff_path(at, before.project_name, change_id)
    return WorkflowDetectedChange(
        project_id=before.project_id,
        project_name=before.project_name,
        before=before,
        after=None,
        before_schedules=before_schedules,
        after_schedules=None,
        diff=None,
        change_kind="deleted",
        change_id=change_id,
        diff_path=diff_path,
        github_diff_url=github_url(diff_path),
        should_create_issue=should_create_issue,
    )


def _workflow_current_file_changes(
    *,
    previous_name: str,
    before: WorkflowProjectSnapshot | None,
    before_schedules: WorkflowProjectScheduleSnapshot | None,
    after: WorkflowProjectSnapshot | None,
    after_schedules: WorkflowProjectScheduleSnapshot | None,
) -> dict[str, bytes | None]:
    """Workflow currentの追加・更新・rename・削除を明示pathへ変換する。"""
    files: dict[str, bytes | None] = {}
    before_prefix = _workflow_path_prefix(previous_name)
    old_files = workflow_snapshot_to_files(before) if before is not None else {}
    if before is not None:
        for relative_path in old_files:
            files[f"{before_prefix}/{relative_path}"] = None
        if before_schedules is not None:
            files[_workflow_schedule_path(previous_name)] = None

    if after is not None:
        after_prefix = _workflow_path_prefix(after.project_name)
        for relative_path, content in workflow_snapshot_to_files(after).items():
            files[f"{after_prefix}/{relative_path}"] = content
        if after_schedules is not None:
            files[_workflow_schedule_path(after.project_name)] = (
                workflow_schedule_snapshot_to_bytes(after_schedules)
            )
    return files


def _workflow_combined_hash(
    project: WorkflowProjectSnapshot | None,
    schedules: WorkflowProjectScheduleSnapshot | None,
) -> str:
    """Workflowファイル状態とschedule状態を1つのhashへ集約する。"""
    content = (
        f"{workflow_project_snapshot_hash(project)}\n"
        f"{workflow_schedule_snapshot_hash(schedules)}"
    )
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _workflow_path_prefix(project_name: str) -> str:
    """安全なproject名からWorkflow currentのprefixを作る。"""
    return f"workflows/current/{_safe_path_component(project_name)}"


def _workflow_schedule_path(project_name: str) -> str:
    """安全なproject名からWorkflow schedule current pathを作る。"""
    return f"workflow_schedules/current/{_safe_path_component(project_name)}.json"


def _saved_query_path(query_id: str) -> str:
    """Query IDから登録クエリcurrent pathを作る。"""
    if not query_id.isdigit():
        raise ValueError("query_id must contain digits only")
    return f"saved_queries/current/{query_id}.json"


def _workflow_diff_path(at: datetime, project_name: str, change_id: str) -> str:
    """Workflow差分のUTC日付別pathを作る。"""
    name = _safe_path_component(project_name)
    return f"diffs/workflows/{at:%Y/%m/%d}/{name}_{change_id}.md"


def _saved_query_diff_path(at: datetime, query_id: str, change_id: str) -> str:
    """登録クエリ差分のUTC日付別pathを作る。"""
    if not query_id.isdigit():
        raise ValueError("query_id must contain digits only")
    return f"diffs/saved_queries/{at:%Y/%m/%d}/{query_id}_{change_id}.md"


def _safe_path_component(value: str) -> str:
    """外部リソース名を単一の安全なrepository path要素に限定する。"""
    if (
        not value
        or value in {".", ".."}
        or not _SAFE_PATH_COMPONENT_RE.fullmatch(value)
    ):
        raise ChangeMonitorError(f"resource name is unsafe for Git path: {value!r}")
    return value


def _required_id(value: str | None) -> str:
    """active targetの安定IDが存在することを型上でも確定する。"""
    if value is None:
        raise ValueError("active resource target did not include stable ID")
    return value


def _merge_files(
    destination: dict[str, bytes | None],
    additions: Mapping[str, bytes | None],
) -> None:
    """複数リソースのFileChangeで同じpathが競合することを拒否する。"""
    for path, content in additions.items():
        if path in destination and destination[path] != content:
            raise ChangeMonitorError(f"generated resource path conflicted: {path}")
        destination[path] = content
