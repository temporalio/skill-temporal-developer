# Temporal Google ADK Agents Integration

## Overview

The Temporal Python SDK ships an integration that lets [Google ADK](https://adk.dev/) agents run inside Temporal Workflows. It is delivered as a contrib module under `temporalio.contrib.google_adk_agents` and is built on the Temporal Python SDK [Plugin system](/develop/plugins-guide).

Use it when you want an ADK `Agent` to gain Temporal's durability guarantees — automatic crash recovery, deterministic replay, long-running tool execution as activities, retries, cancellation, and Temporal UI visibility — without rewriting the agent. The integration wraps ADK model calls and MCP tool calls as Temporal Activities and installs the determinism patches an ADK agent needs to be replay-safe.

The canonical user guide is the integration page at [adk.dev/integrations/temporal/](https://adk.dev/integrations/temporal/). This reference covers Temporal-side setup, the public symbols, and the pitfalls an AI assistant is most likely to get wrong.

## Install

The integration is shipped inside `temporalio` as an optional extra:

```bash
pip install "temporalio[google-adk]"
```

The extra is named `google-adk` (hyphen) and pulls in `google-adk>=1.27.0,<2`.

The module path is `temporalio.contrib.google_adk_agents` (note the `_agents` suffix and underscores).

## What the plugin does

`GoogleAdkPlugin` is a `SimplePlugin` subclass that configures three things for an ADK agent to run safely inside a Workflow:

1. **Determinism patches.** Inside workflow context, `time.time()` is replaced with `workflow.now()` and `uuid.uuid4()` is replaced with `workflow.uuid4()`. ADK internals that would otherwise produce non-deterministic output become replay-safe.
2. **Sandbox passthrough.** When the worker uses `SandboxedWorkflowRunner`, the plugin adds passthrough for exactly these three modules: `google.adk`, `google.genai`, `mcp`. This lets the agent import them inside workflow code without sandbox violations.
3. **Pydantic-aware payload conversion.** The plugin sets a payload converter that extends `PydanticPayloadConverter` and emits JSON with `exclude_unset=True`, so ADK objects (which carry many optional fields) serialise compactly.

The plugin also **registers two activities on the worker**: `invoke_model` and `invoke_model_streaming`. You do not register these yourself — the plugin does it. Tool activities you write are registered the normal way (passed to `Worker(activities=[...])`).

## Core symbols

| Symbol | Module | Purpose |
|---|---|---|
| `GoogleAdkPlugin` | `temporalio.contrib.google_adk_agents` | Worker plugin: determinism patches, sandbox passthrough, Pydantic payload converter, registers `invoke_model` activities. |
| `TemporalModel` | `temporalio.contrib.google_adk_agents` | ADK `BaseLlm` subclass; routes model invocations through Temporal activities. |
| `TemporalMcpToolSet` | `temporalio.contrib.google_adk_agents` | ADK toolset wrapper; MCP tool calls run as activities inside a workflow, with a fallback for non-workflow contexts. |
| `TemporalMcpToolSetProvider` | `temporalio.contrib.google_adk_agents` | Plugin-side factory registration so the worker can serve a named MCP toolset. |
| `activity_tool` | `temporalio.contrib.google_adk_agents.workflow` | Decorator/wrapper that adapts a Temporal activity into an ADK tool while preserving its signature for ADK's tool-schema generation. **Marked experimental.** |

`activity_tool` is **not** re-exported from the package root — import it from `temporalio.contrib.google_adk_agents.workflow`.

### `GoogleAdkPlugin.__init__`

```python
GoogleAdkPlugin(toolset_providers: list[TemporalMcpToolSetProvider] | None = None)
```

### `TemporalModel.__init__`

```python
TemporalModel(
    model_name: str,
    activity_config: ActivityConfig | None = None,
    *,
    summary_fn: Callable[[LlmRequest], str | None] | None = None,
    streaming_topic: str | None = None,
    streaming_batch_interval: timedelta = timedelta(milliseconds=100),
)
```

`activity_config` is the `temporalio.workflow.ActivityConfig` that will be applied to the underlying `invoke_model` / `invoke_model_streaming` activity execution. If you don't pass one, the default uses `start_to_close_timeout=timedelta(seconds=60)`.

### `activity_tool`

```python
def activity_tool(activity_def: Callable, **kwargs: Any) -> Callable: ...
```

`activity_def` is a function decorated with `@activity.defn`. The `**kwargs` are the same options you would pass to `workflow.execute_activity`: `start_to_close_timeout`, `schedule_to_close_timeout`, `heartbeat_timeout`, `retry_policy`, `task_queue`, etc.

## Minimal end-to-end example

A workflow that exposes one Temporal activity as an ADK tool and runs an ADK `Agent` to call it.

**`activities.py`** — define the tool as a Temporal activity:

```python
from temporalio import activity

@activity.defn
async def get_weather(city: str) -> str:
    return f"72°F and sunny in {city}"
```

**`workflows.py`** — wrap the activity as an ADK tool, build the agent, run it from the workflow:

```python
from contextlib import aclosing
from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.contrib.google_adk_agents import TemporalModel
from temporalio.contrib.google_adk_agents.workflow import activity_tool
from temporalio.workflow import ActivityConfig

with workflow.unsafe.imports_passed_through():
    from google.adk.agents import Agent
    from google.adk.runners import InMemoryRunner
    from google.genai import types
    from activities import get_weather

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
        async with aclosing(runner.run_async(
            user_id="user",
            session_id=session.id,
            new_message=types.Content(
                role="user",
                parts=[types.Part.from_text(text=user_message)],
            ),
        )) as events:
            async for event in events:
                if event.content and event.content.parts:
                    for part in event.content.parts:
                        if part.text:
                            result = part.text
        return result
```

**`worker.py`** — register the plugin on the client; the worker registers the workflow and your tool activity:

```python
import asyncio

from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin

from activities import get_weather
from workflows import WeatherAgentWorkflow

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

if __name__ == "__main__":
    asyncio.run(main())
```

Note: `plugins=[GoogleAdkPlugin()]` is passed to **`Client.connect`**, not to `Worker(...)`. The plugin propagates from the client to the worker created with that client. The `invoke_model` / `invoke_model_streaming` activities are added automatically by the plugin — do not list them in the worker's `activities=[...]`.

**`starter.py`** — start the workflow:

```python
import asyncio

from temporalio.client import Client
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin

from workflows import WeatherAgentWorkflow

async def main() -> None:
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

if __name__ == "__main__":
    asyncio.run(main())
```

## MCP tools

MCP support is two paired symbols: one on the agent, one on the plugin. The toolset is identified by a string name that must match on both sides.

```python
import os

from google.adk.agents import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters

from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.google_adk_agents import (
    GoogleAdkPlugin,
    TemporalMcpToolSet,
    TemporalMcpToolSetProvider,
)

def toolset_factory(_):
    return McpToolset(
        connection_params=StdioConnectionParams(
            server_params=StdioServerParameters(
                command="npx",
                args=[
                    "-y",
                    "@modelcontextprotocol/server-filesystem",
                    os.path.dirname(os.path.abspath(__file__)),
                ],
            ),
        ),
    )

agent = Agent(
    name="test_agent",
    model="gemini-2.5-pro",
    tools=[
        TemporalMcpToolSet(
            "my-tools",
            not_in_workflow_toolset=toolset_factory,
        ),
    ],
)

client = await Client.connect(
    "localhost:7233",
    plugins=[
        GoogleAdkPlugin(
            toolset_providers=[
                TemporalMcpToolSetProvider("my-tools", toolset_factory),
            ],
        ),
    ],
)

worker = Worker(client, task_queue="task-queue")
```

Key points:

- The first positional argument to **both** `TemporalMcpToolSet` and `TemporalMcpToolSetProvider` is the toolset name. They must be identical strings.
- `not_in_workflow_toolset=` on `TemporalMcpToolSet` is the fallback used when the agent runs outside a Temporal workflow (see next section).
- The provider exposes its activities to the worker through `toolset_provider._get_activities()`; `GoogleAdkPlugin` aggregates these into the worker's activity registration automatically.

## Running ADK locally without Temporal

The same agent definitions also work outside Temporal under `adk run` or `adk web`. `TemporalModel` and `activity_tool` fall back to local execution when there is no workflow context.

For MCP, define a shared `toolset_factory` and pass it both to `TemporalMcpToolSetProvider` (for the Temporal worker) and to `TemporalMcpToolSet(..., not_in_workflow_toolset=...)` (for the local-run fallback). The single factory is the bridge:

```python
agent = Agent(
    name="test_agent",
    model=TemporalModel("gemini-2.5-pro"),
    tools=[
        TemporalMcpToolSet(
            "my-tools",
            not_in_workflow_toolset=toolset_factory,
        ),
    ],
)
```

## Common mistakes

1. **Wrong module path.** It is `temporalio.contrib.google_adk_agents` — plural `agents`, underscores. Not `temporalio.contrib.google_adk`, not `temporalio.contrib.adk`.
2. **Wrong pip extra.** It is `temporalio[google-adk]` — hyphen, no `_agents` suffix on the extra. Not `temporalio[google_adk]` or `temporalio[google-adk-agents]`.
3. **Plugin passed to the wrong constructor.** `GoogleAdkPlugin()` belongs in `Client.connect(plugins=[...])`. Passing it to `Worker(plugins=[...])` is not the pattern the README shows.
4. **Importing `activity_tool` from the package root.** It is only at `temporalio.contrib.google_adk_agents.workflow.activity_tool` — `__init__.py` does not re-export it.
5. **Registering `invoke_model` yourself.** The plugin registers `invoke_model` and `invoke_model_streaming`. Listing them again on `Worker(activities=[...])` is unnecessary and can collide on activity-name registration.
6. **Inventing helpers from other integrations.** There is no `create_workflow_agent`, no ADK equivalent of the OpenAI Agents SDK's `Runner.run_as_workflow`. You build a normal ADK `Agent(model=TemporalModel(...))` and run it from inside `@workflow.run` using ADK's own runner.
7. **MCP names mismatched between agent and plugin.** The string passed to `TemporalMcpToolSet("X", ...)` must equal the string passed to `TemporalMcpToolSetProvider("X", factory)`.
8. **Wrong kwarg on `TemporalMcpToolSet`.** It is `not_in_workflow_toolset=`, not `fallback=` or `outside_workflow=`.
9. **Assuming extra sandbox passthroughs.** The plugin only adds `google.adk`, `google.genai`, `mcp`. If your agent imports another module that the sandbox rejects (for example `litellm`), you must extend passthrough yourself — see `references/python/determinism-protection.md`.
10. **Skipping `activity_executor` for sync tool activities.** ADK does not change Temporal's activity execution model. If your `activity_tool`-wrapped activity is sync (`def`, not `async def`), the worker still needs an `activity_executor`. See `references/python/sync-vs-async.md`.

## Related references

- **`references/python/python.md`** — Python SDK basics (workers, clients, sandbox, `workflow.unsafe.imports_passed_through()`). The minimal example above assumes you are comfortable with these.
- **`references/python/ai-patterns.md`** — Python AI/LLM patterns: Pydantic data converter, generic LLM activities, tool-calling agent loops. `GoogleAdkPlugin` already sets a Pydantic-based payload converter; do not stack a separate `pydantic_data_converter` on top.
- **`references/core/ai-patterns.md`** — Conceptual AI patterns shared across SDKs.
- **`references/python/determinism-protection.md`** — Sandbox behaviour and how to add passthrough modules beyond the three the plugin adds.
- **`references/python/sync-vs-async.md`** — Choosing sync vs async for the tool activities your agent calls.
- **`docs/develop/plugins-guide.mdx`** (in the Temporal docs) — generic Plugin authoring guide, useful background for what `SimplePlugin` provides.
- **External:** [adk.dev/integrations/temporal/](https://adk.dev/integrations/temporal/) is the canonical integration guide; [adk.dev](https://adk.dev/) covers ADK itself.
