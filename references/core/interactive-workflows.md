# Interactive Workflows

Interactive workflows are workflows that use Temporal features such as signals or updates to pause and wait for external input. When testing and debugging these types of workflows you can send them input via the Temporal CLI.

## Signals

Fire-and-forget messages to a workflow.

```bash
# Send signal to workflow
temporal workflow signal \
  --workflow-id <id> \
  --name "signal_name" \
  --input '{"key": "value"}'
```

## Updates

Request-response style interaction (returns a value).

```bash
# Send update to workflow
temporal workflow update execute \
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

## Typical Steps for Testing Interactive Workflows

```bash
TEMPORAL_WORKER_CMD=<...> ./scripts/ensure-worker.sh # 1. Kill old workers, start fresh one. TEMPORAL_WORKER_CMD might be uv run worker, or whatever is appropriate for your project.
# 2. Run whatever code in order to start a workflow. This code should output the workflow ID, if not, modify it to.
./scripts/wait-for-workflow-status.sh --workflow-id <WORKFLOW_ID> --status RUNNING # 3. Wait until workflow is running
temporal workflow signal --workflow-id <WORKFLOW_ID> --name "signal_name" --input '{"key": "value"}' # 4. Send it interactive events, e.g. a signal. 
./scripts/wait-for-workflow-status.sh --workflow-id <WORKFLOW_ID> --status COMPLETED # 5. Wait for workflow to complete
./scripts/get-workflow-result.sh --workflow-id <WORKFLOW_ID> # 6. Read workflow result
./scripts/kill-worker.sh  # 7. CLEANUP
```
