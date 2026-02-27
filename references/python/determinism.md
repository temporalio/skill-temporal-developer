# Python SDK Determinism

## Overview

The Python SDK runs workflows in a sandbox that provides automatic protection against many non-deterministic operations.

## Why Determinism Matters: History Replay

Temporal achieves durability through **history replay**. Understanding this mechanism is key to writing correct Workflow code.

## Forbidden Operations

- Direct I/O (network, filesystem)
- Threading operations
- `subprocess` calls
- Global mutable state modification
- `time.sleep()` (use `workflow.sleep(timedelta(...))`)
- and so on

## Safe Builtin Alternatives to Common Non Deterministic Things

| Forbidden | Safe Alternative |
|-----------|------------------|
| `datetime.now()` | `workflow.now()` |
| `datetime.utcnow()` | `workflow.now()` |
| `random.random()` | `rng = workflow.new_random() ; rng.randint(1, 100)` |
| `uuid.uuid4()` | `workflow.uuid4()` |
| `time.time()` | `workflow.now().timestamp()` |

## Testing Replay Compatibility

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

See more info at `references/python/determinism-protection.md`

## Best Practices

1. Use `workflow.now()` for all time operations
2. Use `workflow.random()` for random values
3. Use `workflow.uuid4()` for unique identifiers
4. Pass through third-party libraries explicitly
5. Test with replay to catch non-determinism
6. Keep workflows focused on orchestration, delegate I/O to activities
7. Use `workflow.logger` instead of print() for replay-safe logging
