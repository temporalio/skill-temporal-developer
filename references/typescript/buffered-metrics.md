# TypeScript SDK: Buffered Metrics and `RuntimeMetricMeter`

## Scope

This page covers two related extension points on the TypeScript SDK telemetry surface:

- **Buffered metrics** — a mode in which the Worker process accumulates Temporal SDK metric updates in memory so that user code (typically running its own OpenTelemetry pipeline or in-process aggregator) can drain and re-emit them, instead of letting the SDK push directly to Prometheus or an OTLP endpoint.
- **`RuntimeMetricMeter`** — the SDK-internal meter that user-provided code can implement (or wrap) to receive metric instrument creations and updates programmatically.

Both are configured on `Runtime.install({ telemetryOptions })` <!-- docs/develop/typescript/platform/observability.mdx:37 -->, the same entry point used for Prometheus and OTLP. They are alternatives to those output sinks, not stackable transformations on top of them.

If you want the SDK to push metrics directly to Prometheus or an OTLP collector, use the documented `metrics: { prometheus: { bindAddress } }` <!-- docs/develop/typescript/platform/observability.mdx:40 --> or `metrics: { otel: { url } }` <!-- docs/develop/typescript/platform/observability.mdx:39 --> options and stop reading here.

## Supported instrument types

The TypeScript metric-meter surface accepts these OpenTelemetry instrument types:

- `Counter` — monotonically increasing total. Emitted by SDK metrics tagged `Counter` in `docs/references/sdk-metrics.mdx` <!-- docs/references/sdk-metrics.mdx:87–101 -->.
- `Histogram` — distribution of values; Core-based SDKs default to **milliseconds** <!-- docs/references/sdk-metrics.mdx:59–61 -->.
- `Gauge` — instantaneous value sampled at observation time.
- **`UpDownCounter` — signed delta counter; the value can go up or down.** This instrument type is the addition being documented here. Use it for "in-flight" / "currently-pending" style metrics where you want to apply `+1` on start and `-1` on completion rather than `set(currentCount)` (which is what `Gauge` expects). <!-- VERIFY: confirm UpDownCounter symbol name and method shape against typescript.temporal.io/api -->

