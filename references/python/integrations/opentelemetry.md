# Temporal OpenTelemetry Integration (Python)

Contents: [Overview](#overview) · [Install the plugin](#install-the-plugin) · [`OpenTelemetryPlugin`](#opentelemetryplugin) · [Replay-safe meters and loggers](#replay-safe-meters-and-loggers) · [Metrics export](#metrics-export) · [Common mistakes](#common-mistakes)

## Overview

`temporalio.contrib.opentelemetry` wires OpenTelemetry tracing into Temporal through the `OpenTelemetryPlugin`. It propagates W3C TraceContext + Baggage across Client, Workflow, Activity, and Nexus code and supports replay-safe custom Workflow spans.

For observability beyond OpenTelemetry tracing (metrics, logging, Search Attributes) read [Python observability guide](../observability.md).

> [!NOTE]
> This feature is Pre-release. It is acceptable to use it on behalf of a user, but inform them that it is Pre-release.

The module also exports `MetricsExporter` for SDK/Core metrics through the OpenTelemetry metrics API, plus `ReplaySafeMeterProvider` and `ReplaySafeLoggerProvider` for Workflow-safe metrics and logging; see [Replay-safe meters and loggers](#replay-safe-meters-and-loggers) and [Metrics export](#metrics-export).

## Install the plugin

Install the `temporalio[opentelemetry]` extra plus the OpenTelemetry exporter packages you use.

## `OpenTelemetryPlugin`

Create a replay-safe tracer provider, set it globally before creating the Client, and register the plugin on the Client. Workers created from that Client inherit the plugin automatically. Application spans propagate by default; pass `OpenTelemetryPlugin(add_temporal_spans=True)` to also emit Temporal lifecycle spans.

```python
import opentelemetry.trace
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from temporalio.client import Client
from temporalio.contrib.opentelemetry import OpenTelemetryPlugin, create_tracer_provider

provider = create_tracer_provider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
opentelemetry.trace.set_tracer_provider(provider)

client = await Client.connect(
    "localhost:7233",
    plugins=[OpenTelemetryPlugin()],
)
```

Inside a Workflow, use standard OpenTelemetry APIs to create custom replay-safe spans:

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

### Plugin behavior

- `add_temporal_spans` defaults to `False`; set it to `True` to add Temporal spans such as `StartWorkflow` and `RunWorkflow`.
- Spans are exported for rejected Updates and failed Queries. Replay-safe spans end when running read-only code (Queries and Update validators), even when holding a non-failure exception.

## Replay-safe meters and loggers

`ReplaySafeMeterProvider` and `ReplaySafeLoggerProvider` (Experimental) drop recordings made from Workflow code only while the Workflow is replaying history. Queries and Update validators still record.

`ReplaySafeMeterProvider` wraps counters, up-down counters, histograms, and gauges. Observable instruments pass through unwrapped.

## Metrics export

`MetricsExporter` (Experimental; Python SDK 1.31.0 or later) sends the SDK's own metrics into an OpenTelemetry `MeterProvider`. It drains a `temporalio.runtime.MetricBuffer` every `poll_interval` (default 1 second).

```python
from opentelemetry.sdk.metrics import MeterProvider
from temporalio.client import Client
from temporalio.contrib.opentelemetry import MetricsExporter
from temporalio.runtime import MetricBuffer, Runtime, TelemetryConfig

buffer = MetricBuffer(10_000)
runtime = Runtime(telemetry=TelemetryConfig(metrics=buffer))
meter_provider = MeterProvider(metric_readers=[...])  # your OpenTelemetry exporter

async with MetricsExporter(buffer, meter_provider):
    client = await Client.connect("localhost:7233", runtime=runtime)
    ...  # run Workers
```

- Create the `Runtime` that uses the buffer before starting the exporter. `run()` raises `RuntimeError` if the buffer was never attached to a `Runtime`.
- A full buffer drops updates; the running exporter is what drains it. Size the buffer for the poll interval.
- Start it with `async with` or `run()`. `shutdown()` stops it after a final drain.
- `on_error` is called, in addition to logging, when draining or applying one update fails. If it raises, that is logged and ignored.
- Counters are added, histograms recorded, and gauges exported as an observable gauge holding the latest value per attribute set.

## Common mistakes

- **Registering the same plugin on both Client and Worker.** Register on the Client only; Workers inherit it.
- **Creating a Workflow Worker before installing the replay-safe global provider.** Set the provider returned by `create_tracer_provider(...)` globally before constructing a Worker that uses `OpenTelemetryPlugin`.
- **Building a plain `opentelemetry.sdk.trace.TracerProvider` and passing it to `set_tracer_provider`.** `OpenTelemetryPlugin` requires a `ReplaySafeTracerProvider`; build it with `create_tracer_provider(...)`.

## Resources

- SDK metrics and observability reference: [Python observability guide](../observability.md)
