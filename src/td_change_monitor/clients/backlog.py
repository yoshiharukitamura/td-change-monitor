from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import httpx

from td_change_monitor.clients.http import RetryingHttpClient, build_timeout
from td_change_monitor.config import Settings
from td_change_monitor.errors import ExternalApiError


class BacklogClient:
    def __init__(self, settings: Settings, *, client: httpx.AsyncClient | None = None) -> None:
        self._settings = settings
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=settings.backlog_base_url.rstrip("/"),
            timeout=build_timeout(
                settings.http_connect_timeout_seconds,
                settings.http_read_timeout_seconds,
            ),
        )
        self._http = RetryingHttpClient(self._client, max_retries=settings.http_max_retries)

    async def ensure_issue(
        self,
        *,
        change_id: str,
        summary: str,
        description: str,
    ) -> str:
        """Return the existing or newly-created issue key."""
        existing = await self._find_issue(change_id)
        if existing is not None:
            return existing
        return await self._create_issue(summary=summary, description=description)

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def _find_issue(self, change_id: str) -> str | None:
        response = await self._http.request(
            "GET",
            "api/v2/issues",
            params=[
                ("apiKey", self._settings.backlog_api_key.get_secret_value()),
                ("projectId[]", str(self._settings.backlog_project_id)),
                ("keyword", change_id),
                ("count", "100"),
            ],
        )
        payload = response.json()
        if not isinstance(payload, list):
            raise ExternalApiError("invalid Backlog issue list response")
        for item in payload:
            issue = _json_mapping(item)
            key = issue.get("issueKey") or issue.get("key")
            if isinstance(key, str):
                return key
        return None

    async def _create_issue(self, *, summary: str, description: str) -> str:
        data = [
            ("apiKey", self._settings.backlog_api_key.get_secret_value()),
            ("projectId", str(self._settings.backlog_project_id)),
            ("issueTypeId", str(self._settings.backlog_issue_type_id)),
            ("priorityId", str(self._settings.backlog_priority_id)),
            ("summary", summary),
            ("description", description),
        ]
        if self._settings.backlog_assignee_id is not None:
            data.append(("assigneeId", str(self._settings.backlog_assignee_id)))
        for category_id in self._settings.backlog_category_ids:
            data.append(("categoryId[]", str(category_id)))

        response = await self._http.request("POST", "api/v2/issues", data=data)
        payload = _json_mapping(response.json())
        key = payload.get("issueKey") or payload.get("key")
        if not isinstance(key, str):
            raise ExternalApiError("invalid Backlog issue create response")
        return key


def _json_mapping(value: object) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ExternalApiError("expected JSON object")
    return value
