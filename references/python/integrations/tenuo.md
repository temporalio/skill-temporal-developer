# Temporal Tenuo Integration (Python)

## Overview

[Tenuo](https://tenuo.ai/temporal) is a warrant-based authorization layer for AI agent code. The `TenuoTemporalPlugin` adds task-scoped authorization to Temporal: a signed warrant travels with each Workflow, and the plugin's worker interceptor verifies the warrant before every Activity runs.  Agents are constrained by design — an Activity only executes if the warrant permits it, and every action is cryptographically attributable to the entity that authorized it.

The plugin ships in the `tenuo` package under `tenuo.temporal` (not in `temporalio.contrib`).

For Temporal Python SDK setup (Client/Worker, `@workflow.defn`, `@activity.defn`), read `references/python/python.md` first.

## Prerequisites

- Python 3.10+, inherited from `temporalio>=1.23.0`.
- A running Temporal cluster (local `temporal server start-dev` or Temporal Cloud).
- Familiarity with Temporal Workflows, Activities, and Workers.

## Install

```bash
uv pip install "tenuo[temporal]"
```

This pulls in `temporalio>=1.23.0` and `tenuo_core` (a compiled extension with prebuilt wheels).

## Register the Plugin

Register `TenuoTemporalPlugin` on the Temporal `Client`. The Client and Worker share the Client connection, so registering the plugin on the Client is what wires the worker-side interceptor in.

```python
from temporalio.client import Client
from temporalio.worker import Worker
from tenuo import SigningKey
from tenuo.temporal import TenuoTemporalPlugin, TenuoPluginConfig, EnvKeyResolver

# For local development — generate a key pair:
control_key = SigningKey.generate()
issuer_public_key = control_key.public_key

plugin = TenuoTemporalPlugin(
    TenuoPluginConfig(
        key_resolver=EnvKeyResolver(),
        trusted_roots=[issuer_public_key],
    )
)

client = await Client.connect("localhost:7233", plugins=[plugin])
worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    activities=[read_file, write_file],
)
```

### `TenuoPluginConfig` fields

| Field | Purpose |
|---|---|
| `trusted_roots` | Public keys of warrant issuers. The plugin only accepts warrants chained to a root in this list. |
| `key_resolver` | How the worker fetches holder signing keys. Built-in resolvers: `EnvKeyResolver`, `VaultKeyResolver`, `AWSSecretsManagerKeyResolver`. |

### Signing keys via `EnvKeyResolver`

`EnvKeyResolver` reads holder signing keys from environment variables named `TENUO_KEY_<key_id>`, with the key bytes base64- or hex-encoded.

```bash
export TENUO_KEY_agent1=$(python -c "from tenuo import SigningKey; import base64; k=SigningKey.generate(); print(base64.b64encode(k.secret_key_bytes()).decode())")
```

`TENUO_KEY_agent1` registers a key under the id `"agent1"`; pass that id as `key_id=` to `execute_workflow_authorized` / `start_workflow_authorized`. Use `VaultKeyResolver` or `AWSSecretsManagerKeyResolver` instead of `EnvKeyResolver` for production key sources.

## Define authorized Activities and Workflows

Activities are **standard `@activity.defn` functions** with no Tenuo imports in the activity body — authorization is enforced by the plugin's interceptor before the function is invoked.

```python
from pathlib import Path
from temporalio import activity, workflow
from datetime import timedelta

@activity.defn
async def read_file(path: str) -> str:
    return Path(path).read_text()

@activity.defn
async def write_file(path: str, content: str) -> str:
    Path(path).write_text(content)
    return f"Wrote {len(content)} bytes"
```

Workflows that need to run authorized Activities **must inherit from `AuthorizedWorkflow`** and call `self.execute_authorized_activity(...)` instead of `workflow.execute_activity(...)`. The base class fails fast on missing warrant headers.

```python
from tenuo.temporal import AuthorizedWorkflow

@workflow.defn
class MyWorkflow(AuthorizedWorkflow):
    @workflow.run
    async def run(self, input_path: str) -> str:
        data = await self.execute_authorized_activity(
            read_file,
            args=[input_path],
            start_to_close_timeout=timedelta(seconds=30),
        )
        return data.upper()
```

## Start an authorized Workflow

Use `execute_workflow_authorized` (returns the result) or `start_workflow_authorized` (returns a handle). Both attach the warrant and `key_id` to the Workflow start, so the worker can verify and sign Activity invocations.

```python
from tenuo.temporal import execute_workflow_authorized

result = await execute_workflow_authorized(
    client=client,
    workflow_run_fn=MyWorkflow.run,
    workflow_id="process-001",
    warrant=warrant,
    key_id="agent1",
    args=["/data/input/report.txt"],
    task_queue="my-queue",
)
```

```python
from tenuo.temporal import start_workflow_authorized

handle = await start_workflow_authorized(
    client=client,
    workflow_run_fn=ApprovalWorkflow.run,
    workflow_id="approval-001",
    warrant=warrant,
    key_id="agent1",
    args=[request_data],
    task_queue="my-queue",
)

# Signal, query, or await later
await handle.signal(ApprovalWorkflow.approve, decision)
result = await handle.result()
```

The handle returned by `start_workflow_authorized` is a standard `temporalio.client.WorkflowHandle`; signals, queries, and `result()` work as they do for any Temporal Workflow.

## Capability constraints

Mint a warrant with `Warrant.mint_builder()`. Each `.capability(name, **constraints)` call declares one tool the holder is permitted to invoke, with per-argument constraint objects bounding the values.

```python
from tenuo import Warrant, SigningKey, Subpath, UrlSafe, Wildcard

warrant = (
    Warrant.mint_builder()
    .holder(agent_key.public_key)
    .capability("read_file", path=Subpath("/data"))       # path must be under /data
    .capability("search", query=Wildcard())               # query can be anything
    .capability("fetch_url",
        url=UrlSafe(allow_schemes=["https"],
                    allow_domains=["api.example.com"],
                    block_private=True),
        timeout=Wildcard(),                               # unconstrained but declared
    )
    .ttl(3600)
    .mint(control_key)
)
```

Constraint types named on the upstream guide: `Subpath`, `Pattern`, `Range`, `UrlSafe`, `Exact`, `Wildcard`.

A `Wildcard()` constraint is unconstrained but **still must be declared** for the capability to permit that argument — undeclared arguments are rejected.

## Child workflow delegation

`tenuo_execute_child_workflow` starts a child Workflow with an **attenuated** warrant — the child receives a strict subset of the parent's capabilities. Capabilities can only narrow, never widen.

```python
from tenuo.temporal import tenuo_execute_child_workflow

@workflow.defn
class ParentWorkflow:
    @workflow.run
    async def run(self) -> str:
        # Parent has read_file + write_file.
        # Child gets only read_file with a shorter TTL.
        return await tenuo_execute_child_workflow(
            ChildWorkflow.run,
            tools=["read_file"],
            ttl_seconds=60,
            args=["/data/input"],
            id=f"child-{workflow.info().workflow_id}",
            task_queue=workflow.info().task_queue,
        )
```

Do **not** re-pass the parent's `warrant=` to the child — delegation happens through the `tools=` and `ttl_seconds=` arguments, which produce a fresh, narrowed warrant for the child.

## Activity summaries in the Temporal Web UI

`tenuo_execute_activity` runs an Activity with a human-readable `summary=` that the plugin attaches to the Event History so it appears in the Temporal Web UI.

```python
from tenuo.temporal import tenuo_execute_activity

await tenuo_execute_activity(
    read_file,
    args=["/data/report.txt"],
    start_to_close_timeout=timedelta(seconds=30),
    summary="monthly sales report",
)
```

## Security

> Fail-closed by default. Missing or invalid warrants block execution.

> Private keys never leave your infrastructure. Only the `key_id` and warrant material travel in Temporal headers.

Proof-of-possession is computed at schedule time (binding the exact tool and args) and verified on the activity worker before execution.

## Common mistakes

- **Plugin only on the Client, not the Worker connection.** Both Client and Worker must share the connection where `TenuoTemporalPlugin` is registered; the worker-side interceptor is what enforces authorization.
- **Plain `@workflow.defn` class running authorized Activities.** Inherit from `AuthorizedWorkflow` and call `self.execute_authorized_activity(...)` — `workflow.execute_activity(...)` bypasses authorization and the worker rejects the call.
- **`from temporalio.contrib.tenuo import …`.** That module does not exist. Tenuo ships in the `tenuo` package; import from `tenuo` and `tenuo.temporal`.
- **`uv add temporalio[tenuo]`.** The package extra lives on `tenuo`, not `temporalio` — use `uv pip install "tenuo[temporal]"`.
- **Calling `client.execute_workflow(...)` for an authorized Workflow.** Use `execute_workflow_authorized(...)` (or `start_workflow_authorized(...)`) so the warrant and `key_id` are attached to the start.
- **Forgetting `key_id=` on the start helpers.** The worker uses `key_id` to look up the holder signing key via the configured resolver; a missing or unknown id means the Workflow cannot sign Activity invocations and fails closed.
- **`TENUO_SIGNING_KEY_<id>` env-var name.** The convention is `TENUO_KEY_<key_id>` — the key id is appended directly to `TENUO_KEY_`.
- **Re-passing the parent warrant to `tenuo_execute_child_workflow`.** Pass `tools=[...]` and `ttl_seconds=...` instead; the helper attenuates the parent warrant for you.
- **Undeclared `.capability(...)` arguments.** Every argument the Activity will receive needs an explicit constraint (use `Wildcard()` if it is genuinely unconstrained); undeclared arguments are rejected.

## Additional Resources

- [Tenuo Temporal integration guide](https://tenuo.ai/temporal) — upstream source for this reference.
- [Tenuo product docs](https://tenuo.ai/docs) — warrants, capabilities, and constraint types outside Temporal.
- `references/python/python.md` — Temporal Python SDK Client/Worker setup.
- `references/integrations.md` — catalog of all Temporal third-party integrations.
