from __future__ import annotations

from typing import Any

import httpx
from tenacity import AsyncRetrying, retry_if_exception, stop_after_attempt, wait_exponential

from td_change_monitor.errors import ExternalApiError


def build_timeout(connect_seconds: float, read_seconds: float) -> httpx.Timeout:
    """API通信で共通使用するHTTPタイムアウトを作る。

    引数:
        connect_seconds: 接続確立までの上限秒数。
        read_seconds: レスポンス読取待ちの上限秒数。
    戻り値:
        connect/read/write/poolを設定したhttpx.Timeout。
    """
    return httpx.Timeout(
        connect=connect_seconds,
        read=read_seconds,
        write=read_seconds,
        pool=connect_seconds,
    )


class RetryingHttpClient:
    """一時的なHTTP障害だけを指数バックオフで再試行する。"""

    def __init__(self, client: httpx.AsyncClient, *, max_retries: int) -> None:
        """HTTPクライアントと最大試行回数を保持する。

        引数:
            client: 実際の通信を行うhttpx非同期クライアント。
            max_retries: 初回を含む最大試行回数。
        戻り値:
            なし。
        """
        self._client = client
        self._max_retries = max(1, max_retries)

    async def request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        """再試行方針を適用してHTTPリクエストを送る。

        引数:
            method: HTTPメソッド。
            url: base URLからの相対URLまたは絶対URL。
            kwargs: httpxへ渡すquery、JSON、formなどの追加引数。
        戻り値:
            成功したhttpx.Response。
        """
        async for attempt in AsyncRetrying(
            reraise=True,
            stop=stop_after_attempt(self._max_retries),
            wait=wait_exponential(multiplier=0.5, min=0.5, max=5),
            retry=retry_if_exception(_is_retryable),
        ):
            with attempt:
                return await self._request_once(method, url, **kwargs)
        raise AssertionError("unreachable retry loop exit")

    async def _request_once(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        """HTTPリクエストを1回送り、安全な例外へ変換する。

        引数:
            method: HTTPメソッド。
            url: リクエスト先URL。
            kwargs: httpxへ渡す追加引数。
        戻り値:
            2xxレスポンス。
        """
        try:
            response = await self._client.request(method, url, **kwargs)
        except httpx.TransportError as exc:
            request = getattr(exc, "request", None)
            target = _safe_request_url(request) if request is not None else f"{method} {url}"
            raise ExternalApiError(
                f"transport error during {target}",
                transient=True,
            ) from exc

        if response.status_code >= 400:
            transient = response.status_code == 429 or response.status_code >= 500
            raise ExternalApiError(
                f"HTTP {response.status_code} from {_safe_request_url(response.request)}",
                status_code=response.status_code,
                transient=transient,
            )
        return response


def _is_retryable(exc: BaseException) -> bool:
    """例外が再試行可能な外部API障害かを判定する。

    引数:
        exc: tenacityが受け取った例外。
    戻り値:
        transientなExternalApiErrorならTrue。
    """
    return isinstance(exc, ExternalApiError) and exc.transient


def _safe_request_url(request: httpx.Request) -> str:
    """query parameterを除いたリクエストURLを返す。

    引数:
        request: 失敗したhttpxリクエスト。
    戻り値:
        scheme、host、pathだけを含むURL。
    """
    safe_url = request.url.copy_with(query=b"")
    return f"{request.method} {safe_url}"
