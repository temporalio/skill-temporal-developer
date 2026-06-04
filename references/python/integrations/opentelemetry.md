# Temporal OpenTelemetry Integration (Python)

## Overview

`temporalio.contrib.opentelemetry` wires OpenTelemetry tracing into Temporal through the `OpenTelemetryPlugin`.

It propagates W3C TraceContext + W3C Baggage through Temporal headers across Client, Workflow, Activity, and Child Workflow boundaries.

For non-OTel observability (metrics, logging) read `references/python/observability.md`.

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Install

Modify your dependency on the `temporalio` package to add the `opentelemetry` extra, e.g. `uv add temporalio[opentelemetry]` or whatever is appropriate for your package manager.

## `OpenTelemetryPlugin`

Build a `ReplaySafeTracerProvider` with `create_tracer_provider()`, attach span processors, set it as the global tracer provider, then connect with `plugins=[OpenTelemetryPlugin()]`. Workers created from the returned Client inherit the plugin automatically.

```python
import opentelemetry.trace
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from temporalio.client import Client
from temporalio.contrib.opentelemetry import OpenTelemetryPlugin, create_tracer_provider
from temporalio.worker import Worker

provider = create_tracer_provider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter())) # attach your span processors as normal for OTel
opentelemetry.trace.set_tracer_provider(provider)

client = await Client.connect(
    "localhost:7233",
    # Pass add_temporal_spans=True to also emit `StartWorkflow`, `RunWorkflow`,
    # `StartActivity`, `RunActivity` (and similar) spans on top of application spans.
    plugins=[OpenTelemetryPlugin()],
)

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
)
```

Then just use standard OpenTelemetry APIs in your workflow or activity code — durations are accurate.

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

Standalone activities (`references/python/standalone-activities.md`) are supported automatically.

## Common mistakes

- **Registering the same plugin on both Client and Worker.** Register on the Client only; Workers inherit.
- **Calling `Client.connect` before `opentelemetry.trace.set_tracer_provider(provider)`.** With `OpenTelemetryPlugin`, the workflow interceptor factory raises `ValueError("When using OpenTelemetryPlugin, the global trace provider must be a ReplaySafeTracerProvider. Use init_tracer_provider to create one.")`.
- **Building a plain `opentelemetry.sdk.trace.TracerProvider` and passing it to `set_tracer_provider`.** `OpenTelemetryPlugin` requires `ReplaySafeTracerProvider` — build it via `create_tracer_provider(...)`.
- **Adding `with_passthrough_modules("opentelemetry")` to a `SandboxedWorkflowRunner` manually.** The plugin already does this.

## Resources

- SDK metrics reference: `references/python/observability.md`
