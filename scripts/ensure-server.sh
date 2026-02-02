#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"
CLAUDE_TEMPORAL_LOG_DIR="${CLAUDE_TEMPORAL_LOG_DIR:-${TMPDIR:-/tmp}/claude-temporal-logs}"
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"

# Create directories if they don't exist
mkdir -p "$CLAUDE_TEMPORAL_PID_DIR"
mkdir -p "$CLAUDE_TEMPORAL_LOG_DIR"

PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/server.pid"
LOG_FILE="$CLAUDE_TEMPORAL_LOG_DIR/server.log"

# Check if temporal CLI is installed
if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "❌ Temporal CLI not found: $TEMPORAL_CLI" >&2
  echo "Install temporal CLI:" >&2
  echo "  macOS: brew install temporal" >&2
  echo "  Linux: https://github.com/temporalio/cli/releases" >&2
  exit 1
fi

# Function to check if server is responding
check_server_connectivity() {
  # Try to list namespaces as a connectivity test
  if "$TEMPORAL_CLI" operator namespace list --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Check if server is already running
if check_server_connectivity; then
  echo "✓ Temporal server already running at $TEMPORAL_ADDRESS"
  exit 0
fi

# Check if we have a PID file from previous run
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    # Process exists but not responding - might be starting up
    echo "⏳ Server process exists (PID: $OLD_PID), checking connectivity..."
    sleep 2
    if check_server_connectivity; then
      echo "✓ Temporal server ready at $TEMPORAL_ADDRESS"
      exit 0
    fi
    echo "⚠️  Server process exists but not responding, killing and restarting..."
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# Start server in background
echo "🚀 Starting Temporal dev server..."
"$TEMPORAL_CLI" server start-dev > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

echo "⏳ Waiting for server to be ready..."

# Wait up to 30 seconds for server to become ready
TIMEOUT=30
ELAPSED=0
INTERVAL=1

while (( ELAPSED < TIMEOUT )); do
  if check_server_connectivity; then
    echo "✓ Temporal server ready at $TEMPORAL_ADDRESS (PID: $SERVER_PID)"
    echo ""
    echo "Web UI: http://localhost:8233"
    echo "gRPC: $TEMPORAL_ADDRESS"
    echo ""
    echo "Server logs: $LOG_FILE"
    echo "Server PID file: $PID_FILE"
    exit 0
  fi

  # Check if process died
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ Server process died during startup" >&2
    echo "Check logs: $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 2
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "❌ Server startup timeout after ${TIMEOUT}s" >&2
echo "Server might still be starting. Check logs: $LOG_FILE" >&2
echo "Server PID: $SERVER_PID" >&2
exit 2
