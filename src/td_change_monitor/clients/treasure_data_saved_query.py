from __future__ import annotations

from collections.abc import Mapping
from typing import Any
from urllib.parse import urlsplit

import httpx

from td_change_monitor.clients.http import RetryingHttpClient, build_timeout
from td_change_monitor.config import Settings
from td_change_monitor.errors import ExternalApiError
from td_change_monitor.models import (
    SavedQueryDatabaseReference,
    SavedQueryDetail,
    SavedQueryOwnerReference,
    SavedQueryPage,
    SavedQuerySummary,
)


class TreasureDataSavedQueryClient:
    """確認済みのTD Console APIから登録クエリ詳細を取得する。"""

    def __init__(
        self,
        settings: Settings,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        """登録クエリAPI用HTTPクライアントを初期化する。

        引数:
            settings: Console API接続先、TD APIキー、HTTP設定を含む設定。
            client: テストなどで注入するhttpxクライアント。
        戻り値:
            なし。
        """
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=settings.td_console_api_base_url.rstrip("/"),
            timeout=build_timeout(
                settings.http_connect_timeout_seconds,
                settings.http_read_timeout_seconds,
            ),
            headers={
                "Authorization": f"TD1 {settings.td_api_key.get_secret_value()}",
                "Accept": "application/json",
                "id-format": "string",
                "key-format": "camelCase",
            },
        )
        self._http = RetryingHttpClient(
            self._client,
            max_retries=settings.http_max_retries,
        )

    async def fetch_query(self, query_id: str) -> SavedQueryDetail:
        """Query IDから登録クエリの現在状態を取得する。

        引数:
            query_id: 取得する登録クエリの数値ID。
        戻り値:
            動的な実行情報と権限情報を除いて正規化した登録クエリ詳細。
        """
        if not query_id.isdigit():
            raise ValueError("query_id must contain digits only")

        response = await self._http.request("GET", f"v4/queries/{query_id}")
        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD saved query response")
        detail = _saved_query_detail(payload)
        if detail.query_id != query_id:
            raise ExternalApiError("TD saved query response ID did not match request")
        return detail

    async def fetch_query_if_exists(
        self,
        query_id: str,
    ) -> SavedQueryDetail | None:
        """Query IDの登録クエリを取得し、削除済みならNoneを返す。

        引数:
            query_id: 取得する登録クエリの数値ID。
        戻り値:
            現在の登録クエリ詳細。HTTP 404ならNone。
        """
        try:
            return await self.fetch_query(query_id)
        except ExternalApiError as exc:
            if exc.status_code == 404:
                return None
            raise

    async def fetch_query_page(
        self,
        *,
        next_page: str | None = None,
    ) -> SavedQueryPage:
        """登録クエリ一覧の先頭ページまたは指定された次ページを取得する。

        引数:
            next_page: 直前レスポンスのpagination.nextPage。先頭はNone。
        戻り値:
            Query IDを含む登録クエリ一覧1ページと次ページ情報。
        """
        if next_page is None:
            response = await self._http.request(
                "GET",
                "v4/queries/paginated_index",
                params={"minimalConnectorConfig": "true"},
            )
        else:
            response = await self._http.request(
                "GET",
                _validated_next_page(next_page),
            )

        payload = response.json()
        if not isinstance(payload, Mapping):
            raise ExternalApiError("invalid TD saved query list response")
        return _saved_query_page(payload)

    async def fetch_queries(self) -> tuple[SavedQuerySummary, ...]:
        """nextPageを追跡して登録クエリ一覧を全ページ取得する。

        引数:
            なし。
        戻り値:
            Query IDの重複がない全登録クエリ一覧。
        """
        queries: list[SavedQuerySummary] = []
        seen_query_ids: set[str] = set()
        seen_next_pages: set[str] = set()
        next_page: str | None = None

        while True:
            page = await self.fetch_query_page(next_page=next_page)
            for query in page.queries:
                if query.query_id in seen_query_ids:
                    raise ExternalApiError(
                        "TD saved query pagination returned a duplicate query ID"
                    )
                seen_query_ids.add(query.query_id)
                queries.append(query)

            if not page.has_next_page:
                return tuple(queries)
            if page.next_page is None:
                raise ExternalApiError(
                    "TD saved query pagination did not include nextPage"
                )
            if page.next_page in seen_next_pages:
                raise ExternalApiError(
                    "TD saved query pagination returned a repeated nextPage"
                )
            seen_next_pages.add(page.next_page)
            next_page = page.next_page

    async def aclose(self) -> None:
        """内部で生成したHTTP接続を閉じる。

        引数:
            なし。
        戻り値:
            なし。
        """
        if self._owns_client:
            await self._client.aclose()


