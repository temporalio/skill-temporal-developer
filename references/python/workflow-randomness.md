# Python Workflow Randomness

Workflow code is constrained to be deterministic so Temporal can [replay](/develop/python/best-practices/testing-suite#replay) it from history without divergence. Calling `random.random()` or `uuid.uuid4()` directly inside a workflow violates that constraint — every replay would produce a different value, the SDK's generated Commands would no longer match the recorded Events, and the Workflow Execution would fail with a non-determinism error.

The Python SDK exposes two replay-safe alternatives in `temporalio.workflow`: [`workflow.random()`](https://python.temporal.io/temporalio.workflow.html#random) and [`workflow.uuid4()`](https://python.temporal.io/temporalio.workflow.html#uuid4). Each Temporal SDK offers APIs of this shape; results are stored as part of Event History so a re-executed Workflow Function emits the same sequence of Commands even when control flow branches on the result.

For the broader determinism story (forbidden operations, time, sandbox mechanics), see `references/python/determinism.md` and `references/python/determinism-protection.md`.

## `workflow.random()`

Returns a deterministic `random.Random` instance seeded per Workflow Execution. Because the returned object *is* a `random.Random`, all of its methods (`.randint`, `.random`, `.choice`, `.sample`, `.shuffle`, etc.) are reachable through the same instance — they inherit determinism from the seed, not from a separate per-method guarantee.

```python
from temporalio import workflow

@workflow.defn
class JitteredWorkflow:
    @workflow.run
    async def run(self) -> int:
        # Deterministic across replays
        return workflow.random().randint(1, 100)  # docs/develop/python/workflows/basics.mdx:207
```

Notes:

- Call `workflow.random()` from inside `@workflow.run` (or a method reachable from it). It depends on workflow context and is not safe to evaluate at module import time.
- The docs describe the seed only as "per Workflow Execution". Do not assume the seed is the workflow ID, run ID, or any other specific value — it is not documented.
- Never use `random.random()` or other `random` module functions directly inside a workflow.

## `workflow.uuid4()`

Replaces `uuid.uuid4()` for replay-safe UUID generation.

```python
from temporalio import workflow

@workflow.defn
class CorrelatedWorkflow:
    @workflow.run
    async def run(self) -> str:
        unique_id = workflow.uuid4()  # docs/develop/python/workflows/basics.mdx:208
        return str(unique_id)
```


## Forbidden → replay-safe

Scoped to randomness only. For time, see `references/python/determinism.md`.

| Forbidden inside a workflow | Replay-safe replacement |
|---|---|
| `random.random()` | `workflow.random().random()` |
| `random.randint(a, b)` | `workflow.random().randint(a, b)` |
| Any other `random` module function | Method on the `random.Random` returned by `workflow.random()` |
| `uuid.uuid4()` | `workflow.uuid4()` |

## Where else this applies

Workflow inbound and outbound interceptor methods also execute during replay. Use replay-safe APIs for randomness in interceptor code as well.

The Python sandbox restricts known non-deterministic library calls via proxy objects on modules. The sandbox is a safety net for many cases — but the docs describe its restrictions as "a default set that prevents most dangerous standard library calls", not an exhaustive guarantee. Do not rely on the sandbox to catch every misuse; reach for `workflow.random()` / `workflow.uuid4()` directly.

## Common mistakes

### Importing and using `random` directly inside a workflow

```python
# Bad - different result on every replay  # docs/develop/python/workflows/basics.mdx:210
import random
value = random.randint(1, 100)  # docs/develop/python/workflows/basics.mdx:211–212
```

```python
# Good - deterministic across replays  # docs/develop/python/workflows/basics.mdx:206
value = workflow.random().randint(1, 100)
```

### Calling `workflow.random()` at module top level

`workflow.random()` reads workflow execution context. Evaluating it at import time has no workflow context to read from. Always call it inside the workflow's `run` method (or a helper reached from `run`).

```python
# Bad - evaluated at import time, before any workflow exists
_RNG = workflow.random()

@workflow.defn
class BadWorkflow:
    @workflow.run
    async def run(self) -> int:
        return _RNG.randint(1, 100)
```

```python
# Good - called inside the workflow run method
@workflow.defn
class GoodWorkflow:
    @workflow.run
    async def run(self) -> int:
        return workflow.random().randint(1, 100)  # docs/develop/python/workflows/basics.mdx:207
```

### Assuming a Python `workflow.side_effect()` exists

It does not. The Python SDK's randomness surface is `workflow.random()` and `workflow.uuid4()`. For randomness that has to come from outside Temporal entirely (e.g., a hardware RNG, a remote entropy source), put the call in an Activity — Activities run outside the replay path and their results are recorded in history.

### Branching on a non-deterministic input and calling it "random"

`workflow.random()` is replay-safe. A value read from `os.urandom`, the system clock, or any other live source inside the workflow is not, even if it is used in the same `if` statement as `workflow.random()`. The platform-level rule: a Workflow Definition can not have inline logic that branches based on a local time setting or a random number that is not produced by the SDK's replay-safe APIs.

## Worked example: deterministic correlation ID + jittered retry delay

```python
from datetime import timedelta
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from activities.notify import send_notification

@workflow.defn
class JitteredNotificationWorkflow:
    @workflow.run
    async def run(self, user_id: str) -> str:
        # Stable across replays: same ID every time history is replayed
        correlation_id = str(workflow.uuid4())  # docs/develop/python/workflows/basics.mdx:208

        # Stable across replays: jitter is part of the recorded execution
        jitter_seconds = workflow.random().randint(0, 30)  # docs/develop/python/workflows/basics.mdx:207
        await workflow.sleep(timedelta(seconds=jitter_seconds))

        await workflow.execute_activity(
            send_notification,
            args=[user_id, correlation_id],
            start_to_close_timeout=timedelta(seconds=30),
        )
        return correlation_id
```

Both `workflow.uuid4()` and `workflow.random()` produce values that are recorded as part of the Workflow's Event History semantics, so the next replay reads the same correlation ID and the same jitter, and the Workflow's Commands match the recorded Events.

## Related references

- `references/python/determinism.md` — broader determinism rules and the forbidden-operation list (covers `workflow.now()` for time).
- `references/python/determinism-protection.md` — how the Python sandbox enforces these restrictions.
- `references/core/determinism.md` — language-agnostic replay model.
- `references/python/gotchas.md` — anti-patterns adjacent to randomness (timers, sandbox imports).
