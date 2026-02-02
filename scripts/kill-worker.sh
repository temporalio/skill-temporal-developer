#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the helper function to find project workers
source "$SCRIPT_DIR/find-project-workers.sh"

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"
CLAUDE_TEMPORAL_PROJECT_NAME="${CLAUDE_TEMPORAL_PROJECT_NAME:-$(basename "$(pwd)")}"
CLAUDE_TEMPORAL_PROJECT_DIR="${CLAUDE_TEMPORAL_PROJECT_DIR:-$(pwd)}"

PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/worker-$CLAUDE_TEMPORAL_PROJECT_NAME.pid"

# Graceful shutdown timeout (seconds)
GRACEFUL_TIMEOUT=5

# Find ALL workers for this project (both tracked and orphaned)
echo "🔍 Finding all workers for project: $CLAUDE_TEMPORAL_PROJECT_NAME"

# Collect all PIDs
worker_pids=()

# Add PID from file if it exists
if [[ -f "$PID_FILE" ]]; then
  TRACKED_PID=$(cat "$PID_FILE")
  if kill -0 "$TRACKED_PID" 2>/dev/null; then
    worker_pids+=("$TRACKED_PID")
  fi
fi

# Find all workers for this project using the helper function
while IFS= read -r pid; do
  [[ -n "$pid" ]] && worker_pids+=("$pid")
done < <(find_project_workers "$CLAUDE_TEMPORAL_PROJECT_DIR" 2>/dev/null || true)

# Remove duplicates
worker_pids=($(printf "%s\n" "${worker_pids[@]}" | sort -u))

if [[ ${#worker_pids[@]} -eq 0 ]]; then
  echo "No workers running for project: $CLAUDE_TEMPORAL_PROJECT_NAME"
  rm -f "$PID_FILE"
  exit 1
fi

echo "Found ${#worker_pids[@]} worker process(es): ${worker_pids[*]}"

# Attempt graceful shutdown of all workers
echo "⏳ Attempting graceful shutdown..."
for pid in "${worker_pids[@]}"; do
  kill -TERM "$pid" 2>/dev/null || true
done

# Wait for graceful shutdown
ELAPSED=0
while (( ELAPSED < GRACEFUL_TIMEOUT )); do
  all_dead=true
  for pid in "${worker_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      all_dead=false
      break
    fi
  done

  if [[ "$all_dead" == true ]]; then
    echo "✓ All workers stopped gracefully"
    rm -f "$PID_FILE"
    exit 0
  fi

  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

# Force kill any still running
still_running=()
for pid in "${worker_pids[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    still_running+=("$pid")
  fi
done

if [[ ${#still_running[@]} -gt 0 ]]; then
  echo "⚠️  ${#still_running[@]} process(es) still running after ${GRACEFUL_TIMEOUT}s, forcing kill..."
  for pid in "${still_running[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  sleep 1

  # Verify all are dead
  failed_pids=()
  for pid in "${still_running[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      failed_pids+=("$pid")
    fi
  done

  if [[ ${#failed_pids[@]} -gt 0 ]]; then
    echo "❌ Failed to kill worker process(es): ${failed_pids[*]}" >&2
    exit 1
  fi
fi

echo "✓ All workers killed (${#worker_pids[@]} process(es))"
rm -f "$PID_FILE"
exit 0
