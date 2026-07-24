from __future__ import annotations

import asyncio
import hashlib
import io
import tarfile
from pathlib import Path

import pytest

from td_change_monitor.models import (
    WorkflowFileSnapshot,
    WorkflowProjectDetail,
    WorkflowProjectSnapshot,
)
from td_change_monitor.workflow_archive import (
    WORKFLOW_METADATA_FILE,
    WorkflowArchiveError,
    load_workflow_project_snapshot,
    snapshot_from_workflow_archive,
    workflow_snapshot_from_files,
    workflow_snapshot_to_files,
)


def project_detail(
    *,
    revision: str = "revision-2",
    archive_md5: str = "archive-md5-2",
) -> WorkflowProjectDetail:
    return WorkflowProjectDetail(
        project_id="1001",
        project_name="sample_project",
        revision=revision,
        archive_md5=archive_md5,
        archive_type="s3",
    )


def workflow_file(path: str, content: str) -> WorkflowFileSnapshot:
    normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    return WorkflowFileSnapshot(
        path=path,
        content=normalized,
        content_hash=hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
    )


def project_snapshot(
    *files: WorkflowFileSnapshot,
    revision: str = "revision-1",
    archive_md5: str = "archive-md5-1",
) -> WorkflowProjectSnapshot:
    return WorkflowProjectSnapshot(
        project_id="1001",
        project_name="sample_project",
        revision=revision,
        archive_md5=archive_md5,
        files=files,
    )


