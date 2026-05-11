# Workflow randomness and UUIDs (Python)

Replay-safe replacements for `random.*` and `uuid.uuid4()` inside Python Workflow Definitions.

## Overview

Workflow code must be deterministic because the Temporal Server may replay your Workflow to reconstruct its state, and the constraints explicitly list "no randomness". <!-- docs/develop/python/workflows/basics.mdx:169-172 --> The Python SDK provides replay-safe alternatives for common needs (including randomness and UUIDs). <!-- docs/develop/python/workflows/basics.mdx:182 --> Inside a Workflow, call `workflow.random()` in place of the `random` module and `workflow.uuid4()` in place of `uuid.uuid4()`. <!-- docs/develop/python/workflows/basics.mdx:202-203 -->

## Why direct randomness is forbidden

Intrinsic non-determinism is when a Workflow Function Execution might emit a different sequence of Commands on re-execution, regardless of whether all the input parameters are the same. A Workflow Definition cannot have inline logic that branches (emits a different Command sequence) based on a local time setting or a random number. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:247-249 -->

Each Temporal SDK offers APIs that enable Workflow Definitions to have logic that gets and uses time, random numbers, and data from unreliable resources. When those APIs are used, the results are stored as part of the Event History, which means that a re-executed Workflow Function will issue the same sequence of Commands, even if there is branching involved. <!-- docs/encyclopedia/workflow/workflow-definition.mdx:262-263 -->

## API

### `workflow.random()`

Returns a deterministic `random.Random` instance seeded per Workflow Execution. Call it with no arguments. <!-- docs/develop/python/workflows/basics.mdx:202 --> Methods on the returned instance produce the same sequence on every replay; the docs show `randint` used this way. <!-- docs/develop/python/workflows/basics.mdx:207 -->

```python
# Good - deterministic across replays
value = workflow.random().randint(1, 100)
```
<!-- docs/develop/python/workflows/basics.mdx:206-207 -->

Never use `random.random()` or other `random` module functions directly. <!-- docs/develop/python/workflows/basics.mdx:202 -->

<!-- VERIFY: does `workflow.random()` return the same `Random` instance on every call within one Workflow Execution, or a fresh instance each call? The docs say "a deterministic `random.Random` instance seeded per Workflow Execution" without specifying instance identity. -->

<!-- VERIFY: what is the exact seed source? The docs say "seeded per Workflow Execution" without naming the seed value. -->

### `workflow.uuid4()`

Use `workflow.uuid4()` in place of `uuid.uuid4()` to generate UUIDs that are stable across replays. <!-- docs/develop/python/workflows/basics.mdx:203 -->

```python
unique_id = workflow.uuid4()
```
<!-- docs/develop/python/workflows/basics.mdx:208 -->

<!-- VERIFY: exact return type of `workflow.uuid4()`. The docs only say "instead of `uuid.uuid4()`" and do not transcribe a return type. -->

## Anti-patterns

Plain `random` module calls inside a Workflow Definition produce a different result on every replay:

```python
# Bad - different result on every replay
import random
value = random.randint(1, 100)
```
<!-- docs/develop/python/workflows/basics.mdx:210-212 -->

Likewise, `uuid.uuid4()` is not safe in Workflow code; use `workflow.uuid4()` instead. <!-- docs/develop/python/workflows/basics.mdx:203 -->

Do not branch business logic on replay status as a substitute for these APIs. `workflow.unsafe.is_replaying` exists to guard one-shot side effects (such as emitting metrics from an Interceptor), and "Never use this to affect Workflow business logic — branching on replay status breaks determinism." <!-- docs/develop/python/workflows/basics.mdx:223-228 -->

## Interceptors caveat

Workflow inbound and outbound interceptor methods also execute during replay. Use replay-safe APIs for logging, randomness, and time in these interceptors. <!-- docs/develop/python/workers/interceptors.mdx:41 --> That means an interceptor that needs a random number or UUID must call `workflow.random()` / `workflow.uuid4()`, not the stdlib `random` or `uuid` equivalents. Activity and Client interceptors are not affected by replay. <!-- docs/develop/python/workers/interceptors.mdx:46 -->

## Where this fits

- `references/python/determinism.md` — broader determinism rules and replay mechanics for Python Workflows.
- `references/python/determinism-protection.md` — Workflow sandbox internals and passthrough behavior.
