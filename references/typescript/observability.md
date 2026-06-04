# TypeScript SDK Observability

## Overview

The TypeScript SDK provides replay-aware logging, metrics, and distributed tracing (OpenTelemetry) for production observability.

These pillars are complementary: **logging** (below) captures discrete events, **metrics** capture aggregate worker health, **tracing** stitches a single request across Client/Workflow/Activity boundaries, and **Search Attributes** make executions queryable. With the tracing plugin installed they also reinforce each other — trace IDs are injected into log metadata and metric tags (see [Distributed Tracing](#distributed-tracing-opentelemetry)).

## Replay-Aware Logging

Temporal's logger automatically suppresses duplicate messages during replay, preventing log spam when workflows recover state.

### Workflow Logging

Workflows run in a sandboxed environment and cannot use regular Node.js loggers directly. Since SDK 1.8.0, the `@temporalio/workflow` package exports a `log` object that provides replay-aware logging. Internally, it uses Sinks to funnel messages to the Runtime's logger.

```typescript
import { log } from '@temporalio/workflow';

export async function orderWorkflow(orderId: string): Promise<string> {
  log.info('Processing order', { orderId });

  const result = await processPayment(orderId);
  log.debug('Payment processed', { orderId, result });

  return result;
}
```

**Log levels**: `log.debug()`, `log.info()`, `log.warn()`, `log.error()`

The workflow logger automatically suppresses duplicate messages during replay and includes workflow context metadata (workflowId, runId, etc.) on every log entry.

### Activity Logging

```typescript
import { log } from '@temporalio/activity';

export async function processPayment(orderId: string): Promise<string> {
  log.info('Processing payment', { orderId });
  return 'payment-id-123';
}
```

The activity logger adds contextual metadata (activity ID, type, namespace) and funnels messages to the runtime's logger for consistent collection.

## Customizing the Logger

### Basic Configuration

```typescript
import { DefaultLogger, Runtime } from '@temporalio/worker';

const logger = new DefaultLogger('DEBUG', ({ level, message }) => {
  console.log(`Custom logger: ${level} - ${message}`);
});
Runtime.install({ logger });
```

### Winston Integration

```typescript
import winston from 'winston';
import { DefaultLogger, Runtime } from '@temporalio/worker';

const winstonLogger = winston.createLogger({
  level: 'debug',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'temporal.log' })
  ],
});

const logger = new DefaultLogger('DEBUG', (entry) => {
  winstonLogger.log({
    label: entry.meta?.activityId ? 'activity' : entry.meta?.workflowId ? 'workflow' : 'worker',
    level: entry.level.toLowerCase(),
    message: entry.message,
    timestamp: Number(entry.timestampNanos / 1_000_000n),
    ...entry.meta,
  });
});

Runtime.install({ logger });
```

## Metrics

### Prometheus Metrics

```typescript
import { Runtime } from '@temporalio/worker';

Runtime.install({
  telemetryOptions: {
    metrics: {
      prometheus: {
        bindAddress: '127.0.0.1:9091',
      },
    },
  },
});
```

## Distributed Tracing (OpenTelemetry)

OpenTelemetry is the supported way to add distributed tracing to Temporal applications. The `OpenTelemetryPlugin` (from `@temporalio/interceptors-opentelemetry`) traces Workflow Executions, Child Workflows, Activity invocations, and Client `start`/`signal` calls, propagating W3C TraceContext + Baggage across all of them. Workflow-side spans are exported out of the Workflow isolate through an injected Sink.

Construct one plugin instance and pass it to the Client, to `bundleWorkflowCode`, and to `Worker.create` (the Workflow-side interceptors must be in the bundle):

```typescript
import { OpenTelemetryPlugin } from '@temporalio/interceptors-opentelemetry';

const plugin = new OpenTelemetryPlugin({ resource, spanProcessor });

const bundle = await bundleWorkflowCode({ workflowsPath, plugins: [plugin] });
const worker = await Worker.create({ connection, taskQueue, workflowBundle: bundle, plugins: [plugin] });
// const client = new Client({ connection, plugins: [plugin] });
```

**Correlation with logging and metrics.** When a valid span context is active during an Activity or Workflow call, the plugin merges `trace_id` / `span_id` / `trace_flags` into the log metadata used by the `log.*` calls in [Workflow Logging](#workflow-logging) / [Activity Logging](#activity-logging) **and** into the worker metric tags from the [Metrics](#metrics) section — so traces, logs, and metrics share correlation IDs without extra wiring.

This is a deliberately minimal orientation. For the full public API, constructor options, span names, propagator customization, and Standalone Activity propagation, see `references/typescript/integrations/opentelemetry.md`. (That file links back here for the logging, metrics, and sink topics above.)

> [!NOTE]
> `OpenTelemetryPlugin` is in Public Preview. It is fine to use on a user's behalf, but tell them it is a Public Preview feature.

## Search Attributes (Visibility)

See the Search Attributes section of `references/typescript/data-handling.md`

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
6. Use the `OpenTelemetryPlugin` for distributed tracing — it also stamps trace IDs onto your logs and metrics (see [Distributed Tracing](#distributed-tracing-opentelemetry))
