# OpenAI Agents SDK — SandboxAgent Integration

## Overview

The `temporalio.contrib.openai_agents` plugin can route `SandboxAgent` lifecycle and I/O operations through durable Temporal activities.  Every sandbox operation — creating a session, running commands, reading/writing files, PTY interactions — is dispatched as a Temporal activity, so sandbox work is observable, retryable, and recoverable, and session state survives worker restarts.

> [!NOTE]
> This feature is Pre-release. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a Pre-release feature.

The Python SDK exposes integrations via the Plugin system; pass `OpenAIAgentsPlugin(...)` to `Client.connect(..., plugins=[...])`.  For general Temporal AI/LLM patterns (retries, timeouts, multi-agent orchestration) see `references/core/ai-patterns.md` and `references/python/ai-patterns.md`.

**`SandboxAgent` (OpenAI Agents SDK) is unrelated to `SandboxedWorkflowRunner` / `SandboxRestrictions` (Temporal's workflow-code sandbox).** `SandboxAgent` runs LLM-driven code inside a separate compute sandbox (Daytona, Docker, E2B, local Unix); the Temporal workflow sandbox restricts module imports inside workflow code.  Don't mix them.

## Worker configuration

Register one or more `SandboxClientProvider(name, client_instance)` instances on `OpenAIAgentsPlugin(sandbox_clients=[...])`.  Each provider's `name` becomes the prefix for that backend's Temporal activities, so multiple backends can coexist on a single worker.

```python
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

worker = Worker(client, task_queue="my-task-queue", workflows=[MyWorkflow])
await worker.run()
```

- Provider names must be unique.
- The plugin auto-registers all required sandbox activities on the worker — you do not list them under `Worker(..., activities=[...])`.

## Workflow usage

Inside a `@workflow.defn` class, obtain a reference to a registered backend with `temporal_sandbox_client(name)` from `temporalio.contrib.openai_agents.workflow`, and pass it to `SandboxRunConfig(client=...)` nested inside `RunConfig(sandbox=...)`.

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

- The name passed to `temporal_sandbox_client(...)` must exactly match the name used in `SandboxClientProvider` on the worker.
- `SandboxAgent`, `SandboxRunConfig` import from `agents.sandbox`; `RunConfig` from `agents.run`.

## Activity routing

The workflow-side `TemporalSandboxClient` returned by `temporal_sandbox_client(name)` produces a `TemporalSandboxSession` that routes each sandbox call as a Temporal activity.  Activity names are prefixed by the registered provider name, for example:

- `"{name}-sandbox_session_exec"`
- `"{name}-sandbox_session_read"`
- `"{name}-sandbox_session_write"`
- plus PTY-interaction activities.

The `SandboxClientProvider` activities on the worker invoke the underlying real sandbox client (Daytona, Unix-local, etc.).

## Multiple backends in one workflow

A single workflow can target different registered backends by name — register all of them on the worker and reference each by name in the workflow.

```python
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("daytona"),
        options=DaytonaSandboxClientOptions(pause_on_exit=False),
    )),
)

result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("local"),
        options=UnixLocalSandboxClientOptions(),
    )),
)
```

## Constraints

- **`LocalShellTool` and `ComputerTool` are not supported in this integration.** Use `FunctionTool` (or the sandbox session API the agent already has via `SandboxAgent`) for shell-like work.
- **Realtime agents are not supported.**
- **`SQLiteSession` is not supported** as session storage in this distributed setting.

## Common mistakes

- **Calling `Runner.run` outside a `@workflow.defn` method.** The sandbox routing only takes effect when the call is inside a workflow run method; `temporal_sandbox_client(name)` is a workflow-side helper.
- **Mismatched names.** If `temporal_sandbox_client("daytona")` is called but no `SandboxClientProvider("daytona", ...)` is registered on the worker, the call cannot resolve to a backend.
- **Re-registering the same name twice.** Provider names must be unique on a given worker.
- **Treating `SandboxAgent` and `SandboxedWorkflowRunner` as the same thing.** They share the word "sandbox" but are unrelated.
- **Inventing client-options fields.** Only `DaytonaSandboxClientOptions(pause_on_exit=False)` and `UnixLocalSandboxClientOptions()` (bare) appear in the README; other fields are unverified.
