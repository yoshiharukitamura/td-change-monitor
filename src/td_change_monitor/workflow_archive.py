from __future__ import annotations

import hashlib
import io
import json
import tarfile
import tempfile
from collections import Counter, defaultdict
from collections.abc import Mapping
from dataclasses import replace
from pathlib import Path, PurePosixPath
from typing import Protocol

from td_change_monitor.errors import ChangeMonitorError
from td_change_monitor.models import (
    WorkflowArchiveInventory,
    WorkflowFileSnapshot,
    WorkflowProjectDetail,
    WorkflowProjectSnapshot,
    WorkflowSnapshotLoadResult,
)
from td_change_monitor.secret_redaction import redact_detectable_secrets

MONITORED_WORKFLOW_EXTENSIONS = frozenset({".dig", ".sql"})
WORKFLOW_METADATA_FILE = ".workflow_state.json"
_WINDOWS_RESERVED_NAMES = frozenset(
    {
        "aux",
        "con",
        "nul",
        "prn",
        *(f"com{number}" for number in range(1, 10)),
        *(f"lpt{number}" for number in range(1, 10)),
    }
)


class WorkflowArchiveError(ChangeMonitorError):
    """Workflow archiveが安全に処理できない場合の失敗を表す。"""


class WorkflowArchiveFetcher(Protocol):
    """Workflow archive取得に必要なクライアント境界を表す。"""

    async def fetch_project_archive(self, project_id: str, revision: str) -> bytes:
        """指定project・revisionのgzip TARを返す。"""
        ...


async def load_workflow_project_snapshot(
    fetcher: WorkflowArchiveFetcher,
    detail: WorkflowProjectDetail,
    *,
    previous: WorkflowProjectSnapshot | None,
    temp_parent: Path,
    max_file_size_bytes: int,
    max_total_size_bytes: int,
) -> WorkflowSnapshotLoadResult:
    """変更識別情報を確認し、必要な場合だけarchiveからsnapshotを作る。

    引数:
        fetcher: archive取得メソッドを持つWorkflow APIクライアント。
        detail: project詳細APIから取得した現在識別情報。
        previous: Gitから読み込んだ前回snapshot。初回はNone。
        temp_parent: 実行中だけ使用する一時ディレクトリの親。
        max_file_size_bytes: 監視対象1ファイルの展開上限。
        max_total_size_bytes: archive全通常ファイルの展開後合計上限。
    戻り値:
        現在snapshot、archive取得有無、取得時の拡張子棚卸し。
    """
    _validate_size_limit(max_file_size_bytes, "max_file_size_bytes")
    _validate_size_limit(max_total_size_bytes, "max_total_size_bytes")
    if (
        previous is not None
        and previous.project_id == detail.project_id
        and previous.revision == detail.revision
        and previous.archive_md5 == detail.archive_md5
    ):
        return WorkflowSnapshotLoadResult(
            snapshot=replace(
                previous,
                project_name=detail.project_name,
                revision=detail.revision,
                archive_md5=detail.archive_md5,
            ),
            archive_fetched=False,
            inventory=None,
        )

    archive_bytes = await fetcher.fetch_project_archive(
        detail.project_id,
        detail.revision,
    )
    temp_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="td-workflow-",
        dir=temp_parent,
    ) as temporary_directory:
        snapshot, inventory = snapshot_from_workflow_archive(
            archive_bytes,
            detail,
            extraction_root=Path(temporary_directory),
            max_file_size_bytes=max_file_size_bytes,
            max_total_size_bytes=max_total_size_bytes,
        )
    return WorkflowSnapshotLoadResult(
        snapshot=snapshot,
        archive_fetched=True,
        inventory=inventory,
    )


