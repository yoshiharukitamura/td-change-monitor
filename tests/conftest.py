from __future__ import annotations

from pathlib import Path

from pydantic import SecretStr

from td_change_monitor.config import Settings


def make_settings(**overrides: object) -> Settings:
    values = {
        "td_api_base_url": "https://api.td.test/v3",
        "td_api_key": SecretStr("td-secret"),
        "td_audit_database": "audit_db",
        "td_audit_table": "audit_table",
        "git_repository_path": Path("repository"),
        "git_branch": "main",
        "git_committer_email": "bot@example.com",
        "github_repository_url": "https://github.com/owner/repo",
        "backlog_base_url": "https://space.backlog.test",
        "backlog_api_key": SecretStr("backlog-secret"),
        "backlog_project_id": 1,
        "backlog_issue_type_id": 2,
        "backlog_priority_id": 3,
        "http_max_retries": 1,
    }
    values.update(overrides)
    return Settings.model_validate(values)
