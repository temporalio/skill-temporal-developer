# OpenAI Agents SDK: SandboxAgent Integration (Python)

> **Pre-release.** The `sandbox_clients` plugin option and `temporal_sandbox_client()` workflow helper are marked experimental and subject to change.

## What this is

The Temporal Python SDK's `temporalio.contrib.openai_agents` plugin can route every lifecycle and I/O operation of an OpenAI Agents SDK `SandboxAgent` through Temporal activities. `SandboxAgent` is the OpenAI Agents SDK construct that runs agent-generated code inside a remote or local compute sandbox (Daytona, Docker, E2B, local Unix, etc.); the Temporal integration keeps that coordination durable so the agent survives worker restarts and individual sandbox calls are retryable, observable, and recoverable like any other Temporal activity.

This is a layer on top of the broader OpenAI Agents SDK integration — set that up first (see `references/python/ai-patterns.md` and the upstream [README](https://github.com/temporalio/sdk-python/blob/main/temporalio/contrib/openai_agents/README.md) linked from `docs/develop/python/integrations/index.mdx:27`).

**Scope note.** "Sandbox" here means the OpenAI Agents SDK compute sandbox (`agents.sandbox.SandboxAgent`). It is **not** the Temporal Python SDK workflow sandbox (`temporalio.worker.workflow_sandbox.SandboxedWorkflowRunner`) covered in `docs/develop/python/best-practices/python-sdk-sandbox.mdx`. The two are unrelated except that the plugin adds `openai`, `agents`, and `mcp` to the workflow sandbox's passthrough modules so OpenAI Agents code can be imported into a workflow file.

## Architecture

```text
Workflow Code
  ↓
temporal_sandbox_client("daytona")   [returns TemporalSandboxClient]
  ↓
SandboxAgent.run(run_config=RunConfig(sandbox=SandboxRunConfig(client=...)))
  ↓
sandbox agent calls session.exec / session.read / session.write / …
  ↓
TemporalSandboxSession routes each call as a Temporal activity
("daytona-sandbox_session_exec", "daytona-sandbox_session_read", …)
  ↓
SandboxClientProvider activities on the worker call the real sandbox client
  ↓
Actual sandbox backend (Daytona, Docker, local, …)
```

Two halves:

- **Workflow side** — `temporal_sandbox_client(name)` produces a `TemporalSandboxClient` (a stateless `BaseSandboxClient`) and a `TemporalSandboxSession` that translate every method call into `workflow.execute_activity(...)` with an activity name prefixed by `name`.
- **Worker side** — `SandboxClientProvider(name, client)` wraps a real `BaseSandboxClient` (e.g. `DaytonaSandboxClient`, `UnixLocalSandboxClient`) and registers a fixed set of activities under the same `name`-prefixed names. Pass providers in via `OpenAIAgentsPlugin(sandbox_clients=[...])`.

## Worker setup

Register one or more `SandboxClientProvider` instances on the plugin. The plugin auto-registers each provider's activities on the worker.

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

Notes:

- `SandboxClientProvider` and `OpenAIAgentsPlugin` are exported from `temporalio.contrib.openai_agents`.
- `DaytonaSandboxClient` and `UnixLocalSandboxClient` are **not** Temporal classes — they ship with the OpenAI Agents SDK under `agents.extensions.sandbox.*`.
- Provider names must be unique; the plugin raises `ValueError("More than one sandbox client registered with the same name. Please provide unique names.")` if not.
- Each provider name becomes the prefix for that backend's activity names, so multiple backends can coexist on a single worker / task queue.

## Workflow usage

Inside a workflow, build a sandbox client reference with `temporal_sandbox_client(name)` and pass it into `SandboxRunConfig(client=...)` inside `RunConfig`. The `name` must match the `SandboxClientProvider` name registered on the worker exactly.

```python
from temporalio import workflow
from temporalio.contrib.openai_agents.workflow import temporal_sandbox_client
from agents import Runner
from agents.sandbox import SandboxAgent, SandboxRunConfig
from agents.run import RunConfig
from agents.extensions.sandbox.daytona import DaytonaSandboxClientOptions

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

`temporal_sandbox_client(name, config=None)` accepts an optional `ActivityConfig` (the same shape used by `workflow.execute_activity`). When `config` is `None`, the returned `TemporalSandboxClient` defaults to `ActivityConfig(start_to_close_timeout=timedelta(minutes=5))` for every dispatched activity.

### Multiple backends in one workflow

A single workflow can target different backends by name within the same execution, as long as each name is registered on the worker:

```python
# Target the "daytona" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("daytona"),
        options=DaytonaSandboxClientOptions(pause_on_exit=False),
    )),
)

