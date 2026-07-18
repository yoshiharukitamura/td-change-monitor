from __future__ import annotations

from typing import Any

import httpx
from tenacity import AsyncRetrying, retry_if_exception, stop_after_attempt, wait_exponential

from td_change_monitor.errors import ExternalApiError


def build_timeout(connect_seconds: float, read_seconds: float) -> httpx.Timeout:
    return httpx.Timeout(
        connect=connect_seconds,
        read=read_seconds,
        write=read_seconds,
        pool=connect_seconds,
    )


class RetryingHttpClient:
    def __init__(self, client: httpx.AsyncClient, *, max_retries: int) -> None:
        self._client = client
        self._max_retries = max(1, max_retries)

    async def request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
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
    return isinstance(exc, ExternalApiError) and exc.transient


def _safe_request_url(request: httpx.Request) -> str:
    safe_url = request.url.copy_with(query=b"")
    return f"{request.method} {safe_url}"
