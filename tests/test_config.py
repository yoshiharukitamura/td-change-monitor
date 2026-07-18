from __future__ import annotations

from pathlib import Path

from pydantic import SecretStr

from td_change_monitor.config import Settings, load_target_tables_config


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


def test_settings_accept_legacy_non_secret_github_names_for_local_git() -> None:
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
