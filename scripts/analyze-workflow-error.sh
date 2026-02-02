#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: analyze-workflow-error.sh --workflow-id id [options]

Parse workflow history to extract error details and provide recommendations.

Options:
  --workflow-id       workflow ID to analyze, required
  --run-id            specific workflow run ID (optional)
  -h, --help          show this help
USAGE
}

workflow_id=""
run_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-id)  workflow_id="${2-}"; shift 2 ;;
    --run-id)       run_id="${2-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$workflow_id" ]]; then
  echo "workflow-id is required" >&2
  usage
  exit 1
fi

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

# Build temporal command
DESCRIBE_CMD=("$TEMPORAL_CLI" "workflow" "describe" "--workflow-id" "$workflow_id" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")
SHOW_CMD=("$TEMPORAL_CLI" "workflow" "show" "--workflow-id" "$workflow_id" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")

if [[ -n "$run_id" ]]; then
  DESCRIBE_CMD+=("--run-id" "$run_id")
  SHOW_CMD+=("--run-id" "$run_id")
fi

echo "=== Workflow Error Analysis ==="
echo "Workflow ID: $workflow_id"
if [[ -n "$run_id" ]]; then
  echo "Run ID: $run_id"
fi
echo ""

# Get workflow description
if ! describe_output=$("${DESCRIBE_CMD[@]}" 2>&1); then
  echo "❌ Failed to describe workflow" >&2
  echo "$describe_output" >&2
  exit 1
fi

# Get workflow history
if ! show_output=$("${SHOW_CMD[@]}" 2>&1); then
  echo "❌ Failed to get workflow history" >&2
  echo "$show_output" >&2
  exit 1
fi

# Extract status
status=$(echo "$describe_output" | grep -E "^\s*Status:" | awk '{print $2}' | tr -d ' ' || echo "UNKNOWN")
echo "Current Status: $status"
echo ""

# Analyze different error types
workflow_task_failures=$(echo "$show_output" | grep -c "WorkflowTaskFailed" || echo "0")
activity_task_failures=$(echo "$show_output" | grep -c "ActivityTaskFailed" || echo "0")
workflow_exec_failed=$(echo "$show_output" | grep -c "WorkflowExecutionFailed" || echo "0")

# Report findings
if [[ "$workflow_task_failures" -gt 0 ]]; then
  echo "=== WorkflowTaskFailed Detected ==="
  echo "Attempts: $workflow_task_failures"
  echo ""

  # Extract error details
  echo "Error Details:"
  echo "$show_output" | grep -A 10 "WorkflowTaskFailed" | head -n 15
  echo ""

  echo "=== Diagnosis ==="
  echo "Error Type: WorkflowTaskFailed"
  echo ""
  echo "Common Causes:"
  echo "  1. Workflow type not registered with worker"
  echo "  2. Worker missing workflow definition"
  echo "  3. Workflow code has syntax errors"
  echo "  4. Worker not running or not polling correct task queue"
  echo ""
  echo "=== Recommended Actions ==="
  echo "1. Check if worker is running:"
  echo "   $SCRIPT_DIR/list-workers.sh"
  echo ""
  echo "2. Verify workflow is registered in worker.py:"
  echo "   - Check workflows=[YourWorkflow] in Worker() constructor"
  echo ""
  echo "3. Restart worker with updated code:"
  echo "   $SCRIPT_DIR/ensure-worker.sh"
  echo ""
  echo "4. Check worker logs for errors:"
  echo "   tail -f \$CLAUDE_TEMPORAL_LOG_DIR/worker-\$(basename \"\$(pwd)\").log"

elif [[ "$activity_task_failures" -gt 0 ]]; then
  echo "=== ActivityTaskFailed Detected ==="
  echo "Attempts: $activity_task_failures"
  echo ""

  # Extract error details
  echo "Error Details:"
  echo "$show_output" | grep -A 10 "ActivityTaskFailed" | head -n 20
  echo ""

  echo "=== Diagnosis ==="
  echo "Error Type: ActivityTaskFailed"
  echo ""
  echo "Common Causes:"
  echo "  1. Activity code threw an exception"
  echo "  2. Activity type not registered with worker"
  echo "  3. Activity code has bugs"
  echo "  4. External dependency failure (API, database, etc.)"
  echo ""
  echo "=== Recommended Actions ==="
  echo "1. Check activity logs for stack traces:"
  echo "   tail -f \$CLAUDE_TEMPORAL_LOG_DIR/worker-\$(basename \"\$(pwd)\").log"
  echo ""
  echo "2. Verify activity is registered in worker.py:"
  echo "   - Check activities=[your_activity] in Worker() constructor"
  echo ""
  echo "3. Review activity code for errors"
  echo ""
  echo "4. If activity code is fixed, restart worker:"
  echo "   $SCRIPT_DIR/ensure-worker.sh"
  echo ""
  echo "5. Consider adjusting retry policy if transient failure"

elif [[ "$workflow_exec_failed" -gt 0 ]]; then
  echo "=== WorkflowExecutionFailed Detected ==="
  echo ""

  # Extract error details
  echo "Error Details:"
  echo "$show_output" | grep -A 20 "WorkflowExecutionFailed" | head -n 25
  echo ""

  echo "=== Diagnosis ==="
  echo "Error Type: WorkflowExecutionFailed"
  echo ""
  echo "Common Causes:"
  echo "  1. Workflow business logic error"
  echo "  2. Unhandled exception in workflow code"
  echo "  3. Workflow determinism violation"
  echo ""
  echo "=== Recommended Actions ==="
  echo "1. Review workflow code for logic errors"
  echo ""
  echo "2. Check for non-deterministic code:"
  echo "   - Random number generation"
  echo "   - System time calls"
  echo "   - Threading/concurrency"
  echo ""
  echo "3. Review full workflow history:"
  echo "   temporal workflow show --workflow-id $workflow_id"
  echo ""
  echo "4. After fixing code, restart worker:"
  echo "   $SCRIPT_DIR/ensure-worker.sh"

elif [[ "$status" == "TIMED_OUT" ]]; then
  echo "=== Workflow Timeout ==="
  echo ""
  echo "The workflow exceeded its timeout limit."
  echo ""
  echo "=== Recommended Actions ==="
  echo "1. Review workflow timeout settings in starter code"
  echo ""
  echo "2. Check if activities are taking too long:"
  echo "   - Review activity timeout settings"
  echo "   - Check activity logs for performance issues"
  echo ""
  echo "3. Consider increasing timeouts if operations legitimately take longer"

elif [[ "$status" == "RUNNING" ]]; then
  echo "=== Workflow Still Running ==="
  echo ""
  echo "The workflow appears to be running normally."
  echo ""
  echo "To monitor progress:"
  echo "  temporal workflow show --workflow-id $workflow_id"
  echo ""
  echo "To wait for completion:"
  echo "  $SCRIPT_DIR/wait-for-workflow-status.sh --workflow-id $workflow_id --status COMPLETED"

elif [[ "$status" == "COMPLETED" ]]; then
  echo "=== Workflow Completed Successfully ==="
  echo ""
  echo "No errors detected. Workflow completed normally."

else
  echo "=== Status: $status ==="
  echo ""
  echo "Review full workflow details:"
  echo "  temporal workflow describe --workflow-id $workflow_id"
  echo "  temporal workflow show --workflow-id $workflow_id"
fi

echo ""
echo "=== Additional Resources ==="
echo "Web UI: http://localhost:8233/namespaces/$CLAUDE_TEMPORAL_NAMESPACE/workflows/$workflow_id"
