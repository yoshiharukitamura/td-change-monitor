from __future__ import annotations

from pathlib import Path

import pytest
from pydantic import SecretStr

from td_change_monitor.config import (
    MonitorStatus,
    Settings,
    load_resource_targets_config,
    load_target_tables_config,
)


def test_target_config_accepts_table_name_starting_with_digit(tmp_path: Path) -> None:
    config_path = tmp_path / "target_tables.yml"
    config_path.write_text(
        """monitored_tables:
  - database: l2_emberpoint_output
    table: 0426_analytical_grade
exclude:
  table_patterns: []
bootstrap:
  tables: []
""",
        encoding="utf-8",
    )

    config = load_target_tables_config(config_path)

    assert config.monitored_tables == (("l2_emberpoint_output", "0426_analytical_grade"),)


def test_settings_accept_legacy_non_secret_github_names_for_local_git(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(tmp_path)
    settings = Settings.model_validate(
        {
            "td_api_base_url": "https://api.td.test/v3",
            "td_api_key": SecretStr("secret"),
            "GITHUB_BRANCH": "legacy-main",
            "GITHUB_COMMITTER_EMAIL": "legacy@example.com",
            "github_owner": "owner",
            "github_repo": "repo",
            "backlog_base_url": "https://backlog.test",
            "backlog_api_key": SecretStr("secret"),
            "backlog_project_id": 1,
            "backlog_issue_type_id": 2,
            "backlog_priority_id": 3,
        }
    )

    assert settings.git_branch == "legacy-main"
    assert settings.git_committer_email == "legacy@example.com"
    assert settings.github_repository_url == "https://github.com/owner/repo"


def test_load_resource_targets_config_parses_active_and_review_targets(
    tmp_path: Path,
) -> None:
    path = tmp_path / "resource_targets.yml"
    path.write_text(
        """
workflow_projects:
  - project_name: project_a
    project_id: "100"
    target_workflows: [main]
    target_schedule_ids: ["200"]
    monitor_status: monitor
  - project_name: unresolved
    project_id:
    target_workflows: [unknown]
    target_schedule_ids: []
    monitor_status: needs_review
saved_queries:
  - query_id: "300"
    query_name: query_a
    database: db
    owner: User
    monitor_status: evidence_only
""",
        encoding="utf-8",
    )

    config = load_resource_targets_config(path)

    assert [item.project_id for item in config.active_workflow_projects()] == ["100"]
    assert config.workflow_projects[1].monitor_status == MonitorStatus.NEEDS_REVIEW
    assert [item.query_id for item in config.active_saved_queries()] == ["300"]
    assert config.saved_queries[0].monitor_status == MonitorStatus.EVIDENCE_ONLY


def test_resource_targets_require_resolved_id_for_active_status(tmp_path: Path) -> None:
    path = tmp_path / "resource_targets.yml"
    path.write_text(
        """
workflow_projects:
  - project_name: unresolved
    project_id:
    target_workflows: []
    target_schedule_ids: []
    monitor_status: monitor
saved_queries: []
""",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="without ID"):
        load_resource_targets_config(path)
