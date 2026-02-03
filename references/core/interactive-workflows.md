# Interactive Workflows

Interactive workflows pause and wait for external input (signals or updates).

## Signals

Fire-and-forget messages to a workflow.

```bash
# Send signal to workflow
temporal workflow signal \
  --workflow-id <id> \
  --name "signal_name" \
  --input '{"key": "value"}'

# Or via interact script (if available)
uv run interact --workflow-id <id> --signal-name "signal_name" --data '{"key": "value"}'
```

## Updates

Request-response style interaction (returns a value).

```bash
# Send update to workflow
temporal workflow update \
  --workflow-id <id> \
  --name "update_name" \
  --input '{"approved": true}'
```

## Queries

Read-only inspection of workflow state.

```bash
# Query workflow state (read-only)
temporal workflow query \
  --workflow-id <id> \
  --name "get_status"
```

## Testing Interactive Workflows

```bash
./scripts/ensure-worker.sh
uv run starter  # Get workflow_id
./scripts/wait-for-workflow-status.sh --workflow-id $workflow_id --status RUNNING
uv run interact --workflow-id $workflow_id --signal-name "approval" --data '{"approved": true}'
./scripts/wait-for-workflow-status.sh --workflow-id $workflow_id --status COMPLETED
./scripts/get-workflow-result.sh --workflow-id $workflow_id
./scripts/kill-worker.sh  # CLEANUP
```
