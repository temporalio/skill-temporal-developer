# Temporal OpenTelemetry Integration (Python)

## Overview

`temporalio.contrib.opentelemetry` wires OpenTelemetry tracing into Temporal through the `OpenTelemetryPlugin`.

It propagates W3C TraceContext + W3C Baggage through Temporal headers across Client, Workflow, Activity, Child Workflow, and Nexus boundaries.

For non-OTel observability (metrics, logging, telemetry runtime) read `references/python/observability.md`.
For trace propagation through `client.start_activity` / `client.execute_activity` see `references/python/standalone-activities.md`.

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

`OpenTelemetryPlugin` is marked experimental in its docstring.

## Install

```bash
pip install temporalio[opentelemetry]
```

The extra is `opentelemetry`. `uv add temporalio[opentelemetry]` works too.

## Public API

All three symbols are re-exported from `temporalio.contrib.opentelemetry`.

| Symbol | Purpose |
|---|---|
| `OpenTelemetryPlugin` | Client plugin; installs `OpenTelemetryInterceptor` and adds `opentelemetry` sandbox passthrough.  |
| `OpenTelemetryInterceptor` | Underlying interceptor used by `OpenTelemetryPlugin`; requires the global tracer provider be a `ReplaySafeTracerProvider`.  |
| `create_tracer_provider` | Builds a `ReplaySafeTracerProvider`; required when using `OpenTelemetryPlugin`.  |

## `OpenTelemetryPlugin`

Build a `ReplaySafeTracerProvider` with `create_tracer_provider()`, attach span processors, set it as the global tracer provider, then connect with `plugins=[OpenTelemetryPlugin()]`. Workers created from the returned Client inherit the plugin automatically.

```python
import opentelemetry.trace
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from temporalio.client import Client
from temporalio.contrib.opentelemetry import OpenTelemetryPlugin, create_tracer_provider
from temporalio.worker import Worker

provider = create_tracer_provider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
opentelemetry.trace.set_tracer_provider(provider)

client = await Client.connect(
    "localhost:7233",
    plugins=[OpenTelemetryPlugin()],
)

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
)
```

Constructor: `OpenTelemetryPlugin(*, add_temporal_spans: bool = False)`. Keyword-only; `add_temporal_spans=True` adds `StartWorkflow`, `RunWorkflow`, `StartActivity`, `RunActivity` (and similar) spans on top of application spans.

`create_tracer_provider(sampler=None, resource=None, shutdown_on_exit=True, active_span_processor=None, id_generator=None, span_limits=None) -> ReplaySafeTracerProvider`. The provider must be set with `opentelemetry.trace.set_tracer_provider(...)` before `Client.connect`; otherwise the workflow interceptor factory raises `ValueError("When using OpenTelemetryPlugin, the global trace provider must be a ReplaySafeTracerProvider. Use init_tracer_provider to create one.")`.

The plugin's `workflow_runner` callback applies `with_passthrough_modules("opentelemetry")` to `SandboxedWorkflowRunner.restrictions`. Do not add this passthrough manually.

Inside a Workflow, use standard OpenTelemetry APIs — durations are accurate.

```python
from datetime import timedelta
from opentelemetry.trace import get_tracer
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> None:
        tracer = get_tracer(__name__)
        with tracer.start_as_current_span("workflow-operation"):
            await workflow.execute_activity(
                my_activity,
                start_to_close_timeout=timedelta(seconds=30),
            )
```

## Standalone Activities

Trace context propagates through `client.start_activity` and `client.execute_activity` via Temporal headers, the same way it propagates from a Workflow. The client outbound's `start_activity(input: StartActivityInput)` opens a `StartActivity:{activity_type}` span (kind=CLIENT) and injects context into `input.headers`; the activity-side `_TracingActivityInboundInterceptor.execute_activity` extracts that context from `input.headers` and opens a `RunActivity:{activity_type}` span (kind=SERVER).

See `references/python/standalone-activities.md`.

## Nexus

`OpenTelemetryInterceptor.intercept_nexus_operation` wraps inbound Nexus handlers with `RunStartNexusOperationHandler:{service}/{operation}` and `RunCancelNexusOperationHandler:{service}/{operation}` spans (kind=SERVER), extracting context from Nexus operation headers.

See `https://github.com/temporalio/samples-python/tree/main/open_telemetry`.

## Common mistakes

- **Registering the same plugin on both Client and Worker.** Register on the Client only; Workers inherit.
- **Calling `Client.connect` before `opentelemetry.trace.set_tracer_provider(provider)`.** With `OpenTelemetryPlugin`, the workflow interceptor factory raises `ValueError("When using OpenTelemetryPlugin, the global trace provider must be a ReplaySafeTracerProvider. Use init_tracer_provider to create one.")`.
- **Building a plain `opentelemetry.sdk.trace.TracerProvider` and passing it to `set_tracer_provider`.** `OpenTelemetryPlugin` requires `ReplaySafeTracerProvider` — build it via `create_tracer_provider(...)`.
- **Using `addTemporalSpans=True` or other camelCase.** The parameter is `add_temporal_spans` (Python snake_case).
- **Passing the install extra as `temporalio[otel]`.** The extra is `opentelemetry`.
- **Adding `with_passthrough_modules("opentelemetry")` to a `SandboxedWorkflowRunner` manually.** The plugin already does this.

## Resources

- Temporal Python observability docs: `https://docs.temporal.io/develop/python/platform/observability`
- Python SDK OTel contrib README: `https://github.com/temporalio/sdk-python/blob/main/temporalio/contrib/opentelemetry/README.md`
- Python samples — OpenTelemetry: `https://github.com/temporalio/samples-python/tree/main/open_telemetry`
- SDK metrics reference: `references/python/observability.md`
