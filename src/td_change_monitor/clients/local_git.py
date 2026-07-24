from __future__ import annotations

import asyncio
import os
import subprocess
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from td_change_monitor.config import Settings
from td_change_monitor.errors import ChangeMonitorError

GitRunner = Callable[[list[str], Path], subprocess.CompletedProcess[str]]


@dataclass(frozen=True)
class FileChange:
    """1つの自動生成ファイルに対する書き込みまたは削除を表す。"""
    path: str
    content: bytes | None

    @property
    def is_delete(self) -> bool:
        """ファイル変更が削除操作かを返す。

        引数:
            なし。
        戻り値:
            contentがNoneならTrue。
        """
        return self.content is None


class LocalGitRepositoryClient:
    """ローカル作業ツリーの準備、原子的更新、commit、pushを担当する。"""

    def __init__(self, settings: Settings, *, runner: GitRunner | None = None) -> None:
        """Git設定とコマンド実行関数を保持する。

        引数:
            settings: repositoryパス、remote、branch、コミッター設定。
            runner: テストなどで注入するGitコマンド実行関数。
        戻り値:
            なし。
        """
        self._settings = settings
        self._repository = settings.git_repository_path.resolve()
        self._runner = runner or _run_command

    async def prepare(self, *, push_pending: bool) -> None:
        """ブロッキングGit処理を別threadで実行し作業ツリーを準備する。

        引数:
            push_pending: push待ちローカルcommitを先にpushするかどうか。
        戻り値:
            なし。
        """
        await asyncio.to_thread(self._prepare, push_pending)

    async def read_text(self, path: str) -> str | None:
        """repository内の自動生成ファイルをUTF-8で読む。

        引数:
            path: repositoryルートからの相対パス。
        戻り値:
            ファイル内容。存在しなければNone。
        """
        target = self._resolve_generated_path(path)
        if not target.exists():
            return None
        return await asyncio.to_thread(target.read_text, encoding="utf-8")

    async def commit_files(self, *, changes: list[FileChange], message: str) -> str:
        """指定変更だけを反映し、1commitでremoteへpushする。

        引数:
            changes: 書き込み・削除する自動生成ファイル一覧。
            message: Git commitメッセージ。
        戻り値:
            作成してpushしたcommit SHA。
        """
        return await asyncio.to_thread(self._commit_files, changes, message)

    def _prepare(self, push_pending: bool) -> None:
        """branch・stage・作業ツリーを検査しremoteと同期する。

        引数:
            push_pending: remoteより先行するcommitをpushするかどうか。
        戻り値:
            なし。
        """
        if not self._repository.is_dir() or not (self._repository / ".git").exists():
            raise ChangeMonitorError(
                f"GIT_REPOSITORY_PATH is not a Git repository: {self._repository}"
            )
        branch = self._git("branch", "--show-current").stdout.strip()
        if branch != self._settings.git_branch:
            raise ChangeMonitorError(
                f"local Git branch is {branch!r}; expected {self._settings.git_branch!r}"
            )
        if self._git("diff", "--cached", "--name-only").stdout.strip():
            raise ChangeMonitorError("local Git repository already has staged files")
        self._git(
            "pull",
            "--ff-only",
            self._settings.git_remote_name,
            self._settings.git_branch,
        )
        if push_pending:
            self._git("push", self._settings.git_remote_name, self._settings.git_branch)

    def _commit_files(self, changes: list[FileChange], message: str) -> str:
        """ファイル変更を原子的に適用し、明示パスだけをstageしてpushする。

        引数:
            changes: 適用するFileChange一覧。
            message: Git commitメッセージ。
        戻り値:
            push済みcommit SHA。実変更がなければ現在のHEAD SHA。
        """
        # 書き込み前の内容を保持し、サイズ超過やGit失敗時に作業ツリーを元へ戻す。
        if not changes:
            return self._git("rev-parse", "HEAD").stdout.strip()
        ordered = sorted(changes, key=lambda item: item.path)
        backups: dict[Path, bytes | None] = {}
        max_bytes = self._settings.max_generated_file_size_mb * 1024 * 1024
        for change in ordered:
            target = self._resolve_generated_path(change.path)
            if change.content is not None and len(change.content) > max_bytes:
                size_mb = len(change.content) / (1024 * 1024)
                raise ChangeMonitorError(
                    f"generated file exceeds size limit: {change.path} ({size_mb:.2f} MB)"
                )
            backups[target] = target.read_bytes() if target.exists() else None

        committed = False
        try:
            for change in ordered:
                target = self._resolve_generated_path(change.path)
                if change.content is None:
                    target.unlink(missing_ok=True)
                else:
                    _atomic_write(target, change.content)
            for change in ordered:
                self._git("add", "-A", "--", change.path)
            self._validate_staged_paths()
            if self._git("diff", "--cached", "--quiet", check=False).returncode == 0:
                return self._git("rev-parse", "HEAD").stdout.strip()
            self._git(
                "-c",
                f"user.name={self._settings.git_committer_name}",
                "-c",
                f"user.email={self._settings.git_committer_email}",
                "commit",
                "-m",
                message,
            )
            committed = True
            self._git("push", self._settings.git_remote_name, self._settings.git_branch)
            return self._git("rev-parse", "HEAD").stdout.strip()
        except Exception:
            if not committed:
                _restore_files(backups)
                self._git(
                    "reset",
                    "--",
                    *(change.path for change in ordered),
                    check=False,
                )
            raise

    def _validate_staged_paths(self) -> None:
        """stage済みファイルが許可された自動生成パスだけか検証する。

        引数:
            なし。
        戻り値:
            なし。許可外パスがあれば例外を送出する。
        """
        staged = self._git("diff", "--cached", "--name-only").stdout.splitlines()
        unexpected = [path for path in staged if not _is_generated_path(path)]
        if unexpected:
            raise ChangeMonitorError(
                "unexpected staged file; refusing commit: " + ", ".join(sorted(unexpected))
            )

    def _resolve_generated_path(self, path: str) -> Path:
        """相対パスをrepository内の安全な自動生成パスへ解決する。

        引数:
            path: repositoryルート基準の相対パス。
        戻り値:
            repository外へ出ないことを確認した絶対Path。
        """
        if not _is_generated_path(path):
            raise ChangeMonitorError(f"path is outside generated Git targets: {path}")
        relative = PurePosixPath(path)
        if relative.is_absolute() or ".." in relative.parts:
            raise ChangeMonitorError(f"invalid generated path: {path}")
        target = (self._repository / Path(*relative.parts)).resolve()
        if self._repository not in target.parents:
            raise ChangeMonitorError(f"generated path escapes repository: {path}")
        return target

    def _git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        """共通repositoryを作業ディレクトリとしてGitコマンドを実行する。

        引数:
            args: git実行ファイルへ渡す引数列。
            check: 終了コード非0を例外にするかどうか。
        戻り値:
            標準出力・標準エラー・終了コードを含む実行結果。
        """
        result = self._runner([self._settings.git_executable, *args], self._repository)
        if check and result.returncode != 0:
            operation = next((arg for arg in args if not arg.startswith("-")), "command")
            raise ChangeMonitorError(f"git {operation} failed with exit code {result.returncode}")
        return result


