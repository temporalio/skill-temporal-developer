#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: list-recent-workflows.sh [options]

List recently completed/terminated workflows within a time window.

Options:
  --minutes <N>   Look back N minutes (default: 5)
  --status        Filter by status: COMPLETED, FAILED, CANCELED, TERMINATED, TIMED_OUT (optional)
  --workflow-type Filter by workflow type (optional)
  -h, --help      Show this help

Examples:
  # List all workflows from last 5 minutes
  ./tools/list-recent-workflows.sh

  # List failed workflows from last 10 minutes
  ./tools/list-recent-workflows.sh --minutes 10 --status FAILED

  # List completed workflows of specific type from last 2 minutes
  ./tools/list-recent-workflows.sh --minutes 2 --status COMPLETED --workflow-type MyWorkflow

Output format:
  WORKFLOW_ID    STATUS      WORKFLOW_TYPE    CLOSE_TIME
USAGE
}

minutes=5
status=""
workflow_type=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --minutes)      minutes="${2-}"; shift 2 ;;
    --status)       status="${2-}"; shift 2 ;;
    --workflow-type) workflow_type="${2-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

# Validate status if provided
if [[ -n "$status" ]]; then
  case "$status" in
    COMPLETED|FAILED|CANCELED|TERMINATED|TIMED_OUT) ;;
    *) echo "Invalid status: $status" >&2; usage; exit 1 ;;
  esac
fi

# Calculate time threshold (minutes ago)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  time_threshold=$(date -u -v-"${minutes}M" +"%Y-%m-%dT%H:%M:%SZ")
else
  # Linux
  time_threshold=$(date -u -d "$minutes minutes ago" +"%Y-%m-%dT%H:%M:%SZ")
fi

# Build query
query="CloseTime > \"$time_threshold\""

if [[ -n "$status" ]]; then
  query="$query AND ExecutionStatus = \"$status\""
fi

if [[ -n "$workflow_type" ]]; then
  query="$query AND WorkflowType = \"$workflow_type\""
fi

echo "Searching workflows from last $minutes minute(s)..."
echo "Query: $query"
echo ""

# Execute list command
if ! workflow_list=$("$TEMPORAL_CLI" workflow list \
  --address "$TEMPORAL_ADDRESS" \
  --namespace "$CLAUDE_TEMPORAL_NAMESPACE" \
  --query "$query" 2>&1); then
  echo "Failed to list workflows" >&2
  echo "$workflow_list" >&2
  exit 1
fi

# Check if any workflows found
if echo "$workflow_list" | grep -q "No workflows found"; then
  echo "No workflows found in the last $minutes minute(s)"
  exit 0
fi

# Parse and display results
echo "$workflow_list" | head -n 50

# Count results
workflow_count=$(echo "$workflow_list" | awk 'NR>1 && $1 != "" && $1 !~ /^-+$/ {print $1}' | wc -l | tr -d ' ')

echo ""
echo "Found $workflow_count workflow(s)"
echo ""
echo "To get workflow result:"
echo "  ./tools/get-workflow-result.sh --workflow-id <workflow-id>"