def _saved_query_detail(payload: Mapping[str, Any]) -> SavedQueryDetail:
    """登録クエリ詳細レスポンスを変更判定用モデルへ変換する。

    引数:
        payload: `GET /v4/queries/{query_id}`のJSONオブジェクト。
    戻り値:
        SQL、識別情報、エンジン、出力・固定schedule設定を持つ詳細。
    """
    query_string_truncated = payload.get("isQueryStringTruncated")
    if not isinstance(query_string_truncated, bool):
        raise ExternalApiError(
            "TD saved query response did not include isQueryStringTruncated"
        )
    if query_string_truncated:
        raise ExternalApiError("TD saved query response contained truncated SQL")

    summary = _saved_query_summary(payload)
    return SavedQueryDetail(
        query_id=summary.query_id,
        query_name=summary.query_name,
        database=summary.database,
        owner=summary.owner,
        engine_type=summary.engine_type,
        engine_version=summary.engine_version,
        connector_config=summary.connector_config,
        cron=summary.cron,
        timezone=summary.timezone,
        delay=summary.delay,
        priority=summary.priority,
        retry_limit=summary.retry_limit,
        description=summary.description,
        draft=summary.draft,
        query_string=_required_string(
            payload,
            "queryString",
            allow_whitespace_prefix=True,
        ),
    )


def _saved_query_summary(payload: object) -> SavedQuerySummary:
    """一覧または詳細レスポンスの1要素を共通の設定モデルへ変換する。

    引数:
        payload: queries配列の1要素または詳細JSONオブジェクト。
    戻り値:
        SQL本文と動的情報を除いた登録クエリの識別情報と設定。
    """
    if not isinstance(payload, Mapping):
        raise ExternalApiError("invalid TD saved query item")
    database = payload.get("database")
    owner = payload.get("user")
    connector_config = payload.get("connectorConfig")
    if not isinstance(database, Mapping):
        raise ExternalApiError("TD saved query response did not include database")
    if not isinstance(owner, Mapping):
        raise ExternalApiError("TD saved query response did not include user")
    if connector_config is not None and not isinstance(connector_config, Mapping):
        raise ExternalApiError("TD saved query connectorConfig was invalid")

    return SavedQuerySummary(
        query_id=_required_string(payload, "id"),
        query_name=_required_string(payload, "name", allow_whitespace_prefix=True),
        database=SavedQueryDatabaseReference(
            database_id=_required_string(database, "id"),
            database_name=_required_string(database, "name"),
        ),
        owner=SavedQueryOwnerReference(
            owner_id=_required_string(owner, "id"),
            owner_name=_required_string(owner, "name"),
        ),
        engine_type=_required_string(payload, "type"),
        engine_version=_required_string(payload, "engineVersion"),
        connector_config=dict(connector_config) if connector_config is not None else None,
        cron=_optional_string(payload, "cron"),
        timezone=_required_string(payload, "timeZone"),
        delay=_required_integer(payload, "delay"),
        priority=_required_integer(payload, "priority"),
        retry_limit=_required_integer(payload, "retryLimit"),
        description=_optional_string(payload, "description"),
        draft=_required_boolean(payload, "draft"),
    )


