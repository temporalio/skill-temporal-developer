# OpenAI Agents Sandbox Support (`temporalio.contrib.openai_agents`)

> ⚠️ **Pre-release** — This functionality is subject to change prior to General Availability. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Sandbox Support -->

## Disambiguation: this is not the Python SDK workflow sandbox

`SandboxAgent` <!-- upstream: openai-agents-python (via sdk-python README §Sandbox Support) --> is a class from the **OpenAI Agents Python SDK** that runs an agent inside a remote or local execution sandbox (Daytona, Docker, E2B, local Unix). It is **not** the Temporal Python SDK's workflow sandbox. The workflow sandbox is a distinct concept — `SandboxedWorkflowRunner` and `SandboxRestrictions` <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx --> — which isolates Workflow code from non-deterministic library calls. The two share the word "sandbox" and nothing else: this reference is about routing OpenAI Agents sandbox session operations through durable Temporal activities; for the workflow runner, see `docs/develop/python/best-practices/python-sdk-sandbox.mdx`.

<!-- Sources: docs/develop/python/best-practices/python-sdk-sandbox.mdx, sdk-python/temporalio/contrib/openai_agents/README.md §Sandbox Support -->

## What this is

The sandbox integration lets `SandboxAgent` from the OpenAI Agents SDK execute inside a remote or local sandbox (Daytona, Docker, E2B, local Unix, etc.) while keeping all coordination durable in Temporal. Every sandbox operation — creating a session, running commands, reading/writing files, PTY interactions — is dispatched as a Temporal activity, so sandbox work is observable, retryable, and recoverable like any other activity, and sandbox session state is serialized with the workflow so it survives worker restarts. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Sandbox Support -->

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md §Sandbox Support intro -->

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

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md §Architecture (transcribed verbatim) -->

## Worker configuration

Register one or more `SandboxClientProvider` <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration --> instances with the plugin. Each provider pairs a unique name with a real `BaseSandboxClient` implementation <!-- VERIFY: README describes the second argument as a `BaseSandboxClient` implementation in prose, but does not show an explicit type signature — only example usage with `DaytonaSandboxClient()` and `UnixLocalSandboxClient()` -->. The plugin automatically registers all required activities on the worker.

```python
import asyncio
import docker
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.openai_agents import OpenAIAgentsPlugin, SandboxClientProvider, ModelActivityParameters
# OpenAIAgentsPlugin            <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration -->
# SandboxClientProvider         <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration -->
# ModelActivityParameters       <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration -->
from agents.extensions.sandbox.daytona import DaytonaSandboxClient
# DaytonaSandboxClient          <!-- upstream: openai-agents-python (via sdk-python README §Worker Configuration import line) -->
from agents.extensions.sandbox.unix_local import UnixLocalSandboxClient
# UnixLocalSandboxClient        <!-- upstream: openai-agents-python (via sdk-python README §Worker Configuration import line) -->

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

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration (code block transcribed verbatim) -->

## Workflow usage

In the workflow, use `temporal_sandbox_client()` <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage --> to create a reference to a registered backend by name. Pass it to `SandboxRunConfig` inside `RunConfig`:

```python
from temporalio import workflow
from temporalio.contrib.openai_agents.workflow import temporal_sandbox_client
# temporal_sandbox_client       <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage -->
from agents import Runner
# Runner                        <!-- upstream: openai-agents-python (via sdk-python README §Workflow Usage import line) -->
from agents.sandbox import SandboxAgent, SandboxRunConfig
# SandboxAgent                  <!-- upstream: openai-agents-python (via sdk-python README §Workflow Usage import line) -->
# SandboxRunConfig              <!-- upstream: openai-agents-python (via sdk-python README §Workflow Usage import line) -->
from agents.run import RunConfig
# RunConfig                     <!-- upstream: openai-agents-python (via sdk-python README §Workflow Usage import line) -->

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

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage (code block transcribed verbatim) -->

## Multiple backends

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

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md §Multiple Backends (code block transcribed verbatim) -->

## Provider name rule

Provider names must be unique. The name passed to `temporal_sandbox_client()` on the workflow side **must exactly match** the name passed to `SandboxClientProvider(...)` on the worker side. That name then becomes the prefix for every activity that backend's sessions dispatch — for example `"daytona-sandbox_session_exec"`, `"daytona-sandbox_session_read"`, `"daytona-sandbox_session_write"`, and so on. This is what lets multiple backends coexist on a single worker without colliding. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration & §Workflow Usage & §Architecture -->

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md (provider-name uniqueness, name-matching rule, activity-name prefix pattern) -->

## Gotchas / open questions

