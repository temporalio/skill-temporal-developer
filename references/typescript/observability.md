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

The TypeScript SDK exposes telemetry through `Runtime.install({ telemetryOptions: { metrics: { … } } })`. Two metrics sinks are documented: a gRPC OpenTelemetry collector and a Prometheus bind address.

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

The shape `metrics: { prometheus: { bindAddress } }` is the documented Prometheus form; the observability page's worked example uses `'0.0.0.0:9464'`.

### OpenTelemetry collector

The alternative documented sink is `metrics: { otel: { url } }`, pointing at a gRPC OpenTelemetry collector.

### Custom metric handling (buffered metrics)

TypeScript SDK metrics are defined in the Core SDK, which is the same shared core that backs the Python, .NET, and Ruby SDKs. On those sibling Core-based SDKs, the docs describe a custom-metric-handling path that bypasses Prometheus / OpenTelemetry export and instead lets the host application drain metric updates programmatically:

- **Ruby:** an instance of `Temporalio::Runtime::MetricBuffer` is passed as the `buffer` argument to `MetricsOptions`, and `retrieve_updates` is called periodically on the buffer to get metric updates.
- **.NET:** a `CustomMetricMeter` is set on `Telemetry.Metrics`; the `Temporalio.Extensions.DiagnosticSource` extension provides an implementation that forwards to a `System.Diagnostics.Metrics.Meter`.


Until the TypeScript-side API is grounded in `docs/develop/typescript/platform/observability.mdx` (or an authoritative `sdk-typescript` source becomes available), prefer the documented Prometheus or OpenTelemetry sinks above. For end-to-end examples of metrics export from the TypeScript SDK, see the `interceptors-opentelemetry` sample referenced from the TypeScript observability page.

## Search Attributes (Visibility)

See the Search Attributes section of `references/typescript/data-handling.md`

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
