# TypeScript SDK Buffered Metrics & Custom Metrics

> [!NOTE]
> The Metric API and buffered metrics are experimental in the TypeScript SDK; the APIs may change.

This reference covers two related TypeScript SDK features:

1. **The `MetricMeter` API** — emit custom metrics from worker, workflow, and activity code using four instrument types.
2. **`MetricsBuffer`** — in-process buffer for capturing all metric updates (Core + custom) when you want to forward them somewhere other than Prometheus or OTLP (e.g., StatsD, Datadog DogStatsD, in-process aggregation).

For the standard Prometheus / OTel collector export paths, see `references/typescript/observability.md`.

## When to use which

| Goal | Use |
|---|---|
| Scrape metrics with Prometheus | `telemetryOptions.metrics.prometheus.bindAddress` (see `observability.md`) |
| Push to an OTLP collector | `telemetryOptions.metrics.otel.url` (see `observability.md`) |
| Custom export (StatsD, Datadog client, log shipper, tests) | `MetricsBuffer` + `retrieveUpdates()` |
| Emit your own application metrics | `metricMeter` from the relevant package |

`MetricsBuffer` and a Prometheus / OTel exporter are **mutually exclusive** on the `metrics` field — pick one transport per Runtime.

## Instrument types

The `MetricMeter` interface exposes four instrument types:

| Method | Returns | `kind` literal | Use for |
|---|---|---|---|
| `createCounter(name, unit?, description?)` | `MetricCounter` | `"counter"` | Monotonically increasing totals (events, requests).  |
| `createUpDownCounter(name, unit?, description?)` | `MetricUpDownCounter` | `"up-down-counter"` | Values that go up and down (in-flight requests, queue depth, active connections).  |
| `createGauge(name, valueType?, unit?, description?)` | `MetricGauge` | `"gauge"` | Instantaneous measurements set to an absolute value.  |
| `createHistogram(name, valueType?, unit?, description?)` | `MetricHistogram` | `"histogram"` | Distributions of non-negative values.  |

`MetricCounter` and `MetricUpDownCounter` always record integers (`valueType: "int"`). Only `createGauge` and `createHistogram` accept a `valueType` parameter (`"int" | "float"`).

`MetricKind` is `"counter" | "histogram" | "gauge" | "up-down-counter"` — note the hyphenated form.

### Instrument methods

```typescript
counter.add(value: number, extraTags?: MetricTags): void        // value ≥ 0
upDownCounter.add(value: number, extraTags?: MetricTags): void  // value may be negative
gauge.set(value: number, extraTags?: MetricTags): void
histogram.record(value: number, extraTags?: MetricTags): void   // value ≥ 0
```

Every instrument also has `withTags(tags: MetricTags): <SameInstrument>` which returns a clone with permanent extra tags. `MetricTags` is `Record<string, string | number | boolean>`.

## Accessing the meter

`metricMeter` is the entry point in each runtime context. It is a **property, not a function**.

**Worker / Client process (top-level):**

```typescript
import { Runtime } from '@temporalio/worker';

const meter = Runtime.instance().metricMeter;
const tasksInFlight = meter.createUpDownCounter('app_tasks_in_flight', undefined, 'Tasks currently being processed');
tasksInFlight.add(1, { worker: 'payments' });
// ...later
tasksInFlight.add(-1, { worker: 'payments' });
```

**Inside a Workflow:**

```typescript
import { metricMeter } from '@temporalio/workflow';

export async function chargeWorkflow(orderId: string): Promise<void> {
  const charges = metricMeter.createCounter('charges_started');
  charges.add(1, { orderId });
}
```

The workflow `metricMeter` is automatically tagged with workflow context.

**Inside an Activity:**

```typescript
import { metricMeter } from '@temporalio/activity';

export async function callPaymentGateway(orderId: string): Promise<void> {
  const latency = metricMeter.createHistogram('gateway_latency', 'float', 'ms');
  const start = performance.now();
  // ... do work ...
  latency.record(performance.now() - start, { orderId });
}
```

The activity `metricMeter` is automatically tagged with activity context; `ActivityOutboundCallsInterceptor.getMetricTags()` can add custom tags.

If telemetry is not configured, the meter resolves to `noopMetricMeter` — calls are silently dropped.

## Buffered metrics

`MetricsBuffer` (exported from `@temporalio/worker`) captures every metric update — both Core-emitted SDK metrics and anything you record through `metricMeter` — into an in-memory queue you drain on your schedule.

### Setup

```typescript
import { MetricsBuffer, Runtime } from '@temporalio/worker';

const buffer = new MetricsBuffer({ maxBufferSize: 100_000 });

Runtime.install({
  telemetryOptions: {
    metrics: buffer,
  },
});
```

