from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import httpx

from td_change_monitor.clients.http import RetryingHttpClient, build_timeout
from td_change_monitor.config import Settings
from td_change_monitor.errors import ExternalApiError
from td_change_monitor.models import (
    WorkflowDefinitionSummary,
    WorkflowProjectDetail,
    WorkflowProjectReference,
    WorkflowReference,
    WorkflowScheduleDetail,
)


class TreasureDataWorkflowClient:
    """確認済みのTreasure Workflow APIから一覧情報を取得する。"""

    def __init__(
        self,
        settings: Settings,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        """Workflow API用HTTPクライアントを初期化する。

        引数:
            settings: Workflow接続先、TD APIキー、HTTP設定を含む設定。
            client: テストなどで注入するhttpxクライアント。
        戻り値:
            なし。
        """
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=settings.td_workflow_api_base_url.rstrip("/"),
            timeout=build_timeout(
                settings.http_connect_timeout_seconds,
                settings.http_read_timeout_seconds,
            ),
            headers={
                "Authorization": f"TD1 {settings.td_api_key.get_secret_value()}",
                "Accept": "application/json",
            },
        )
        self._http = RetryingHttpClient(self._client, max_retries=settings.http_max_retries)

    async def fetch_workflow_page_by_project_name(
        self,
        project_name: str,
        *,
        last_id: int = 0,
        count: int = 3,
    ) -> tuple[WorkflowDefinitionSummary, ...]:
        """プロジェクト名で絞ったWorkflow一覧の1ページを取得する。

        引数:
            project_name: 検索するWorkflowプロジェクト名。
            last_id: このIDより後を取得するためのページ開始値。
            count: 取得するWorkflowの最大件数。
        戻り値:
            ID、名前、project、revision、timezoneだけを持つWorkflow一覧。
        """
        if not project_name.strip():
            raise ValueError("project_name must not be blank")
        if last_id < 0:
            raise ValueError("last_id must be zero or greater")
        if count < 1:
            raise ValueError("count must be one or greater")

        response = await self._http.request(
            "GET",
            "api/workflows",
            params={
                "last_id": last_id,
                "count": count,
                "order": "asc",
                "name_pattern": project_name,
                "search_project_name": "true",
            },
        )
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD Workflow list response")
        workflows = payload.get("workflows")
        if not isinstance(workflows, list):
            raise ExternalApiError("TD Workflow list response did not include workflows")
        return tuple(_workflow_summary(item) for item in workflows)

    async def fetch_project(self, project_id: str) -> WorkflowProjectDetail:
        """Workflowプロジェクトの現在revisionとarchive識別情報を取得する。

        引数:
            project_id: 取得するWorkflowプロジェクトの数値ID。
        戻り値:
            project ID、名前、revision、archiveMd5、archiveType。
        """
        if not project_id.isdigit():
            raise ValueError("project_id must contain digits only")

        response = await self._http.request("GET", f"api/projects/{project_id}")
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD Workflow project response")
        return _project_detail(payload)

    async def fetch_project_archive(self, project_id: str, revision: str) -> bytes:
        """指定revisionのWorkflowプロジェクトarchiveを取得する。

        引数:
            project_id: archiveを取得するWorkflowプロジェクトの数値ID。
            revision: project詳細APIで取得したrevision。
        戻り値:
            呼出元が安全な一時領域だけで扱うgzip圧縮TARのバイト列。
        """
        if not project_id.isdigit():
            raise ValueError("project_id must contain digits only")
        if not revision.strip():
            raise ValueError("revision must not be blank")

        response = await self._http.request(
            "GET",
            f"api/projects/{project_id}/archive",
            params={
                "revision": revision,
                "direct_download": "false",
            },
            headers={"Accept": "application/gzip"},
        )
        if not response.content:
            raise ExternalApiError("TD Workflow archive response was empty")
        return response.content

    async def fetch_schedule(self, schedule_id: str) -> WorkflowScheduleDetail:
        """schedule IDから所属project、Workflow、有効状態を取得する。

        引数:
            schedule_id: 取得するWorkflow scheduleの数値ID。
        戻り値:
            自然変化する次回実行日時を除いたschedule詳細。
        """
        if not schedule_id.isdigit():
            raise ValueError("schedule_id must contain digits only")

        response = await self._http.request("GET", f"api/schedules/{schedule_id}")
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD Workflow schedule response")
        return _schedule_detail(payload)

    async def fetch_project_schedule_page(
        self,
        project_id: str,
        *,
        last_id: int = 0,
    ) -> tuple[WorkflowScheduleDetail, ...]:
        """projectに属するschedule一覧の1ページを取得する。

        引数:
            project_id: scheduleを列挙するWorkflowプロジェクトの数値ID。
            last_id: このschedule IDより後を取得するページ開始値。
        戻り値:
            動的な次回実行日時を除いて正規化したschedule一覧。
        """
        if not project_id.isdigit():
            raise ValueError("project_id must contain digits only")
        if last_id < 0:
            raise ValueError("last_id must be zero or greater")

        response = await self._http.request(
            "GET",
            f"api/projects/{project_id}/schedules",
            params={"last_id": last_id},
        )
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD Workflow schedule list response")
        schedules = payload.get("schedules")
        if not isinstance(schedules, list):
            raise ExternalApiError(
                "TD Workflow schedule list response did not include schedules"
            )
        return tuple(_schedule_detail(item) for item in schedules)

    async def fetch_project_schedules(
        self,
        project_id: str,
    ) -> tuple[WorkflowScheduleDetail, ...]:
        """projectに属するscheduleを空ページまで繰り返して全件取得する。

        引数:
            project_id: scheduleを列挙するWorkflowプロジェクトの数値ID。
        戻り値:
            schedule ID順に取得した全ページの正規化済みschedule一覧。
        """
        schedules: list[WorkflowScheduleDetail] = []
        last_id = 0
        while True:
            page = await self.fetch_project_schedule_page(project_id, last_id=last_id)
            if not page:
                return tuple(schedules)

            next_last_id = max(int(schedule.schedule_id) for schedule in page)
            if next_last_id <= last_id:
                raise ExternalApiError("TD Workflow schedule pagination did not advance")
            schedules.extend(page)
            last_id = next_last_id

    async def aclose(self) -> None:
        """内部で生成したHTTP接続を閉じる。

        引数:
            なし。
        戻り値:
            なし。
        """
        if self._owns_client:
            await self._client.aclose()


