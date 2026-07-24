from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from pathlib import PurePosixPath

import yaml

from td_change_monitor.errors import ChangeMonitorError
from td_change_monitor.models import (
    WorkflowFileSnapshot,
    WorkflowProjectScheduleSnapshot,
    WorkflowProjectSnapshot,
    WorkflowScheduleChange,
    WorkflowScheduleChangeKind,
    WorkflowScheduleDetail,
    WorkflowScheduleSnapshot,
)

_SUPPORTED_SCHEDULE_TYPES = frozenset(
    {
        "hourly",
        "daily",
        "weekly",
        "monthly",
        "minutes_interval",
        "cron",
    }
)
_SCHEDULE_FIELDS = (
    "workflow_id",
    "workflow_name",
    "enabled",
    "schedule_type",
    "schedule_value",
    "timezone",
    "definition_path",
)


class WorkflowScheduleDefinitionError(ChangeMonitorError):
    """schedule APIとWorkflow定義を安全に対応付けられない失敗を表す。"""


def build_workflow_project_schedule_snapshot(
    project: WorkflowProjectSnapshot,
    schedules: tuple[WorkflowScheduleDetail, ...],
) -> WorkflowProjectScheduleSnapshot:
    """schedule APIとproject内のdigを結合して比較用snapshotを作る。

    引数:
        project: archiveまたはGitから復元した現在のWorkflow project状態。
        schedules: project schedule一覧APIから取得した固定識別情報と有効状態。
    戻り値:
        schedule ID順に並べたプロジェクト単位の正規化済みschedule状態。
    """
    definitions = _index_schedule_definitions(project.files)
    normalized: list[WorkflowScheduleSnapshot] = []
    seen_ids: set[str] = set()

    for schedule in schedules:
        if schedule.project.project_id != project.project_id:
            raise WorkflowScheduleDefinitionError(
                "Workflow schedule belonged to a different project"
            )
        if schedule.schedule_id in seen_ids:
            raise WorkflowScheduleDefinitionError(
                "Workflow schedule list contained a duplicate schedule ID"
            )
        seen_ids.add(schedule.schedule_id)

        definition_file = _find_definition_file(
            definitions,
            schedule.workflow.workflow_name,
        )
        try:
            schedule_type, schedule_value, timezone = (
                parse_workflow_schedule_definition(definition_file)
            )
        except WorkflowScheduleDefinitionError as exc:
            raise WorkflowScheduleDefinitionError(
                "Workflow schedule definition was invalid: "
                f"project_id={project.project_id}, "
                f"workflow={schedule.workflow.workflow_name}, "
                f"path={definition_file.path}; {exc}"
            ) from exc
        normalized.append(
            WorkflowScheduleSnapshot(
                schedule_id=schedule.schedule_id,
                workflow_id=schedule.workflow.workflow_id,
                workflow_name=schedule.workflow.workflow_name,
                enabled=schedule.enabled,
                schedule_type=schedule_type,
                schedule_value=schedule_value,
                timezone=timezone,
                definition_path=definition_file.path,
            )
        )

    return WorkflowProjectScheduleSnapshot(
        project_id=project.project_id,
        project_name=project.project_name,
        schedules=tuple(sorted(normalized, key=lambda item: _numeric_id_key(item.schedule_id))),
    )


def parse_workflow_schedule_definition(
    file: WorkflowFileSnapshot,
) -> tuple[str, str, str]:
    """digのトップレベルから固定schedule種別・値・timezoneを取り出す。

    引数:
        file: schedule APIの対象Workflowと一意に対応した`.dig`ファイル。
    戻り値:
        `(schedule_type, schedule_value, timezone)`。timezone省略時はUTC。
    """
    if PurePosixPath(file.path).suffix.lower() != ".dig":
        raise WorkflowScheduleDefinitionError(
            "Workflow schedule definition was not a dig file"
        )

    timezone = "UTC"
    schedule_entries: list[tuple[str, str]] = []
    lines = file.content.splitlines()
    index = 0
    while index < len(lines):
        raw_line = lines[index]
        line = _strip_inline_comment(raw_line).rstrip()
        if not line.strip() or _indent_width(line) != 0:
            index += 1
            continue

        key, value = _split_mapping_entry(line)
        if key == "timezone":
            timezone = _required_scalar(value, "timezone")
        elif key == "schedule":
            if value.strip():
                schedule_entries = _parse_inline_schedule_mapping(value)
            else:
                schedule_entries = _parse_schedule_block(lines, index + 1)
        index += 1

    if len(schedule_entries) != 1:
        raise WorkflowScheduleDefinitionError(
            "Workflow definition did not contain exactly one supported schedule"
        )
    schedule_type, schedule_value = schedule_entries[0]
    return schedule_type, schedule_value, timezone


