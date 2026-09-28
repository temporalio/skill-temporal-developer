# Interactive Workflows

Use signals and updates to send input to a running Workflow Execution, and queries to inspect its state. To test a workflow that waits for input, start it with `temporal workflow start` so the CLI returns a Workflow ID without waiting for completion. Use that ID with the commands below.

For server and worker setup, see [development server and worker management](dev-management.md). For starting workflows and reading their results, see [CLI workflow commands](cli-workflow-commands.md).

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
