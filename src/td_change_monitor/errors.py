from __future__ import annotations


class ChangeMonitorError(RuntimeError):
    """Base exception for expected application failures."""


class ExternalApiError(ChangeMonitorError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        transient: bool = False,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.transient = transient


class UnresolvedAuditEventsError(ChangeMonitorError):
    def __init__(self, count: int) -> None:
        super().__init__(f"{count} audit event(s) could not be resolved to a table")
        self.count = count
