# Activity Operator Commands (TypeScript)

Use Activity Operator Commands via the Temporal CLI and an Activity's ID/Run ID. SDKs do not expose Pause/Unpause/Update Options as client methods.

## Start or locate a Standalone Activity

Start and remember the `activityId`:

```ts
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: 'my-standalone-activity-id',
  args: ['Temporal'],
});
```

Or get a handle to an existing execution:

```ts
const existing = client.activity.getHandle<string>('my-standalone-activity-id');
```

The Activity ID is what CLI commands below will target.

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

