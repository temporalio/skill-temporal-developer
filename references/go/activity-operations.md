# Activity Operator Commands (Go)

Use Activity Operator Commands via the Temporal CLI and an Activity's ID/Run ID. SDKs do not expose Pause/Unpause/Update Options as client methods.

## Start or locate a Standalone Activity

Get a handle to an existing Standalone Activity by ActivityID (and optional RunID):

```go
handle := c.GetActivityHandle(client.GetActivityHandleOptions{
    ActivityID: "my-standalone-activity-id",
    RunID:      "the-run-id",
})
```

Use the same `ActivityID` with the CLI commands below.

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

```bash
temporal activity update-options \
  --activity-id my-standalone-activity-id \
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