def build_archive(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for path, content in files.items():
            info = tarfile.TarInfo(path)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


class FakeArchiveFetcher:
    def __init__(self, archive_bytes: bytes) -> None:
        self.archive_bytes = archive_bytes
        self.calls: list[tuple[str, str]] = []

    async def fetch_project_archive(self, project_id: str, revision: str) -> bytes:
        self.calls.append((project_id, revision))
        return self.archive_bytes


def test_archive_extracts_only_confirmed_extensions_and_builds_inventory(
    tmp_path: Path,
) -> None:
    archive = build_archive(
        {
            "main.dig": b"+task:\n  td>: queries/main.sql\n",
            "queries/main.sql": b"SELECT 1\r\n",
            "settings.yml": b"secret: not-read\n",
        }
    )

    snapshot, inventory = snapshot_from_workflow_archive(
        archive,
        project_detail(),
        extraction_root=tmp_path / "extract",
        max_file_size_bytes=1024,
        max_total_size_bytes=4096,
    )
    output = workflow_snapshot_to_files(snapshot)

    assert [file.path for file in snapshot.files] == [
        "main.dig",
        "queries/main.sql",
    ]
    assert inventory.extension_counts == ((".dig", 1), (".sql", 1), (".yml", 1))
    assert set(output) == {
        WORKFLOW_METADATA_FILE,
        "main.dig",
        "queries/main.sql",
    }
    assert b"not-read" not in b"".join(output.values())


def test_archive_redacts_detectable_secrets_before_snapshot_and_git_output(
    tmp_path: Path,
) -> None:
    slack_webhook = "https://hooks.slack.com/services/" + "T" * 12 + "/" + "B" * 12
    slack_token = "xoxb-" + "1" * 12 + "-" + "a" * 24
    archive = build_archive(
        {
            "main.dig": (
                f"+notify:\n  http>: {slack_webhook}\n"
                f"  token: '{slack_token}'\n"
            ).encode()
        }
    )

    snapshot, _ = snapshot_from_workflow_archive(
        archive,
        project_detail(),
        extraction_root=tmp_path / "extract",
        max_file_size_bytes=1024,
        max_total_size_bytes=4096,
    )
    output = workflow_snapshot_to_files(snapshot)

    assert slack_webhook not in snapshot.files[0].content
    assert slack_token not in snapshot.files[0].content
    assert output["main.dig"].count(b"<REDACTED_SECRET>") == 2


def test_git_snapshot_reader_redacts_legacy_secret_after_hash_validation() -> None:
    slack_token = "xoxb-" + "2" * 12 + "-" + "b" * 24
    legacy = project_snapshot(
        workflow_file("main.dig", f"token: '{slack_token}'\n")
    )

    restored = workflow_snapshot_from_files(workflow_snapshot_to_files(legacy))

    assert slack_token not in restored.files[0].content
    assert "<REDACTED_SECRET>" in restored.files[0].content


def test_snapshot_git_files_round_trip() -> None:
    snapshot = project_snapshot(
        workflow_file("main.dig", "+task:\n  td>: query.sql\n"),
        workflow_file("query.sql", "SELECT 1\n"),
    )

    restored = workflow_snapshot_from_files(workflow_snapshot_to_files(snapshot))

    assert restored == snapshot


def test_unchanged_revision_does_not_fetch_archive(tmp_path: Path) -> None:
    async def scenario() -> None:
        previous = project_snapshot(
            workflow_file("main.dig", "+task:\n  echo>: ok\n"),
            revision="same-revision",
            archive_md5="same-md5",
        )
        fetcher = FakeArchiveFetcher(b"not-used")

        result = await load_workflow_project_snapshot(
            fetcher,
            project_detail(revision="same-revision", archive_md5="same-md5"),
            previous=previous,
            temp_parent=tmp_path / "temporary",
            max_file_size_bytes=1024,
            max_total_size_bytes=4096,
        )

        assert not result.archive_fetched
        assert result.inventory is None
        assert result.snapshot == previous
        assert fetcher.calls == []

    asyncio.run(scenario())


def test_changed_revision_fetches_archive_and_removes_temporary_files(
    tmp_path: Path,
) -> None:
    async def scenario() -> None:
        fetcher = FakeArchiveFetcher(
            build_archive(
                {
                    "main.dig": b"+task:\n  td>: query.sql\n",
                    "query.sql": b"SELECT 2\n",
                }
            )
        )
        temp_parent = tmp_path / "temporary"

        result = await load_workflow_project_snapshot(
            fetcher,
            project_detail(),
            previous=project_snapshot(workflow_file("query.sql", "SELECT 1\n")),
            temp_parent=temp_parent,
            max_file_size_bytes=1024,
            max_total_size_bytes=4096,
        )

        assert result.archive_fetched
        assert fetcher.calls == [("1001", "revision-2")]
        assert [file.path for file in result.snapshot.files] == ["main.dig", "query.sql"]
        assert temp_parent.exists()
        assert list(temp_parent.iterdir()) == []

    asyncio.run(scenario())


def test_archive_rejects_path_traversal(tmp_path: Path) -> None:
    archive = build_archive({"../escaped.sql": b"SELECT 1\n"})

    with pytest.raises(WorkflowArchiveError, match="unsafe path"):
        snapshot_from_workflow_archive(
            archive,
            project_detail(),
            extraction_root=tmp_path / "extract",
            max_file_size_bytes=1024,
            max_total_size_bytes=4096,
        )

    assert not (tmp_path / "escaped.sql").exists()


def test_archive_rejects_links(tmp_path: Path) -> None:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        info = tarfile.TarInfo("linked.sql")
        info.type = tarfile.SYMTYPE
        info.linkname = "../outside.sql"
        archive.addfile(info)

    with pytest.raises(WorkflowArchiveError, match="link or special file"):
        snapshot_from_workflow_archive(
            buffer.getvalue(),
            project_detail(),
            extraction_root=tmp_path / "extract",
            max_file_size_bytes=1024,
            max_total_size_bytes=4096,
        )


def test_archive_rejects_monitored_file_over_size_limit(tmp_path: Path) -> None:
    archive = build_archive({"large.sql": b"x" * 11})

    with pytest.raises(WorkflowArchiveError, match="file exceeded size limit"):
        snapshot_from_workflow_archive(
            archive,
            project_detail(),
            extraction_root=tmp_path / "extract",
            max_file_size_bytes=10,
            max_total_size_bytes=100,
        )