def snapshot_from_workflow_archive(
    archive_bytes: bytes,
    detail: WorkflowProjectDetail,
    *,
    extraction_root: Path,
    max_file_size_bytes: int,
    max_total_size_bytes: int,
) -> tuple[WorkflowProjectSnapshot, WorkflowArchiveInventory]:
    """gzip TARを検証し、監視対象だけを一時展開してsnapshot化する。

    引数:
        archive_bytes: Workflow APIから取得したgzip TAR。
        detail: project ID、名前、revision、archiveMd5。
        extraction_root: 検証済みファイルを展開する空の一時領域。
        max_file_size_bytes: `.dig`・`.sql`1件の上限。
        max_total_size_bytes: archive内通常ファイル合計の上限。
    戻り値:
        正規化済みproject snapshotと拡張子棚卸し。
    """
    if not archive_bytes:
        raise WorkflowArchiveError("Workflow archive was empty")
    extraction_root.mkdir(parents=True, exist_ok=True)
    root = extraction_root.resolve()

    try:
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
            members = archive.getmembers()
            validated = _validate_members(
                members,
                max_file_size_bytes=max_file_size_bytes,
                max_total_size_bytes=max_total_size_bytes,
            )
            inventory = _build_inventory(validated)
            files = tuple(
                _extract_monitored_file(
                    archive,
                    member,
                    relative_path,
                    root=root,
                )
                for member, relative_path in validated
                if member.isfile()
                and PurePosixPath(relative_path).suffix.lower()
                in MONITORED_WORKFLOW_EXTENSIONS
            )
    except (tarfile.TarError, OSError, UnicodeError) as exc:
        raise WorkflowArchiveError("Workflow archive could not be processed") from exc

    return (
        WorkflowProjectSnapshot(
            project_id=detail.project_id,
            project_name=detail.project_name,
            revision=detail.revision,
            archive_md5=detail.archive_md5,
            files=tuple(sorted(files, key=lambda item: item.path)),
        ),
        inventory,
    )


def workflow_snapshot_to_files(
    snapshot: WorkflowProjectSnapshot,
) -> dict[str, bytes]:
    """project snapshotをGit保存対象の相対パスと内容へ変換する。

    引数:
        snapshot: 保存対象のWorkflow project snapshot。
    戻り値:
        metadata JSONと`.dig`・`.sql`だけを持つマッピング。
    """
    sanitized_files: list[tuple[str, str]] = []
    for file in snapshot.files:
        relative_path = _validate_snapshot_path(file.path)
        if PurePosixPath(relative_path).suffix.lower() not in MONITORED_WORKFLOW_EXTENSIONS:
            raise ValueError("Workflow snapshot contained an unmonitored extension")
        # snapshotの生成元にかかわらず、Gitへ書き出す直前にも秘密値を除去する。
        sanitized_files.append(
            (relative_path, redact_detectable_secrets(file.content))
        )

    metadata = {
        "project_id": snapshot.project_id,
        "project_name": snapshot.project_name,
        "revision": snapshot.revision,
        "archive_md5": snapshot.archive_md5,
        "files": [
            {
                "path": path,
                "sha256": _text_hash(content),
            }
            for path, content in sanitized_files
        ],
    }
    output = {
        WORKFLOW_METADATA_FILE: json.dumps(
            metadata,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        ).encode("utf-8")
    }
    for relative_path, content in sanitized_files:
        output[relative_path] = content.encode("utf-8")
    return output


def workflow_project_snapshot_hash(
    snapshot: WorkflowProjectSnapshot | None,
) -> str:
    """Workflow projectの正規化済み状態から決定的なSHA-256を作る。

    引数:
        snapshot: project snapshot。削除後など存在しない場合はNone。
    戻り値:
        metadataと監視対象内容に基づくhash。Noneなら固定文字列。
    """
    if snapshot is None:
        return "none"
    digest = hashlib.sha256()
    for path, content in sorted(workflow_snapshot_to_files(snapshot).items()):
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(content)
        digest.update(b"\0")
    return digest.hexdigest()