def _is_generated_path(path: str) -> bool:
    """パスが自動生成を許可された管理対象か判定する。

    引数:
        path: repositoryルート基準の相対パス。
    戻り値:
        各resourceのcurrent、diff、Audit、stateのいずれかならTrue。
    """
    normalized = path.replace("\\", "/")
    return (
        normalized.startswith("schemas/current/")
        or normalized.startswith("workflows/current/")
        or normalized.startswith("workflow_schedules/current/")
        or normalized.startswith("saved_queries/current/")
        or normalized.startswith("diffs/")
        or normalized.startswith("audit_events/")
        or normalized == "state/state.json"
    )


def _atomic_write(target: Path, content: bytes) -> None:
    """一時ファイルを経由して対象ファイルを原子的に置換する。

    引数:
        target: 書き込み先の絶対Path。
        content: 書き込むバイト列。
    戻り値:
        なし。
    """
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, target)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def _restore_files(backups: dict[Path, bytes | None]) -> None:
    """処理失敗時に変更対象ファイルを実行前状態へ戻す。

    引数:
        backups: 対象Pathと変更前内容の対応。元がなければNone。
    戻り値:
        なし。
    """
    for target, content in backups.items():
        if content is None:
            target.unlink(missing_ok=True)
        else:
            _atomic_write(target, content)


def _run_command(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """Gitコマンドを非対話設定で実行する。

    引数:
        args: 実行ファイルを含むコマンド引数一覧。
        cwd: Git repositoryの作業ディレクトリ。
    戻り値:
        UTF-8として取得したコマンド実行結果。
    """
    return subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
