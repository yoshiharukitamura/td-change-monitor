from __future__ import annotations


class ChangeMonitorError(RuntimeError):
    """業務上想定される実行失敗の基底例外を表す。"""


class ExternalApiError(ChangeMonitorError):
    """TDまたはBacklogとの通信失敗を表す。"""

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        transient: bool = False,
    ) -> None:
        """APIエラーの詳細を保持する。

        引数:
            message: エラー内容を表すメッセージ。
            status_code: HTTPステータスコード。不明な場合はNone。
            transient: 再試行可能な一時障害かどうか。
        戻り値:
            なし。
        """
        super().__init__(message)
        self.status_code = status_code
        self.transient = transient


class UnresolvedAuditEventsError(ChangeMonitorError):
    """対象tableを特定できないAuditイベントが存在する失敗を表す。"""

    def __init__(self, count: int) -> None:
        """解決不能イベント数を保持する。

        引数:
            count: tableを特定できなかったイベント数。
        戻り値:
            なし。
        """
        super().__init__(f"{count} audit event(s) could not be resolved to a table")
        self.count = count
