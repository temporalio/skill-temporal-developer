#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
TEMPORAL_CLI="${TEMPORAL_CLI:-temporal}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}"
CLAUDE_TEMPORAL_NAMESPACE="${CLAUDE_TEMPORAL_NAMESPACE:-default}"

usage() {
  cat <<'USAGE'
Usage: bulk-cancel-workflows.sh [options]

Cancel multiple workflows.

Options:
  --workflow-ids      file containing workflow IDs (one per line), required unless --pattern
  --pattern           cancel workflows matching pattern (regex)
  --reason            cancellation reason (default: "Bulk cancellation")
  -h, --help          show this help

Examples:
  # Cancel workflows from file
  ./bulk-cancel-workflows.sh --workflow-ids stalled.txt

  # Cancel workflows matching pattern
  ./bulk-cancel-workflows.sh --pattern "test-.*"

  # Cancel with custom reason
  ./bulk-cancel-workflows.sh --workflow-ids stalled.txt --reason "Cleaning up test workflows"
USAGE
}

workflow_ids_file=""
pattern=""
reason="Bulk cancellation"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-ids)  workflow_ids_file="${2-}"; shift 2 ;;
    --pattern)       pattern="${2-}"; shift 2 ;;
    --reason)        reason="${2-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$workflow_ids_file" && -z "$pattern" ]]; then
  echo "Either --workflow-ids or --pattern is required" >&2
  usage
  exit 1
fi

if ! command -v "$TEMPORAL_CLI" >/dev/null 2>&1; then
  echo "Temporal CLI not found: $TEMPORAL_CLI" >&2
  exit 1
fi

# Collect workflow IDs
workflow_ids=()

if [[ -n "$workflow_ids_file" ]]; then
  if [[ ! -f "$workflow_ids_file" ]]; then
    echo "File not found: $workflow_ids_file" >&2
    exit 1
  fi

  # Read workflow IDs from file
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Trim whitespace
    line=$(echo "$line" | xargs)
    workflow_ids+=("$line")
  done < "$workflow_ids_file"
fi

if [[ -n "$pattern" ]]; then
  echo "Finding workflows matching pattern: $pattern"

  # List workflows and filter by pattern
  LIST_CMD=("$TEMPORAL_CLI" "workflow" "list" "--address" "$TEMPORAL_ADDRESS" "--namespace" "$CLAUDE_TEMPORAL_NAMESPACE")

  if workflow_list=$("${LIST_CMD[@]}" 2>&1); then
    # Parse workflow IDs from list and filter by pattern
    while IFS= read -r wf_id; do
      [[ -z "$wf_id" ]] && continue
      if echo "$wf_id" | grep -E "$pattern" >/dev/null 2>&1; then
        workflow_ids+=("$wf_id")
      fi
    done < <(echo "$workflow_list" | awk 'NR>1 && $1 != "" {print $1}' | grep -v "^-")
  else
    echo "Failed to list workflows" >&2
    echo "$workflow_list" >&2
    exit 1
  fi
fi

# Check if we have any workflow IDs
if [[ "${#workflow_ids[@]}" -eq 0 ]]; then
  echo "No workflows to cancel"
  exit 0
fi

echo "Found ${#workflow_ids[@]} workflow(s) to cancel"
echo "Reason: $reason"
echo ""

# Confirm with user
read -p "Continue with cancellation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancellation aborted"
  exit 0
fi

echo ""
echo "Canceling workflows..."
echo ""

success_count=0
failed_count=0

# Cancel each workflow
for workflow_id in "${workflow_ids[@]}"; do
  echo -n "Canceling: $workflow_id ... "

  if "$TEMPORAL_CLI" workflow cancel \
      --workflow-id "$workflow_id" \
      --address "$TEMPORAL_ADDRESS" \
      --namespace "$CLAUDE_TEMPORAL_NAMESPACE" \
      --reason "$reason" \
      >/dev/null 2>&1; then
    echo "✓"
    success_count=$((success_count + 1))
  else
    echo "❌ (may already be canceled or not exist)"
    failed_count=$((failed_count + 1))
  fi
done

echo ""
echo "=== Summary ==="
echo "Successfully canceled: $success_count"
echo "Failed: $failed_count"
echo "Total: ${#workflow_ids[@]}"
