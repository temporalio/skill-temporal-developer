# Temporal OpenTelemetry Integration (TypeScript)

## Overview

`@temporalio/interceptors-opentelemetry` wires OpenTelemetry tracing into Temporal through the `OpenTelemetryPlugin`. It traces Workflow Executions, Child Workflows, Activity invocations, and Client `start`/`signal` calls, propagating W3C TraceContext + Baggage across all of them.

Workflow-side spans are emitted out of the Workflow isolate through an injected Sink that hands serialized spans to a host-side `SpanProcessor`.

For non-OTel observability (metrics, runtime logger, sinks) read `references/typescript/observability.md`.

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Install

Install `@temporalio/interceptors-opentelemetry` plus the OpenTelemetry peer packages you use — typically `@opentelemetry/api`, `@opentelemetry/sdk-trace-base`, `@opentelemetry/resources`, and an exporter (e.g. `@opentelemetry/exporter-trace-otlp-grpc`).

## `OpenTelemetryPlugin`

Construct one `OpenTelemetryPlugin` and pass it to the Client, `bundleWorkflowCode`, and `Worker.create`. It must reach `bundleWorkflowCode` so the Workflow-side interceptors are included in the bundle. Lifecycle spans (workflow / activity / client) are then created automatically.

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

// `resource` and `spanProcessor` are required; pass an optional `tracer` to override
// the tracer used by the Client/Activity interceptors.
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

Pass the same plugin to the Client so client-side `start` and `signal` calls are traced:

```ts
import { Client, Connection } from '@temporalio/client';

const client = new Client({
  connection: await Connection.connect(),
  plugins: [plugin],
});
```

The SDK uses the global OpenTelemetry propagator (default: W3C TraceContext + Baggage). To use a non-default propagator (e.g. Jaeger), call `propagation.setGlobalPropagator(...)` at the top level of your Workflow code BEFORE the Worker bundles it.

## Standalone Activities

Standalone Activities (`references/typescript/standalone-activities.md`) are traced automatically — the same plugin registration extracts the parent span context whether the Activity was scheduled by a Workflow or directly by a Client.

## Common mistakes

- **Passing only `resource` or only `spanProcessor`.** Both are required; `new OpenTelemetryPlugin()` with no argument throws.
- **Passing the plugin to `Worker.create` but not `bundleWorkflowCode`.** Workflow-side interceptors must be in the bundle.
- **Installing `@temporalio/opentelemetry`.** The package is `@temporalio/interceptors-opentelemetry`.
- **Expecting a non-default propagator (e.g. Jaeger) to work without setting the global propagator before `bundleWorkflowCode` runs.**

## Resources

- SDK metrics / observability reference: `references/typescript/observability.md`
