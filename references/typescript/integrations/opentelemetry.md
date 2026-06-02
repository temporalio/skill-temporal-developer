# Temporal OpenTelemetry Integration (TypeScript)

## Overview

`@temporalio/interceptors-opentelemetry` is a contrib package for the Temporal TypeScript SDK that ships an `OpenTelemetryPlugin` plus per-tier interceptors for tracing Workflow Executions, Child Workflows, Activity invocations, Nexus Operations, and Client `start`/`signal` calls with OpenTelemetry.

Workflow-side spans are emitted out of the Workflow isolate through an injected Sink (`makeWorkflowExporter`) that hands serialized spans to a host-side `SpanProcessor`.

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

For non-OTel observability (metrics, runtime logger, sinks) read `references/typescript/observability.md`. For Standalone Activities (client-scheduled Activities) read `references/typescript/standalone-activities.md`.

## Install

```bash
npm i @temporalio/interceptors-opentelemetry
```

Peer packages this integration normally needs:

- `@opentelemetry/api` — global propagator, tracer, context.
- `@opentelemetry/sdk-trace-base` — `SpanProcessor`, `BatchSpanProcessor`, `BasicTracerProvider`.
- `@opentelemetry/resources` — `Resource` attached to exported spans.
- An exporter, e.g. `@opentelemetry/exporter-trace-otlp-grpc`.

## Public API

| Export | Kind | From |
|---|---|---|
| `OpenTelemetryPlugin` | class extending `SimplePlugin` | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryPluginOptions` | interface | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryWorkflowClientInterceptor` | class (Client) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryWorkflowClientCallsInterceptor` | `@deprecated` alias of above | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryActivityInboundInterceptor` | class (Activity) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryActivityOutboundInterceptor` | class (Activity) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryNexusInboundInterceptor` | class (Nexus) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryNexusOutboundInterceptor` | class (Nexus) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryInboundInterceptor` | class (Workflow inbound) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryOutboundInterceptor` | class (Workflow outbound) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryInternalsInterceptor` | class (Workflow internals) | `@temporalio/interceptors-opentelemetry` |
| `makeWorkflowExporter` | function | `@temporalio/interceptors-opentelemetry` |
| `SpanName` | enum | `@temporalio/interceptors-opentelemetry` |
| `SPAN_DELIMITER` | const (`':'`) | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetrySinks` | type | `@temporalio/interceptors-opentelemetry` |
| `OpenTelemetryWorkflowExporter` | type | `@temporalio/interceptors-opentelemetry` |
| `SerializableSpan` | type | `@temporalio/interceptors-opentelemetry` |

## Register via the plugin (recommended)

Construct one `OpenTelemetryPlugin` instance and pass it to BOTH `bundleWorkflowCode({ plugins })` and `Worker.create({ plugins })` so the Workflow-side interceptors are included in the bundle.

```ts
import { Resource } from '@opentelemetry/resources';
import { BasicTracerProvider, BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { NativeConnection, Worker, bundleWorkflowCode } from '@temporalio/worker';
import { OpenTelemetryPlugin } from '@temporalio/interceptors-opentelemetry';

const resource = new Resource({ 'service.name': 'orders-worker' });
const spanProcessor = new BatchSpanProcessor(new OTLPTraceExporter());

const provider = new BasicTracerProvider({ resource });
provider.addSpanProcessor(spanProcessor);
provider.register();

const plugin = new OpenTelemetryPlugin({ resource, spanProcessor });

const bundle = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  plugins: [plugin],
});

const connection = await NativeConnection.connect();
const worker = await Worker.create({
  connection,
  taskQueue: 'orders',
  workflowBundle: bundle,
  activities: { /* ... */ },
  plugins: [plugin],
});
await worker.run();
```

The Client accepts the same plugin via the standard plugin path; the plugin contributes `OpenTelemetryWorkflowClientInterceptor` so client-side `start` and `signal` calls are traced.

```ts
import { Client, Connection } from '@temporalio/client';
import { OpenTelemetryPlugin } from '@temporalio/interceptors-opentelemetry';

const client = new Client({
  connection: await Connection.connect(),
  plugins: [plugin],
});
```

## Constructor options

`new OpenTelemetryPlugin(otelOptions: OpenTelemetryPluginOptions)`.

| Field | Type | Required | Purpose |
|---|---|---|---|
| `resource` | `Resource` (`@opentelemetry/resources`) | Yes | Resource attributes attached to exported spans. |
| `spanProcessor` | `SpanProcessor` (`@opentelemetry/sdk-trace-base`) | Yes | Receives Workflow, Activity, Client, and Nexus spans. |
| `tracer` | `otel.Tracer` (`@opentelemetry/api`) | No | Override the tracer used by Client/Activity/Nexus interceptors; defaults to `otel.trace.getTracer('@temporalio/interceptor-client'|'-activity'|'-nexus')`. |

## Trace context propagation

The TypeScript SDK uses the global OpenTelemetry propagator; the default is W3C TraceContext + W3C Baggage.

To extend (e.g. add Jaeger), call `propagation.setGlobalPropagator(new CompositePropagator({ propagators: [...] }))` at the top level of your Workflow code BEFORE the Worker bundles it.

```ts
import { propagation } from '@opentelemetry/api';
import { CompositePropagator, W3CBaggagePropagator, W3CTraceContextPropagator } from '@opentelemetry/core';
import { JaegerPropagator } from '@opentelemetry/propagator-jaeger';