def workflow_snapshot_from_files(
    files: Mapping[str, bytes],
) -> WorkflowProjectSnapshot:
    """Gitから読み込んだmetadataと監視ファイルからsnapshotを復元する。

    引数:
        files: projectディレクトリ配下の相対パスとUTF-8内容。
    戻り値:
        hash整合性を検証したWorkflowProjectSnapshot。
    """
    metadata_bytes = files.get(WORKFLOW_METADATA_FILE)
    if metadata_bytes is None:
        raise ValueError("Workflow snapshot metadata was missing")
    try:
        metadata = json.loads(metadata_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Workflow snapshot metadata was invalid") from exc
    if not isinstance(metadata, Mapping):
        raise ValueError("Workflow snapshot metadata was invalid")

    file_entries = metadata.get("files")
    if not isinstance(file_entries, list):
        raise ValueError("Workflow snapshot metadata did not include files")
    snapshots: list[WorkflowFileSnapshot] = []
    for entry in file_entries:
        if not isinstance(entry, Mapping):
            raise ValueError("Workflow snapshot file metadata was invalid")
        path = entry.get("path")
        expected_hash = entry.get("sha256")
        if not isinstance(path, str) or not isinstance(expected_hash, str):
            raise ValueError("Workflow snapshot file metadata was invalid")
        relative_path = _validate_snapshot_path(path)
        content_bytes = files.get(relative_path)
        if content_bytes is None:
            raise ValueError("Workflow snapshot file was missing")
        try:
            content = _normalize_text(content_bytes.decode("utf-8"))
        except UnicodeDecodeError as exc:
            raise ValueError("Workflow snapshot file was not UTF-8") from exc
        actual_hash = _text_hash(content)
        if actual_hash != expected_hash:
            raise ValueError("Workflow snapshot file hash did not match")
        # 過去に保存されたsnapshotを読む場合も、後続処理には秘密値を渡さない。
        content = redact_detectable_secrets(content)
        actual_hash = _text_hash(content)
        snapshots.append(
            WorkflowFileSnapshot(
                path=relative_path,
                content=content,
                content_hash=actual_hash,
            )
        )

    return WorkflowProjectSnapshot(
        project_id=_metadata_string(metadata, "project_id"),
        project_name=_metadata_string(metadata, "project_name"),
        revision=_metadata_string(metadata, "revision"),
        archive_md5=_metadata_string(metadata, "archive_md5"),
        files=tuple(sorted(snapshots, key=lambda item: item.path)),
    )


def _validate_members(
    members: list[tarfile.TarInfo],
    *,
    max_file_size_bytes: int,
    max_total_size_bytes: int,
) -> tuple[tuple[tarfile.TarInfo, str], ...]:
    """TAR memberを展開前に一括検証する。

    引数:
        members: tarfileが返した全member。
        max_file_size_bytes: 監視対象1ファイルの上限。
        max_total_size_bytes: 全通常ファイル合計の上限。
    戻り値:
        memberと安全なPOSIX相対パスの組。
    """
    validated: list[tuple[tarfile.TarInfo, str]] = []
    seen_paths: set[str] = set()
    total_size = 0
    for member in members:
        if not member.isfile() and not member.isdir():
            raise WorkflowArchiveError("Workflow archive contained a link or special file")
        relative_path = _safe_member_path(member.name)
        path_key = relative_path.casefold()
        if path_key in seen_paths:
            raise WorkflowArchiveError("Workflow archive contained a duplicate path")
        seen_paths.add(path_key)

        if member.isfile():
            if member.size < 0:
                raise WorkflowArchiveError("Workflow archive contained an invalid size")
            total_size += member.size
            if total_size > max_total_size_bytes:
                raise WorkflowArchiveError("Workflow archive exceeded total size limit")
            suffix = PurePosixPath(relative_path).suffix.lower()
            if (
                suffix in MONITORED_WORKFLOW_EXTENSIONS
                and member.size > max_file_size_bytes
            ):
                raise WorkflowArchiveError(
                    "Workflow monitored file exceeded size limit"
                )
        validated.append((member, relative_path))
    return tuple(validated)


def _extract_monitored_file(
    archive: tarfile.TarFile,
    member: tarfile.TarInfo,
    relative_path: str,
    *,
    root: Path,
) -> WorkflowFileSnapshot:
    """検証済みmemberを一時領域へ書き、UTF-8 snapshotへ変換する。

    引数:
        archive: 読取中のTAR。
        member: 通常ファイルとして検証済みのmember。
        relative_path: 安全性を検証済みのPOSIX相対パス。
        root: 展開先一時ディレクトリの解決済み絶対パス。
    戻り値:
        改行をLFへ統一したWorkflowFileSnapshot。
    """
    source = archive.extractfile(member)
    if source is None:
        raise WorkflowArchiveError("Workflow archive file could not be read")
    content = redact_detectable_secrets(
        _normalize_text(source.read().decode("utf-8"))
    )
    target = (root / Path(*PurePosixPath(relative_path).parts)).resolve()
    if not target.is_relative_to(root):
        raise WorkflowArchiveError("Workflow archive path escaped temporary directory")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")
    return WorkflowFileSnapshot(
        path=relative_path,
        content=content,
        content_hash=_text_hash(content),
    )


def _build_inventory(
    members: tuple[tuple[tarfile.TarInfo, str], ...],
) -> WorkflowArchiveInventory:
    """通常ファイルを拡張子別に集計し、最大3件の例を作る。

    引数:
        members: 安全性検証済みmemberと相対パス。
    戻り値:
        拡張子別件数とファイル例。
    """
    counts: Counter[str] = Counter()
    examples: defaultdict[str, list[str]] = defaultdict(list)
    for member, relative_path in members:
        if not member.isfile():
            continue
        extension = PurePosixPath(relative_path).suffix.lower() or "<none>"
        counts[extension] += 1
        if len(examples[extension]) < 3:
            examples[extension].append(relative_path)
    return WorkflowArchiveInventory(
        extension_counts=tuple(sorted(counts.items())),
        examples=tuple(
            (extension, tuple(paths))
            for extension, paths in sorted(examples.items())
        ),
    )


def _safe_member_path(raw_path: str) -> str:
    """TAR member名をWindowsでも安全なPOSIX相対パスへ検証する。

    引数:
        raw_path: TAR headerに格納されたmember名。
    戻り値:
        `.`要素を除いたPOSIX相対パス。
    """
    if not raw_path or "\\" in raw_path:
        raise WorkflowArchiveError("Workflow archive contained an unsafe path")
    path = PurePosixPath(raw_path)
    parts = tuple(part for part in path.parts if part not in ("", "."))
    if path.is_absolute() or not parts or ".." in parts:
        raise WorkflowArchiveError("Workflow archive contained an unsafe path")
    for part in parts:
        stem = part.split(".", maxsplit=1)[0].casefold()
        if (
            ":" in part
            or part.endswith((" ", "."))
            or stem in _WINDOWS_RESERVED_NAMES
        ):
            raise WorkflowArchiveError("Workflow archive contained an unsafe path")
    return PurePosixPath(*parts).as_posix()


def _validate_snapshot_path(path: str) -> str:
    """Git保存snapshotのファイルパスをarchiveと同じ規則で検証する。

    引数:
        path: snapshot metadata内の相対パス。
    戻り値:
        安全なPOSIX相対パス。
    """
    try:
        return _safe_member_path(path)
    except WorkflowArchiveError as exc:
        raise ValueError("Workflow snapshot path was invalid") from exc


def _metadata_string(payload: Mapping[str, object], key: str) -> str:
    """metadata必須項目を空でない文字列として取得する。

    引数:
        payload: metadata JSONオブジェクト。
        key: 取得する項目名。
    戻り値:
        検証済み文字列。
    """
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Workflow snapshot metadata did not include {key}")
    return value


def _normalize_text(content: str) -> str:
    """Workflowテキストの改行コードだけをLFへ統一する。

    引数:
        content: archiveまたはGitから読み込んだテキスト。
    戻り値:
        空白・コメントを変えず改行だけを統一した文字列。
    """
    return content.replace("\r\n", "\n").replace("\r", "\n")


def _text_hash(content: str) -> str:
    """正規化済みテキストのSHA-256を返す。

    引数:
        content: hash対象のUTF-8テキスト。
    戻り値:
        64桁のSHA-256文字列。
    """
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _validate_size_limit(value: int, name: str) -> None:
    """展開サイズ上限が正の整数か検証する。

    引数:
        value: 検証するbyte上限。
        name: エラー表示用の引数名。
    戻り値:
        なし。
    """
    if isinstance(value, bool) or value < 1:
        raise ValueError(f"{name} must be one or greater")
