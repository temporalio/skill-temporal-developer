# Cadence Go Versioning

Cadence Go uses `workflow.GetVersion` for replay-safe changes.

## Basic Example

```go
v := workflow.GetVersion(ctx, "step1", workflow.DefaultVersion, 1)
if v == workflow.DefaultVersion {
	err = workflow.ExecuteActivity(ctx, ActivityA).Get(ctx, nil)
} else {
	err = workflow.ExecuteActivity(ctx, ActivityB).Get(ctx, nil)
}
```

## Lifecycle

1. Add `GetVersion` with old and new branches.
2. Wait for older executions to drain.
3. Raise minimum supported version.
4. Remove obsolete branch when safe.

## When To Use

- Replacing an activity
- Reordering commands
- Changing child workflow structure

## When Not To Use

- Pure activity implementation changes
- Refactors that do not affect workflow commands

Cadence in this skill does not use Temporal Worker Versioning / Build IDs.
