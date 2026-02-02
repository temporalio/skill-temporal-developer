#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: find-stalled-workflows.sh [options]

Detect workflows with systematic issues (e.g., workflow task failures).

Options:
  --query         filter workflows by query (optional)
  -h, --help      show this help
USAGE
}

query=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)    query="${2-}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq not found. Install jq for better output formatting." >&2
  echo "This script will continue with basic text parsing..." >&2
fi

# Build list command - only look for RUNNING workflows since stalled workflows must be running
LIST_CMD=("$TEMPORAL_CLI" "workflow" "list" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")

if [[ -n "$query" ]]; then
  # Append user query to running filter
  LIST_CMD+=("--query" "ExecutionStatus='Running' AND ($query)")
else
  # Default: only find running workflows
  LIST_CMD+=("--query" "ExecutionStatus='Running'")
fi

echo "Scanning for stalled workflows..."
echo ""

# Get list of running workflows
if ! workflow_list=$("${LIST_CMD[@]}" 2>&1); then
  echo "Failed to list workflows" >&2
  echo "$workflow_list" >&2
  exit 1
fi

# Parse workflow IDs from list
# The output format is: Status WorkflowId Type StartTime
# WorkflowId is in column 2
workflow_ids=$(echo "$workflow_list" | awk 'NR>1 {print $2}' | grep -v "^-" | grep -v "^$" || true)

if [[ -z "$workflow_ids" ]]; then
  echo "No workflows found"
  exit 0
fi

# Print header
printf "%-40s %-35s %-10s\n" "WORKFLOW_ID" "ERROR_TYPE" "ATTEMPTS"
printf "%-40s %-35s %-10s\n" "----------------------------------------" "-----------------------------------" "----------"

found_stalled=false

# Check each workflow for errors
while IFS= read -r workflow_id; do
  [[ -z "$workflow_id" ]] && continue

  # Get workflow event history using 'show' to see failure events
  if show_output=$("$TEMPORAL_CLI" workflow show --workflow-id "$workflow_id" --address "$TEMPORAL_ADDRESS" --namespace "$CLAUDE_TEMPORAL_NAMESPACE" 2>/dev/null); then

    # Check for workflow task failures
    workflow_task_failures=$(echo "$show_output" | grep -c "WorkflowTaskFailed" 2>/dev/null || echo "0")
    workflow_task_failures=$(echo "$workflow_task_failures" | tr -d '\n' | tr -d ' ')
    activity_task_failures=$(echo "$show_output" | grep -c "ActivityTaskFailed" 2>/dev/null || echo "0")
    activity_task_failures=$(echo "$activity_task_failures" | tr -d '\n' | tr -d ' ')

    # Report if significant failures found
    if [[ "$workflow_task_failures" -gt 0 ]]; then
      found_stalled=true
      # Truncate long workflow IDs for display
      display_id=$(echo "$workflow_id" | cut -c1-40)
      printf "%-40s %-35s %-10s\n" "$display_id" "WorkflowTaskFailed" "$workflow_task_failures"
    elif [[ "$activity_task_failures" -gt 2 ]]; then
      # Only report activity failures if they're excessive (>2)
      found_stalled=true
      display_id=$(echo "$workflow_id" | cut -c1-40)
      printf "%-40s %-35s %-10s\n" "$display_id" "ActivityTaskFailed" "$activity_task_failures"
    fi
  fi
done <<< "$workflow_ids"

echo ""

if [[ "$found_stalled" == false ]]; then
  echo "No stalled workflows detected"
else
  echo "Found stalled workflows. To investigate:"
  echo "  ./tools/analyze-workflow-error.sh --workflow-id <workflow-id>"
  echo ""
  echo "To cancel all stalled workflows:"
  echo "  ./tools/find-stalled-workflows.sh | awk 'NR>2 {print \$1}' > stalled.txt"
  echo "  ./tools/bulk-cancel-workflows.sh --workflow-ids stalled.txt"
fi
