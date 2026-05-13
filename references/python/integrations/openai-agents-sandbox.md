# OpenAI Agents SDK — Sandbox Support (Python)

> ⚠️ **Pre-release.** Sandbox Support is part of the `temporalio.contrib.openai_agents` integration and is "subject to change prior to General Availability." <!-- openai_agents/README.md §Sandbox Support -->

## What this covers

The Python `temporalio.contrib.openai_agents` integration lets `SandboxAgent` (from the OpenAI Agents SDK) execute inside a remote or local sandbox — Daytona, Docker, E2B, or a local Unix shell — while every sandbox operation is dispatched through a Temporal activity. The result: sandbox sessions are observable, retryable, and survive worker restarts. <!-- openai_agents/README.md §Sandbox Support -->

This reference covers only the sandbox feature. For the broader OpenAI Agents SDK integration (durable agents, tool calling, MCP, streaming, OTEL), see `references/python/ai-patterns.md` and the upstream README at `temporalio/sdk-python:temporalio/contrib/openai_agents/README.md`.

## Mental model

```text
Workflow code
  │
  ▼  temporal_sandbox_client("daytona")        ← returns TemporalSandboxClient
  │
  ▼  SandboxAgent.run(run_config=RunConfig(
  │     sandbox=SandboxRunConfig(client=...)))
  │
  ▼  session.exec / session.read / session.write / PTY …
  │
  ▼  TemporalSandboxSession routes each call as a Temporal activity
  │   (e.g. "daytona-sandbox_session_exec", "daytona-sandbox_session_read")
  │
  ▼  SandboxClientProvider activities on the worker
  │
  ▼  Real sandbox backend (Daytona, Docker, local, …)
```
<!-- openai_agents/README.md §Sandbox Support / Architecture -->

The boundary that matters: the **workflow** holds a `TemporalSandboxClient` keyed by a registered name; the **worker** holds the real `BaseSandboxClient` implementation. Every session operation crosses that boundary as an activity, which is why session state can be replayed and recovered. <!-- openai_agents/README.md §Sandbox Support -->

## Worker configuration

Register one or more `SandboxClientProvider` instances on `OpenAIAgentsPlugin`. The plugin registers all required activities on the worker automatically. <!-- openai_agents/README.md §Sandbox Support / Worker Configuration -->

```python
import asyncio
from datetime import timedelta

from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.openai_agents import (
    OpenAIAgentsPlugin,
    SandboxClientProvider,
    ModelActivityParameters,
)
from agents.extensions.sandbox.daytona import DaytonaSandboxClient
from agents.extensions.sandbox.unix_local import UnixLocalSandboxClient


async def main():
    client = await Client.connect(
        "localhost:7233",
        plugins=[
            OpenAIAgentsPlugin(
                model_params=ModelActivityParameters(
                    start_to_close_timeout=timedelta(seconds=30),
                ),
                sandbox_clients=[
                    SandboxClientProvider("daytona", DaytonaSandboxClient()),
                    SandboxClientProvider("local", UnixLocalSandboxClient()),
                ],
            ),
        ],
    )

    worker = Worker(
        client,
        task_queue="my-task-queue",
        workflows=[MyWorkflow],
    )
    await worker.run()
```
<!-- openai_agents/README.md §Sandbox Support / Worker Configuration -->

Two rules pinned by the README:

- **Provider names must be unique.** Each name becomes the prefix for that backend's activities, which is what allows multiple backends to coexist on a single worker. <!-- openai_agents/README.md §Sandbox Support / Worker Configuration -->
- **Register sandbox clients on the plugin, not on `Worker(...)`.** The plugin is what wires the activities. <!-- openai_agents/README.md §Sandbox Support / Worker Configuration -->

## Workflow usage

Inside the workflow, get a backend handle by **name** with `temporal_sandbox_client()`, then hand it to `SandboxRunConfig` inside `RunConfig`. <!-- openai_agents/README.md §Sandbox Support / Workflow Usage -->

