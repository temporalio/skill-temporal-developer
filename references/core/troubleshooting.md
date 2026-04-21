# Cadence Troubleshooting

## Workflow Is Stuck

Check:

1. Is a worker polling the correct task list?
2. Is the workflow blocked on a signal, timer, activity, or query-only inspection?
3. Does the workflow history show repeated decision task failures?

Useful commands:

```bash
cadence workflow describe --workflow_id <id>
cadence workflow show --workflow_id <id>
cadence workflow stack --workflow_id <id>
cadence tasklist desc --tl <task-list>
```

## Non-Deterministic Error

Symptoms:

- Workflow repeatedly fails decision tasks
- History contains nondeterministic failure details

Common causes:

- Changed workflow command order
- Removed activity or timer call without versioning
- Replaced a workflow primitive with a different one

Fix:

- Restore replay-compatible code
- Use `GetVersion` or a new workflow type
- Consider reset or bad-binary recovery when already deployed broadly

## Activity Keeps Retrying

Check:

- Activity timeout values
- Retry policy
- Worker availability for the activity task list
- Heartbeats for long-running activities

## Signal Seems Ignored

Check:

- Signal name matches exactly
- Workflow is actually waiting on or processing that signal
- Signal changes state in a way that unblocks workflow logic
- You are signaling the right workflow ID and run ID semantics for your use case

## Query Fails

Check:

- Worker is running
- Query handler is registered
- Query handler is read-only and non-blocking
- Use strong consistency only when needed because it can add latency

## Search Attributes Do Not Work

Check:

- Cadence advanced visibility is enabled
- Search attributes are allowlisted
- Query uses the correct indexed field name and type

## Reset And Recovery

Cadence CLI supports workflow reset and domain bad-binary recovery flows. Use them only after confirming the replay implications of the target history point.
