#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"
CLAUDE_TEMPORAL_LOG_DIR="${CLAUDE_TEMPORAL_LOG_DIR:-${TMPDIR:-/tmp}/claude-temporal-logs}"
CLAUDE_TEMPORAL_PROJECT_NAME="${CLAUDE_TEMPORAL_PROJECT_NAME:-$(basename "$(pwd)")}"

PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/worker-$CLAUDE_TEMPORAL_PROJECT_NAME.pid"
LOG_FILE="$CLAUDE_TEMPORAL_LOG_DIR/worker-$CLAUDE_TEMPORAL_PROJECT_NAME.log"

# Function to get process uptime
get_uptime() {
  local pid=$1
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | xargs -I{} date -j -f "%c" "{}" "+%s" 2>/dev/null || echo "0")
  else
    # Linux
    local start_time=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
  fi

  if [[ "$start_time" == "0" ]]; then
    echo "unknown"
    return
  fi

  local now=$(date +%s)
  local elapsed=$((now - start_time))

  # For Linux, etimes already gives elapsed seconds
  if [[ "$(uname)" != "Darwin" ]]; then
    elapsed=$start_time
  fi

  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))

  if (( hours > 0 )); then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

echo "=== Worker Health Check ==="
echo "Project: $CLAUDE_TEMPORAL_PROJECT_NAME"
echo ""

# Check if PID file exists
if [[ ! -f "$PID_FILE" ]]; then
  echo "Worker Status: NOT RUNNING"
  echo "No PID file found: $PID_FILE"
  exit 1
fi

# Read PID
WORKER_PID=$(cat "$PID_FILE")

# Check if process is alive
if ! kill -0 "$WORKER_PID" 2>/dev/null; then
  echo "Worker Status: DEAD"
  echo "PID file exists but process is not running"
  echo "PID: $WORKER_PID (stale)"
  echo ""
  echo "To clean up and restart:"
  echo "  rm -f $PID_FILE"
  echo "  ./tools/ensure-worker.sh"
  exit 1
fi

# Process is alive
echo "Worker Status: RUNNING"
echo "PID: $WORKER_PID"
echo "Uptime: $(get_uptime "$WORKER_PID")"
echo ""

# Check log file
if [[ -f "$LOG_FILE" ]]; then
  echo "Log file: $LOG_FILE"
  echo "Log size: $(wc -c < "$LOG_FILE" | tr -d ' ') bytes"
  echo ""

  # Check for recent errors in logs (last 50 lines)
  if tail -n 50 "$LOG_FILE" | grep -iE "(error|exception|fatal|traceback)" >/dev/null 2>&1; then
    echo "⚠️  Recent errors found in logs (last 50 lines):"
    echo ""
    tail -n 50 "$LOG_FILE" | grep -iE "(error|exception|fatal)" | tail -n 10
    echo ""
    echo "Full logs: $LOG_FILE"
    exit 1
  fi

  # Show last log entry
  echo "Last log entry:"
  tail -n 1 "$LOG_FILE" 2>/dev/null || echo "(empty log)"
  echo ""

  echo "✓ Worker appears healthy"
  echo ""
  echo "To view logs:"
  echo "  tail -f $LOG_FILE"
else
  echo "⚠️  Log file not found: $LOG_FILE"
  echo ""
  echo "Worker is running but no logs found"
  exit 1
fi
