# Python SDK Determinism

## Overview

The Python SDK runs workflows in a sandbox that provides automatic protection against many non-deterministic operations.

## Why Determinism Matters: History Replay

Temporal achieves durability through **history replay**. Understanding this mechanism is key to writing correct Workflow code.

### How Replay Works

1. **Initial Execution**: When your Workflow runs for the first time, the SDK records Commands (like "schedule activity") to the Event History stored by Temporal Server.

2. **Recovery/Continuation**: When a Worker restarts, loses connectivity, or picks up a Workflow Task, it must restore the Workflow's state by replaying the code from the beginning.

3. **Command Matching**: During replay, the SDK re-executes your Workflow code but doesn't actually run Activities again. Instead, it compares the Commands your code generates against the Events in history. If there's a match, it uses the stored result.

4. **Non-determinism Detection**: If your code generates different Commands than what's in history (e.g., different Activity name, different order), the SDK raises a `NondeterminismError`.

### Example: Why datetime.now() Breaks Replay

```python
# BAD - Non-deterministic
@workflow.defn
class BadWorkflow:
    @workflow.run
    async def run(self) -> str:
        import datetime
        if datetime.datetime.now().hour < 12:  # Different value on replay!
            await workflow.execute_activity(morning_activity, ...)
        else:
            await workflow.execute_activity(afternoon_activity, ...)
```

If this runs at 11:59 AM initially and replays at 12:01 PM, it will try to schedule a different Activity, causing `NondeterminismError`.

```python
# GOOD - Deterministic
@workflow.defn
class GoodWorkflow:
    @workflow.run
    async def run(self) -> str:
        if workflow.now().hour < 12:  # Consistent during replay
            await workflow.execute_activity(morning_activity, ...)
        else:
            await workflow.execute_activity(afternoon_activity, ...)
```

### Testing Replay Compatibility

Use the `Replayer` class to verify your code changes are compatible with existing histories:

```python
from temporalio.worker import Replayer
from temporalio.client import WorkflowHistory

async def test_replay_compatibility():
    replayer = Replayer(workflows=[MyWorkflow])

    # Test against a saved history
    with open("workflow_history.json") as f:
        history = WorkflowHistory.from_json("my-workflow-id", f.read())

    # This will raise NondeterminismError if incompatible
    await replayer.replay_workflow(history)
```

## Sandbox Behavior

The sandbox:
- Isolates global state via `exec` compilation
- Restricts non-deterministic library calls via proxy objects
- Passes through standard library with restrictions

## Safe Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `datetime.now()` | `workflow.now()` |
| `datetime.utcnow()` | `workflow.now()` |
| `random.random()` | `workflow.random().random()` |
| `random.randint()` | `workflow.random().randint()` |
| `uuid.uuid4()` | `workflow.uuid4()` |
| `time.time()` | `workflow.now().timestamp()` |

## Pass-Through Pattern

For third-party libraries that need to bypass sandbox restrictions:

```python
with workflow.unsafe.imports_passed_through():
    import pydantic
    from my_module import my_activity
```

## Disabling Sandbox

```python
# Per-workflow
@workflow.defn(sandboxed=False)
class UnsandboxedWorkflow:
    pass

# Per-block
with workflow.unsafe.sandbox_unrestricted():
    # Unrestricted code
    pass

# Globally (worker level)
from temporalio.worker import UnsandboxedWorkflowRunner
Worker(..., workflow_runner=UnsandboxedWorkflowRunner())
```

## Forbidden Operations

- Direct I/O (network, filesystem)
- Threading operations
- `subprocess` calls
- Global mutable state modification
- `time.sleep()` (use `asyncio.sleep()`)

## Commands and Events

Understanding the relationship between your code and the Event History:

| Workflow Code | Command Generated | Event Created |
|--------------|-------------------|---------------|
| `workflow.execute_activity()` | ScheduleActivityTask | ActivityTaskScheduled |
| `asyncio.sleep()` / `workflow.sleep()` | StartTimer | TimerStarted |
| `workflow.execute_child_workflow()` | StartChildWorkflowExecution | ChildWorkflowExecutionStarted |
| `workflow.continue_as_new()` | ContinueAsNewWorkflowExecution | WorkflowExecutionContinuedAsNew |
| Return from `@workflow.run` | CompleteWorkflowExecution | WorkflowExecutionCompleted |

## Best Practices

1. Use `workflow.now()` for all time operations
2. Use `workflow.random()` for random values
3. Use `workflow.uuid4()` for unique identifiers
4. Pass through third-party libraries explicitly
5. Test with replay to catch non-determinism
6. Keep workflows focused on orchestration, delegate I/O to activities
7. Use `workflow.logger` instead of print() for replay-safe logging
