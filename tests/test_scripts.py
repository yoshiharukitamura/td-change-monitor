from __future__ import annotations

import os
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def test_gitignore_excludes_logs_temporary_files_and_environment() -> None:
    patterns = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()

    assert ".env" in patterns
    assert "logs/" in patterns
    assert "*.log" in patterns
    assert "*.tmp" in patterns
    assert not any(pattern.startswith("!logs/") for pattern in patterns)


def test_python_source_does_not_use_github_api_or_token() -> None:
    source = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "src").rglob("*.py"))

    assert "api.github.com" not in source
    assert "GITHUB_TOKEN" not in source
    assert "github_token" not in source


@pytest.mark.skipif(os.name != "nt", reason="PowerShell retention test runs on Windows")
def test_cleanup_logs_removes_only_expired_log_files(tmp_path: Path) -> None:
    log_dir = tmp_path / "logs"
    log_dir.mkdir()
    old_log = log_dir / "old.log"
    current_log = log_dir / "current.log"
    unrelated = log_dir / "keep.txt"
    old_log.write_text("old", encoding="utf-8")
    current_log.write_text("current", encoding="utf-8")
    unrelated.write_text("keep", encoding="utf-8")
    old_at = (datetime.now(UTC) - timedelta(days=31)).timestamp()
    os.utime(old_log, (old_at, old_at))
    environment = dict(os.environ)
    environment["LOCAL_LOG_RETENTION_DAYS"] = "30"

    result = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "scripts" / "cleanup_logs.ps1"),
            "-ProjectDir",
            str(tmp_path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert not old_log.exists()
    assert current_log.exists()
    assert unrelated.exists()
