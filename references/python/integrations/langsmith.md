# LangSmith Tracing Integration (Python — experimental)

## Status

This integration is **experimental**.

Until a canonical LangSmith integration page lands in `docs/develop/python/integrations/`, treat **every concrete token below** (package names, import paths, class names, environment variables, example code) as unverified. The rest of this file describes (a) where it sits in the plugin landscape, (b) the surrounding contracts a tracing plugin must satisfy, and (c) the questions you must answer from authoritative sources before wiring it into production code.

## What it is

A Temporal Python SDK plugin that emits LangSmith traces for Workflow and Activity executions.

It fits the general Plugin pattern documented in the Python SDK: an object passed via `plugins=[…]` on both the `Client` and the `Worker`, that registers interceptors and/or context propagators to attach tracing spans to Temporal's call graph. `docs/develop/plugins-guide.mdx:30`

## Where it sits relative to other Python tracing options

The Python SDK already ships a built-in tracing path that does **not** involve LangSmith:

- `pip install temporalio[opentelemetry]`
- `temporalio.contrib.opentelemetry.TracingInterceptor` set as an interceptor on `Client.connect()`
- Spans are created for all Client calls, Activities, and Workflow invocations on the Worker, serialized through the server into a single trace per Workflow Execution.

LangSmith tracing is **separate from** OpenTelemetry tracing. They can in principle coexist (both via the Python plugin/interceptor mechanism) but the docs clone does not describe their interaction.

For LLM-call tracing specifically, the closest sibling in the Python integrations catalog is **Braintrust** (`docs/develop/python/integrations/braintrust.mdx`). It is structurally similar — a `*Plugin` object passed to both `Worker` and `Client.connect()` — but the API surface and environment variables there are Braintrust-specific and **must not be transliterated** to LangSmith.

## Prerequisites — confirmable from docs

- A working Python SDK setup with `Client.connect(...)` and a `Worker`.
- Familiarity with the Python plugin abstraction (`SimplePlugin`, `plugins=[…]` arguments on Client and Worker).
- If your Workflows run in the sandbox (the default), the plugin must declare the modules it expects the workflow runner to passthrough.

## Prerequisites — unverified, ask before installing

## Wiring shape — pattern only, not a working sample

The plugin wiring pattern in Python is the same across tracing plugins: construct a plugin instance, pass it to `Client.connect(...)` and to `Worker(...)`. Concretely, you will replace the placeholders below with the actual symbols from the LangSmith plugin documentation:

```python
# Client side
from temporalio.client import Client
# from <VERIFY: package> import <VERIFY: plugin class>

client = await Client.connect(
    "localhost:7233",
    plugins=[<VERIFY: plugin instance>],
)
```

```python
# Worker side
from temporalio.worker import Worker
# from <VERIFY: package> import <VERIFY: plugin class>

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    plugins=[<VERIFY: plugin instance>],
)
```

The `plugins=[…]` argument on both `Client.connect()` and `Worker(...)` is the documented insertion point for plugins in the Python SDK.

## Tracing LLM calls

Whether this plugin auto-traces LLM calls or expects you to instrument them yourself (e.g., via `langsmith.traceable`) is **not** documented in the local docs clone.

For LLM client configuration that is independent of LangSmith, the Python ai-patterns guidance still applies:

- Disable client-side retries (`max_retries=0`) and let Temporal's activity retry policy handle retries.
- Use the Pydantic data converter if your activities pass LLM response objects across the activity boundary.

## Sandbox interaction

The Python SDK runs Workflow code in a sandbox by default.

Any tracing plugin that needs to read modules from inside the Workflow sandbox (for example, to consult a tracing-context module that was loaded before the sandbox boot) must expose a `workflow_runner` hook that adds the relevant modules to the runner's passthrough list when the runner is a `SandboxedWorkflowRunner`.

## Replay and versioning

A tracing plugin should be safe across Workflow replays — the SDK warns that plugin changes can introduce non-determinism in long-running Workflows.

If you upgrade the LangSmith plugin while Workflows are running, run replay tests against pinned histories before rolling the new version into production.

## Common mistakes to avoid

The list below mixes anti-patterns documented for sibling tracing plugins with anti-patterns that are obviously load-bearing for any tracing plugin. Items not explicitly grounded in the LangSmith docs are marked.

- **Wiring the plugin on only one side.** A trace that starts at `client.execute_workflow` and continues into the Worker requires the plugin on both `Client.connect()` and `Worker(...)`.
- **Letting the LLM client retry.** If the activity calls an LLM SDK, set the LLM client's `max_retries=0` so the trace records one Temporal-managed retry rather than N silent client-side retries.
- **Putting tracing initialization inside the workflow function.** Workflow code must be deterministic; any tracing setup that allocates a span or reads wall-clock time belongs in an Activity (or in the worker bootstrap), not in the `@workflow.defn` class.
- **Skipping sandbox passthrough.** If you see import-time errors only when running inside the sandbox, the plugin (or your wiring) is missing a passthrough declaration.

## Related skill references

- `references/python/python.md` — Python SDK getting-started, plugin/Client/Worker shape.
- `references/python/ai-patterns.md` — LLM activity patterns, Pydantic data converter, retry policy.
- `references/python/observability.md` — baseline Python observability (logging, metrics, OpenTelemetry).
- `references/integrations.md` — the catalog this file is registered in.

## Related docs (authoritative — read these before relying on anything above)

- `docs/develop/python/integrations/index.mdx` — Python integrations table. Re-check whether LangSmith has been added.
- `docs/develop/python/integrations/braintrust.mdx` — structural template only; do not copy environment-variable names or class names from this page.
- `docs/develop/plugins-guide.mdx` — the canonical guide to building/consuming Python plugins, sandbox passthrough, replay testing.
- `docs/develop/python/platform/observability.mdx` — Python tracing baseline (OpenTelemetry).
- `docs/develop/python/workers/interceptors.mdx` — interceptor mechanics underlying every tracing plugin.