def diff_workflow_schedule_snapshots(
    before: WorkflowProjectScheduleSnapshot,
    after: WorkflowProjectScheduleSnapshot,
) -> tuple[WorkflowScheduleChange, ...]:
    """前回と現在のschedule状態をschedule ID単位で比較する。

    引数:
        before: Gitに保存されていた前回のプロジェクトschedule状態。
        after: APIと現在のdigから作ったプロジェクトschedule状態。
    戻り値:
        schedule ID順に並べた追加・削除・変更の最終差分。
    """
    if before.project_id != after.project_id:
        raise ValueError("Workflow schedule snapshots must have the same project_id")

    before_by_id = _unique_schedules(before.schedules)
    after_by_id = _unique_schedules(after.schedules)
    changes: list[WorkflowScheduleChange] = []

    for schedule_id in sorted(
        before_by_id.keys() | after_by_id.keys(),
        key=_numeric_id_key,
    ):
        old = before_by_id.get(schedule_id)
        new = after_by_id.get(schedule_id)
        if old is None:
            changes.append(
                WorkflowScheduleChange(
                    kind=WorkflowScheduleChangeKind.ADDED,
                    schedule_id=schedule_id,
                    changed_fields=(),
                    before=None,
                    after=new,
                )
            )
            continue
        if new is None:
            changes.append(
                WorkflowScheduleChange(
                    kind=WorkflowScheduleChangeKind.DELETED,
                    schedule_id=schedule_id,
                    changed_fields=(),
                    before=old,
                    after=None,
                )
            )
            continue

        changed_fields = tuple(
            field
            for field in _SCHEDULE_FIELDS
            if getattr(old, field) != getattr(new, field)
        )
        if changed_fields:
            changes.append(
                WorkflowScheduleChange(
                    kind=WorkflowScheduleChangeKind.MODIFIED,
                    schedule_id=schedule_id,
                    changed_fields=changed_fields,
                    before=old,
                    after=new,
                )
            )
    return tuple(changes)


def workflow_schedule_snapshot_to_bytes(
    snapshot: WorkflowProjectScheduleSnapshot,
) -> bytes:
    """正規化済みschedule状態をGit保存用JSONへ変換する。

    引数:
        snapshot: 保存するプロジェクト単位のschedule状態。
    戻り値:
        動的な次回実行日時を含まないUTF-8 JSON。
    """
    payload = {
        "project_id": snapshot.project_id,
        "project_name": snapshot.project_name,
        "schedules": [
            {
                "schedule_id": schedule.schedule_id,
                "workflow_id": schedule.workflow_id,
                "workflow_name": schedule.workflow_name,
                "enabled": schedule.enabled,
                "schedule_type": schedule.schedule_type,
                "schedule_value": schedule.schedule_value,
                "timezone": schedule.timezone,
                "definition_path": schedule.definition_path,
            }
            for schedule in snapshot.schedules
        ],
    }
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        indent=2,
    ).encode("utf-8")


def workflow_schedule_snapshot_hash(
    snapshot: WorkflowProjectScheduleSnapshot | None,
) -> str:
    """Workflow scheduleの正規化済み状態から決定的なSHA-256を作る。

    引数:
        snapshot: project単位のschedule状態。存在しない場合はNone。
    戻り値:
        Git保存形式のhash。Noneなら固定文字列。
    """
    if snapshot is None:
        return "none"
    return hashlib.sha256(workflow_schedule_snapshot_to_bytes(snapshot)).hexdigest()


def workflow_schedule_snapshot_from_bytes(
    content: bytes,
) -> WorkflowProjectScheduleSnapshot:
    """Git保存済みJSONからプロジェクトschedule状態を復元する。

    引数:
        content: `workflow_schedules/current`から読んだUTF-8 JSON。
    戻り値:
        項目型とschedule ID重複を検証した正規化済みsnapshot。
    """
    try:
        payload = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Workflow schedule snapshot JSON was invalid") from exc
    if not isinstance(payload, Mapping):
        raise ValueError("Workflow schedule snapshot JSON was invalid")

    raw_schedules = payload.get("schedules")
    if not isinstance(raw_schedules, list):
        raise ValueError("Workflow schedule snapshot did not include schedules")
    schedules = tuple(_schedule_from_mapping(item) for item in raw_schedules)
    _unique_schedules(schedules)
    return WorkflowProjectScheduleSnapshot(
        project_id=_required_string(payload, "project_id"),
        project_name=_required_string(payload, "project_name"),
        schedules=tuple(sorted(schedules, key=lambda item: _numeric_id_key(item.schedule_id))),
    )


