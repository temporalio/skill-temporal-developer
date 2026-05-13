# Google ADK Integration (Python)

## Overview

The `temporalio.contrib.google_adk_agents` module lets Google ADK agents run inside Temporal Workflows. <!-- sdk-python: temporalio/contrib/google_adk_agents/__init__.py --> It routes the ADK agent's LLM calls and MCP tool calls through Temporal Activities and replaces non-deterministic stdlib calls (`time.time()`, `uuid.uuid4()`) with workflow-safe equivalents while inside a workflow. <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py -->

The Temporal Python docs catalog lists Google ADK as an agent-framework integration and points to the upstream guide at `adk.dev/integrations/temporal/`. <!-- docs/develop/python/integrations/index.mdx:26 -->

> **Experimental.** The integration is marked experimental in the SDK source; class names and signatures may change. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py docstrings, workflow.py warning -->

## Install

```bash
pip install "temporalio[google-adk]"
```

The `google-adk` extra pulls in `google-adk` itself. <!-- sdk-python: pyproject.toml [project.optional-dependencies] google-adk = ["google-adk>=1.27.0,<2"] -->

## Public API

`temporalio.contrib.google_adk_agents` exports exactly four symbols: <!-- sdk-python: temporalio/contrib/google_adk_agents/__init__.py __all__ -->

| Symbol | Purpose |
|---|---|
| `TemporalModel` | An ADK model that executes each LLM call as a Temporal Activity. |
| `GoogleAdkPlugin` | A Temporal plugin (Client + Worker) that configures the Pydantic payload converter and sandbox passthrough for ADK/Gemini/MCP modules. |
| `TemporalMcpToolSet` | An ADK MCP toolset whose tool invocations dispatch as Temporal Activities. |
| `TemporalMcpToolSetProvider` | A factory wrapper that registers an MCP toolset for use by `TemporalMcpToolSet`. |

`activity_tool` is a separate helper at `temporalio.contrib.google_adk_agents.workflow`. <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py --> It wraps an `@activity.defn` so it can be passed to an `Agent` as a tool; inside a workflow it dispatches via `workflow.execute_activity`, outside one it calls the underlying function directly.

`Agent`, `Runner`/`InMemoryRunner`, and `McpToolset` come from upstream `google.adk` — they are **not** re-exported by the integration.

## Plugin registration

`GoogleAdkPlugin` is registered on the Temporal `Client`. The same client is then handed to the `Worker`, which inherits the plugin's sandbox and converter configuration. <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py -->

```python
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.google_adk_agents import GoogleAdkPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[GoogleAdkPlugin()],
)

worker = Worker(
    client,
    task_queue="my-agent-task-queue",
    workflows=[MyAgentWorkflow],
    activities=[...],
)
await worker.run()
```

