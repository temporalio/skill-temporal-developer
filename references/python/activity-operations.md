# Activity Operator Commands (Python)

This page shows how a Python app can participate in Activity Operator Commands by identifying the right Activity ID/Run ID and invoking the documented CLI. SDKs do not expose Pause/Unpause/Update Options as client methods.

## Start or locate a Standalone Activity

Start and capture the Activity ID you will operate on later:

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

You can also rebind to an existing execution:

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

`activity_id` is the stable key you will pass to CLI commands below.

## Pause

```bash
temporal activity pause \
  --activity-id my-standalone-activity-id \
  --reason "pausing for investigation"
```

Pause stops new retries; timers continue to run while paused.

## Unpause

```bash
temporal activity unpause \
  --activity-id my-standalone-activity-id
```

Unpause immediately schedules the next attempt if past due.

## Update Options

Extend Schedule-To-Close before unpausing a long-running job:

```bash
temporal activity update-options \
  --activity-id my-standalone-activity-id \
  --schedule-to-close-timeout 24h
```

Changes take effect immediately if scheduled, or on the next execution if currently running.

## Restore Original Options (batch-only)

```bash
temporal activity update-options \
  --query 'WorkflowType="YourWorkflow"' \
  --restore-original-options
```

`--restore-original-options` only works with `--query` and requires a stored snapshot.

## Requirements

Standalone Activity operations require Temporal Server v1.32.0+ and Temporal CLI v1.9.1+.

