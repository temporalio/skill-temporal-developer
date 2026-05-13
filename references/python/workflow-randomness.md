# Python: Deterministic Randomness in Workflows

Replay-safe random numbers and UUIDs inside Temporal Workflow code (Python SDK).

## TL;DR

| Need | Bad (non-deterministic) | Good (replay-safe) |
| --- | --- | --- |
| Random numbers | `random.random()`, `random.randint(...)`, or other `random` module functions <!-- docs/develop/python/workflows/basics.mdx:202 --> | `workflow.random().randint(1, 100)` — returns a deterministic `random.Random` instance seeded per Workflow Execution <!-- docs/develop/python/workflows/basics.mdx:202,207 --> |
| UUIDs | `uuid.uuid4()` <!-- docs/develop/python/workflows/basics.mdx:203 --> | `workflow.uuid4()` <!-- docs/develop/python/workflows/basics.mdx:203,208 --> |

## Why this matters

Workflow code must be deterministic to support replay: every execution of a Workflow Definition must produce the same Commands in the same sequence given the same input. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:159-160 --> A Workflow Definition cannot have inline logic that branches based on a local time setting or a random number — that is classified as *intrinsic non-determinism*. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:245-249 -->

If a generated Command doesn't match what the Event History expects, the Workflow Execution returns a non-deterministic error. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:202 --> The encyclopedia walks through this exact failure mode using a random number generator that returns `84` on first execution and `14` on replay, causing the conditional branch to take a different path and emit the wrong `ScheduleActivityTask` Command. <!-- docs/encyclopedia/event-history/python.mdx:273-306 -->

Temporal SDKs solve this by providing replay-safe APIs whose results are stored in Event History, so re-execution issues the same sequence of Commands even with branching. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:262-263 -->

## `workflow.random()`

`workflow.random()` returns a deterministic `random.Random` instance seeded per Workflow Execution. <!-- docs/develop/python/workflows/basics.mdx:202 --> Because the returned object is a standard library `random.Random`, any method on `random.Random` works on it (for example `.randint`, `.random`, `.choice`, `.shuffle`, `.sample`, `.uniform` — these are stdlib methods, not Temporal extensions).

```python
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> int:
        # Good - deterministic across replays
        value = workflow.random().randint(1, 100)
        return value
```

<!-- Source: docs/develop/python/workflows/basics.mdx:200-213 -->

Do not use `random.random()` or other `random` module functions directly. <!-- docs/develop/python/workflows/basics.mdx:202 -->

<!-- VERIFY: Does workflow.random() return the same Random instance on each call within a single Workflow Execution, or a fresh one? The Python docs say only "seeded per Workflow Execution" and do not specify. -->

<!-- VERIFY: Exact seed source. The docs state "seeded per Workflow Execution" but do not specify what value is used as the seed. -->

## `workflow.uuid4()`

`workflow.uuid4()` is the replay-safe replacement for `uuid.uuid4()`. <!-- docs/develop/python/workflows/basics.mdx:203 -->

```python
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        unique_id = workflow.uuid4()
        return str(unique_id)
```

<!-- Source: docs/develop/python/workflows/basics.mdx:205-208 -->

`workflow.uuid4()` is the only UUID helper named in the Python Workflow docs covered here. For other UUID versions (v1, v3, v5, v7, etc.), generate the value in an Activity and return it to the Workflow.

<!-- VERIFY: Whether workflow.random() and workflow.uuid4() share underlying seed state is not stated in the docs reviewed. -->

## Sandbox interaction

The Python SDK runs Workflow code in a sandbox environment to help prevent non-determinism errors. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:29 --> The sandbox applies *restrictions* that prevent known non-deterministic library calls, using proxy objects on modules wrapped around the custom importer set in the sandbox. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:63-64 --> A default set of restrictions prevents most dangerous standard library calls. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:68 -->

That is why direct calls to non-deterministic stdlib APIs (such as `random.random()` from inside Workflow code) are caught by the sandbox — use `workflow.random()` and `workflow.uuid4()` instead.

The Python sandbox is not completely isolated, and some libraries can internally mutate state, which can result in breaking determinism. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:30 --> For sandbox internals and customization, see `references/python/determinism-protection.md`.

## Common mistakes

- **Capitalization drift.** Python uses lowercase `workflow.random()` and `workflow.uuid4()`. `Workflow.Random()` is not the Python form. <!-- docs/develop/python/workflows/basics.mdx:202-203 -->
- **Invented UUID variants.** The Python Workflow docs covered here name only `workflow.uuid4()`. Do not assume `workflow.uuid7()`, `workflow.uuid5()`, or `workflow.new_uuid()` exist.
- **Importing `random` at module level and calling it inside the Workflow.** Even with the import, calling `random.random()` / `random.randint(...)` inside Workflow code is non-deterministic and is what `workflow.random()` exists to replace. <!-- docs/develop/python/workflows/basics.mdx:202,210-213 -->
- **Treating `workflow.random()` as cryptographically secure.** It returns a stdlib `random.Random` instance <!-- docs/develop/python/workflows/basics.mdx:202 --> — that is a general-purpose PRNG, not a CSPRNG. For cryptographic randomness, do the work in an Activity.
- **Branching on `random.random()` directly.** Inline branching on a raw random number is the canonical example of intrinsic non-determinism. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:207,247-249 --> The walkthrough in `docs/encyclopedia/event-history/python.mdx:259-308` shows precisely how this corrupts replay.
- **Conflating `workflow.unsafe.is_replaying` with randomness.** That API is for replay detection in advanced cases (such as Interceptors), not for randomness, and branching Workflow business logic on replay status breaks determinism. <!-- docs/develop/python/workflows/basics.mdx:223-230 -->

## What still requires an Activity

The docs reviewed here do not provide Workflow-side APIs for the following — do them in an Activity and pass the result back to the Workflow:

- Cryptographically secure randomness (CSPRNG, secrets, key material).
- UUID versions other than v4 (only `workflow.uuid4()` is named). <!-- docs/develop/python/workflows/basics.mdx:203 -->
- External entropy sources such as `/dev/urandom` or hardware RNGs.

The general guidance: to handle non-deterministic operations like API calls, LLM/AI invocations, database queries, and other external interactions, put them in Activities. Activities execute outside the replay path and are automatically retried so they don't cause non-determinism errors. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:163-167 -->

## See also

- `references/python/determinism.md` — broader Python determinism guidance.
- `references/python/determinism-protection.md` — Python sandbox internals and customization.
- `references/core/determinism.md` — cross-SDK determinism concepts.