def _index_schedule_definitions(
    files: tuple[WorkflowFileSnapshot, ...],
) -> tuple[WorkflowFileSnapshot, ...]:
    """project snapshotから`.dig`だけをpath順で取り出す。

    引数:
        files: project snapshot内の監視対象ファイル。
    戻り値:
        path順に並べた`.dig`ファイル。
    """
    return tuple(
        sorted(
            (
                file
                for file in files
                if PurePosixPath(file.path).suffix.lower() == ".dig"
            ),
            key=lambda item: item.path,
        )
    )


def _find_definition_file(
    files: tuple[WorkflowFileSnapshot, ...],
    workflow_name: str,
) -> WorkflowFileSnapshot:
    """Workflow名と一意に対応するdigを決定する。

    引数:
        files: project内の`.dig`ファイル。
        workflow_name: schedule APIが返した対象Workflow名。
    戻り値:
        path全体またはbasenameがWorkflow名と一致する唯一のファイル。
    """
    exact = [
        file
        for file in files
        if PurePosixPath(file.path).with_suffix("").as_posix() == workflow_name
    ]
    if len(exact) == 1:
        return exact[0]
    if len(exact) > 1:
        raise WorkflowScheduleDefinitionError(
            "Workflow name matched multiple dig definition paths"
        )

    by_basename = [
        file for file in files if PurePosixPath(file.path).stem == workflow_name
    ]
    if len(by_basename) != 1:
        raise WorkflowScheduleDefinitionError(
            "Workflow name did not match exactly one dig definition"
        )
    return by_basename[0]


def _parse_schedule_block(
    lines: list[str],
    start_index: int,
) -> list[tuple[str, str]]:
    """`schedule:`直下の対応済み演算子と固定値を読む。

    引数:
        lines: dig全行。
        start_index: `schedule:`の次行を示す0始まり位置。
    戻り値:
        対応済みschedule演算子と値の一覧。
    """
    entries: list[tuple[str, str]] = []
    block_indent: int | None = None
    for raw_line in lines[start_index:]:
        line = _strip_inline_comment(raw_line).rstrip()
        if not line.strip():
            continue
        indent = _indent_width(line)
        if indent == 0:
            break
        if block_indent is None:
            block_indent = indent
        if indent != block_indent:
            continue

        key, value = _split_mapping_entry(line.lstrip())
        schedule_type = key.removesuffix(">")
        if key.endswith(">") and schedule_type not in _SUPPORTED_SCHEDULE_TYPES:
            raise WorkflowScheduleDefinitionError(
                f"Workflow schedule operator was unsupported: {key}"
            )
        if key.endswith(">"):
            entries.append(
                (
                    schedule_type,
                    _required_scalar(value, f"{schedule_type} schedule"),
                )
            )
    return entries


def _parse_inline_schedule_mapping(value: str) -> list[tuple[str, str]]:
    """インラインYAML mappingから対応済み固定schedule演算子を読む。

    引数:
        value: `schedule:`の右辺にあるYAML flow mapping。
    戻り値:
        対応済みschedule演算子と固定値の一覧。
    """
    try:
        payload = yaml.safe_load(value)
    except yaml.YAMLError as exc:
        raise WorkflowScheduleDefinitionError(
            "Workflow inline schedule mapping was invalid"
        ) from exc
    if not isinstance(payload, Mapping):
        raise WorkflowScheduleDefinitionError(
            "Workflow inline schedule was not a mapping"
        )

    entries: list[tuple[str, str]] = []
    for raw_key, raw_value in payload.items():
        if not isinstance(raw_key, str):
            raise WorkflowScheduleDefinitionError(
                "Workflow inline schedule key was invalid"
            )
        schedule_type = raw_key.removesuffix(">")
        if raw_key.endswith(">") and schedule_type not in _SUPPORTED_SCHEDULE_TYPES:
            raise WorkflowScheduleDefinitionError(
                f"Workflow schedule operator was unsupported: {raw_key}"
            )
        if not raw_key.endswith(">"):
            continue
        if isinstance(raw_value, bool) or not isinstance(raw_value, str | int | float):
            raise WorkflowScheduleDefinitionError(
                f"Workflow schedule {schedule_type} schedule was not a scalar"
            )
        entries.append(
            (
                schedule_type,
                _required_scalar(str(raw_value), f"{schedule_type} schedule"),
            )
        )
    return entries


