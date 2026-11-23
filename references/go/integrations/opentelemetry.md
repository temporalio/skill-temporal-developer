# Temporal OpenTelemetry Integration (Go)

## Overview

Two modules wire OpenTelemetry into the Go SDK:

| Module | Stage | Use |
|---|---|---|
| `go.temporal.io/sdk/contrib/opentelemetry-v2` | Experimental | Plugin with replay-safe tracing, context propagation, and optional SDK metrics |
| `go.temporal.io/sdk/contrib/opentelemetry` (v1) | Released | Tracing interceptor and OpenTelemetry metrics handler |

For logging, Tally/Prometheus metrics, and Search Attributes read the [Go observability guide](../observability.md).

> [!NOTE]
> The v2 plugin is Experimental and its APIs may change. It is acceptable to use it on behalf of a user, but tell them it is Experimental.

## Install the v2 plugin

```bash
go get go.temporal.io/sdk/contrib/opentelemetry-v2@latest
```

The package name is `opentelemetry`; the examples alias it as `temporalotel`.

## `NewPlugin`

Create a replay-safe tracer provider, set it as the OpenTelemetry global, then create the plugin and register it on the Client. Workers created from that Client get the plugin automatically.

```go
import (
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.temporal.io/sdk/client"
	temporalotel "go.temporal.io/sdk/contrib/opentelemetry-v2"
	"go.temporal.io/sdk/worker"
)

provider := temporalotel.NewReplaySafeTracerProvider(sdktrace.WithBatcher(exporter))
otel.SetTracerProvider(provider)
defer provider.Shutdown(ctx)

plugin, err := temporalotel.NewPlugin(temporalotel.PluginOptions{})
c, err := client.Dial(client.Options{Plugins: []client.Plugin{plugin}})
w := worker.New(c, "my-task-queue", worker.Options{})
```

### Spans

By default the plugin only propagates trace context through Temporal headers. It creates no spans of its own.

To emit a span per Temporal operation, set `PluginOptions.TracerOptions.AddTemporalSpans`. `TracerOptions` comes from `go.temporal.io/sdk/interceptor/tracing`. Span names include `StartWorkflow`, `RunWorkflow`, `RunActivity`, and `ContinueAsNew`. Starting a Standalone Activity adds a `StartActivity` span tagged with the Activity ID.

### Metrics

Set `PluginOptions.MetricsHandlerOptions` to a non-nil value to replace the Client's metrics handler with an OpenTelemetry one.

- Configure a Meter Provider first. OpenTelemetry's default global Meter Provider records nothing.
- Either call `otel.SetMeterProvider` before creating the plugin or pass a meter in `MetricsHandlerOptions.Meter`.
- Without `Meter`, the handler uses the global provider's meter named `temporal-sdk-go`.
- `UseMonotonicCounters` works as described in [v1 metrics handler](#v1-metrics-handler).

```go
plugin, err := temporalotel.NewPlugin(temporalotel.PluginOptions{
	TracerOptions:         tracing.TracerOptions{AddTemporalSpans: true},
	MetricsHandlerOptions: &temporalotel.MetricsHandlerOptions{UseMonotonicCounters: true},
})
```

### Custom spans

In Workflow code, build the tracer with `temporalotel.Tracer("name")` and start spans from the Workflow context. These spans are replay-safe.

In Client and Activity code, use `otel.Tracer(...)`.

```go
func MyWorkflow(ctx workflow.Context) error {
	tracer := temporalotel.Tracer("my-workflow")
	ctx, span := tracer.Start(ctx, "workflow-operation")
	defer span.End()
	// ...
}
```

## v1 setup

The v1 module provides a tracing interceptor and a metrics handler that you register on the Client yourself:

```go
import (
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/contrib/opentelemetry"
	"go.temporal.io/sdk/interceptor"
)

tracingInterceptor, err := opentelemetry.NewTracingInterceptor(opentelemetry.TracerOptions{})
c, err := client.Dial(client.Options{
	Interceptors:   []interceptor.ClientInterceptor{tracingInterceptor},
	MetricsHandler: opentelemetry.NewMetricsHandler(opentelemetry.MetricsHandlerOptions{}),
})
```

## v1 metrics handler

`MetricsHandlerOptions.UseMonotonicCounters` defaults to `false`, which records SDK counters as OpenTelemetry `Int64UpDownCounter`. Set it to `true` to record them as `Int64Counter`, which exporters classify as monotonic sums. Counter increments must then be non-negative.

The v1 tracing interceptor also creates a `StartActivity` span, tagged with the Activity ID, when a Client starts a Standalone Activity.

## Common mistakes

- **Setting a plain `sdktrace.TracerProvider` as the global provider.** The v2 plugin requires the global provider to come from `NewReplaySafeTracerProvider`; the Workflow tracer panics otherwise.
- **Using `otel.Tracer` inside Workflow code.** Use `temporalotel.Tracer` so spans stay replay-safe.
