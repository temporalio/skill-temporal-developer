# Cadence Determinism

Cadence restores workflow state by replaying the event history for a workflow execution. During replay, workflow code must make the same decisions in the same order as it did originally.

If replayed code produces a different command sequence, Cadence reports a non-deterministic error and the workflow stops making progress.

## Replay Model

1. Workflow code runs and emits commands.
2. Cadence records matching events in history.
3. On worker restart, cache eviction, or a new event, workflow code is replayed from the beginning.
4. The SDK compares replayed commands with recorded history.

Examples of workflow commands:

| Workflow action | Command | Recorded event |
|---|---|---|
| Execute activity | `ScheduleActivityTask` | `ActivityTaskScheduled` |
| Start timer / sleep | `StartTimer` | `TimerStarted` |
| Start child workflow | `StartChildWorkflowExecution` | `ChildWorkflowExecutionStarted` |
| Continue as new | `ContinueAsNewWorkflowExecution` | `WorkflowExecutionContinuedAsNew` |

## Safe Workflow Code

Workflow code must avoid direct interaction with nondeterministic process state.

Use Cadence APIs instead of language-native equivalents:

- Time: `workflow.Now`, `Workflow.currentTimeMillis`, `Workflow.sleep`
- Concurrency: `workflow.Go`, `workflow.Channel`, `workflow.Selector`, `Promise`
- External calls: activities, not direct I/O in workflow code

## Common Sources Of Non-Determinism

- Reordering, adding, or removing activity calls
- Reordering or removing child workflow calls
- Replacing one workflow command with another without versioning
- Using random values or wall-clock time directly in workflow code
- Using native threads, goroutines, channels, timers, or futures instead of Cadence workflow primitives
- Depending on map iteration order or other unstable collection ordering

## Changes That Usually Do Not Need Versioning

- Changing activity implementation code
- Adjusting activity retry behavior
- Changing activity arguments if command ordering is unchanged
- Refactoring local pure code that does not affect emitted commands

## Recovery Options

When code changes do affect command ordering, use one of these strategies:

- `GetVersion` / `Workflow.getVersion` for compatible in-place evolution
- Start a new workflow type for large incompatible changes
- Reset or recover executions operationally when appropriate

See `references/core/versioning.md`.
