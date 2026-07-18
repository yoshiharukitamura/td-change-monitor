.PHONY: sync build lint typecheck test verify

export UV_PROJECT_ENVIRONMENT ?= .venv-linux
export UV_LINK_MODE ?= copy

sync:
	uv sync

build:
	uv build

lint:
	uv run ruff check .

typecheck:
	uv run mypy src

test:
	uv run pytest

verify:
	uv lock
	uv sync
	uv build
	uv run ruff check .
	uv run mypy src
	uv run pytest
