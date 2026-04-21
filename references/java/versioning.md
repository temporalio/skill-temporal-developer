# Cadence Java Versioning

Cadence Java uses `Workflow.getVersion` for replay-safe code evolution.

## Basic Example

```java
int version = Workflow.getVersion("step1", Workflow.DEFAULT_VERSION, 1);
if (version == Workflow.DEFAULT_VERSION) {
  activities.activityA();
} else {
  activities.activityB();
}
```

## When To Use

- Replace one activity with another
- Reorder workflow commands
- Change child workflow structure

## Cleanup Lifecycle

1. Introduce version branch
2. Drain older executions
3. Raise minimum supported version
4. Remove old branch when safe

For very large changes, prefer starting a new workflow type.
