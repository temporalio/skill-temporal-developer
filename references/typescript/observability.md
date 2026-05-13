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

The two documented `telemetryOptions.metrics` shapes are `prometheus: { bindAddress }` for scraping and `otel: { url }` for a gRPC OpenTelemetry collector.

### Custom metric meter (buffered metrics)

In addition to Prometheus and the OTel gRPC exporter, the TypeScript SDK supports an in-process **custom metric meter** — sometimes called "buffered metrics" — for routing SDK-emitted metrics through application code rather than to an external collector. Typical uses are bridging Temporal metrics into an existing in-process OpenTelemetry SDK, an internal aggregator, or test assertions about which metrics were emitted.

The supported instrument types are Counter, Histogram, and Gauge, plus **`UpDownCounter`** (the newly-added instrument type that motivated this entry — useful for tracking values that can both increase and decrease, such as in-flight work).

For the exact TypeScript surface — the option key under `telemetryOptions.metrics`, the meter class/interface that callers implement or pass in, and the spelling of each instrument-type token — see the TypeScript SDK API typedoc at `https://typescript.temporal.io/`. The shapes below are working names from the upstream release notes and must be confirmed against the typedoc before being relied on:

- The option key on `telemetryOptions.metrics` for a custom in-process meter
- The meter class/interface name (working name: `RuntimeMetricMeter`)
- Instrument types: Counter, Histogram, Gauge, and `UpDownCounter`
- Whether the meter is set once per process via `Runtime.install` like other telemetry options

A worked code example is intentionally omitted here because each token in such an example would need to be confirmed first; an inaccurate sample is worse than a pointer. Once the tokens above are grounded, a small sample can be added that constructs the meter, passes it through `telemetryOptions.metrics`, and shows a single `UpDownCounter` being incremented and decremented.

The cross-SDK *concept* of a custom in-process meter is also documented for the .NET SDK (`docs/develop/dotnet/platform/observability.mdx:64-88`). That page is a useful peer for understanding the shape of the feature but its specific tokens (`CustomMetricMeter`, the `Telemetry`/`Metrics` property names) are .NET-only and must not be transcribed into the TypeScript section.

## Search Attributes (Visibility)

See the Search Attributes section of `references/typescript/data-handling.md`

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
