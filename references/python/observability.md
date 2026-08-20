# Python SDK Observability

## Overview

The Python SDK provides comprehensive observability through logging, metrics, tracing (OpenTelemetry), and visibility (Search Attributes).

These pillars are complementary: **logging** (below) captures discrete events, **metrics** capture aggregate health, **tracing** stitches a single request across Client/Workflow/Activity boundaries, and **Search Attributes** make executions queryable.

## Logging

### Workflow Logging (Replay-Safe)

Use `workflow.logger` for replay-safe logging that avoids duplicate messages:

```python
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, name: str) -> str:
        workflow.logger.info("Workflow started", extra={"name": name})

        result = await workflow.execute_activity(
            my_activity,
            start_to_close_timeout=timedelta(minutes=5),
        )

        workflow.logger.info("Activity completed", extra={"result": result})
        return result
```

The workflow logger automatically:

- Suppresses duplicate logs during replay
- Includes workflow context (workflow ID, run ID, etc.)

### Activity Logging

Use `activity.logger` for context-aware activity logging:

```python
@activity.defn
async def process_order(order_id: str) -> str:
    activity.logger.info(f"Processing order {order_id}")

    # Perform work...

    activity.logger.info("Order processed successfully")
    return "completed"
```

Activity logger includes:

- Activity ID, type, and task queue
- Workflow ID and run ID
- Attempt number (for retries)

### Customizing Logger Configuration

```python
import logging

# Applies to temporalio.workflow.logger and temporalio.activity.logger, as Temporal inherits the default logger
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
```

## Metrics

### Enabling SDK Metrics

```python
from temporalio.client import Client
from temporalio.runtime import Runtime, TelemetryConfig, PrometheusConfig

# Create a custom runtime
runtime = Runtime(
    telemetry=TelemetryConfig(
        metrics=PrometheusConfig(bind_address="0.0.0.0:9000")
    )
)

# Set it as the global default BEFORE any Client/Worker is created
# Do this only ONCE.
Runtime.set_default(runtime, error_if_already_set=True)
# error_if_already_set can be False if you want to overwrite an existing default without raising.

# ...elsewhere, client = ... as usual
```

### Key SDK Metrics

- `temporal_request` - Client requests to server
- `temporal_workflow_task_execution_latency` - Workflow task processing time
- `temporal_activity_execution_latency` - Activity execution time
- `temporal_workflow_task_replay_latency` - Replay duration

## Distributed Tracing (OpenTelemetry)

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

OpenTelemetry is the supported way to add distributed tracing to Temporal applications. The `OpenTelemetryPlugin` (from `temporalio.contrib.opentelemetry`, installed via the `temporalio[opentelemetry]` extra) propagates W3C TraceContext + Baggage through Temporal headers across Client, Workflow, Activity (including Standalone), and Child Workflow boundaries, so one trace follows a request through your whole execution — with replay-safe, accurate span durations.

```python
import opentelemetry.trace
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from temporalio.client import Client
from temporalio.contrib.opentelemetry import OpenTelemetryPlugin, create_tracer_provider

provider = create_tracer_provider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))  # attach your span processors as normal for OTel
opentelemetry.trace.set_tracer_provider(provider)

client = await Client.connect("localhost:7233", plugins=[OpenTelemetryPlugin()])
```

Workers created from this Client inherit the plugin automatically. Inside a Workflow you then use standard OpenTelemetry APIs (`get_tracer(...).start_as_current_span(...)`); pass `OpenTelemetryPlugin(add_temporal_spans=True)` to also emit `StartWorkflow` / `RunWorkflow` / `StartActivity` / `RunActivity` spans automatically alongside the SDK metrics above.

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

**Common mistakes:**

- **Registering the same plugin on both Client and Worker.** Register on the Client only; Workers inherit.
- **Calling `Client.connect` before `opentelemetry.trace.set_tracer_provider(provider)`.** `OpenTelemetryPlugin` raises an exception unless the global tracer provider is already set.
- **Building a plain `opentelemetry.sdk.trace.TracerProvider` and passing it to `set_tracer_provider`.** `OpenTelemetryPlugin` requires a `ReplaySafeTracerProvider` — build it via `create_tracer_provider(...)`.

## Search Attributes (Visibility)

See the Search Attributes section of `references/python/data-handling.md`

## Best Practices

1. Use `workflow.logger` in workflows, `activity.logger` in activities
2. Don't use print() in workflows - it will produce duplicate output on replay
3. Configure metrics for production monitoring
4. Use Search Attributes for business-level visibility
5. Use the `OpenTelemetryPlugin` for distributed tracing across Client/Workflow/Activity boundaries.
