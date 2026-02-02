#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"

# Graceful shutdown timeout (seconds)
GRACEFUL_TIMEOUT=5

usage() {
  cat <<'USAGE'
Usage: kill-all-workers.sh [options]

Kill all tracked workers across all projects.

Options:
  -p, --project       kill only specific project worker
  --include-server    also kill temporal dev server
  -h, --help          show this help
USAGE
}

specific_project=""
include_server=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)      specific_project="${2-}"; shift 2 ;;
    --include-server)  include_server=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Check if PID directory exists
if [[ ! -d "$CLAUDE_TEMPORAL_PID_DIR" ]]; then
  echo "No PID directory found: $CLAUDE_TEMPORAL_PID_DIR"
  exit 0
fi

# Function to kill a process gracefully then forcefully
kill_process() {
  local pid=$1
  local name=$2

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "$name (PID $pid): already dead"
    return 0
  fi

  # Attempt graceful shutdown
  kill -TERM "$pid" 2>/dev/null || true

  # Wait for graceful shutdown
  local elapsed=0
  while (( elapsed < GRACEFUL_TIMEOUT )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name (PID $pid): stopped gracefully ✓"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Force kill if still running
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
      echo "$name (PID $pid): failed to kill ❌" >&2
      return 1
    fi
    echo "$name (PID $pid): force killed ✓"
  fi

  return 0
}

killed_count=0

# Kill specific project worker if requested
if [[ -n "$specific_project" ]]; then
  PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/worker-$specific_project.pid"
  if [[ -f "$PID_FILE" ]]; then
    WORKER_PID=$(cat "$PID_FILE")
    if kill_process "$WORKER_PID" "worker-$specific_project"; then
      rm -f "$PID_FILE"
      killed_count=$((killed_count + 1))
    fi
  else
    echo "No worker found for project: $specific_project"
    exit 1
  fi
else
  # Kill all workers
  shopt -s nullglob
  PID_FILES=("$CLAUDE_TEMPORAL_PID_DIR"/worker-*.pid)
  shopt -u nullglob

  for pid_file in "${PID_FILES[@]}"; do
    # Extract project name from filename
    filename=$(basename "$pid_file")
    project="${filename#worker-}"
    project="${project%.pid}"

    # Read PID
    worker_pid=$(cat "$pid_file")

    if kill_process "$worker_pid" "worker-$project"; then
      rm -f "$pid_file"
      killed_count=$((killed_count + 1))
    fi
  done
fi

# Kill server if requested
if [[ "$include_server" == true ]]; then
  SERVER_PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/server.pid"
  if [[ -f "$SERVER_PID_FILE" ]]; then
    SERVER_PID=$(cat "$SERVER_PID_FILE")
    if kill_process "$SERVER_PID" "server"; then
      rm -f "$SERVER_PID_FILE"
      killed_count=$((killed_count + 1))
    fi
  fi
fi

if [[ "$killed_count" -eq 0 ]]; then
  echo "No processes to kill"
else
  echo ""
  echo "Total: $killed_count process(es) killed"
fi