propagation.setGlobalPropagator(
  new CompositePropagator({
    propagators: [
      new W3CTraceContextPropagator(),
      new W3CBaggagePropagator(),
      new JaegerPropagator(),
    ],
  }),
);
```

## Span names

`SpanName` enum values; emitted spans are formed as `${SpanName.X}${SPAN_DELIMITER}${suffix}` where `SPAN_DELIMITER = ':'`.

| Enum | String | Where |
|---|---|---|
| `WORKFLOW_START` | `StartWorkflow` | Client `start` |
| `WORKFLOW_SIGNAL` | `SignalWorkflow` | Client `signal`, Workflow `signalWorkflow` outbound |
| `WORKFLOW_EXECUTE` | `RunWorkflow` | Workflow inbound `execute` |
| `CHILD_WORKFLOW_START` | `StartChildWorkflow` | Workflow outbound `startChildWorkflowExecution` |
| `ACTIVITY_START` | `StartActivity` | Workflow outbound `scheduleActivity` / `scheduleLocalActivity` |
| `ACTIVITY_EXECUTE` | `RunActivity` | Activity inbound `execute` |
| `CONTINUE_AS_NEW` | `ContinueAsNew` | Workflow outbound `continueAsNew` |
| `NEXUS_OPERATION_START` | `StartNexusOperation` | Workflow outbound `startNexusOperation` |
| `NEXUS_START_OPERATION_EXECUTE` | `RunStartNexusOperation` | Nexus inbound `startOperation` |
| `NEXUS_CANCEL_OPERATION_EXECUTE` | `RunCancelNexusOperation` | Nexus inbound `cancelOperation` |

## Standalone Activities

`OpenTelemetryActivityInboundInterceptor` extracts the parent span context from `input.headers` regardless of whether the Activity was scheduled by a Workflow or directly by a Client (Standalone Activities). The same plugin registration traces both paths.

For Standalone Activities themselves read `references/typescript/standalone-activities.md`.

## Nexus

`OpenTelemetryNexusInboundInterceptor` wraps inbound `startOperation` and `cancelOperation`, extracting parent context from `input.ctx.headers` and tagging spans with `NEXUS_SERVICE_ATTR_KEY` / `NEXUS_OPERATION_ATTR_KEY`. `OpenTelemetryNexusOutboundInterceptor` emits `trace_id` / `span_id` / `trace_flags` on log attributes and metric tags when a valid span context is active.

OpenTelemetry is the supported tracing path for Nexus in TypeScript; see the [`interceptors-opentelemetry`](https://github.com/temporalio/samples-typescript/tree/main/interceptors-opentelemetry) sample.

## Log and metric correlation

When a valid OTel span context is active during an Activity, Workflow, or Nexus call, the outbound interceptors merge three keys — `trace_id`, `span_id`, `trace_flags` — into the result of `getLogAttributes` (used by `log.*`) and `getMetricTags` (used by worker metric tags). `trace_flags` is formatted as `0${spanContext.traceFlags.toString(16)}`.

## Common mistakes

- Don't pass only `resource` or only `spanProcessor`. Both are required on `OpenTelemetryPluginOptions`.
- Don't call `new OpenTelemetryPlugin()` with no argument; the constructor requires `otelOptions`.
- Don't pass the plugin to `Worker.create` but skip `bundleWorkflowCode` — Workflow-side interceptors must be in the bundle.
- Don't install `@temporalio/opentelemetry`. The package is `@temporalio/interceptors-opentelemetry`.
- Don't use the `makeWorkflowExporter(spanExporter, resource)` overload — it is `@deprecated`. Pass a `SpanProcessor` instead.
- Don't expect non-default propagators (e.g. Jaeger) to work without setting the global propagator before `bundleWorkflowCode` runs.

## Resources

- TypeScript observability guide: <https://docs.temporal.io/develop/typescript/platform/observability>
- Contrib package README: <https://github.com/temporalio/sdk-typescript/blob/main/contrib/interceptors-opentelemetry/README.md>
- Sample: <https://github.com/temporalio/samples-typescript/tree/main/interceptors-opentelemetry>
- SDK metrics reference: <https://docs.temporal.io/references/sdk-metrics>