def _saved_query_page(payload: Mapping[str, Any]) -> SavedQueryPage:
    """一覧レスポンスを登録クエリ1ページへ変換する。

    引数:
        payload: `GET /v4/queries/paginated_index`のJSONオブジェクト。
    戻り値:
        正規化したqueries、総件数、次ページ情報。
    """
    queries = payload.get("queries")
    pagination = payload.get("pagination")
    if not isinstance(queries, list):
        raise ExternalApiError("TD saved query list did not include queries")
    if not isinstance(pagination, Mapping):
        raise ExternalApiError("TD saved query list did not include pagination")

    has_next_page = _required_boolean(pagination, "hasNextPage")
    next_page = _optional_string(pagination, "nextPage")
    if has_next_page and next_page is None:
        raise ExternalApiError("TD saved query pagination did not include nextPage")
    parsed_queries: list[SavedQuerySummary] = []
    for item in queries:
        # Console一覧にはdatabaseまたはuserがnullのクエリが含まれる場合がある。
        # これらは対象Excelのdatabase・ownerと照合できないため、一覧照合から除外する。
        # ID指定の詳細取得では従来どおり必須項目として検証し、監視を曖昧にしない。
        if (
            isinstance(item, Mapping)
            and (
                not isinstance(item.get("database"), Mapping)
                or not isinstance(item.get("user"), Mapping)
            )
        ):
            continue
        parsed_queries.append(_saved_query_summary(item))
    return SavedQueryPage(
        queries=tuple(parsed_queries),
        total_count=_required_integer(pagination, "queriesFound"),
        has_next_page=has_next_page,
        next_page=next_page,
    )


def _validated_next_page(next_page: str) -> str:
    """APIが返したnextPageを同一Console APIの相対URLに限定する。

    引数:
        next_page: pagination.nextPageの文字列。
    戻り値:
        同一APIパスであることを確認した相対URL。
    """
    parts = urlsplit(next_page)
    if (
        not next_page.strip()
        or parts.scheme
        or parts.netloc
        or parts.fragment
        or parts.path != "/v4/queries/paginated_index"
    ):
        raise ExternalApiError("TD saved query nextPage was invalid")
    return next_page


def _required_string(
    payload: Mapping[str, Any],
    key: str,
    *,
    allow_whitespace_prefix: bool = False,
) -> str:
    """必須API項目を空でない文字列へ正規化する。

    引数:
        payload: 対象項目を含むJSONオブジェクト。
        key: 取得する項目名。
        allow_whitespace_prefix: 先頭空白を値として保持するかどうか。
    戻り値:
        文字列へ正規化した項目値。
    """
    value = payload.get(key)
    if not isinstance(value, str | int) or not str(value).strip():
        raise ExternalApiError(f"TD saved query response did not include {key}")
    normalized = str(value)
    return normalized if allow_whitespace_prefix else normalized.strip()


def _optional_string(payload: Mapping[str, Any], key: str) -> str | None:
    """任意API項目を文字列またはNoneへ正規化する。

    引数:
        payload: 対象項目を含むJSONオブジェクト。
        key: 取得する項目名。
    戻り値:
        項目がnullならNone、それ以外は元の文字列。
    """
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ExternalApiError(f"TD saved query {key} was invalid")
    return value


def _required_integer(payload: Mapping[str, Any], key: str) -> int:
    """必須API項目をboolではない整数として取得する。

    引数:
        payload: 対象項目を含むJSONオブジェクト。
        key: 取得する項目名。
    戻り値:
        APIレスポンスに含まれる整数値。
    """
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ExternalApiError(f"TD saved query {key} was invalid")
    return value


def _required_boolean(payload: Mapping[str, Any], key: str) -> bool:
    """必須API項目を真偽値として取得する。

    引数:
        payload: 対象項目を含むJSONオブジェクト。
        key: 取得する項目名。
    戻り値:
        APIレスポンスに含まれる真偽値。
    """
    value = payload.get(key)
    if not isinstance(value, bool):
        raise ExternalApiError(f"TD saved query {key} was invalid")
    return value
