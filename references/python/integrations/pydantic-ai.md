# Temporal Pydantic AI Integration (Python)

## Overview

[Pydantic AI](https://ai.pydantic.dev/) ships first-party Temporal support in its `pydantic_ai.durable_exec.temporal` submodule. Wrapping a Pydantic AI `Agent` in `TemporalAgent` makes its model requests, tool calls, and MCP server communication run as Temporal Activities, while the agent loop itself runs deterministically inside a Temporal Workflow.

Unlike most other Python AI integrations in this catalog, this code **does not** live under `temporalio.contrib`. Install it from Pydantic AI, not from a Temporal extra.

For the language-agnostic AI/LLM patterns shared across integrations (when to put a tool in an Activity vs. workflow, centralized retry policy, multi-agent orchestration) read `references/core/ai-patterns.md`. For Python-side LLM patterns that apply when **not** using this integration (Pydantic data converter, generic LLM Activity shape, disabling client-side retries) read `references/python/ai-patterns.md`. Both are still relevant context — `TemporalAgent` configures `pydantic_data_converter` for you, but the broader patterns about retry classification and tool placement still apply.

## Install

The integration is a Pydantic AI extra, not a Temporal one:

```bash
pip install "pydantic-ai-slim[temporal]"
```

The `temporal` extra pulls in `temporalio>=1.24.0`.

Use `pip install pydantic-ai` if you want the full Pydantic AI install.

## Imports

```python
from temporalio import workflow
from temporalio.client import Client
from temporalio.worker import Worker

from pydantic_ai import Agent
from pydantic_ai.durable_exec.temporal import (
    PydanticAIPlugin,
    PydanticAIWorkflow,
    TemporalAgent,
)
```

## Required: agent `name` and toolset `id`

Pydantic AI builds Temporal Activity names from the wrapped `Agent.name` and from each dynamic toolset's `id`. Activity names must be stable and unique, so these two fields are **mandatory** when an agent is wrapped in `TemporalAgent`, even though they are optional outside Temporal.

- **Don't change `name` or `id` after deploying to production.** Renaming an agent or toolset breaks Activity identity for any in-flight Workflows replaying against existing history.

```python
agent = Agent(
    "openai:gpt-4o",
    instructions="You answer geography questions.",
    name="geography",
)
```

For dynamic toolsets registered with `@agent.toolset`, set `id=` explicitly on the decorator.

## Wrap the agent

`TemporalAgent` is the wrapper. It freezes the agent's model and toolsets at wrap time and reroutes I/O through dynamically registered Temporal Activities.

```python
from pydantic_ai.durable_exec.temporal import TemporalAgent

temporal_agent = TemporalAgent(agent)
```

Construct it once at module scope so the same instance is referenced from both the Workflow and the Worker registration.

### `TemporalAgent` constructor parameters

| Parameter | Type | Purpose |
|---|---|---|
| `wrapped` | `AbstractAgent` | The Pydantic AI agent to make durable (positional, required). |
| `name` | `str \| None` | Override `wrapped.name` for Activity naming. |
| `models` | `Mapping[str, Model] \| None` | Pre-registered model instances, keyed by model name. Required for arbitrary `Model` objects (see below). |
| `provider_factory` | `TemporalProviderFactory \| None` | Callable receiving the run context and provider name to construct a provider per Activity invocation. |
| `event_stream_handler` | `EventStreamHandler \| None` | Streaming alternative — see "Streaming" below. |
| `activity_config` | `ActivityConfig \| None` | Base Temporal Activity config applied to every model/toolset/tool Activity. |
| `model_activity_config` | `ActivityConfig \| None` | Override for the model-request Activity. |
| `toolset_activity_config` | `dict[str, ActivityConfig] \| None` | Per-toolset override, keyed by toolset `id`. |
| `tool_activity_config` | `dict[str, dict[str, ActivityConfig \| Literal[False]]] \| None` | Per-tool override, nested as `{toolset_id: {tool_name: config_or_False}}`. Use `False` to opt a non-I/O tool out of Activity dispatch. |
| `run_context_type` | `type[TemporalRunContext]` | Custom `TemporalRunContext` subclass for serializing the run context across the Activity boundary. |

- **`TemporalAgent` does not accept arbitrary `Model` instances.** Use model strings (`"openai:gpt-4o"`) or pre-register via `models={"my-model": MyModel(...)}`.
- **If no `activity_config` is given, model and tool Activities default to `start_to_close_timeout=60s`.** Override per-tier (`model_activity_config`, `toolset_activity_config`, `tool_activity_config`) when you need different timeouts or retry policies.

## Register the plugin on the Client

Pass `PydanticAIPlugin()` to `Client.connect()`:

```python
from temporalio.client import Client
from temporalio.worker import Worker
from pydantic_ai.durable_exec.temporal import PydanticAIPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[PydanticAIPlugin()],
)

async with Worker(
    client,
    task_queue="geography",
    workflows=[GeographyWorkflow],
):
    ...
```

`PydanticAIPlugin` configures `pydantic_data_converter` on the Client so Pydantic models cross the Activity boundary correctly, registers the dynamically created Activities on Workers created from that Client, and treats `pydantic_ai.exceptions.UserError` as non-retryable. Temporal automatically propagates Client plugins that implement the Worker plugin protocol, so do not also pass `PydanticAIPlugin()` to `Worker`; doing so runs the plugin twice.

Do not also set `data_converter=pydantic_data_converter` yourself — the plugin owns that wiring. The standalone `pydantic_data_converter` setup in `references/python/ai-patterns.md` is for code paths that are **not** using `TemporalAgent`.

### `AgentPlugin` — alternative Worker registration

`AgentPlugin` is a Worker-only plugin for registering a single `TemporalAgent` directly when you don't want to declare it on a `PydanticAIWorkflow` subclass. Use `PydanticAIPlugin` on the Client and `AgentPlugin(temporal_agent)` on the Worker.

## Define the Workflow

Subclass `PydanticAIWorkflow` and list every `TemporalAgent` instance the workflow uses in `__pydantic_ai_agents__`. The plugin reads that list to register the agent's Activities on the Worker.

```python
from temporalio import workflow
from pydantic_ai.durable_exec.temporal import PydanticAIWorkflow

@workflow.defn
class GeographyWorkflow(PydanticAIWorkflow):
    __pydantic_ai_agents__ = [temporal_agent]

    @workflow.run
    async def run(self, prompt: str) -> str:
        result = await temporal_agent.run(prompt)
        return result.output
```

Multiple agents in one Workflow: include each in `__pydantic_ai_agents__` and call `await each_agent.run(...)` as needed.

## Dependencies and the run context

Anything passed as `deps=` to `TemporalAgent.run()` must round-trip through `pydantic_data_converter`, so dependency objects must be serializable as Pydantic types (dataclasses, `BaseModel`, or other types the converter supports — see `references/python/ai-patterns.md` for the converter rules).

Inside an Activity, the `RunContext` exposes only the fields Pydantic AI can serialize across the boundary. By default that is: `deps`, `run_id`, `metadata`, `retries`, `tool_call_id`, `tool_name`, `tool_call_approved`, `tool_call_metadata`, `retry`, `max_retries`, `run_step`, `usage`, `partial_output`. Model, prompt, messages, and tracer are not available there.

Subclass `TemporalRunContext` and pass it as `run_context_type=` on `TemporalAgent` if you need to expose additional serializable fields.

## Streaming

`Agent.run_stream()`, `Agent.run_stream_events()`, and `Agent.iter()` are not supported on a `TemporalAgent`, because Temporal Activities cannot stream output back to the calling Workflow turn-by-turn.

The supported alternative is `event_stream_handler` on the underlying `Agent` (or passed to `TemporalAgent(..., event_stream_handler=...)`). The handler runs inside the Activity and forwards events to an out-of-band sink — a message queue, database, or a Temporal Workflow Stream — that the UI subscribes to. See `references/python/workflow-streams.md` for the Workflow Streams sink option.

## Logfire integration

Pydantic AI ships a Temporal-aware `LogfirePlugin` that publishes both Temporal telemetry and Pydantic AI events to Logfire. Register it alongside `PydanticAIPlugin` on the Client:

```python
from pydantic_ai.durable_exec.temporal import LogfirePlugin, PydanticAIPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[PydanticAIPlugin(), LogfirePlugin()],
)
```

If `pandas` is installed and used from inside an Activity that calls `logfire.info(...)`, pass `pandas` through the Workflow sandbox to avoid an import race:

```python
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    import pandas
```

## End-to-end example

```python
from temporalio import workflow
from temporalio.client import Client
from temporalio.worker import Worker

from pydantic_ai import Agent
from pydantic_ai.durable_exec.temporal import (
    PydanticAIPlugin,
    PydanticAIWorkflow,
    TemporalAgent,
)

agent = Agent(
    "openai:gpt-4o",
    instructions="You answer geography questions.",
    name="geography",
)
temporal_agent = TemporalAgent(agent)


@workflow.defn
class GeographyWorkflow(PydanticAIWorkflow):
    __pydantic_ai_agents__ = [temporal_agent]

    @workflow.run
    async def run(self, prompt: str) -> str:
        result = await temporal_agent.run(prompt)
        return result.output


async def main() -> None:
    client = await Client.connect(
        "localhost:7233",
        plugins=[PydanticAIPlugin()],
    )

    async with Worker(
        client,
        task_queue="geography",
        workflows=[GeographyWorkflow],
    ):
        result = await client.execute_workflow(
            GeographyWorkflow.run,
            "What is the capital of Mexico?",
            id="geo-1",
            task_queue="geography",
        )
        print(result)
```

## Hard constraints

- **`Agent.name` must be set and stable.** It anchors Activity identity for the agent's model and toolset Activities; renaming after deploy breaks replay.
- **Dynamic toolsets must set `id=` explicitly** for the same reason.
- **The Pydantic AI integration ships in `pydantic_ai.durable_exec.temporal`**, not in `temporalio.contrib`. Install it via `pip install "pydantic-ai-slim[temporal]"`.
- **Register `PydanticAIPlugin` on `Client.connect()` only.** Workers created from that Client inherit the plugin; passing it to `Worker` again runs it twice.
- **`TemporalAgent` does not accept arbitrary `Model` instances.** Use model strings or pre-register via `models={...}`.
- **Streaming via `Agent.run_stream()` / `run_stream_events()` / `iter()` is unsupported.** Use `event_stream_handler` and an out-of-band sink.
- **Dependencies passed to `TemporalAgent.run(deps=...)` must be Pydantic-serializable** because they cross the Activity boundary.
- **Default Activity `start_to_close_timeout` is 60 seconds** when no `activity_config` is supplied. Set per-tier configs (`model_activity_config`, `toolset_activity_config`, `tool_activity_config`) when you need different timeouts or retry policies.

## Common mistakes

- **Omitting `id=` on an `@agent.toolset` dynamic toolset.** `TemporalAgent` raises while wrapping the agent; define a stable ID before constructing the wrapper.
- **Setting `data_converter=pydantic_data_converter` in addition to `PydanticAIPlugin()`.** The plugin already configures the data converter — drop the extra arg.

## Resources

- `references/python/ai-patterns.md` — Python AI/LLM patterns for code paths that don't use this integration (Pydantic data converter, generic LLM Activity, retry classification).
- `references/core/ai-patterns.md` — language-agnostic agent patterns (tool placement, multi-agent orchestration).
- `references/python/integrations/langsmith.md` — companion observability plugin if you prefer LangSmith over Logfire.
- Upstream guide — [Pydantic AI Temporal integration](https://pydantic.dev/docs/ai/integrations/durable_execution/temporal/).
- Upstream API reference — [`pydantic_ai.durable_exec.temporal`](https://pydantic.dev/docs/ai/api/pydantic-ai/durable_exec/).