def _workflow_summary(payload: object) -> WorkflowDefinitionSummary:
    """Workflow APIの1要素を必要最小限のモデルへ変換する。

    引数:
        payload: `workflows`配列内の1要素。
    戻り値:
        Workflowと所属プロジェクトの識別情報。
    """
    if not isinstance(payload, Mapping):
        raise ExternalApiError("invalid TD Workflow item")
    project = payload.get("project")
    if not isinstance(project, Mapping):
        raise ExternalApiError("TD Workflow item did not include project")
    return WorkflowDefinitionSummary(
        workflow_id=_required_string(payload, "id"),
        workflow_name=_required_string(payload, "name"),
        project=WorkflowProjectReference(
            project_id=_required_string(project, "id"),
            project_name=_required_string(project, "name"),
        ),
        revision=_required_string(payload, "revision"),
        timezone=_required_string(payload, "timezone"),
    )


def _project_detail(payload: Mapping[str, Any]) -> WorkflowProjectDetail:
    """project詳細レスポンスを変更判定用モデルへ変換する。

    引数:
        payload: `GET /api/projects/{id}`のJSONオブジェクト。
    戻り値:
        日次比較に必要な固定識別項目だけを持つプロジェクト詳細。
    """
    return WorkflowProjectDetail(
        project_id=_required_string(payload, "id"),
        project_name=_required_string(payload, "name"),
        revision=_required_string(payload, "revision"),
        archive_md5=_required_string(payload, "archiveMd5"),
        archive_type=_required_string(payload, "archiveType"),
    )


def _schedule_detail(payload: Mapping[str, Any]) -> WorkflowScheduleDetail:
    """schedule詳細レスポンスを日次比較用モデルへ変換する。

    引数:
        payload: `GET /api/schedules/{id}`のJSONオブジェクト。
    戻り値:
        schedule、project、WorkflowのID・名前と有効状態。
    """
    project = payload.get("project")
    workflow = payload.get("workflow")
    if not isinstance(project, Mapping):
        raise ExternalApiError("TD Workflow schedule did not include project")
    if not isinstance(workflow, Mapping):
        raise ExternalApiError("TD Workflow schedule did not include workflow")
    disabled_at = payload.get("disabledAt")
    if disabled_at is not None and not isinstance(disabled_at, str):
        raise ExternalApiError("TD Workflow schedule disabledAt was invalid")
    return WorkflowScheduleDetail(
        schedule_id=_required_string(payload, "id"),
        project=WorkflowProjectReference(
            project_id=_required_string(project, "id"),
            project_name=_required_string(project, "name"),
        ),
        workflow=WorkflowReference(
            workflow_id=_required_string(workflow, "id"),
            workflow_name=_required_string(workflow, "name"),
        ),
        enabled=disabled_at is None,
    )


def _required_string(payload: Mapping[str, Any], key: str) -> str:
    """API項目を空でない文字列へ正規化する。

    引数:
        payload: 対象項目を含むJSONオブジェクト。
        key: 取得する項目名。
    戻り値:
        文字列へ正規化した項目値。
    """
    value = payload.get(key)
    if not isinstance(value, str | int) or not str(value).strip():
        raise ExternalApiError(f"TD Workflow item did not include {key}")
    return str(value)
