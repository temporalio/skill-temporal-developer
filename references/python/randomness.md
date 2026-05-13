# Workflow Randomness (Python SDK)

Workflow code in Python must be deterministic so the Temporal Server can [replay](/develop/python/best-practices/testing-suite#replay) it and reconstruct state. Replay re-executes the workflow from the beginning, so any randomness drawn from non-replay-safe sources (`random.random()`, `uuid.uuid4()`, `secrets.*`) will produce different values on each run and break replay.

The `temporalio.workflow` module exposes two replay-safe callables for randomness:

- **`workflow.random()`** — returns a deterministic `random.Random` instance, seeded per Workflow Execution.
- **`workflow.uuid4()`** — replay-safe replacement for `uuid.uuid4()`.

The "no randomness" rule is one of the workflow logic constraints listed at the top of the determinism section in `basics.mdx`.

## `workflow.random()`

Returns a deterministic `random.Random` instance seeded per Workflow Execution.  Because the underlying object is a standard-library `random.Random`, you call its methods (`randint`, `choice`, `sample`, etc.) on the returned instance — there is no `workflow.randint` or `workflow.choice` shortcut.

```python
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> int:
        # Good — deterministic across replays
        return workflow.random().randint(1, 100)  # docs/develop/python/workflows/basics.mdx:207
```

Bad — using the `random` module directly produces a different result on every replay and triggers a non-determinism error:

```python
# Bad — different result on every replay
import random
value = random.randint(1, 100)  # docs/develop/python/workflows/basics.mdx:210-212
```

The docs do not specify whether `workflow.random()` returns a fresh `Random` each call or a shared per-Execution instance. Treat the contract as: *whatever you get, it is deterministic across replays of the same Execution*.

The docs do not name the seed source ("seeded per Workflow Execution" is the verbatim wording). Do not write "seeded with the workflow ID" or "seeded with the run ID" — those are not in the documentation.

## `workflow.uuid4()`

Replay-safe replacement for `uuid.uuid4()`.

```python
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        unique_id = workflow.uuid4()  # docs/develop/python/workflows/basics.mdx:208
        return str(unique_id)
```

The docs show `workflow.uuid4()` being assigned to `unique_id` without showing the return type explicitly; the contract documented is "use instead of `uuid.uuid4()`".

## Where these APIs must be used

Workflow code itself is the primary place. **Workflow inbound and outbound interceptor methods also execute during replay**, so any interceptor code path that needs randomness must use `workflow.random()` / `workflow.uuid4()`.  Activity interceptors and Client interceptors are not affected by replay.

## Common mistakes

- **Calling `random.random()`, `random.randint(...)`, `random.choice(...)`, etc. inside a workflow.** The docs explicitly say "Never use `random.random()` or other `random` module functions directly."
- **Calling `uuid.uuid4()` inside a workflow.** Use `workflow.uuid4()` instead.
- **Inventing kwargs.** `workflow.random()` and `workflow.uuid4()` are called with no arguments in the docs. Do not pass `seed=`, `version=`, etc.
- **Branching on `workflow.unsafe.is_replaying` to "skip" random calls during replay.** The docs warn: "Never use this to affect Workflow business logic — branching on replay status breaks determinism."  Just call `workflow.random()` unconditionally — it is already replay-safe.
- **Reaching for `secrets`, `os.urandom`, `numpy.random`, or `hashlib`-based "randomness".** The docs in `basics.mdx` cover `random` and `uuid` explicitly. They are silent on these other sources, so do not assume any of them are safe inside workflow code. If you need cryptographically strong randomness, generate it in an [Activity](/activities) and return the value.
- **Generating randomness in module-level code that the workflow file imports.** Workflow files are re-executed on every replay; randomness drawn during import is non-deterministic. Move the call into the workflow method.

## Related references

- `references/python/determinism.md` — broader determinism rules, the full replay-safe alternatives table, sandbox notes.
- `references/python/data-handling.md` — also lists `workflow.uuid4()` and `workflow.random()` in its "Deterministic APIs for Values" section.
- `references/python/determinism-protection.md` — Python sandbox internals.
- `references/core/determinism.md` — language-agnostic explanation of why determinism matters and how replay works.
