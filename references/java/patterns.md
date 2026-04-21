# Cadence Java Patterns

## Signals

```java
public interface OrderWorkflow {
  @WorkflowMethod
  void run(String id);

  @SignalMethod
  void approve();
}
```

Signals are the main way to inject durable external input.

## Queries

```java
public interface OrderWorkflow {
  @QueryMethod
  String status();
}
```

Query methods must be read-only and non-blocking.

## Child Workflows

Use `Workflow.newChildWorkflowStub(...)` when a problem should be partitioned into separate workflow lifecycles.

## Continue As New

Use `Workflow.continueAsNew(...)` for long-running loops and signal-heavy workflows.

## Signal With Start

Use client-side signal-with-start flows when the caller is unsure whether the target workflow already exists.

## No Updates

This skill intentionally excludes Temporal-style `@UpdateMethod` guidance.