Anti-patterns to avoid (each maps to a regression the upstream README's wording clearly excludes):

- **Wrong module path.** Do not write `from temporalio.contrib.openai import …`. The correct module is `temporalio.contrib.openai_agents` (plural with underscore). <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Worker Configuration -->
- **Wrong workflow-side module.** Do not write `from temporalio.contrib.openai_agents import temporal_sandbox_client`. The helper lives in the `.workflow` submodule: `from temporalio.contrib.openai_agents.workflow import temporal_sandbox_client`. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage -->
- **Wrong `SandboxAgent` import.** Do not write `from agents import SandboxAgent`. The README imports it from the `agents.sandbox` submodule: `from agents.sandbox import SandboxAgent, SandboxRunConfig`. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage -->
- **Do not instantiate `TemporalSandboxClient(...)` in user code.** The README mentions `TemporalSandboxClient` only in the architecture prose as the type returned by the `temporal_sandbox_client("name")` factory; user code never constructs it directly. Always call the `temporal_sandbox_client("name")` callable. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Architecture & §Workflow Usage -->
- **Do not invent a `create_workflow_agent(...)` entry point.** Some older notes reference such a function; the README's only workflow-side helper for the sandbox integration is `temporal_sandbox_client()`, used together with `SandboxAgent` and `Runner.run(...)`. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Workflow Usage -->
- **Do not enumerate PTY-specific activity suffixes.** The README lists only `sandbox_session_exec`, `sandbox_session_read`, `sandbox_session_write` as concrete activity names, and refers to "PTY interactions" only in prose. Do not invent names like `sandbox_session_pty_resize` or `sandbox_session_kill`. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Architecture -->
- **Do not soften or omit the pre-release banner.** The README marks this functionality as pre-release and subject to change prior to General Availability; reproduce that warning when documenting it. <!-- upstream: sdk-python/temporalio/contrib/openai_agents/README.md §Sandbox Support -->
- **Do not conflate with the workflow sandbox.** `SandboxAgent` (OpenAI Agents SDK) is distinct from `SandboxedWorkflowRunner` / `SandboxRestrictions` (Temporal Python SDK). They share the word "sandbox" only. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx -->

Open questions raised during authoring (each warrants a follow-up against the upstream module before depending on the claim):

- <!-- VERIFY: type signature of `SandboxClientProvider`'s second argument — README describes it as a `BaseSandboxClient` implementation in prose ("Each provider pairs a unique name with a real `BaseSandboxClient` implementation") but does not show an explicit type annotation or class import for `BaseSandboxClient`. -->
- <!-- VERIFY: optional arguments of `temporal_sandbox_client()` beyond the single positional `name` — README's examples only show the one-positional-arg form `temporal_sandbox_client("daytona")`. -->
- <!-- VERIFY: full enumeration of sandbox session operations beyond `exec`, `read`, `write` — README mentions "PTY interactions" in prose but does not list activity-name suffixes for them. -->
- <!-- VERIFY: install/extras requirement — README does not specify whether a `pip install` extras line (for example to pull in the `agents.extensions.sandbox.daytona` / `.unix_local` backends, or the `agents.sandbox` import) is required, nor what its exact name would be. -->

<!-- Sources: sdk-python/temporalio/contrib/openai_agents/README.md (anti-patterns derived from the README's explicit naming and module paths); docs/develop/python/best-practices/python-sdk-sandbox.mdx (disambiguation reference) -->

## See also

- [`references/python/ai-patterns.md`](./ai-patterns.md) — broader OpenAI Agents integration overview within this skill. **Note:** that file's OpenAI Agents section references `temporalio.contrib.openai` and `create_workflow_agent`, which do not match the upstream module; the actual module is `temporalio.contrib.openai_agents` and the sandbox helper is `temporal_sandbox_client()` (see this file). Treat that section as out-of-date for sandbox content.
- [`docs/develop/python/best-practices/python-sdk-sandbox.mdx`](../../../documentation/docs/develop/python/best-practices/python-sdk-sandbox.mdx) — the **different** sandbox: the Python SDK's `SandboxedWorkflowRunner` / `SandboxRestrictions` for Workflow code isolation.
- [`docs/develop/plugins-guide.mdx`](../../../documentation/docs/develop/plugins-guide.mdx) — Plugin system that `OpenAIAgentsPlugin` is built on (see lines 44 and 228 for pointers to the upstream implementation).
- [`docs/develop/python/integrations/index.mdx:27`](../../../documentation/docs/develop/python/integrations/index.mdx) — Python integrations table row listing "OpenAI Agents SDK" and linking to the upstream guide.
- Upstream README: <https://github.com/temporalio/sdk-python/blob/main/temporalio/contrib/openai_agents/README.md> — authoritative source for every Temporal-side symbol on this page.
