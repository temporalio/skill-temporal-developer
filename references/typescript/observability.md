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

### Custom Metric Handling: Buffered Metrics

`MetricsBuffer` is an **experimental** alternative to the Prometheus and OpenTelemetry exporters. Instead of pushing metrics out of the process, the buffer accumulates SDK-emitted metric updates in memory and lets your code drain them with `retrieveUpdates()` <!-- ts-api: classes/worker.MetricsBuffer -->. Reach for it when you want to forward metrics to a backend the SDK does not natively support, or when you want to assert on emitted metrics in tests. The buffered metrics API is documented as: "Buffered metrics is an experimental feature. APIs may be subject to change." <!-- ts-api: classes/worker.Runtime (metricsBuffer) --> — treat names below as subject to change.

```typescript
import { MetricsBuffer, Runtime } from '@temporalio/worker';

const buffer = new MetricsBuffer({
  maxBufferSize: 10_000,        // default: 10000 — events past this are dropped
  useSecondsForDurations: false, // default: false (Core-based SDKs emit histograms in ms)
});

Runtime.install({
  telemetryOptions: {
    metrics: /* attach the buffer to the runtime's metrics exporter config */ buffer as any,
    // VERIFY: the API reference describes MetricsBuffer as being set on
    // `RuntimeOptions.telemetry.metricsExporter`, but the published docs and
    // existing examples use `telemetryOptions.metrics`. Confirm the exact
    // field name against the version of @temporalio/worker you're using.
  },
});

// Drain the buffer periodically. Call frequency is application-specific —
// the Ruby docs prescribe "periodically" without a specific cadence.
setInterval(() => {
  for (const update of buffer.retrieveUpdates()) {
    // update.attributes: MetricTags
    // update.metric: the Metric being updated
    // update.value: number — "For counters this is a delta;
    //                        for gauges and histograms this is the value itself."
    forwardToBackend(update);
  }
}, 5_000);
```

Notes:

- `MetricsBufferOptions.maxBufferSize` defaults to `10000`; when the buffer is full, "metric updates will be dropped and an error will be logged." <!-- ts-api: classes/worker.MetricsBuffer -->
- `MetricsBufferOptions.useSecondsForDurations` defaults to `false`. Core-based SDKs emit histograms in milliseconds unless you opt into seconds. <!-- ts-api: interfaces/worker.MetricsBufferOptions; docs/references/sdk-metrics.mdx:55-65 -->
- `BufferedMetricUpdate` has three fields: `attributes`, `metric`, `value`. No timestamp, no unit, no description field. <!-- ts-api: interfaces/worker.BufferedMetricUpdate -->

This pattern mirrors the Ruby SDK's `Temporalio::Runtime::MetricBuffer` (provided as the `buffer` argument to `MetricsOptions`, drained via `retrieve_updates`) <!-- docs/develop/ruby/platform/observability.mdx:58-61 --> and the .NET SDK's `CustomMetricMeter` on `Telemetry.Metrics` <!-- docs/develop/dotnet/platform/observability.mdx:64-87 -->. Spelling differs by SDK — TypeScript uses `MetricsBuffer` / `retrieveUpdates()`, not the Ruby `MetricBuffer` / `retrieve_updates`.

### Custom Metric Handling: Recording Your Own Metrics

The runtime exposes a `MetricMeter` via `Runtime.metricMeter` <!-- ts-api: classes/worker.Runtime (metricMeter) -->. Use it to record your own application metrics through the same pipeline the SDK uses for its built-in metrics — they will flow to whatever exporter you have configured (Prometheus, OTel collector, or `MetricsBuffer`).

`MetricMeter` supports four instrument types:

| Method                                 | Instrument        | Use for                                                            |
| -------------------------------------- | ----------------- | ------------------------------------------------------------------ |
| `createCounter(name, …)`               | Counter           | Monotonically increasing totals (events, errors).                  |
| `createHistogram(name, …)`             | Histogram         | Distributions (latencies, sizes).                                  |
| `createGauge(name, …)`                 | Gauge             | Point-in-time absolute values (queue depth as a snapshot).         |
| `createUpDownCounter(name, …)`         | UpDownCounter     | Signed deltas — values that can increase **and** decrease.         |

<!-- ts-api: interfaces/common.MetricMeter -->

`UpDownCounter` is the most recent addition. Its `add(value, extraTags?)` method accepts negative values: "Add the given value to the up-down counter. Value may be negative." <!-- ts-api: interfaces/common.MetricUpDownCounter --> Use it for things like in-flight request counters where `add(1)` on entry and `add(-1)` on exit produces a running balance, without you having to maintain the gauge value yourself.

```typescript
import { Runtime } from '@temporalio/worker';

const meter = Runtime.instance().metricMeter;
const inFlight = meter.createUpDownCounter('myapp_inflight_requests');

inFlight.add(1, { route: '/checkout' });   // request started
// ... do work ...
inFlight.add(-1, { route: '/checkout' });  // request finished
```

The same `MetricMeter` exposes `withTags(tags)` to clone a meter with attributes pre-applied <!-- ts-api: interfaces/common.MetricMeter -->. Each instrument also has its own `withTags(tags)` to clone the instrument with additional tags.

## Search Attributes (Visibility)

See the Search Attributes section of `references/typescript/data-handling.md`

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