`MetricsBufferOptions`:

| Option | Type | Default | Notes |
|---|---|---|---|
| `maxBufferSize` | `number` | `10000` | Max events buffered before new updates are dropped and an error is logged. |
| `useSecondsForDurations` | `boolean` | `false` | If `true`, duration metrics use seconds instead of milliseconds. |

### Draining

```typescript
const runtime = Runtime.instance();
const buffer = runtime.metricsBuffer;
if (!buffer) return; // buffered metrics not configured

setInterval(() => {
  for (const update of buffer.retrieveUpdates()) {
    forward(update);
  }
}, 1_000);
```

`retrieveUpdates()` returns an `ArrayIterator<BufferedMetricUpdate>` containing every event accumulated since the last call.

### `BufferedMetricUpdate` shape

```typescript
interface BufferedMetricUpdate {
  attributes: MetricTags;  // tags for this update
  metric: Metric;          // the metric (includes kind, name, valueType, unit?, description?)
  value: number;           // delta for counters/up-down-counters; absolute for gauges; sample for histograms
}
```

The SDK reuses `attributes` and `metric` objects across updates for performance, so do not store references — copy what you need before the next call to `retrieveUpdates()`.

Dispatch by `metric.kind`:

```typescript
switch (update.metric.kind) {
  case 'counter':           return statsd.increment(update.metric.name, update.value, update.attributes);
  case 'up-down-counter':   return statsd.gauge(update.metric.name, update.value, update.attributes);  // delta
  case 'gauge':             return statsd.gauge(update.metric.name, update.value, update.attributes);
  case 'histogram':         return statsd.distribution(update.metric.name, update.value, update.attributes);
}
```

## Hard constraints

- **Drain on a timer.** If `retrieveUpdates()` is not called regularly, the buffer fills, new updates are dropped, and an error is logged. Size the buffer for your drain interval.
- **Buffered metrics and Prometheus / OTel are exclusive.** The `metrics` field on `telemetryOptions` is a single transport — install either a `MetricsBuffer` or a `PrometheusMetricsExporter` / `OtelCollectorExporter`, not both.
- **`Runtime.install` is once per process.** Configure it before constructing any `Worker` or `Client`.
- **Do not retain `attributes`/`metric` references across iterations.** The SDK mutates the same objects between events. Copy fields you need to keep.
- **Counters and up-down-counters are int-only.** Pass integer values to `add`; floats are truncated to the declared `valueType`.
- **`metricMeter` is a property.** Access via `Runtime.instance().metricMeter` or `import { metricMeter } from '@temporalio/workflow' | '@temporalio/activity'`. There is no `RuntimeMetricMeter` exported type.

## Common mistakes

| Mistake | Fix |
|---|---|
| `meter.createUpDownCounter(name, 'int', ...)` | Counters/up-down-counters take no `valueType` — only `(name, unit?, description?)`.  |
| Using `"upDownCounter"` as the kind literal | The literal is `"up-down-counter"`.  |
| `Runtime.instance().retrieveBufferedMetrics()` | `Runtime.instance().metricsBuffer?.retrieveUpdates()`.  |
| `import { MetricsBuffer } from '@temporalio/common'` | Import from `@temporalio/worker`.  |
| Calling `meter.createCounter()` without `Runtime.install` | Without telemetry configured, `metricMeter` is `noopMetricMeter` and all updates are dropped silently.  |
| Storing `update.attributes` from a previous iteration | Objects are reused — copy before the next `retrieveUpdates` call.  |
| Configuring both `prometheus` and a `MetricsBuffer` | One transport per `telemetryOptions.metrics`.  |

## Worked example: forward to StatsD with an UpDownCounter

```typescript
import { MetricsBuffer, Runtime } from '@temporalio/worker';
import { StatsD } from 'hot-shots';

const buffer = new MetricsBuffer({ maxBufferSize: 50_000 });
Runtime.install({ telemetryOptions: { metrics: buffer } });

const statsd = new StatsD();

setInterval(() => {
  for (const { metric, value, attributes } of buffer.retrieveUpdates()) {
    const tags = Object.entries(attributes).map(([k, v]) => `${k}:${v}`);
    switch (metric.kind) {
      case 'counter':
      case 'up-down-counter':
        statsd.count(metric.name, value, tags);
        break;
      case 'gauge':
        statsd.gauge(metric.name, value, tags);
        break;
      case 'histogram':
        statsd.distribution(metric.name, value, tags);
        break;
    }
  }
}, 1_000);

// Application metric using the runtime meter:
const meter = Runtime.instance().metricMeter;
const inFlight = meter.createUpDownCounter('app_orders_in_flight');
inFlight.add(1, { region: 'us-east' });
// ...
inFlight.add(-1, { region: 'us-east' });
```

