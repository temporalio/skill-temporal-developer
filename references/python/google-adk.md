# Google ADK Integration (Python)

Run [Google Agent Development Kit](https://adk.dev/) agents inside Temporal Workflows. The Temporal Python SDK ships a contrib package — `temporalio.contrib.google_adk_agents` — that routes ADK model calls and tools through Temporal Activities so an ADK agent gets durable execution, automatic retries, and replay-safe state. <!-- sdk-python: temporalio/contrib/google_adk_agents/README.md -->

The integration is listed in the Python integrations table at `docs/develop/python/integrations/index.mdx:26` with the canonical setup guide hosted at `https://adk.dev/integrations/temporal/`. The Temporal docs themselves do not duplicate the API reference — the SDK source and the adk.dev guide are the ground truth.

## When to use this

Use this integration when:

- You already build agents with `google.adk.agents.Agent` and want them to survive worker restarts.
- You need ADK tool calls (or MCP tools) to retry with Temporal's retry policies instead of being lost on a process crash.
- You want to keep `adk run` / `adk web` working locally without standing up a Temporal server during iteration. <!-- adk.dev/integrations/temporal/ -->

If your agent is built with the OpenAI Agents SDK rather than ADK, see the "OpenAI Agents SDK Integration" section in [`ai-patterns.md`](./ai-patterns.md) instead.

## Install

The integration is gated behind an extra on the Temporal Python SDK:

```bash
pip install "temporalio[google-adk]"
```

<!-- sdk-python: pyproject.toml [project.optional-dependencies] google-adk = ["google-adk>=1.27.0,<2"] -->

This pulls in `google-adk>=1.27.0,<2` alongside the core SDK.

## What the contrib package exports

`temporalio.contrib.google_adk_agents` exports exactly four symbols at the package root: <!-- sdk-python: temporalio/contrib/google_adk_agents/__init__.py __all__ -->

| Symbol | Source submodule | Purpose |
|---|---|---|
| `TemporalModel` | `_model` | Drop-in `Model` for an ADK `Agent` that routes each LLM call through a Temporal Activity. |
| `GoogleAdkPlugin` | `_plugin` | Worker/Client plugin that wires in the deterministic runtime patches, Pydantic serialization, and any MCP toolset providers. |
| `TemporalMcpToolSet` | `_mcp` | An MCP toolset whose individual tool invocations run as Activities. |
| `TemporalMcpToolSetProvider` | `_mcp` | Registers a named factory for an `McpToolset` with the plugin so workers can construct it lazily. |

Plus one helper in the `workflow` submodule:

- `temporalio.contrib.google_adk_agents.workflow.activity_tool(activity_def, **kwargs)` — wraps a `@activity.defn` function into an ADK-callable tool, forwarding `**kwargs` (e.g. `start_to_close_timeout=`, `retry_policy=`) as the activity invocation options. <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py -->

> Note: `activity_tool` is **not** re-exported from the package root. Import it from the `.workflow` submodule.

## Minimal end-to-end setup

The three pieces — agent, worker, client — all need the plugin so headers, serialization, and the deterministic runtime line up. <!-- adk.dev/integrations/temporal/ -->

### 1. Define the agent and the workflow

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
    return f"72F and sunny in {city}"


weather_tool = activity_tool(
    get_weather,
    start_to_close_timeout=timedelta(seconds=30),
    retry_policy=RetryPolicy(maximum_attempts=3),
)

agent = Agent(
    name="weather_agent",
    model=TemporalModel(
        "gemini-flash-latest",
        activity_config=ActivityConfig(summary="Weather Agent"),
    ),
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
        async with aclosing(
            runner.run_async(
                user_id="user",
                session_id=session.id,
                new_message=types.Content(
                    role="user",
                    parts=[types.Part.from_text(text=user_message)],
                ),
            )
        ) as events:
            async for event in events:
                if event.content and event.content.parts:
                    for part in event.content.parts:
                        if part.text:
                            result = part.text
        return result
```

<!-- adk.dev/integrations/temporal/ §"Define Agent and Workflow" -->

Key shapes to keep verbatim:

- `TemporalModel("gemini-flash-latest", activity_config=ActivityConfig(...))` — first positional is `model_name: str`; `activity_config` is the only non-keyword-only optional. Keyword-only options on `TemporalModel` are `summary_fn`, `streaming_topic`, and `streaming_batch_interval` (defaults to `timedelta(milliseconds=100)`). <!-- sdk-python: temporalio/contrib/google_adk_agents/_model.py __init__ -->
- `activity_tool(get_weather, start_to_close_timeout=..., retry_policy=...)` — `**kwargs` are forwarded as activity invocation options. <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py -->
- `InMemoryRunner` comes from `google.adk.runners`, not from the Temporal contrib package. <!-- adk.dev/integrations/temporal/ -->

### 2. Configure the worker

```python
import asyncio

from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin


async def main() -> None:
    client = await Client.connect(
        "localhost:7233",
        plugins=[GoogleAdkPlugin()],
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

<!-- adk.dev/integrations/temporal/ §"Configure Worker" -->

`GoogleAdkPlugin()` is passed to `Client.connect(..., plugins=[...])`. The plugin abstraction is documented at `docs/develop/plugins-guide.mdx:20`; per that guide, plugins customize worker setup including registering Workflow and Activity definitions and modifying worker and client options. <!-- docs/develop/plugins-guide.mdx:20-22 -->

### 3. Start the workflow

```python
import asyncio

from temporalio.client import Client
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin


async def start() -> None:
    client = await Client.connect(
        "localhost:7233",
        plugins=[GoogleAdkPlugin()],
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

<!-- adk.dev/integrations/temporal/ §"Execute Workflow" -->

The starting client also needs `plugins=[GoogleAdkPlugin()]` so request headers and the Pydantic-aware data converter match what the worker is configured with.

## MCP toolsets

For Model Context Protocol tools, wrap the `McpToolset` factory in a `TemporalMcpToolSetProvider` and register it with the plugin. Inside the agent, refer to the same toolset by name via `TemporalMcpToolSet`.

```python
from google.adk.agents import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters

from temporalio.client import Client
from temporalio.contrib.google_adk_agents import (
    GoogleAdkPlugin,
    TemporalMcpToolSet,
    TemporalMcpToolSetProvider,
    TemporalModel,
)


def toolset_factory(_):
    return McpToolset(
        connection_params=StdioConnectionParams(
            server_params=StdioServerParameters(
                command="npx",
                args=[
                    "-y",
                    "@modelcontextprotocol/server-filesystem",
                    "/path/to/dir",
                ],
            ),
        ),
    )


toolset_provider = TemporalMcpToolSetProvider("my-tools", toolset_factory)

client = await Client.connect(
    "localhost:7233",
    plugins=[GoogleAdkPlugin(toolset_providers=[toolset_provider])],
)

agent = Agent(
    name="tool_agent",
    model=TemporalModel("gemini-flash-latest"),
    tools=[TemporalMcpToolSet("my-tools", not_in_workflow_toolset=toolset_factory)],
)
```

<!-- adk.dev/integrations/temporal/ §"MCP Tool Integration" -->

Signatures to honor:

- `TemporalMcpToolSetProvider(name: str, toolset_factory: Callable[[Any | None], McpToolset])`. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py __init__ -->
- `TemporalMcpToolSet(name, config=None, factory_argument=None, not_in_workflow_toolset=None)`. `name` must match the provider name passed to the plugin. `config` is an `ActivityConfig`. `not_in_workflow_toolset` is the same factory the provider uses; supplying it enables the local-execution fallback. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py __init__ -->
- `GoogleAdkPlugin(toolset_providers: list[TemporalMcpToolSetProvider] | None = None)`. <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py __init__ -->

## Local development (no Temporal server)

`TemporalModel`, `activity_tool`, and `TemporalMcpToolSet` detect whether they're inside a Workflow at call time and fall back to direct execution outside one. That means the same `Agent` definition works with `adk run` and `adk web` without a running Temporal server. <!-- adk.dev/integrations/temporal/ §"Local Development" -->

For `TemporalMcpToolSet` specifically, the fallback only works if you pass `not_in_workflow_toolset=<factory>` — without it, there is no source for an `McpToolset` outside a workflow context. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py -->

## What the plugin actually does

`GoogleAdkPlugin` configures the worker for ADK in two ways: <!-- sdk-python: temporalio/contrib/google_adk_agents/README.md -->

1. **Deterministic runtime** — substitutes ADK's calls to `time.time()` with `workflow.now()` and `uuid.uuid4()` with `workflow.uuid4()` when executing inside a workflow, so replays stay deterministic.
2. **Pydantic serialization** — installs the Pydantic-aware data converter so ADK's Pydantic request/response models round-trip through Temporal payloads without custom converters.

This is why the same plugin instance must be passed to both `Client.connect(...)` (so the client encodes payloads with Pydantic) and through that client to the `Worker` (so the worker decodes them and patches the runtime). The plugin pattern itself, including the data converter and workflow-runner hooks Python plugins use, is described at `docs/develop/plugins-guide.mdx`. <!-- docs/develop/plugins-guide.mdx:525-545, 840-864 -->

## Common mistakes

| Wrong | Right | Why |
|---|---|---|
| `from temporalio.contrib.google.adk import …` | `from temporalio.contrib.google_adk_agents import …` | The package is `google_adk_agents` (single underscore-separated module). <!-- sdk-python: temporalio/contrib/google_adk_agents/__init__.py --> |
| `from temporalio.contrib.google_adk_agents import activity_tool` | `from temporalio.contrib.google_adk_agents.workflow import activity_tool` | `activity_tool` is in the `.workflow` submodule and not re-exported. <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py --> |
| `pip install temporalio[adk]` | `pip install "temporalio[google-adk]"` | Extra name is `google-adk`. <!-- sdk-python: pyproject.toml --> |
| `TemporalModel(model="gemini-...")` or `TemporalModel(name="…")` | `TemporalModel("gemini-...", activity_config=ActivityConfig(...))` | First arg is positional `model_name: str`. <!-- sdk-python: temporalio/contrib/google_adk_agents/_model.py --> |
| Forgetting `plugins=[GoogleAdkPlugin()]` on the starting client | Pass it to `Client.connect(...)` everywhere — worker and starter | Without it, the starting client's payload conversion doesn't match the worker's. <!-- adk.dev/integrations/temporal/ --> |
| Reusing `create_workflow_agent(...)` from the OpenAI Agents example | Use `google.adk.agents.Agent(..., model=TemporalModel(...))` | `create_workflow_agent` is part of the separate OpenAI Agents contrib and does not exist for ADK. <!-- adk.dev/integrations/temporal/ --> |

## See also

- `references/python/ai-patterns.md` — generic LLM/Activity patterns, including the OpenAI Agents SDK contrib for comparison.
- `docs/develop/python/integrations/index.mdx` — Python integrations index.
- `docs/develop/plugins-guide.mdx` — plugin system this integration is built on.
- `https://adk.dev/integrations/temporal/` — upstream integration guide.
- `https://github.com/temporalio/sdk-python/tree/main/temporalio/contrib/google_adk_agents` — source of truth for symbol signatures.