```python
from temporalio import workflow
from temporalio.contrib.openai_agents.workflow import temporal_sandbox_client
from agents import Runner
from agents.sandbox import SandboxAgent, SandboxRunConfig
from agents.run import RunConfig


@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, prompt: str) -> str:
        agent = SandboxAgent(
            name="Coding Assistant",
            instructions="You are a helpful coding assistant with access to a sandbox.",
        )

        result = await Runner.run(
            agent,
            prompt,
            run_config=RunConfig(
                sandbox=SandboxRunConfig(
                    client=temporal_sandbox_client("daytona"),
                    options=DaytonaSandboxClientOptions(pause_on_exit=False),
                ),
            ),
        )
        return result.final_output
```
<!-- openai_agents/README.md §Sandbox Support / Workflow Usage -->

The name passed to `temporal_sandbox_client()` must **exactly match** the name registered in `SandboxClientProvider` on the worker. A mismatch fails at activity-dispatch time, not at workflow start. <!-- openai_agents/README.md §Sandbox Support / Workflow Usage -->

## Multiple backends in one workflow

A single workflow can target different backends by name — register all backends on the worker, reference each by name in the workflow: <!-- openai_agents/README.md §Sandbox Support / Multiple Backends -->

```python
# Run on the "daytona" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("daytona"),
        options=DaytonaSandboxClientOptions(pause_on_exit=False),
    )),
)

# Run on the "local" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("local"),
        options=UnixLocalSandboxClientOptions(),
    )),
)
```
<!-- openai_agents/README.md §Sandbox Support / Multiple Backends -->

## Common mistakes

| Wrong | Right | Why |
|---|---|---|
| `temporal_sandbox_client(DaytonaSandboxClient())` | `temporal_sandbox_client("daytona")` | Workflows reference backends by **registered name**, not by client object. |
| Passing `sandbox_clients=[...]` to `Worker(...)` | Passing it to `OpenAIAgentsPlugin(...)` | The plugin registers the dispatching activities; `Worker` does not. |
| `Agent(...)` for sandbox runs | `SandboxAgent(...)` | Only `SandboxAgent` carries the session-operation surface that routes through activities. |
| `Runner.run(agent, prompt, client=...)` | `Runner.run(agent, prompt, run_config=RunConfig(sandbox=SandboxRunConfig(client=..., options=...)))` | The client is part of `SandboxRunConfig`, which lives on `RunConfig`. |
| Two providers with the same name | Each provider needs a unique name | The name is the activity prefix; collisions ambiguate dispatch. |

<!-- All rows above corroborated by openai_agents/README.md §Sandbox Support / Worker Configuration & Workflow Usage. -->

## What is *not* documented here

These are intentionally absent because the upstream README does not enumerate them — do not infer them:

- The full list of `*-sandbox_session_*` activity names. The README shows two examples (`daytona-sandbox_session_exec`, `daytona-sandbox_session_read`); the rest are not enumerated. <!-- openai_agents/README.md §Sandbox Support / Architecture -->
- The fields on `DaytonaSandboxClientOptions` / `UnixLocalSandboxClientOptions` beyond `pause_on_exit=False` shown in the README example. <!-- openai_agents/README.md §Sandbox Support / Workflow Usage, Multiple Backends -->
- Client class names for Docker / E2B. The README mentions these as supported backends in prose but does not show class names. <!-- openai_agents/README.md §Sandbox Support intro -->
- Retry policy / timeout defaults for the sandbox activities. The README does not specify them. <!-- VERIFY: are sandbox activity timeouts configurable through `OpenAIAgentsPlugin`? -->

If you need any of these, read the live upstream README at `temporalio/sdk-python:temporalio/contrib/openai_agents/README.md` or the `temporalio.contrib.openai_agents` source.

## Related

- `references/python/ai-patterns.md` — broader OpenAI Agents SDK integration patterns (durable agents, `activity_as_tool`, plugin setup).
- `references/integrations.md` — catalog row for this integration.
- Upstream README: `temporalio/sdk-python:temporalio/contrib/openai_agents/README.md` — authoritative source for `SandboxAgent`, `SandboxClientProvider`, `temporal_sandbox_client`, and the dispatch model.