`GoogleAdkPlugin.__init__` takes an optional `toolset_providers: list[TemporalMcpToolSetProvider] | None`. <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py --> Pass providers here when you use `TemporalMcpToolSet`; see [MCP tools](#mcp-tools) below.

The plugin configures:

- The Pydantic payload converter required for ADK message objects. You do **not** need to set `data_converter=pydantic_data_converter` on the client yourself — the plugin handles it.
- Sandbox passthrough for the `google.adk`, `google.genai`, and `mcp` modules so they don't get re-imported on every workflow execution. <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py -->

## `TemporalModel`

`TemporalModel` is an ADK `BaseLlm` whose `generate_content` runs inside a Temporal Activity, so each LLM call is durable and retried by Temporal rather than the model client. <!-- sdk-python: temporalio/contrib/google_adk_agents/_model.py -->

Constructor: <!-- sdk-python: temporalio/contrib/google_adk_agents/_model.py -->

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

`model_name` is positional. `activity_config` configures the per-call Activity (timeouts, retry policy, task queue, etc.) and is imported from `temporalio.workflow`:

```python
from datetime import timedelta
from temporalio.workflow import ActivityConfig
from temporalio.common import RetryPolicy
from temporalio.contrib.google_adk_agents import TemporalModel

model = TemporalModel(
    "gemini-2.5-pro",
    activity_config=ActivityConfig(
        start_to_close_timeout=timedelta(seconds=60),
        retry_policy=RetryPolicy(maximum_attempts=3),
        summary="Researcher LLM call",
    ),
)
```

## Wrapping activities as ADK tools

ADK tools are plain Python callables. To make a tool durable, define it as a Temporal Activity and wrap it with `activity_tool`: <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py -->

```python
from datetime import timedelta
from temporalio import activity
from temporalio.common import RetryPolicy
from temporalio.contrib.google_adk_agents.workflow import activity_tool

@activity.defn
async def get_weather(city: str) -> str:
    ...

weather_tool = activity_tool(
    get_weather,
    start_to_close_timeout=timedelta(seconds=30),
    retry_policy=RetryPolicy(maximum_attempts=3),
)
```

`activity_tool` preserves the wrapped function's `__name__`, `__doc__`, and `__signature__` so ADK's tool-schema generation still works. Outside a workflow (e.g. during local `adk run`/`adk web`) it invokes the activity function directly; inside a workflow it dispatches via `workflow.execute_activity`. <!-- sdk-python: temporalio/contrib/google_adk_agents/workflow.py -->

## Putting it together: agent inside a workflow

```python
from google.adk.agents import Agent
from google.adk.runners import InMemoryRunner

from temporalio import workflow
from temporalio.contrib.google_adk_agents import TemporalModel
from temporalio.contrib.google_adk_agents.workflow import activity_tool

# `weather_tool` and the model are constructed at import time
# (outside the workflow class) just like a normal ADK agent.

agent = Agent(
    name="weather_agent",
    model=TemporalModel("gemini-2.5-pro"),
    tools=[weather_tool],
)

@workflow.defn
class WeatherAgentWorkflow:
    @workflow.run
    async def run(self, user_message: str) -> str:
        runner = InMemoryRunner(agent=agent, app_name="weather_app")
        # ... drive the runner; final response is the workflow result.
```

Worker / start side is the standard `Client.connect(..., plugins=[GoogleAdkPlugin()])` followed by `client.execute_workflow(WeatherAgentWorkflow.run, ...)`. <!-- adk.dev: integrations/temporal -->

## MCP tools

For MCP toolsets, use the provider/toolset pair. The factory is called both to register Activities with the worker (via the plugin) and as a local fallback when the agent runs outside a workflow. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py -->

`TemporalMcpToolSetProvider(name, toolset_factory)` — the factory returns a `google.adk` `McpToolset`. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py -->

`TemporalMcpToolSet(name, config=None, factory_argument=None, not_in_workflow_toolset=None)` — `name` must match the provider's `name`. `config` is an `ActivityConfig` for the tool's activity. `not_in_workflow_toolset` is the local-fallback factory used when the agent runs outside a workflow. <!-- sdk-python: temporalio/contrib/google_adk_agents/_mcp.py -->

```python
from google.adk.tools.mcp_tool import McpToolset
from temporalio.client import Client
from temporalio.contrib.google_adk_agents import (
    GoogleAdkPlugin,
    TemporalMcpToolSet,
    TemporalMcpToolSetProvider,
)

def toolset_factory(_):
    return McpToolset(...)  # construct your MCP toolset

provider = TemporalMcpToolSetProvider("fs-tools", toolset_factory)

client = await Client.connect(
    "localhost:7233",
    plugins=[GoogleAdkPlugin(toolset_providers=[provider])],
)

agent = Agent(
    name="fs_agent",
    model=TemporalModel("gemini-2.5-pro"),
    tools=[TemporalMcpToolSet("fs-tools", not_in_workflow_toolset=toolset_factory)],
)
```

## Determinism shims

Inside workflow context only, the plugin replaces: <!-- sdk-python: temporalio/contrib/google_adk_agents/_plugin.py -->

- `time.time()` with `workflow.now()`
- `uuid.uuid4()` with `workflow.uuid4()`

Outside a workflow (local `adk run`, `adk web`, or plain Python), the standard implementations run unchanged. This is what makes the same agent definition usable both in production-as-workflow and in local development.

## Local development

The wrappers are intentionally pass-through outside of workflows:

- `TemporalModel.generate_content` calls the underlying ADK model directly if `workflow.in_workflow()` is false.
- `activity_tool` calls the wrapped activity function directly.
- `TemporalMcpToolSet` falls back to whatever `not_in_workflow_toolset` returns.

So you can iterate on the agent with `adk run`/`adk web` against the same code, then move it under a workflow for durability. <!-- adk.dev: integrations/temporal -->

## Common mistakes

- **Importing `activity_tool` from the wrong place.** It is at `temporalio.contrib.google_adk_agents.workflow`, not at the package root. The package root exports only the four classes above.
- **Passing `model=` to `TemporalModel`.** It's positional (`model_name`). `TemporalModel("gemini-2.5-pro")`, not `TemporalModel(model="gemini-2.5-pro")`.
- **Setting `data_converter=pydantic_data_converter` manually.** `GoogleAdkPlugin` already configures the Pydantic converter — doing it again can override or conflict.
- **Forgetting `not_in_workflow_toolset`.** Without it, `TemporalMcpToolSet` has no way to construct the underlying toolset when invoked outside a workflow, breaking local development.
- **Using `Agent`/`InMemoryRunner` from anywhere other than `google.adk`.** They are upstream Google ADK classes — the integration does not re-export them.
- **Treating the API as stable.** It is experimental; pin the SDK version and re-check the upstream README before upgrading.

## Related

- General Python LLM patterns (Pydantic data converter, generic LLM activity, tool-calling loop): `references/python/ai-patterns.md`. The patterns there describe building agent loops by hand; `temporalio.contrib.google_adk_agents` is the framework-integrated alternative when the agent is defined with Google ADK.
- Core AI patterns: `references/core/ai-patterns.md`.
- The catalog row and other Python integrations: `references/integrations.md`.
