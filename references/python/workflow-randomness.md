# Workflow Randomness (Python)

How to obtain random values inside a Temporal Workflow without breaking determinism. The Python SDK exposes two replay-safe primitives on `temporalio.workflow` and forbids every other source of randomness.

## Why this matters

Workflow code must be deterministic to support replay. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:163-165 --> "No randomness" is one of the explicit determinism requirements for Python Workflow code. <!-- docs/develop/python/workflows/basics.mdx:172 -->

During replay, the SDK regenerates Commands from your Workflow code and matches them against the Event History. If intrinsic non-determinism such as inline random branching causes a different Command to be produced, the Workflow Execution returns a non-deterministic error. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:202,207 -->

For the broader replay/sandbox picture see `references/python/determinism.md`.

## The two APIs

### `workflow.random()`

Returns a deterministic `random.Random` instance seeded per Workflow Execution. <!-- docs/develop/python/workflows/basics.mdx:202 -->

- It is a **function**, not an attribute. Call it, then call methods on the returned instance.
- The seed is per-Execution: deterministic across all replays of one Workflow Execution; different across distinct Executions.
- Use any method that `random.Random` provides (e.g. `.randint`, `.random`, `.choice`) on the returned instance.

```python
from temporalio import workflow

@workflow.defn
class PickWinner:
    @workflow.run
    async def run(self, candidates: list[str]) -> str:
        rng = workflow.random()
        return rng.choice(candidates)
```

### `workflow.uuid4()`

Deterministic replacement for `uuid.uuid4()`. <!-- docs/develop/python/workflows/basics.mdx:203 -->

```python
from temporalio import workflow

@workflow.defn
class CreateOrder:
    @workflow.run
    async def run(self) -> str:
        order_id = workflow.uuid4()
        return str(order_id)
```

## Canonical good / bad examples

The Python docs ship a side-by-side good/bad pair for randomness inside a Workflow: <!-- docs/develop/python/workflows/basics.mdx:205-213 -->

```python
# Good — deterministic across replays
value = workflow.random().randint(1, 100)
unique_id = workflow.uuid4()

# Bad — different result on every replay
import random
value = random.randint(1, 100)
```

The instruction is unambiguous: "Never use `random.random()` or other `random` module functions directly." <!-- docs/develop/python/workflows/basics.mdx:202 -->

## Common mistakes

### Using the function as an attribute

```python
# WRONG — workflow.random is a function; this is missing the call
value = workflow.random.randint(1, 100)

# RIGHT — call workflow.random() first, then call methods on the returned Random
value = workflow.random().randint(1, 100)
```

The docs' canonical form is `workflow.random().randint(1, 100)`. <!-- docs/develop/python/workflows/basics.mdx:207 -->

### Calling `uuid.uuid4()` directly

```python
# WRONG — uuid.uuid4() is non-deterministic and produces a different value on every replay
import uuid
order_id = uuid.uuid4()

# RIGHT — workflow.uuid4() is replay-safe
order_id = workflow.uuid4()
```

The docs direct you to `workflow.uuid4()` instead of `uuid.uuid4()`. <!-- docs/develop/python/workflows/basics.mdx:203 -->

Note: `uuid.uuid4()` is fine in **client/starter code** (e.g. generating a Workflow ID before calling `client.execute_workflow(...)`) — the prohibition is only on calls made *inside* Workflow code.

### Reaching for `secrets`, `os.urandom`, or `random.SystemRandom`

The docs name only `workflow.random()` and `workflow.uuid4()` as replay-safe randomness primitives. Cryptographic-randomness sources (`secrets`, `os.urandom`, `random.SystemRandom`) are not addressed positively anywhere. If you need cryptographic randomness, put the call in an Activity so the value is produced once, recorded in history, and replayed from history thereafter. See `references/python/determinism.md` for the general "move non-determinism into Activities" pattern.

### Confusing per-Execution seeding with per-Workflow-Type seeding

The seed is "per Workflow Execution." <!-- docs/develop/python/workflows/basics.mdx:202 --> Two distinct Workflow Executions of the same Workflow Type will see different random values. Don't rely on `workflow.random()` to return the same value across separate Executions — it won't.

### Porting the wrong language's token

Other SDKs name these APIs differently. Don't transliterate:

- Java uses `Workflow.newRandom()` and `Workflow.randomUUID()`. <!-- docs/develop/java/workflows/side-effects.mdx:66,76 -->
- TypeScript transparently replaces `Math.random()` in the sandbox, so plain `Math.random()` works. <!-- docs/develop/typescript/workflows/basics.mdx:137,161 -->
- .NET exposes `Workflow.Random`. <!-- docs/develop/dotnet/workflows/basics.mdx:112 -->

Python's interface is `workflow.random()` (function returning `random.Random`) and `workflow.uuid4()` (function returning `uuid.UUID`). <!-- docs/develop/python/workflows/basics.mdx:202-203 --> Don't invent properties or alternate names.

## When you need randomness the SDK does not provide

If `workflow.random()` and `workflow.uuid4()` are not enough — for example, you need cryptographically secure tokens, or a value drawn from a system entropy source — generate the value inside an Activity and return it to the Workflow. The Activity result is recorded in the Event History and replays deterministically thereafter. See `references/python/determinism.md` and `references/python/python.md` for the Activity-execution pattern.

## See also

- `references/python/determinism.md` — replay model, safe-alternatives table, sandbox overview.
- `references/python/determinism-protection.md` — Python sandbox behavior, forbidden operations, pass-through imports.
- `references/python/gotchas.md` — broader Python anti-patterns inside Workflows.
- `references/core/determinism.md` — language-agnostic replay/Commands/Events explanation.
