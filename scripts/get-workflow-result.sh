#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: get-workflow-result.sh --workflow-id <workflow-id> [options]

Get the result/output from a completed workflow execution.

Options:
  --workflow-id <id>  Workflow ID to query (required)
  --run-id <id>       Specific run ID (optional)
  --raw              Output raw JSON result only
  -h, --help          Show this help

Examples:
  # Get workflow result with formatted output
  ./tools/get-workflow-result.sh --workflow-id my-workflow-123

  # Get raw JSON result only
  ./tools/get-workflow-result.sh --workflow-id my-workflow-123 --raw

  # Get result for specific run
  ./tools/get-workflow-result.sh --workflow-id my-workflow-123 --run-id abc-def-ghi

Output:
  - Workflow status (COMPLETED, FAILED, etc.)
  - Workflow result/output (if completed successfully)
  - Failure message (if failed)
  - Termination reason (if terminated)
USAGE
}

workflow_id=""
run_id=""
raw_mode=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-id)  workflow_id="${2-}"; shift 2 ;;
    --run-id)       run_id="${2-}"; shift 2 ;;
    --raw)          raw_mode=true; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$workflow_id" ]]; then
  echo "Error: --workflow-id is required" >&2
  usage
  exit 1
fi

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

# Build describe command
DESCRIBE_CMD=("$TEMPORAL_CLI" "workflow" "describe" "--workflow-id" "$workflow_id" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")

if [[ -n "$run_id" ]]; then
  DESCRIBE_CMD+=("--run-id" "$run_id")
fi

# Get workflow details
if ! describe_output=$("${DESCRIBE_CMD[@]}" 2>&1); then
  echo "Failed to describe workflow: $workflow_id" >&2
  echo "$describe_output" >&2
  exit 1
fi

# Extract workflow status
status=$(echo "$describe_output" | grep -i "Status:" | head -n1 | awk '{print $2}' || echo "UNKNOWN")

if [[ "$raw_mode" == true ]]; then
  # Raw mode: just output the result payload
  # Use 'temporal workflow show' to get execution history with result
  if ! show_output=$("$TEMPORAL_CLI" workflow show --workflow-id "$workflow_id" --address "$TEMPORAL_ADDRESS" --namespace "$CLAUDE_TEMPORAL_NAMESPACE" 2>&1); then
    echo "Failed to get workflow result" >&2
    exit 1
  fi

  # Extract result from WorkflowExecutionCompleted event
  echo "$show_output" | grep -A 10 "WorkflowExecutionCompleted" | grep -E "result|Result" || echo "{}"
  exit 0
fi

# Formatted output
echo "════════════════════════════════════════════════════════════"
echo "Workflow: $workflow_id"
echo "Status: $status"
echo "════════════════════════════════════════════════════════════"
echo ""

case "$status" in
  COMPLETED)
    echo "✅ Workflow completed successfully"
    echo ""
    echo "Result:"
    echo "────────────────────────────────────────────────────────────"

    # Get workflow result using 'show' command
    if show_output=$("$TEMPORAL_CLI" workflow show --workflow-id "$workflow_id" --address "$TEMPORAL_ADDRESS" --namespace "$CLAUDE_TEMPORAL_NAMESPACE" 2>/dev/null); then
      # Extract result from WorkflowExecutionCompleted event
      result=$(echo "$show_output" | grep -A 20 "WorkflowExecutionCompleted" | grep -E "result|Result" || echo "")

      if [[ -n "$result" ]]; then
        echo "$result"
      else
        echo "(No result payload - workflow may return None/void)"
      fi
    else
      echo "(Unable to extract result)"
    fi
    ;;

  FAILED)
    echo "❌ Workflow failed"
    echo ""
    echo "Failure details:"
    echo "────────────────────────────────────────────────────────────"

    # Extract failure message
    failure=$(echo "$describe_output" | grep -A 5 "Failure:" || echo "")
    if [[ -n "$failure" ]]; then
      echo "$failure"
    else
      echo "(No failure details available)"
    fi

    echo ""
    echo "To analyze error:"
    echo "  ./tools/analyze-workflow-error.sh --workflow-id $workflow_id"
    ;;

  CANCELED)
    echo "🚫 Workflow was canceled"
    echo ""

    # Try to extract cancellation reason
    cancel_info=$(echo "$describe_output" | grep -i "cancel" || echo "")
    if [[ -n "$cancel_info" ]]; then
      echo "Cancellation info:"
      echo "$cancel_info"
    fi
    ;;

  TERMINATED)
    echo "⛔ Workflow was terminated"
    echo ""

    # Extract termination reason
    term_reason=$(echo "$describe_output" | grep -i "reason:" | head -n1 || echo "")
    if [[ -n "$term_reason" ]]; then
      echo "Termination reason:"
      echo "$term_reason"
    fi
    ;;

  TIMED_OUT)
    echo "⏱️  Workflow timed out"
    echo ""

    timeout_info=$(echo "$describe_output" | grep -i "timeout" || echo "")
    if [[ -n "$timeout_info" ]]; then
      echo "Timeout info:"
      echo "$timeout_info"
    fi
    ;;

  RUNNING)
    echo "🏃 Workflow is still running"
    echo ""
    echo "Cannot get result for running workflow."
    echo ""
    echo "To wait for completion:"
    echo "  ./tools/wait-for-workflow-status.sh --workflow-id $workflow_id --status COMPLETED"
    exit 1
    ;;

  *)
    echo "Status: $status"
    echo ""
    echo "Full workflow details:"
    echo "$describe_output"
    ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "To view full workflow history:"
echo "  temporal workflow show --workflow-id $workflow_id"
echo ""
echo "To view in Web UI:"
echo "  http://localhost:8233/namespaces/$CLAUDE_TEMPORAL_NAMESPACE/workflows/$workflow_id"