# Target the "local" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("local"),
        options=UnixLocalSandboxClientOptions(),
    )),
)
```

## Activities registered per provider

The plugin registers exactly these activities for each `SandboxClientProvider(name, ...)`. Activity names are formed as `f"{name}-{operation}"`. Two groups: client-level lifecycle and session-level I/O + lifecycle.

Client-level (create/resume/delete a session):

- `{name}-sandbox_client_create`
- `{name}-sandbox_client_resume`
- `{name}-sandbox_client_delete`

Session-level (I/O + lifecycle):

- `{name}-sandbox_session_exec`
- `{name}-sandbox_session_read`
- `{name}-sandbox_session_write`
- `{name}-sandbox_session_running`
- `{name}-sandbox_session_persist_workspace`
- `{name}-sandbox_session_hydrate_workspace`
- `{name}-sandbox_session_pty_exec_start`
- `{name}-sandbox_session_pty_write_stdin`
- `{name}-sandbox_session_start`
- `{name}-sandbox_session_stop`
- `{name}-sandbox_session_shutdown`

Each activity receives a single Pydantic model argument (`ExecArgs`, `ReadArgs`, `WriteArgs`, `PtyExecStartArgs`, etc.) defined in `temporalio/contrib/openai_agents/sandbox/_temporal_activity_models.py`.

## Data converter requirement

Activity arguments and results carry Pydantic models, including binary payloads (stdout/stderr buffers, workspace snapshots, PTY output) wrapped as base64 in JSON via the `JsonSafeBytes` annotation. This relies on the Pydantic data converter being installed on the client.

`OpenAIAgentsPlugin` sets `OpenAIPayloadConverter` (a Pydantic-aware data converter exported from `temporalio.contrib.openai_agents`) by default, so under typical setup you do not need to wire one manually.

## Session state durability

`TemporalSandboxSession` holds only the serializable `SandboxSessionState` plus a `supports_pty` flag — no live connection to the physical sandbox. Workers reconnect via the `*-sandbox_client_resume` activity using the persisted state, so sessions survive worker restarts and the workflow can keep referencing the same `SandboxAgent` across replays.

## Common mistakes

- **Importing `SandboxAgent`, `SandboxRunConfig`, `DaytonaSandboxClient`, or `UnixLocalSandboxClient` from `temporalio.*`.** These are OpenAI Agents SDK types: `SandboxAgent`/`SandboxRunConfig` live under `agents.sandbox`; `DaytonaSandboxClient` lives under `agents.extensions.sandbox.daytona`; `UnixLocalSandboxClient` lives under `agents.extensions.sandbox.unix_local`.
- **Mismatching the provider name between worker and workflow.** The name is used as a literal activity-name prefix; a typo means dispatched activities will never find a handler.
- **Reusing the same provider name across two providers.** `OpenAIAgentsPlugin` validates uniqueness at registration and raises `ValueError`.
- **Assuming a default activity timeout other than 5 minutes.** When `temporal_sandbox_client()` is called without a `config`, the dispatched activities use `start_to_close_timeout=timedelta(minutes=5)`. Override via the `config` parameter if sandbox operations may take longer (e.g. snapshot persist/hydrate of large workspaces).
- **Treating `sandbox_clients` as stable.** It is pre-release in both the README and the public docstring on `OpenAIAgentsPlugin`.
- **Conflating with the Python workflow sandbox.** Workflow-sandbox passthroughs (`workflow.unsafe.imports_passed_through()`, `SandboxRestrictions.with_passthrough_modules(...)`) protect determinism of workflow imports and are documented in `docs/develop/python/best-practices/python-sdk-sandbox.mdx`. The compute-sandbox integration described here is unrelated; the only intersection is that the plugin pre-passes `openai`, `agents`, and `mcp` through the workflow sandbox so the imports above work inside a `@workflow.defn` file.

## Related references

- `references/python/ai-patterns.md` — broader OpenAI Agents SDK + Temporal patterns.
- `references/core/ai-patterns.md` — language-agnostic AI patterns.
- `docs/develop/plugins-guide.mdx` — general plugin model the integration is built on.
- Upstream: [`temporalio/contrib/openai_agents/README.md`](https://github.com/temporalio/sdk-python/blob/main/temporalio/contrib/openai_agents/README.md) — authoritative reference (linked from `docs/develop/python/integrations/index.mdx:27`).
