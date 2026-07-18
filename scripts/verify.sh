#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"

cd "$project_dir"
export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-.venv-linux}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

uv lock
uv sync
uv build
uv run ruff check .
uv run mypy src
uv run pytest
