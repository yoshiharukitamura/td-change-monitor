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
    path: str
    content: bytes | None

    @property
    def is_delete(self) -> bool:
        return self.content is None


class LocalGitRepositoryClient:
    def __init__(self, settings: Settings, *, runner: GitRunner | None = None) -> None:
        self._settings = settings
        self._repository = settings.git_repository_path.resolve()
        self._runner = runner or _run_command

    async def prepare(self, *, push_pending: bool) -> None:
        await asyncio.to_thread(self._prepare, push_pending)

    async def read_text(self, path: str) -> str | None:
        target = self._resolve_generated_path(path)
        if not target.exists():
            return None
        return await asyncio.to_thread(target.read_text, encoding="utf-8")

    async def commit_files(self, *, changes: list[FileChange], message: str) -> str:
        return await asyncio.to_thread(self._commit_files, changes, message)

    def _prepare(self, push_pending: bool) -> None:
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
        staged = self._git("diff", "--cached", "--name-only").stdout.splitlines()
        unexpected = [path for path in staged if not _is_generated_path(path)]
        if unexpected:
            raise ChangeMonitorError(
                "unexpected staged file; refusing commit: " + ", ".join(sorted(unexpected))
            )

    def _resolve_generated_path(self, path: str) -> Path:
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
        result = self._runner([self._settings.git_executable, *args], self._repository)
        if check and result.returncode != 0:
            operation = next((arg for arg in args if not arg.startswith("-")), "command")
            raise ChangeMonitorError(f"git {operation} failed with exit code {result.returncode}")
        return result


def _is_generated_path(path: str) -> bool:
    normalized = path.replace("\\", "/")
    return (
        normalized.startswith("schemas/current/")
        or normalized.startswith("diffs/")
        or normalized.startswith("audit_events/")
        or normalized == "state/state.json"
    )


def _atomic_write(target: Path, content: bytes) -> None:
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
    for target, content in backups.items():
        if content is None:
            target.unlink(missing_ok=True)
        else:
            _atomic_write(target, content)


def _run_command(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
