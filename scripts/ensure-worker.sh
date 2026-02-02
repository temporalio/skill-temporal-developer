#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"
CLAUDE_TEMPORAL_LOG_DIR="${CLAUDE_TEMPORAL_LOG_DIR:-${TMPDIR:-/tmp}/claude-temporal-logs}"
CLAUDE_TEMPORAL_PROJECT_DIR="${CLAUDE_TEMPORAL_PROJECT_DIR:-$(pwd)}"
CLAUDE_TEMPORAL_PROJECT_NAME="${CLAUDE_TEMPORAL_PROJECT_NAME:-$(basename "$CLAUDE_TEMPORAL_PROJECT_DIR")}"
TEMPORAL_WORKER_CMD="${TEMPORAL_WORKER_CMD:-uv run worker}"

# Create directories if they don't exist
mkdir -p "$CLAUDE_TEMPORAL_PID_DIR"
mkdir -p "$CLAUDE_TEMPORAL_LOG_DIR"

PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/worker-$CLAUDE_TEMPORAL_PROJECT_NAME.pid"
LOG_FILE="$CLAUDE_TEMPORAL_LOG_DIR/worker-$CLAUDE_TEMPORAL_PROJECT_NAME.log"

# Always kill any existing workers (both tracked and orphaned)
# This ensures we don't accumulate orphaned processes
echo "🔍 Checking for existing workers..."

# Use the helper function to find all workers
source "$SCRIPT_DIR/find-project-workers.sh"
existing_workers=$(find_project_workers "$CLAUDE_TEMPORAL_PROJECT_DIR" 2>/dev/null || true)

if [[ -n "$existing_workers" ]]; then
  worker_count=$(echo "$existing_workers" | wc -l | tr -d ' ')
  echo "Found $worker_count existing worker(s), stopping them..."

  if "$SCRIPT_DIR/kill-worker.sh" 2>&1; then
    echo "✓ Existing workers stopped"
  else
    # kill-worker.sh will have printed error messages
    echo "⚠️  Some workers may not have been stopped, continuing anyway..."
  fi
elif [[ -f "$PID_FILE" ]]; then
  # PID file exists but no workers found - clean up stale PID file
  echo "Removing stale PID file..."
  rm -f "$PID_FILE"
fi

# Clear old log file
> "$LOG_FILE"

# Start worker in background
echo "🚀 Starting worker for project: $CLAUDE_TEMPORAL_PROJECT_NAME"
echo "Command: $TEMPORAL_WORKER_CMD"

# Start worker, redirect output to log file
eval "$TEMPORAL_WORKER_CMD" > "$LOG_FILE" 2>&1 &
WORKER_PID=$!

# Save PID
echo "$WORKER_PID" > "$PID_FILE"

echo "Worker PID: $WORKER_PID"
echo "Log file: $LOG_FILE"

# Wait for worker to be ready (simple approach: wait and check if still running)
echo "⏳ Waiting for worker to be ready..."

# Wait 10 seconds for worker to initialize
sleep 10

# Check if process is still running
if ! kill -0 "$WORKER_PID" 2>/dev/null; then
  echo "❌ Worker process died during startup" >&2
  echo "Last 20 lines of log:" >&2
  tail -n 20 "$LOG_FILE" >&2 || true
  rm -f "$PID_FILE"
  exit 1
fi

# Check if log file has content (worker is producing output)
if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
  echo "✓ Worker ready (PID: $WORKER_PID)"
  echo ""
  echo "To monitor worker logs:"
  echo "  tail -f $LOG_FILE"
  echo ""
  echo "To check worker health:"
  echo "  $SCRIPT_DIR/monitor-worker-health.sh"
  exit 0
else
  echo "⚠️  Worker is running but no logs detected" >&2
  echo "Check logs: $LOG_FILE" >&2
  exit 2
fi
