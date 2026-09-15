# Activity Operator Commands (Ruby)

Use Activity Operator Commands via the Temporal CLI and an Activity's ID/Run ID. SDKs do not expose Pause/Unpause/Update Options as client methods.

## Start or locate a Standalone Activity

Start and capture the `id` for later operations:

```ruby
handle = client.start_activity(
  StandaloneActivity::MyActivities::ComposeGreeting,
  'Hello', 'World',
  id: 'standalone-activity-id',
  task_queue: 'standalone-activity-sample',
  start_to_close_timeout: 10
)
```

Or create a handle for an existing execution by Activity ID:

```ruby
handle = client.activity_handle('standalone-activity-id')
```

Use this Activity ID with the CLI commands below.

## Pause

```bash
temporal activity pause \
  --activity-id standalone-activity-id \
  --reason "pausing for investigation"
```

Pause stops new retries; timers continue to run while paused.

## Unpause

```bash
temporal activity unpause \
  --activity-id standalone-activity-id
```

Unpause immediately schedules the next attempt if past due.

## Update Options

```bash
temporal activity update-options \
  --activity-id standalone-activity-id \
  --schedule-to-close-timeout 24h
```

Takes effect immediately if scheduled, or on the next execution if currently running.

## Restore Original Options (batch-only)

```bash
temporal activity update-options \
  --query 'WorkflowType="YourWorkflow"' \
  --restore-original-options
```

`--restore-original-options` only works with `--query` and requires a stored snapshot.

## Requirements

Standalone Activity operations require Temporal Server v1.32.0+ and Temporal CLI v1.9.1+.

