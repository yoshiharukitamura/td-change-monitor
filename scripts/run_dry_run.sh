#!/usr/bin/env bash
set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
log_dir="$project_dir/logs"
lock_file="$project_dir/.td_change_monitor.lock"
log_file="$log_dir/td_change_monitor_dry_run_$(date '+%Y%m%d_%H%M%S').log"

mkdir -p "$log_dir"

retention_days="${LOCAL_LOG_RETENTION_DAYS:-}"
if [[ -z "$retention_days" && -f "$project_dir/.env" ]]; then
  retention_days="$(sed -n 's/^LOCAL_LOG_RETENTION_DAYS[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$project_dir/.env" | tail -n 1)"
fi
retention_days="${retention_days:-30}"
if [[ ! "$retention_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "LOCAL_LOG_RETENTION_DAYS must be a positive integer."
  exit 2
fi
find "$log_dir" -type f -name '*.log' -mtime "+$retention_days" -delete

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not installed or not on PATH." | tee "$log_file"
  exit 127
fi

cd "$project_dir" || exit 1
export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-.venv-linux}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

(
  if ! flock -n 9; then
    echo "TDChangeMonitor is already running." | tee "$log_file"
    exit 10
  fi

  uv run td-change-monitor --dry-run "$@" 2>&1 | tee "$log_file"
  exit "${PIPESTATUS[0]}"
) 9>"$lock_file"

exit_code=$?
find "$log_dir" -type f -name '*.log' -mtime "+$retention_days" -delete
exit "$exit_code"