def _strip_inline_comment(line: str) -> str:
    """引用符内の`#`を残し、引用符外のdigコメントだけを除く。

    引数:
        line: digの1行。
    戻り値:
        コメント開始以降を除いた行。
    """
    quote: str | None = None
    escaped = False
    for index, character in enumerate(line):
        if escaped:
            escaped = False
            continue
        if quote == '"' and character == "\\":
            escaped = True
            continue
        if character in {"'", '"'}:
            if quote is None:
                quote = character
            elif quote == character:
                quote = None
            continue
        if character == "#" and quote is None:
            return line[:index]
    return line


def _split_mapping_entry(line: str) -> tuple[str, str]:
    """digの単純な`key: value`行をkeyとvalueへ分ける。

    引数:
        line: コメント除去済みの非空行。
    戻り値:
        前後空白を除いたkeyと、先頭空白を除いたvalue。
    """
    key, separator, value = line.partition(":")
    if not separator or not key.strip():
        raise WorkflowScheduleDefinitionError(
            "Workflow schedule definition contained an invalid mapping entry"
        )
    return key.strip(), value.lstrip()


def _required_scalar(value: str, field: str) -> str:
    """固定schedule項目を空でない文字列へ正規化する。

    引数:
        value: コメント除去済みのmapping値。
        field: エラー表示用の項目名。
    戻り値:
        外側の同種引用符だけを除いた固定値。
    """
    normalized = value.strip()
    if (
        len(normalized) >= 2
        and normalized[0] == normalized[-1]
        and normalized[0] in {"'", '"'}
    ):
        normalized = normalized[1:-1]
    if not normalized:
        raise WorkflowScheduleDefinitionError(
            f"Workflow schedule {field} was blank"
        )
    return normalized


def _indent_width(line: str) -> int:
    """行頭の空白数を返し、tabによる曖昧なindentを拒否する。

    引数:
        line: indent判定対象のdig 1行。
    戻り値:
        行頭spaceの数。
    """
    prefix = line[: len(line) - len(line.lstrip())]
    if "\t" in prefix:
        raise WorkflowScheduleDefinitionError(
            "Workflow schedule definition used tab indentation"
        )
    return len(prefix)


def _unique_schedules(
    schedules: tuple[WorkflowScheduleSnapshot, ...],
) -> dict[str, WorkflowScheduleSnapshot]:
    """schedule一覧をID索引へ変換し、重複IDを拒否する。

    引数:
        schedules: 正規化済みschedule一覧。
    戻り値:
        schedule IDをkeyとする辞書。
    """
    result: dict[str, WorkflowScheduleSnapshot] = {}
    for schedule in schedules:
        if schedule.schedule_id in result:
            raise ValueError("Workflow schedule snapshot contained a duplicate ID")
        result[schedule.schedule_id] = schedule
    return result


def _schedule_from_mapping(payload: object) -> WorkflowScheduleSnapshot:
    """Git JSON内のschedule 1件を型検証してモデルへ変換する。

    引数:
        payload: `schedules`配列の1要素。
    戻り値:
        検証済みWorkflowScheduleSnapshot。
    """
    if not isinstance(payload, Mapping):
        raise ValueError("Workflow schedule snapshot item was invalid")
    enabled = payload.get("enabled")
    if not isinstance(enabled, bool):
        raise ValueError("Workflow schedule snapshot enabled was invalid")
    schedule_type = _required_string(payload, "schedule_type")
    if schedule_type not in _SUPPORTED_SCHEDULE_TYPES:
        raise ValueError("Workflow schedule snapshot type was unsupported")
    return WorkflowScheduleSnapshot(
        schedule_id=_required_string(payload, "schedule_id"),
        workflow_id=_required_string(payload, "workflow_id"),
        workflow_name=_required_string(payload, "workflow_name"),
        enabled=enabled,
        schedule_type=schedule_type,
        schedule_value=_required_string(payload, "schedule_value"),
        timezone=_required_string(payload, "timezone"),
        definition_path=_required_string(payload, "definition_path"),
    )


def _required_string(payload: Mapping[object, object], key: str) -> str:
    """JSON mappingの必須項目を空でない文字列として読む。

    引数:
        payload: 検証対象のJSON mapping。
        key: 取得する項目名。
    戻り値:
        空でない文字列。
    """
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Workflow schedule snapshot did not include {key}")
    return value


def _numeric_id_key(value: str) -> tuple[int, str]:
    """数字IDを桁数と文字列で安定ソートする。

    引数:
        value: schedule ID。
    戻り値:
        大きなIDでも整数変換に依存しないソートkey。
    """
    return len(value), value
