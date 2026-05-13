# Temporal Google ADK Integration (Python)

> **Experimental.** As of Temporal Python SDK `1.24.0`, this integration is experimental and may have future breaking changes.

## Overview

The Temporal Python SDK ships a contrib module that lets [Google ADK](https://adk.dev/) agents run inside Temporal Workflows with durable-execution guarantees. LLM calls become Temporal Activities, tool functions become Activities, and MCP toolsets become Activities — so an agent that crashes mid-run resumes from the last recorded step instead of starting over.

The integration is listed in the Temporal Python integrations table alongside Braintrust, OpenAI Agents SDK, Pydantic AI, and Tenuo.  It is built on the Temporal Python SDK's Plugin system.

Canonical upstream guide: `https://adk.dev/integrations/temporal/`.

## Prerequisites

- Python `3.10+`.
- Temporal Python SDK `1.24.0` or later.
- A Gemini API key (or any other model ADK supports).
- A running Temporal server — local dev server, self-hosted, or Temporal Cloud.

## Installation

```bash
pip install "temporalio[google-adk]"
```

The extra name is `google-adk` (hyphen). The installed module path is `temporalio.contrib.google_adk_agents` (underscores, with `_agents` suffix).

## Module map

| Symbol | Import from | Role |
|---|---|---|
| `GoogleAdkPlugin` | `temporalio.contrib.google_adk_agents` | Plugin registered on both Client and Worker.  |
| `TemporalModel` | `temporalio.contrib.google_adk_agents` | ADK model that routes LLM calls through Temporal Activities.  |
| `TemporalMcpToolSet` | `temporalio.contrib.google_adk_agents` | Agent-side toolset wrapper that executes MCP tools as Activities.  |
| `TemporalMcpToolSetProvider` | `temporalio.contrib.google_adk_agents` | Plugin-side provider that pairs with `TemporalMcpToolSet`.  |
| `activity_tool` | `temporalio.contrib.google_adk_agents.workflow` | Wraps an `@activity.defn` function into an ADK tool.  |

Casing is exact: `GoogleAdkPlugin`, `TemporalMcpToolSet`, `TemporalMcpToolSetProvider` (title-case "Adk" and "Mcp", not "ADK" / "MCP").

## Basic agent in a Workflow

A Workflow definition wraps an ADK `Agent` whose model is a `TemporalModel` and whose tools are `activity_tool`-wrapped Activities. The full upstream example:

```python
from contextlib import aclosing
from datetime import timedelta
from google.adk.agents import Agent
from google.adk.runners import InMemoryRunner
from google.genai import types
from temporalio import activity, workflow
from temporalio.common import RetryPolicy
from temporalio.contrib.google_adk_agents import TemporalModel
from temporalio.contrib.google_adk_agents.workflow import activity_tool
from temporalio.workflow import ActivityConfig

@activity.defn
async def get_weather(city: str) -> str:
    """Get current weather for a city."""
    return f"72°F and sunny in {city}"

weather_tool = activity_tool(
    get_weather,
    start_to_close_timeout=timedelta(seconds=30),
    retry_policy=RetryPolicy(maximum_attempts=3),
)

agent = Agent(
    name="weather_agent",
    model=TemporalModel(
      "gemini-flash-latest",
      activity_config=ActivityConfig(summary="Weather Agent")),
    tools=[weather_tool],
)

@workflow.defn
class WeatherAgentWorkflow:
    @workflow.run
    async def run(self, user_message: str) -> str:
        runner = InMemoryRunner(agent=agent, app_name="weather_app")
        session = await runner.session_service.create_session(
            user_id="user", app_name="weather_app"
        )
        result = ""
        async with aclosing(runner.run_async(
            user_id="user",
            session_id=session.id,
            new_message=types.Content(
                role="user", parts=[types.Part.from_text(text=user_message)]
            ),
        )) as events:
            async for event in events:
                if event.content and event.content.parts:
                    for part in event.content.parts:
                        if part.text:
                            result = part.text
        return result
```

Key shape rules visible in this example:

- `activity_tool` is a **function**, not a decorator. Define the Activity with `@activity.defn` as usual, then wrap it with `activity_tool(fn, start_to_close_timeout=..., retry_policy=...)` and pass the **wrapped object** to `Agent(tools=[...])`.
- `TemporalModel` takes the model name as a positional string and an `activity_config=ActivityConfig(...)` keyword argument. The `summary` shows up on the Activity in the Temporal UI.
- The raw Activity function (`get_weather` above) is still registered on the Worker — the wrapper just makes ADK invoke it as an Activity, not bypass Worker registration.

## Worker setup

Register the plugin on both the Client and the Worker:

```python
import asyncio
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin

async def main():
    client = await Client.connect(
        "localhost:7233",
        plugins=[GoogleAdkPlugin()]
    )

    worker = Worker(
        client,
        task_queue="my-agent-task-queue",
        workflows=[WeatherAgentWorkflow],
        activities=[get_weather],
    )
    await worker.run()

asyncio.run(main())
```

## Client invocation

Start the agent like any other Workflow. The client also needs `GoogleAdkPlugin` so that serialization and span propagation match what the Worker expects:

```python
import asyncio
from temporalio.client import Client
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin

async def start():
    client = await Client.connect(
        "localhost:7233",
        plugins=[GoogleAdkPlugin()]
    )
    result = await client.execute_workflow(
        WeatherAgentWorkflow.run,
        "What's the weather in San Francisco?",
        id="weather-agent-1",
        task_queue="my-agent-task-queue",
    )
    print(result)

asyncio.run(start())
```

## MCP tools

ADK's MCP toolsets (e.g. filesystem MCP) wrap as Temporal Activities via a pair: `TemporalMcpToolSetProvider` on the plugin, `TemporalMcpToolSet` on the agent. Both are constructed with the same name so they bind together. The `not_in_workflow_toolset=` argument is the factory used when the agent runs **outside** a Workflow (e.g., under `adk web`) — it must be supplied so local-fallback works.

```python
from google.adk.agents import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters
from temporalio.client import Client
from temporalio.contrib.google_adk_agents import (
    GoogleAdkPlugin,
    TemporalModel,
    TemporalMcpToolSet,
    TemporalMcpToolSetProvider,
)

def toolset_factory(_):
    return McpToolset(
        connection_params=StdioConnectionParams(
            server_params=StdioServerParameters(
                command="npx",
                args=["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"],
            ),
        ),
    )

toolset_provider = TemporalMcpToolSetProvider("my-tools", toolset_factory)
client = await Client.connect(
    "localhost:7233",
    plugins=[GoogleAdkPlugin(toolset_providers=[toolset_provider])]
)

agent = Agent(
    name="tool_agent",
    model=TemporalModel("gemini-flash-latest"),
    tools=[TemporalMcpToolSet("my-tools", not_in_workflow_toolset=toolset_factory)],
)
```

Note that when MCP toolsets are in play, the plugin on `Client.connect(...)` is `GoogleAdkPlugin(toolset_providers=[toolset_provider])` — the providers list is registered on the plugin, not on the agent.

## Local development with `adk web`

The Temporal wrappers automatically fall back to direct (non-Temporal) execution when run outside a Temporal Workflow, so `adk web` and other ADK development commands work without a running Temporal server.  This is the reason `TemporalMcpToolSet` requires `not_in_workflow_toolset=`: outside the Workflow there is no Activity context to dispatch into, and the agent uses the factory directly.

## How it works

The plugin's job is to make ADK's agent runtime safe inside Temporal's deterministic Workflow sandbox. According to the upstream guide:

- LLM calls are executed as Temporal Activities via `TemporalModel`, with retries and replay handled by Temporal.
- Non-deterministic Python calls are replaced with Workflow-safe equivalents — e.g., `time.time()` → `workflow.now()`, `uuid.uuid4()` → `workflow.uuid4()`.
- ADK and `google.genai` modules are configured for the Temporal sandbox (passed through so imports work inside Workflow code).
- Pydantic serialization is configured automatically for ADK's data types — you do not need to add `pydantic_data_converter` yourself for ADK payloads.

For background on the Plugin abstraction itself — what plugins can supply (Activities, Workflows, interceptors, converters, context propagators) and the deterministic-Workflow constraints they must respect — see the [Plugins guide](../../../../documentation/docs/develop/plugins-guide.mdx) at `docs/develop/plugins-guide.mdx`.

## Capabilities

The upstream guide lists these capabilities; the file does not provide concrete code for each, so treat the table as a pointer, not a recipe:

| Capability | What it means |
|---|---|
| Durable tool execution | `activity_tool` wraps tool functions as Activities, supporting long-running tools, automatic retries, and heartbeating. |
| MCP tool support | `TemporalMcpToolSet` executes MCP tools as Activities with full event propagation. |
| Human-in-the-loop | A Workflow can wait for Signals/Updates and resume the agent when human input arrives. |
| Deterministic runtime | `GoogleAdkPlugin` swaps non-deterministic calls for Temporal-safe equivalents (see "How it works" above). |
| Debuggability | Every LLM call and tool execution is visible as an Activity in the Temporal UI. |
| Observability | OpenTelemetry with resilient cross-process spans. |
| Safe versioning | Deploy new agent versions using Temporal Worker Versioning without disrupting in-flight executions. |
| Multi-agent orchestration | Multiple agents can be composed within a Workflow. |

For Python-side patterns shared across LLM integrations (Pydantic data converter, disabling client retries, structured outputs, multi-agent pipelines, etc.), see `references/python/ai-patterns.md` and `references/core/ai-patterns.md`.

## Common mistakes

- **Wrong module path.** It is `temporalio.contrib.google_adk_agents` (suffix `_agents`), **not** `temporalio.contrib.google_adk` or `temporalio.contrib.adk`.
- **Wrong pip extra.** It is `pip install "temporalio[google-adk]"` (hyphen, in quotes). Not `google_adk`, not `temporalio-google-adk`.
- **Treating `activity_tool` as a decorator.** It's a wrapper function — write `weather_tool = activity_tool(get_weather, ...)` and pass `weather_tool` to `Agent(tools=[...])`.
- **Forgetting `activity_config` on `TemporalModel`.** The upstream example always shows `activity_config=ActivityConfig(summary="...")`; without a `summary` the Activity is harder to identify in the Temporal UI.
- **Forgetting `not_in_workflow_toolset=` on `TemporalMcpToolSet`.** Required for `adk web` local-fallback to work.
- **Registering the plugin on only one side.** The upstream guide shows `plugins=[GoogleAdkPlugin()]` on **both** `Client.connect(...)` and the `Worker(...)`.
- **Forgetting to register the underlying Activity on the Worker.** `activity_tool(get_weather, ...)` wraps `get_weather` but does not register it — `Worker(activities=[get_weather])` still lists the raw function.
- **Assuming the integration is stable.** It is experimental as of Temporal Python SDK `1.24.0`.

## Related

- `references/python/ai-patterns.md` — Python LLM/agent patterns, Pydantic data converter, OpenAI Agents SDK contrib.
- `references/core/ai-patterns.md` — Conceptual AI/LLM patterns.
- `docs/develop/plugins-guide.mdx` — How the SDK Plugin abstraction works (the abstraction `GoogleAdkPlugin` is built on).
- `docs/develop/python/integrations/index.mdx` — Python integrations index.
- Upstream guide: `https://adk.dev/integrations/temporal/`.
