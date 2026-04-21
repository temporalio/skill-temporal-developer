# Cadence Workflow Versioning

Cadence workflow code must stay replay-compatible with histories created by older deployments.

The two main approaches are:

1. In-place versioning with `GetVersion`
2. Workflow type versioning with a new workflow type

## Why Versioning Is Needed

If an existing workflow run reaches replay after deployment, the new code must still match the old history.

Example of an incompatible change:

```text
Old workflow:
  ActivityA
  ActivityB

New workflow:
  ActivityA
  ActivityC
```

If replay reaches the second step for an old run, the recorded history contains `ActivityB`, not `ActivityC`.

## Approach 1: GetVersion

Cadence Go and Java SDKs support replay-safe branching.

Use it when you are:

- Adding, removing, or reordering workflow commands
- Replacing one activity or child workflow with another
- Making a change that would otherwise alter replayed command structure

General lifecycle:

1. Introduce `GetVersion` and keep both old and new branches
2. Wait for older executions to drain
3. Raise the minimum supported version and remove truly obsolete branches

Language-specific references:

- Go: `references/go/versioning.md`
- Java: `references/java/versioning.md`

## Approach 2: New Workflow Type

Create a new workflow type when:

- The change is a large rewrite
- Compatibility branches would make the code hard to maintain
- You want operationally clear separation between old and new logic

Typical rollout:

1. Keep old and new workflow types registered
2. Start new executions on the new type
3. Let old executions complete or recover them operationally
4. Remove the old type later

## Operational Recovery

Cadence also provides operational recovery mechanisms such as reset flows and bad binary handling. These are useful when deployments already introduced incompatible behavior or a bug reached production.

Use them carefully and only after understanding how histories will replay.

## Best Practices

1. Version only changes that affect replayed commands.
2. Use stable, descriptive change IDs.
3. Test replay compatibility before production rollout.
4. Prefer a new workflow type for large incompatible rewrites.
5. Do not remove compatibility branches until older executions are truly drained.
