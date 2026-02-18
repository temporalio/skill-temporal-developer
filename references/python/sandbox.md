# Python Workflow Sandbox

## Overview

The Python SDK runs workflows in a sandbox that provides automatic protection against non-deterministic operations. This is unique to Python - TypeScript uses V8 isolation with automatic replacements instead.

## How the Sandbox Works

The sandbox:
- Isolates global state via `exec` compilation
- Restricts non-deterministic library calls via proxy objects
- Passes through standard library with restrictions
- Reloads workflow files on each execution

## Safe Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `datetime.now()` | `workflow.now()` |
| `datetime.utcnow()` | `workflow.now()` |
| `random.random()` | `workflow.random().random()` |
| `random.randint()` | `workflow.random().randint()` |
| `uuid.uuid4()` | `workflow.uuid4()` |
| `time.time()` | `workflow.now().timestamp()` |
| `asyncio.wait()` | `workflow.wait()` (deterministic ordering) |
| `asyncio.as_completed()` | `workflow.as_completed()` |

## Pass-Through Pattern

Third-party libraries that aren't sandbox-aware need explicit pass-through:

```python
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    import pydantic
    from my_module import my_dataclass
```

**When to use pass-through:**
- Data classes and models (Pydantic, dataclasses)
- Serialization libraries
- Type definitions
- Any library that doesn't do I/O or non-deterministic operations

## Importing Activities

Activities should be imported through pass-through since they're defined outside the sandbox:

```python
# workflows/order.py
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from activities.payment import process_payment
    from activities.shipping import ship_order

@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order_id: str) -> str:
        await workflow.execute_activity(
            process_payment,
            order_id,
            start_to_close_timeout=timedelta(minutes=5),
        )
        return await workflow.execute_activity(
            ship_order,
            order_id,
            start_to_close_timeout=timedelta(minutes=10),
        )
```

## Disabling the Sandbox

### Per-Workflow

```python
@workflow.defn(sandboxed=False)
class UnsandboxedWorkflow:
    @workflow.run
    async def run(self) -> str:
        # No sandbox protection - use with caution
        return "result"
```

### Per-Block

```python
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        with workflow.unsafe.sandbox_unrestricted():
            # Unrestricted code block
            pass
        return "result"
```

### Globally (Worker Level)

```python
from temporalio.worker import Worker, UnsandboxedWorkflowRunner

worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    workflow_runner=UnsandboxedWorkflowRunner(),
)
```

## Forbidden Operations

These operations will fail or cause non-determinism in the sandbox:

- **Direct I/O**: Network calls, file reads/writes
- **Threading**: `threading` module operations
- **Subprocess**: `subprocess` calls
- **Global state**: Modifying mutable global variables
- **Blocking sleep**: `time.sleep()` (use `asyncio.sleep()`)

## File Organization

**Critical**: Keep workflow definitions in separate files from activity definitions.

The sandbox reloads workflow definition files on every execution. Minimizing file contents improves Worker performance.

```
my_temporal_app/
├── workflows/
│   └── order.py         # Only workflow classes
├── activities/
│   └── payment.py       # Only activity functions
├── models/
│   └── order.py         # Shared data models
├── worker.py            # Worker setup, imports both
└── starter.py           # Client code
```

## Common Issues

### Import Errors

```
Error: Cannot import 'pydantic' in sandbox
```

**Fix**: Use pass-through:
```python
with workflow.unsafe.imports_passed_through():
    import pydantic
```

### Non-Determinism from Libraries

Some libraries do internal caching or use current time:

```python
# May cause non-determinism
import some_library
result = some_library.cached_operation()  # Cache changes between replays
```

**Fix**: Move to activity or use pass-through with caution.

### Slow Worker Startup

Large workflow files slow down worker initialization because they're reloaded frequently.

**Fix**: Keep workflow files minimal, move logic to activities.

## Best Practices

1. **Separate workflow and activity files** for performance
2. **Use pass-through explicitly** for third-party libraries
3. **Keep workflow files small** to minimize reload time
4. **Move I/O to activities** always
5. **Test with replay** to catch sandbox issues early
