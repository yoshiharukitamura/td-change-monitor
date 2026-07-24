from __future__ import annotations

import asyncio
import shutil
import subprocess
from pathlib import Path

import pytest
from conftest import make_settings

from td_change_monitor.clients.local_git import (
    FileChange,
    LocalGitRepositoryClient,
)
from td_change_monitor.errors import ChangeMonitorError


def run_git(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    )


@pytest.fixture
def git_repository(tmp_path: Path) -> tuple[Path, list[list[str]]]:
    if shutil.which("git") is None:
        pytest.skip("git executable is not installed")
    remote = tmp_path / "remote.git"
    work = tmp_path / "work"
    remote.mkdir()
    work.mkdir()
    run_git(remote, "init", "--bare")
    run_git(work, "init", "-b", "main")
    run_git(work, "config", "user.name", "Test User")
    run_git(work, "config", "user.email", "test@example.com")
    (work / "README.md").write_text("test repository\n", encoding="utf-8")
    run_git(work, "add", "README.md")
    run_git(work, "commit", "-m", "Initial commit")
    run_git(work, "remote", "add", "origin", str(remote))
    run_git(work, "push", "-u", "origin", "main")
    commands: list[list[str]] = []
    return work, commands


def recording_runner(
    commands: list[list[str]],
):
    def runner(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
        commands.append(args)
        return subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    return runner


def test_local_git_stages_only_allowed_paths_in_one_commit_and_pushes(
    git_repository: tuple[Path, list[list[str]]],
) -> None:
    work, commands = git_repository
    client = LocalGitRepositoryClient(
        make_settings(git_repository_path=work),
        runner=recording_runner(commands),
    )
    before_count = int(run_git(work, "rev-list", "--count", "HEAD").stdout)

    asyncio.run(client.prepare(push_pending=True))
    sha = asyncio.run(
        client.commit_files(
            changes=[
                FileChange("schemas/current/db/table.json", b"{}\n"),
                FileChange("schemas/current/db/table2.json", b"{}\n"),
                FileChange("diffs/2026/07/13/db.table_change.md", b"diff\n"),
                FileChange("audit_events/2026/07/13/db.table_change.json", b"{}\n"),
                FileChange("state/state.json", b"{}\n"),
            ],
            message="Record test changes",
        )
    )

    assert sha == run_git(work, "rev-parse", "HEAD").stdout.strip()
    assert int(run_git(work, "rev-list", "--count", "HEAD").stdout) == before_count + 1
    assert run_git(work, "status", "--short").stdout == ""
    assert run_git(work, "rev-parse", "origin/main").stdout.strip() == sha
    add_commands = [args for args in commands if "add" in args]
    assert len(add_commands) == 5
    assert all(args[-2] == "--" for args in add_commands)
    assert all(args[-1] != "." for args in add_commands)
    assert not list(work.rglob("*.tmp"))


def test_local_git_rejects_oversized_generated_file_without_writing(
    git_repository: tuple[Path, list[list[str]]],
) -> None:
    work, commands = git_repository
    client = LocalGitRepositoryClient(
        make_settings(git_repository_path=work, max_generated_file_size_mb=1),
        runner=recording_runner(commands),
    )

    with pytest.raises(ChangeMonitorError, match="exceeds size limit"):
        asyncio.run(
            client.commit_files(
                changes=[
                    FileChange(
                        "diffs/2026/07/13/db.table_large.md",
                        b"x" * (1024 * 1024 + 1),
                    )
                ],
                message="Must fail",
            )
        )

    assert not (work / "diffs").exists()
    assert run_git(work, "status", "--short").stdout == ""


def test_local_git_rejects_detectable_secret_without_writing(
    git_repository: tuple[Path, list[list[str]]],
) -> None:
    work, commands = git_repository
    client = LocalGitRepositoryClient(
        make_settings(git_repository_path=work),
        runner=recording_runner(commands),
    )
    webhook = (
        "https://hooks.slack.com/services/" + "T" * 12 + "/" + "B" * 12
    ).encode()

    with pytest.raises(ChangeMonitorError, match="contains a detectable secret"):
        asyncio.run(
            client.commit_files(
                changes=[FileChange("workflows/current/sample/main.dig", webhook)],
                message="Must fail",
            )
        )

    assert not (work / "workflows").exists()
    assert run_git(work, "status", "--short").stdout == ""


def test_local_git_rejects_paths_outside_generated_directories(
    git_repository: tuple[Path, list[list[str]]],
) -> None:
    work, commands = git_repository
    client = LocalGitRepositoryClient(
        make_settings(git_repository_path=work),
        runner=recording_runner(commands),
    )

    with pytest.raises(ChangeMonitorError, match="outside generated Git targets"):
        asyncio.run(
            client.commit_files(
                changes=[FileChange("README.md", b"replaced\n")],
                message="Must fail",
            )
        )

    assert (work / "README.md").read_text(encoding="utf-8") == "test repository\n"


def test_local_git_refuses_unexpected_staged_file_and_restores_generated_files(
    git_repository: tuple[Path, list[list[str]]],
) -> None:
    work, commands = git_repository
    client = LocalGitRepositoryClient(
        make_settings(git_repository_path=work),
        runner=recording_runner(commands),
    )
    (work / "README.md").write_text("changed by user\n", encoding="utf-8")
    run_git(work, "add", "README.md")

    with pytest.raises(ChangeMonitorError, match="unexpected staged file"):
        asyncio.run(
            client.commit_files(
                changes=[FileChange("state/state.json", b"{}\n")],
                message="Must fail",
            )
        )

    assert not (work / "state" / "state.json").exists()
    assert run_git(work, "diff", "--cached", "--name-only").stdout.strip() == "README.md"
    assert not list(work.rglob("*.tmp"))
