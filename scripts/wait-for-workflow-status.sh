#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: wait-for-workflow-status.sh --workflow-id id --status status [options]

Poll workflow for specific status.

Options:
  --workflow-id       workflow ID to monitor, required
  --status            status to wait for, required
                      (RUNNING, COMPLETED, FAILED, CANCELED, TERMINATED, TIMED_OUT)
  --run-id            specific workflow run ID (optional)
  -T, --timeout       seconds to wait (integer, default: 300)
  -i, --interval      poll interval in seconds (default: 2)
  -h, --help          show this help
USAGE
}

workflow_id=""
run_id=""
target_status=""
timeout=300
interval=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-id)  workflow_id="${2-}"; shift 2 ;;
    --run-id)       run_id="${2-}"; shift 2 ;;
    --status)       target_status="${2-}"; shift 2 ;;
    -T|--timeout)   timeout="${2-}"; shift 2 ;;
    -i|--interval)  interval="${2-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$workflow_id" || -z "$target_status" ]]; then
  echo "workflow-id and status are required" >&2
  usage
  exit 1
fi

if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
  echo "timeout must be an integer number of seconds" >&2
  exit 1
fi

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

# Build temporal command
TEMPORAL_CMD=("$TEMPORAL_CLI" "workflow" "describe" "--workflow-id" "$workflow_id" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")

if [[ -n "$run_id" ]]; then
  TEMPORAL_CMD+=("--run-id" "$run_id")
fi

# Normalize target status to uppercase
target_status=$(echo "$target_status" | tr '[:lower:]' '[:upper:]')

# End time in epoch seconds
start_epoch=$(date +%s)
deadline=$((start_epoch + timeout))

echo "Polling workflow: $workflow_id"
echo "Target status: $target_status"
echo "Timeout: ${timeout}s"
echo ""

while true; do
  # Query workflow status
  if output=$("${TEMPORAL_CMD[@]}" 2>&1); then
    # Extract status from output
    # The output includes a line like: "  Status          COMPLETED"
    if current_status=$(echo "$output" | grep -E "^\s*Status\s" | awk '{print $2}' | tr -d ' '); then
      echo "Current status: $current_status ($(date '+%H:%M:%S'))"

      if [[ "$current_status" == "$target_status" ]]; then
        echo ""
        echo "✓ Workflow reached status: $target_status"
        exit 0
      fi

      # Check if workflow reached a terminal state different from target
      case "$current_status" in
        COMPLETED|FAILED|CANCELED|TERMINATED|TIMED_OUT)
          if [[ "$current_status" != "$target_status" ]]; then
            echo ""
            echo "⚠️  Workflow reached terminal status: $current_status (expected: $target_status)"
            exit 1
          fi
          ;;
      esac
    else
      echo "⚠️  Could not parse workflow status from output" >&2
    fi
  else
    echo "⚠️  Failed to query workflow (it may not exist yet)" >&2
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    echo ""
    echo "❌ Timeout after ${timeout}s waiting for status: $target_status" >&2
    exit 1
  fi

  sleep "$interval"
done
