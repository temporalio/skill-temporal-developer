# Interactive Workflows In Cadence

Interactive workflows wait for external input while preserving durable state.

In official Cadence scope, the primary interactive mechanisms are:

- Signals for durable external input
- Queries for read-only inspection

## Signals

Send a signal to a running workflow:

```bash
cadence workflow signal \
  --workflow_id <id> \
  --name <signal-name> \
  --input '"value"'
```

Signals are durable and can be sent even if no worker is currently running.

## Queries

Query workflow state:

```bash
cadence workflow query \
  --workflow_id <id> \
  --query_type <query-name>
```

Built-in stack trace query:

```bash
cadence workflow stack --workflow_id <id>
```

Queries are read-only and require workflow code to expose a query handler or query method.

## Typical Debugging Flow

1. Start the worker for the task list used by the workflow.
2. Start the workflow and record its workflow ID.
3. Send one or more signals with `cadence workflow signal`.
4. Inspect state using `cadence workflow query` or `cadence workflow stack`.
5. Use `cadence workflow describe` or `cadence workflow show` for history inspection.

## No Update Examples

Temporal-style Updates are intentionally not documented here because they are not part of the official Cadence scope for this skill.
