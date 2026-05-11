# LangSmith Tracing Plugin (Python)

## Overview

`LangSmithPlugin` is an experimental Temporal Python SDK plugin <!-- sdk-python: contrib/langsmith/README.md top banner --> that lets [LangSmith](https://smith.langchain.com/) `@traceable` calls work inside Temporal Workflows and Activities, propagates trace context across Worker boundaries, and prevents duplicate traces on Workflow replay. <!-- sdk-python: contrib/langsmith/README.md intro -->

It is built on Temporal's Plugin system — an abstraction that customizes a Temporal Worker setup, including registering Workflow and Activity definitions, modifying worker and client options, and more. <!-- docs/develop/plugins-guide.mdx:20-22 --> Observability/tracing middleware is one of the use cases the plugin system is designed for. <!-- docs/develop/plugins-guide.mdx:30 -->

The plugin is at the **experimental** release stage. <!-- sdk-python: contrib/langsmith/README.md top banner --> Experimental features have APIs that are subject to change. <!-- docs/evaluate/development-production-features/release-stages.mdx:26 -->

> The plugin is not yet listed in the Python SDK's third-party integrations table. <!-- docs/develop/python/integrations/index.mdx:23-29 --> <!-- VERIFY: re-check the integrations index on next docs sync; LangSmith may move from "experimental upstream" to a row in this table. -->

## Install

```bash
uv add temporalio[langsmith]
```
<!-- sdk-python: contrib/langsmith/README.md §Quick Start -->

## Quick Start

Register the plugin on the Temporal Client. The recommendation is to register it on both the Client (starter) side and on all Workers; you only strictly need it on the side that produces traces, but adding it everywhere avoids surprises with context propagation. <!-- sdk-python: contrib/langsmith/README.md §API Reference (closing paragraph) -->

```python
from temporalio.client import Client
from temporalio.contrib.langsmith import LangSmithPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[LangSmithPlugin(project_name="my-project")],
)
```
<!-- sdk-python: contrib/langsmith/README.md §Quick Start -->

The Client and Worker do not need to share the same plugin configuration — for example, they can use different `add_temporal_runs` settings. <!-- sdk-python: contrib/langsmith/README.md §API Reference (closing paragraph) -->

## API Reference

```python
LangSmithPlugin(
    client=None,              # langsmith.Client instance (auto-created if None)
    project_name=None,        # LangSmith project name
    add_temporal_runs=False,  # Show Temporal operation nodes in traces
    default_metadata=None,    # Custom metadata attached to all traces
    default_tags=None,        # Custom tags attached to all traces
)
```
<!-- sdk-python: contrib/langsmith/README.md §API Reference -->

A lower-level `LangSmithInterceptor` is also exported from `temporalio.contrib.langsmith` <!-- sdk-python: contrib/langsmith/__init__.py --> but `LangSmithPlugin` is the supported entry point — use the plugin unless you have a specific reason to wire the interceptor manually.

## Where `@traceable` Works

| Location                       | Works? | Notes                                                                                                                     |
|--------------------------------|--------|---------------------------------------------------------------------------------------------------------------------------|
| Inside Workflow methods        | Yes    | `@traceable` calls from inside `@workflow.run`, `@workflow.signal`, etc. — sync or async                                  |
| Inside Activity methods        | Yes    | `@traceable` calls from inside `@activity.defn` — sync or async                                                           |
| On `@activity.defn` functions  | Yes    | Stack `@traceable` **above** `@activity.defn`. The trace fires on every retry (see "Wrapping Retriable Steps" below)      |
| On `@workflow.defn` classes    | No     | Use `@traceable` inside `@workflow.run` instead. Decorating the workflow class or the `@workflow.run` function is unsupported |

<!-- sdk-python: contrib/langsmith/README.md §"Where `@traceable` Works" -->

Decorator order matters when stacking on an Activity:

```python
from langsmith import traceable
from temporalio import activity

@traceable(name="Call OpenAI", run_type="llm")  # outer
@activity.defn                                   # inner
async def call_openai(req: OpenAIRequest) -> Response:
    ...
```
<!-- sdk-python: contrib/langsmith/README.md §"Migrating Existing LangSmith Code" + matrix row "On @activity.defn functions" -->

## `add_temporal_runs`

By default `add_temporal_runs=False` and only your `@traceable` application logic appears in the trace tree. <!-- sdk-python: contrib/langsmith/README.md §"`add_temporal_runs`" --> Setting it to `True` also adds Temporal operation nodes (`StartWorkflow`, `RunWorkflow`, `StartActivity`, `RunActivity`, etc.) so the orchestration layer is visible alongside application logic. <!-- sdk-python: contrib/langsmith/README.md §"`add_temporal_runs`" -->

`StartFoo` and `RunFoo` appear as siblings in the tree: the start is the short-lived outbound RPC that enqueues work on a task queue and completes immediately; the run is the actual execution, which may be delayed and may take much longer. <!-- sdk-python: contrib/langsmith/README.md §"`add_temporal_runs`" -->

Use `False` (the default) when you want a clean LangSmith view focused on LLM and chain calls. Use `True` when you are debugging the Temporal layer and want orchestration events in the same trace.

## Replay Safety

Temporal Workflows are deterministic and replay from event history on recovery. The plugin handles this so you don't have to: <!-- sdk-python: contrib/langsmith/README.md §"Replay Safety" -->

- **No duplicate traces on replay.** Run IDs are derived deterministically from the Workflow's random seed, so replayed operations produce the same IDs and LangSmith deduplicates them.
- **No non-deterministic calls injected.** The plugin uses `workflow.now()` for timestamps and `workflow.random()` for UUIDs in trace metadata, not `datetime.now()` and `uuid4()`.
- **Background I/O stays outside the sandbox.** LangSmith HTTP calls are submitted to a background thread pool that doesn't interfere with deterministic Workflow execution.

<!-- All four bullets: sdk-python: contrib/langsmith/README.md §"Replay Safety" -->

## Wrapping Retriable Steps

A `@traceable` on an `@activity.defn` fires on every retry. To group attempts under one logical step, wrap the activity call from the Workflow in an outer `@traceable`:

```python
@traceable(name="Call OpenAI", run_type="llm")
@activity.defn
async def call_openai(...):
    ...

@traceable(name="my_step", run_type="chain")
async def my_step(message: str) -> str:
    return await workflow.execute_activity(call_openai, ...)
```

The resulting trace groups retries under the outer run:

```
my_step
  Call OpenAI           # first attempt
    openai.responses.create
  Call OpenAI           # retry
    openai.responses.create
```
<!-- sdk-python: contrib/langsmith/README.md §"Example: Wrapping Retriable Steps in a Trace" -->

## Context Propagation

The plugin propagates trace context across process boundaries (Client → Workflow → Activity → Child Workflow → Nexus) via Temporal headers; you don't need to pass any context manually. <!-- sdk-python: contrib/langsmith/README.md §"Context Propagation" --> This is the same header-based mechanism Temporal Plugins use generally for context propagation. <!-- docs/develop/plugins-guide.mdx:815-833 -->

## Related references

- `references/python/observability.md` — broader Python observability picture (logs, metrics, OpenTelemetry tracing). LangSmith tracing is complementary to OpenTelemetry-based tracing, not a replacement.
- `references/python/ai-patterns.md` — Pydantic data converter setup and LLM activity patterns. Use those patterns alongside this plugin.
- Upstream README: <https://github.com/temporalio/sdk-python/tree/main/temporalio/contrib/langsmith> — canonical reference; consult on every release because the plugin is experimental.