`UpDownCounter` matches the OpenTelemetry instrument of the same name; see the [OTel specification for UpDownCounter](https://opentelemetry.io/docs/specs/otel/metrics/api/#updowncounter) for semantic background. The Temporal-specific point is that buffered metrics and `RuntimeMetricMeter` will now hand you instrument-creation calls for this fourth type in addition to the three above. <!-- VERIFY: that all four types are surfaced through the same factory API; cross-check ts-api: worker.RuntimeMetricMeter / MetricMeter interface -->

### `Counter` vs. `UpDownCounter` — decision rule

- Reach for **`Counter`** when the value only ever increases (request totals, error totals, items processed).
- Reach for **`UpDownCounter`** when the value represents a *level* you adjust with signed deltas (workers checked out of a pool, requests in flight, queue depth tracked by add/remove events).
- Reach for **`Gauge`** when you observe the level directly at sample time and don't want to track increments (free memory, current connection count read from a syscall).

A common mistake is to use `Counter` for an in-flight metric and then need to "decrement on completion" — `Counter` rejects negative deltas. Switching to `UpDownCounter` is the correct fix; do **not** track two `Counter`s and subtract on the dashboard.

## Wiring a custom meter at `Runtime.install`

The custom-meter slot lives under `telemetryOptions.metrics` on the same object passed to `Runtime.install` that already accepts `prometheus` and `otel`:

```ts
import { Runtime } from '@temporalio/worker';

Runtime.install({
  telemetryOptions: {
    metrics: {
      // <-- buffered-metrics / custom-meter option key goes here.
      // VERIFY: exact key name (e.g. customMetricMeter, metricMeter, buffer) and shape
      // against https://typescript.temporal.io/api/interfaces/worker.TelemetryOptions
    },
  },
});
```

<!-- VERIFY: the exact `metrics.*` key for buffered metrics / custom meter on TelemetryOptions. The two documented sibling keys (`prometheus`, `otel`) are at docs/develop/typescript/platform/observability.mdx:39–40; this third key is not yet in docs/. Resolve against typescript.temporal.io/api/interfaces/worker.TelemetryOptions before publishing concrete code. -->

Once wired, the SDK will route every metric update it produces (the names cataloged in `docs/references/sdk-metrics.mdx` <!-- docs/references/sdk-metrics.mdx:87 -->) through your meter rather than through the built-in Prometheus or OTLP exporters.

### Conceptual analogue — .NET `CustomMetricMeter`

The .NET SDK exposes the same idea under `Telemetry.Metrics.CustomMetricMeter` <!-- docs/develop/dotnet/platform/observability.mdx:67–87 -->, which takes a `System.Diagnostics.Metrics.Meter` instance. The TypeScript equivalent serves the same purpose (route SDK metrics into a user-owned pipeline) but has its own type name and constructor shape — do **not** transcribe `CustomMetricMeter` into TypeScript code.

## Recipe: in-flight request gauge via `UpDownCounter`

Goal: emit a metric whose value is the number of in-flight Activity invocations on this Worker, *without* polling.

1. Install a custom meter at `Runtime.install` (see snippet above). <!-- docs/develop/typescript/platform/observability.mdx:37 -->
2. From the custom meter, create an `UpDownCounter` instrument named e.g. `activity_inflight`. <!-- VERIFY: instrument-creation factory method on the TS meter API -->
3. In an Activity interceptor (or directly in Activity code), call the instrument's `add(+1, { activity_type })` on entry and `add(-1, { activity_type })` on exit. <!-- VERIFY: that the value-recording method on UpDownCounter is `add` and that the second argument is `attributes`/`tags` -->
4. Drain or re-export from the meter using whatever transport the meter is wired to (your OTel SDK pipeline, an in-process aggregator, a log line every N seconds, etc.).

Every step above relies on a verified API token; before shipping a runnable example, resolve the four `<!-- VERIFY -->` markers against `https://typescript.temporal.io/api/`.

## Common mistakes

- **Inventing the option key.** "buffered metrics" is the *feature name*, not necessarily the option key. The option key on `telemetryOptions.metrics` is whatever the TS API declares; do not write `metrics: { buffered: { ... } }` without confirming it.
- **Stacking exporters.** The `metrics: { prometheus: { ... } }`, `metrics: { otel: { ... } }`, and custom-meter options are alternatives. Don't write a configuration that sets two — at best one wins, at worst the SDK rejects the shape.
- **Using `record()` on `UpDownCounter`.** Histogram-style instruments expose `record`; counters and up-down-counters expose `add`. <!-- VERIFY: that this convention holds in the TS meter API -->
- **Confusing `Gauge` with `UpDownCounter`.** A `Gauge` is set to an absolute current value (`set(7)`); an `UpDownCounter` is adjusted by signed deltas (`add(+1)`, `add(-1)`). If your code knows the current level directly, use `Gauge`; if it knows only the increment/decrement events, use `UpDownCounter`.
- **Treating `UpDownCounter` as "Counter, but mutable."** `Counter` is required to be non-negative; rejecting that is the whole point of having a separate `UpDownCounter` type. Do not paper over a missing `UpDownCounter` by allowing negative `Counter.add` — that breaks Counter semantics for downstream backends.
- **Cross-using .NET names.** `CustomMetricMeter` is a .NET type name. The TS surface uses its own names (likely involving `MetricMeter` / `RuntimeMetricMeter`); do not write `new CustomMetricMeter(...)` in TypeScript.
- **Assuming a default.** Do not write "defaults to `Counter`" or "defaults to OTLP if no exporter set" without a citation; the default behavior of `Runtime.install` with no `metrics` configured is documented behavior, but defaults *for the custom meter slot specifically* are not currently in `docs/`. <!-- VERIFY: behavior when telemetryOptions.metrics is unset vs. empty -->

## Related

- `references/typescript/observability.md` — TypeScript SDK observability entry point (Runtime, logging, Prometheus/OTLP exporters).
- `docs/references/sdk-metrics.mdx` — catalog of metric names the SDK emits; useful for knowing what your custom meter will see.
- `docs/develop/dotnet/platform/observability.mdx` §"Set a custom metric meter" — conceptual analogue in another Core-based SDK.

<!-- Sources:
docs/develop/typescript/platform/observability.mdx (Runtime.install, telemetryOptions, prometheus/otel option keys),
docs/references/sdk-metrics.mdx (instrument types Temporal itself emits; Core-based-SDK Histogram unit defaults),
docs/develop/dotnet/platform/observability.mdx (CustomMetricMeter analogue — for conceptual framing only),
typescript.temporal.io/api/ (authoritative for all TS-specific symbols flagged with `<!-- VERIFY -->`; the docs clone does not yet describe this feature).
-->
