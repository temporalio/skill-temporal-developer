# TypeScript SDK Observability

## Overview

The TypeScript SDK provides replay-aware logging, metrics, and integrations for production observability.

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

Workers can emit metrics through telemetry options passed to `Runtime.install`. <!-- docs/develop/typescript/platform/observability.mdx:37 --> The documented keys under `telemetryOptions.metrics` are `otel` (for a gRPC OpenTelemetry collector URL) and `prometheus` (for a scrape endpoint bind address). <!-- docs/develop/typescript/platform/observability.mdx:39-40 --> For the catalog of metric names the SDK can emit, see the [SDK metrics reference](/references/sdk-metrics). <!-- docs/develop/typescript/platform/observability.mdx:31,34 -->

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

The `metrics: { prometheus: { bindAddress } }` shape is the documented Prometheus option; <!-- docs/develop/typescript/platform/observability.mdx:40 --> the address shown above is an illustrative value, not a default. The docs example uses `0.0.0.0:9464`, also illustrative. <!-- docs/develop/typescript/platform/observability.mdx:48 -->

For an end-to-end TypeScript metrics setup, see the [`interceptors-opentelemetry`](https://github.com/temporalio/samples-typescript/tree/main/interceptors-opentelemetry) sample. <!-- docs/develop/typescript/platform/observability.mdx:35 -->

### Buffered metrics and custom metric meters

> API surface is not yet covered by the Temporal documentation guide; the symbols below are pointers to the TypeDoc API surface.

In addition to the documented `otel` and `prometheus` exporters, <!-- docs/develop/typescript/platform/observability.mdx:39-40 --> the TypeScript SDK exposes a way for the runtime to deliver metric measurements to user-supplied code — for example, to bridge Temporal SDK metrics into a host application's own metrics pipeline. This is the same concept that the .NET SDK exposes as a custom metric meter, <!-- docs/develop/dotnet/platform/observability.mdx:64-88 --> applied to the TypeScript runtime. It complements (rather than replaces) the existing exporter options.

The TypeScript-SDK entry point for this surface is `RuntimeMetricMeter`. <!-- VERIFY: typescript.temporal.io/api/... — confirm the exact exported symbol name and module path for the TypeScript metric meter surface --> The exact constructor shape, instrument-creation method names, and the option key (if any) under which a custom meter is wired into `Runtime.install` are not described in the Temporal documentation guide; only `otel` and `prometheus` appear as documented keys under `telemetryOptions.metrics`. <!-- docs/develop/typescript/platform/observability.mdx:39-40 --> <!-- VERIFY: typescript.temporal.io/api/... — confirm how a `RuntimeMetricMeter` is registered on the Runtime (option key under `telemetryOptions.metrics`, or a separate `Runtime.install` option) -->

The TypeScript-SDK metric meter now supports the `UpDownCounter` instrument type. <!-- VERIFY: typescript.temporal.io/api/... — confirm the exact exported symbol name for the up-down counter instrument type --> An up-down counter is a non-monotonic counter — that is, a counter whose recorded values may go both up and down — distinguishing it from a monotonic counter that only increases. The set of other instrument types supported by the TypeScript metric meter is not enumerated in the Temporal documentation guide. <!-- VERIFY: typescript.temporal.io/api/... — confirm the full list of instrument types exposed by the TypeScript metric meter -->

Note that "buffered metrics" here refers to this runtime mechanism for delivering measurements to user code; it is distinct from the [SDK metrics reference](/references/sdk-metrics) catalog, which lists *which* metrics the SDK emits rather than *how* a custom sink receives them.

## Search Attributes (Visibility)

See the Search Attributes section of `references/typescript/data-handling.md`

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
