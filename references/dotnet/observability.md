# .NET SDK Observability

## Overview

The .NET SDK provides observability through logging, metrics, tracing, and visibility (Search Attributes) using standard .NET patterns.

## Logging

### Workflow Logging (Replay-Safe)

Use `Workflow.Logger` for replay-safe logging that avoids duplicate messages:

```csharp
[Workflow]
public class MyWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(string name)
    {
        Workflow.Logger.LogInformation("Workflow started for {Name}", name);

        var result = await Workflow.ExecuteActivityAsync(
            (MyActivities a) => a.MyActivityAsync(),
            new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });

        Workflow.Logger.LogInformation("Activity completed with {Result}", result);
        return result;
    }
}
```

The workflow logger automatically:

- Suppresses duplicate logs during replay
- Includes workflow context (workflow ID, run ID, etc.)

### Activity Logging

Use `ActivityExecutionContext.Current.Logger` for context-aware activity logging:

```csharp
[Activity]
public async Task<string> ProcessOrderAsync(string orderId)
{
    var logger = ActivityExecutionContext.Current.Logger;
    logger.LogInformation("Processing order {OrderId}", orderId);

    // Perform work...

    logger.LogInformation("Order processed successfully");
    return "completed";
}
```

### Customizing Logger Configuration

```csharp
using Microsoft.Extensions.Logging;

var client = await TemporalClient.ConnectAsync(new("localhost:7233")
{
    LoggerFactory = LoggerFactory.Create(builder =>
        builder
            .AddSimpleConsole(options => options.TimestampFormat = "[HH:mm:ss] ")
            .SetMinimumLevel(LogLevel.Information)),
});
```

## Metrics

### Enabling SDK Metrics

Metrics are configured on `TemporalRuntime`. Create the runtime globally before any client/worker and set a Prometheus endpoint or custom metric meter.

```csharp
using Temporalio.Client;
using Temporalio.Runtime;

// Create runtime with Prometheus endpoint
var runtime = new TemporalRuntime(new()
{
    Telemetry = new() { Metrics = new() { Prometheus = new("0.0.0.0:9000") } },
});

// Use this runtime for all clients
var client = await TemporalClient.ConnectAsync(
    new("localhost:7233") { Runtime = runtime });
```

Alternatively, use `Temporalio.Extensions.DiagnosticSource` to bridge metrics to a .NET `System.Diagnostics.Metrics.Meter` for integration with OpenTelemetry or other .NET metrics pipelines.

`PrometheusOptions` leaves metric names bare by default. Match dashboard and alert queries to the names you choose:

- `HasCounterTotalSuffix` adds `_total` to counter names.
- `HasUnitSuffix` adds the unit to histogram names.
- `UseSecondsForDuration` reports durations in seconds instead of milliseconds.

To export histograms over OTLP as base-2 exponential histograms (Prometheus native histograms), set `OpenTelemetryOptions.HistogramAggregation` to `new OpenTelemetryHistogramAggregation.Base2Exponential()`. The default is `ExplicitBuckets`.

- The setting applies to every histogram, including custom ones.
- It cannot be combined with `HistogramBucketOverrides`.
- `NameSuffix` is appended to every histogram name and defaults to `_native`.
- `MaxSize` defaults to 160. `MaxScale` defaults to 20 and accepts -10 to 20.

### Key SDK Metrics

- `temporal_request` — Client requests to server
- `temporal_workflow_task_execution_latency` — Workflow task processing time
- `temporal_activity_execution_latency` — Activity execution time
- `temporal_workflow_task_replay_latency` — Replay duration

## Tracing (OpenTelemetry)

`Temporalio.Extensions.OpenTelemetry` provides `TracingInterceptor`. Add it to the Client; Workers created from that Client use it too:

```csharp
var client = await TemporalClient.ConnectAsync(new("localhost:7233")
{
    Interceptors = new[] { new TracingInterceptor() },
});
```

Add its activity sources to the tracer provider, including `TracingInterceptor.NexusSource.Name` for Nexus spans:

```csharp
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .AddSource(
        TracingInterceptor.ClientSource.Name,
        TracingInterceptor.WorkflowsSource.Name,
        TracingInterceptor.ActivitiesSource.Name,
        TracingInterceptor.NexusSource.Name)
    .Build();
```

Starting a Standalone Activity from a Client creates a `StartActivity:<activity type>` span, tagged with the Activity ID under `TracingInterceptorOptions.TagNameActivityId` (default `temporalActivityID`; `null` omits the tag).

## Worker Heartbeating

A running Worker sends a heartbeat to the Temporal Service every 60 seconds by default. `temporal worker list` and `temporal worker describe` show what the heartbeats report, including Worker configuration, host load, SDK runtime, and OS. Set the interval between 1 and 60 seconds. Keep heartbeats enabled unless the user asks otherwise, because disabling them leaves those commands with missing or inaccurate Workers.

Set `WorkerHeartbeatInterval` on `TemporalRuntimeOptions` (`null` disables heartbeats), and set `DisableEnvironmentInfo` to omit runtime, hosting, and platform info.

## Search Attributes (Visibility)

Custom searchable fields for workflow visibility. These can be set at workflow start:

```csharp
using Temporalio.Common;

var handle = await client.StartWorkflowAsync(
    (OrderWorkflow wf) => wf.RunAsync(order),
    new(id: $"order-{order.Id}", taskQueue: "orders")
    {
        TypedSearchAttributes = new SearchAttributeCollection.Builder()
            .Set(SearchAttributeKey.CreateKeyword("OrderId"), order.Id)
            .Set(SearchAttributeKey.CreateKeyword("OrderStatus"), "pending")
            .Set(SearchAttributeKey.CreateDouble("OrderTotal"), order.Total)
            .ToSearchAttributeCollection(),
    });
```

Or upserted during workflow execution:

```csharp
[Workflow]
public class OrderWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(Order order)
    {
        // ... process order ...

        // Update search attribute
        Workflow.UpsertTypedSearchAttributes(
            SearchAttributeKey.CreateKeyword("OrderStatus").ValueSet("completed"));
        return "done";
    }
}
```

### Querying Workflows by Search Attributes

```csharp
await foreach (var wf in client.ListWorkflowsAsync(
    "OrderStatus = \"processing\" OR OrderStatus = \"pending\""))
{
    Console.WriteLine($"Workflow {wf.Id} is still processing");
}
```

## Best Practices

1. Use `Workflow.Logger` in workflows, `ActivityExecutionContext.Current.Logger` in activities
2. Don't use `Console.WriteLine` in workflows — it will produce duplicate output on replay
3. Configure metrics for production monitoring
4. Use Search Attributes for business-level visibility
