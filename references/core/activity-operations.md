> [!NOTE]
> Activity Operations are operational controls exposed via the Temporal CLI, UI, and gRPC API. They do not exist as SDK client methods and cannot be invoked from Workflow or Activity code.

# Activity Operator Commands (Pause, Unpause, Update Options)

This page describes Activity Operator Commands that manage a running Activity Execution. It focuses on Pause, Unpause, and Update Options, and clarifies when and how to restore original options.

## Scope & Support

- Applies to Workflow Activities and Standalone Activities; not applicable to Local Activities.
- Standalone support requires Temporal Server v1.32.0+ and Temporal CLI v1.9.1+.

## Operations Summary

- Pause — stop scheduling retries; in-flight execution continues unless the Activity heartbeats.
- Unpause — resume a paused Activity; next attempt starts immediately.
- Update Options — change timeouts, retry policy, or task queue without restarting; takes effect immediately if scheduled, or on next execution if currently running.
- Restore Original Options — batch-only restoration of previously snapshotted options using `--restore-original-options`.

See the CLI reference for full flag lists: `temporal activity pause`, `temporal activity unpause`, `temporal activity update-options`.

## Semantics & Gotchas

- Timers keep running while Paused (Schedule-To-Close is not stopped). Plan to extend it first if needed.
- No new attempts are scheduled while Paused; Unpause starts overdue retries immediately.
- Before the first attempt of a Standalone Activity, Unpause honors the original Start Delay; if elapsed, dispatches immediately.
- Interruption of an in-flight attempt is best-effort and delivered via heartbeat. Activities that don't heartbeat won't be interrupted mid-attempt.

## CLI Patterns

Pause (Workflow Activity):

```bash
temporal activity pause \
  --workflow-id <wf-id> \
  --activity-id <activity-id> \
  --reason "<why>"
```

Pause (Standalone Activity):

```bash
temporal activity pause \
  --activity-id <activity-id> \
  --reason "<why>"
```

Unpause (Workflow or Standalone):

```bash
temporal activity unpause \
  --workflow-id <wf-id> \
  --activity-id <activity-id>
```

Update Options (extend Schedule-To-Close):

```bash
temporal activity update-options \
  --workflow-id <wf-id> \
  --activity-id <activity-id> \
  --schedule-to-close-timeout 24h
```

Restore Original Options (batch-only for Workflow Activities):

```bash
temporal activity update-options \
  --query 'WorkflowType="YourWorkflow"' \
  --restore-original-options
```

Flags and behaviors for these commands are defined in the CLI reference.

## Batch vs. Single-Activity

- Standalone Activities: batch operations currently apply to Request Cancel, Terminate, and Delete (not Pause/Unpause/Update Options).
- Workflow Activities: `--query` supports batch for Reset, Unpause, and Update Options.
- `--restore-original-options` works only with `--query` and cannot be combined with other option changes.

## Observability & Billing

- No Event History entries are produced by Activity Operations; use CLI/UI to inspect state.
- In Temporal Cloud, Pause and Update Options each count as one Action; Unpause is free.

## Language-specific pages

See:

- `references/python/activity-operations.md`
- `references/typescript/activity-operations.md`
- `references/go/activity-operations.md`
- `references/ruby/activity-operations.md`

