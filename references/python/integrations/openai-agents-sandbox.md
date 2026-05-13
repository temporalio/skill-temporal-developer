# OpenAI Agents Sandbox Integration (Python, Pre-release)

⚠️ **Pre-release** - This functionality is subject to change prior to General Availability.

## Overview

The sandbox integration lets `SandboxAgent` from the OpenAI Agents SDK execute inside a remote or local sandbox (Daytona, Docker, E2B, local Unix, etc.) while keeping all coordination durable in Temporal.  Every sandbox operation — creating a session, running commands, reading/writing files, PTY interactions — is dispatched as a Temporal activity, so sandbox work is fully observable, retryable, and recoverable like any other activity, and sandbox session state is serialized with the workflow so it survives worker restarts.

This is a feature of the broader `OpenAIAgentsPlugin` shipped by Temporal's Python SDK; see the contrib README for the full integration and the [plugins guide](../../../../documentation/docs/develop/plugins-guide.mdx) for plugin concepts.  The OpenAI Agents SDK row in the Python integrations catalog points at the same README.

**Disambiguation.** `SandboxAgent` (OpenAI Agents SDK, an *external compute sandbox* such as Daytona/Docker/E2B/local Unix) is unrelated to `SandboxedWorkflowRunner` (Temporal Python SDK, a *workflow-determinism sandbox*). Workflow code that uses `SandboxAgent` still runs inside `SandboxedWorkflowRunner`; the two concepts compose. See [`docs/develop/python/best-practices/python-sdk-sandbox.mdx`](../../../../documentation/docs/develop/python/best-practices/python-sdk-sandbox.mdx) and [`references/python/determinism-protection.md`](../determinism-protection.md) for the workflow sandbox.

## Architecture

Routing flow, reproduced from the README's diagram:

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

In short: workflow code obtains a `TemporalSandboxClient` from `temporal_sandbox_client(name)`, hands it to `SandboxAgent.run` via `SandboxRunConfig`, and each session operation becomes a Temporal activity routed by name to the matching `SandboxClientProvider` on the worker.

## Worker Configuration

Register one or more `SandboxClientProvider` instances with the plugin. Each provider pairs a unique name with a real `BaseSandboxClient` implementation. The plugin automatically registers all required activities on the worker.

```python
import asyncio
import docker
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.openai_agents import OpenAIAgentsPlugin, SandboxClientProvider, ModelActivityParameters
from agents.extensions.sandbox.daytona import DaytonaSandboxClient
from agents.extensions.sandbox.unix_local import UnixLocalSandboxClient

async def main():
    client = await Client.connect(
        "localhost:7233",
        plugins=[
            OpenAIAgentsPlugin(
                model_params=ModelActivityParameters(
                    start_to_close_timeout=timedelta(seconds=30)
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

Key points:

- `SandboxClientProvider(name, client)` pairs a unique string name with a `BaseSandboxClient`.
- Provider names must be unique; each name becomes the prefix for that backend's activities, allowing multiple backends to coexist on a single worker.
- `SandboxClientProvider` is imported from `temporalio.contrib.openai_agents` alongside `OpenAIAgentsPlugin` and `ModelActivityParameters`.
- Concrete sandbox clients shown in the README are `DaytonaSandboxClient` (from `agents.extensions.sandbox.daytona`) and `UnixLocalSandboxClient` (from `agents.extensions.sandbox.unix_local`).   Other backends mentioned in prose (Docker, E2B) are not given import paths in the README.

## Workflow Usage

In the workflow, use `temporal_sandbox_client()` to create a reference to a registered backend by name. Pass it to `SandboxRunConfig` inside `RunConfig`:

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

Key points:

- `temporal_sandbox_client` is imported from `temporalio.contrib.openai_agents.workflow` (the workflow-side module), not from `temporalio.contrib.openai_agents`.
- `SandboxAgent` and `SandboxRunConfig` are imported from `agents.sandbox` — they belong to the OpenAI Agents SDK, not to Temporal.
- `RunConfig` is imported from `agents.run`.
- The name passed to `temporal_sandbox_client()` must exactly match the name used in `SandboxClientProvider` on the worker.
- `options=` accepts backend-specific option objects such as `DaytonaSandboxClientOptions(pause_on_exit=False)` and `UnixLocalSandboxClientOptions()` (see Multiple Backends).

## Multiple Backends

A single workflow can target different backends by name. Register all backends on the worker and reference each by name in the workflow:

```python
# Run a task on the "daytona" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("daytona"),
        options=DaytonaSandboxClientOptions(pause_on_exit=False),
    )),
)

# Run a different task on the "local" backend
result = await Runner.run(
    agent, prompt,
    run_config=RunConfig(sandbox=SandboxRunConfig(
        client=temporal_sandbox_client("local"),
        options=UnixLocalSandboxClientOptions(),
    )),
)
```

## Activity Naming

Sandbox operations are dispatched as activities whose names follow the pattern:

```text
{sandbox_name}-sandbox_session_{operation}
```

`{sandbox_name}` is the string registered with `SandboxClientProvider(name, …)`; `{operation}` is the session operation being performed. Concrete examples shown in the README's architecture diagram:

- `daytona-sandbox_session_exec`
- `daytona-sandbox_session_read`

The README prose also mentions session creation, command execution, file read/write, and PTY interactions as sandbox operations dispatched as activities, but does not enumerate the exact operation tokens for create/write/PTY.

Because the activity prefix is the provider name, multiple backends produce non-colliding activity names on the same worker.

## Interaction with the Python Workflow Sandbox

Workflow code that uses `SandboxAgent` still runs inside Temporal's workflow-determinism sandbox (`SandboxedWorkflowRunner`), which is an unrelated layer that restricts non-deterministic module access.  Plugins extend the workflow sandbox via a `workflow_runner` hook that adds passthrough modules as needed, and the `OpenAIAgentsPlugin` is the canonical Python plugin example.

For background on the workflow sandbox itself, see:

- [`references/python/determinism-protection.md`](../determinism-protection.md)
- [`docs/develop/python/best-practices/python-sdk-sandbox.mdx`](../../../../documentation/docs/develop/python/best-practices/python-sdk-sandbox.mdx)

## Common Mistakes

- **Confusing `SandboxAgent` with `SandboxedWorkflowRunner`.** They share only the word "sandbox". `SandboxAgent` is from the OpenAI Agents SDK and runs in an external compute sandbox (Daytona, Docker, E2B, local Unix); `SandboxedWorkflowRunner` is Temporal's workflow-determinism sandbox.
- **Mismatched provider name between worker and workflow.** The string in `SandboxClientProvider(name, …)` on the worker MUST exactly match the string in `temporal_sandbox_client(name)` in the workflow. A mismatch leaves the sandbox activities unrouted. This constraint is load-bearing.
- **Importing `temporal_sandbox_client` from the wrong module.** It lives in `temporalio.contrib.openai_agents.workflow`, not in `temporalio.contrib.openai_agents`.
- **Importing `SandboxAgent` or `SandboxRunConfig` from Temporal.** These are OpenAI Agents SDK types, imported from `agents.sandbox`.
- **Forgetting the Pre-release status when planning production rollout.** The README explicitly flags this functionality as subject to change prior to General Availability.

## Related References

- [Contrib README — OpenAI Agents SDK Integration for Temporal](https://github.com/temporalio/sdk-python/blob/main/temporalio/contrib/openai_agents/README.md) — canonical source for this feature.
- [`references/python/ai-patterns.md`](../ai-patterns.md) — general OpenAI/LLM patterns in Temporal workflows.
- [`references/python/determinism-protection.md`](../determinism-protection.md) — the *workflow* sandbox (`SandboxedWorkflowRunner`); distinct from `SandboxAgent`.
- [`docs/develop/plugins-guide.mdx`](../../../../documentation/docs/develop/plugins-guide.mdx) — the broader plugin system that hosts `OpenAIAgentsPlugin`.
