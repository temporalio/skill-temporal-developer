# Standalone Activities — .NET SDK

Read `references/core/standalone-activities.md` first for the concept, CLI inventory, prerequisites, and Public Preview limitations. This file covers the .NET SDK API.

.NET SDK support for Standalone Activities is at **Public Preview**.

## Prerequisites

- **.NET 8.0+.**
- **Temporal .NET SDK v1.12.0 or higher.**
- **Temporal CLI v1.7.0 or higher.**

Start the dev server:

```bash
temporal server start-dev
```

The Temporal Server is then on `localhost:7233` and the Web UI on `http://localhost:8233`; the Standalone Activities nav item is in the top-left of the UI.

## Defining the Activity

An Activity in the .NET SDK is a method decorated with the `[Activity]` attribute. A Standalone Activity is written exactly like an Activity orchestrated by a Workflow — the same Activity can be executed both ways.

```csharp
namespace TemporalioSamples.StandaloneActivity;

using Temporalio.Activities;

public static class MyActivities
{
    [Activity]
    public static Task<string> ComposeGreetingAsync(ComposeGreetingInput input) =>
        Task.FromResult($"{input.Greeting}, {input.Name}!");
}

public record ComposeGreetingInput(string Greeting, string Name);
```

## Running the Worker

Worker setup matches the Workflow-driven case: create a Worker, register the Activity, run the Worker. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

```csharp
using Microsoft.Extensions.Logging;
using Temporalio.Client;
using Temporalio.Common.EnvConfig;
using Temporalio.Worker;
using TemporalioSamples.StandaloneActivity;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions();
connectOptions.TargetHost ??= "localhost:7233";
connectOptions.LoggerFactory = LoggerFactory.Create(builder =>
    builder.
        AddSimpleConsole(options => options.TimestampFormat = "[HH:mm:ss] ").
        SetMinimumLevel(LogLevel.Information));
var client = await TemporalClient.ConnectAsync(connectOptions);

const string taskQueue = "standalone-activity-sample";

using var tokenSource = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    tokenSource.Cancel();
    eventArgs.Cancel = true;
};

using var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions(taskQueue).
        AddActivity(MyActivities.ComposeGreetingAsync));

await worker.ExecuteAsync(tokenSource.Token);
```

`ClientEnvConfig.LoadClientConnectOptions()` reads environment variables and TOML profiles, so the same code works against a local dev server and Temporal Cloud without changes.

## Execute a Standalone Activity

`client.ExecuteActivityAsync()` durably enqueues the Activity, waits for the Worker to execute it, and returns the result. Call this from application code, **not** from inside a Workflow Definition.

```csharp
using Temporalio.Client;
using Temporalio.Common.EnvConfig;
using TemporalioSamples.StandaloneActivity;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions();
connectOptions.TargetHost ??= "localhost:7233";
var client = await TemporalClient.ConnectAsync(connectOptions);

var result = await client.ExecuteActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
Console.WriteLine($"Activity result: {result}");
```

You can pass the Activity as either a lambda expression (type-safe) or a string Activity type name:

```csharp
// Using a lambda expression (type-safe)
var result = await client.ExecuteActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });

// Using a string type name
var result = await client.ExecuteActivityAsync<string>(
    "ComposeGreeting",
    new object?[] { new ComposeGreetingInput("Hello", "World") },
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
```

### `StartActivityOptions` requirements

`StartActivityOptions` requires `Id`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`.

CLI:

```bash
temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```

## Start without waiting for the result

`client.StartActivityAsync()` starts the Activity and returns a handle without waiting.

```csharp
using Temporalio.Client;
using Temporalio.Common.EnvConfig;
using TemporalioSamples.StandaloneActivity;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions();
connectOptions.TargetHost ??= "localhost:7233";
var client = await TemporalClient.ConnectAsync(connectOptions);

var handle = await client.StartActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
Console.WriteLine($"Started activity: {handle.Id}");

// Wait for the result later
var result = await handle.GetResultAsync();
Console.WriteLine($"Activity result: {result}");
```

CLI:

```bash
temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```

## Get a handle to an existing Standalone Activity

`client.GetActivityHandle()` returns a handle to a previously started Standalone Activity. Both untyped and typed forms are available:

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```

Use the handle to wait for the result, describe, cancel, or terminate.

## Wait for the result

`ExecuteActivityAsync` is `StartActivityAsync` followed by `await handle.GetResultAsync()`:

```csharp
var result = await handle.GetResultAsync();
```

CLI:

```bash
temporal activity result --activity-id my-standalone-activity-id
```

## List Standalone Activities

`client.ListActivitiesAsync()` returns an `IAsyncEnumerable<ActivityExecution>` matching a List Filter. **These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included.**

```csharp
using Temporalio.Client;
using Temporalio.Common.EnvConfig;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions();
connectOptions.TargetHost ??= "localhost:7233";
var client = await TemporalClient.ConnectAsync(connectOptions);

await foreach (var info in client.ListActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'"))
{
    Console.WriteLine(
        $"ActivityID: {info.ActivityId}, Type: {info.ActivityType}, Status: {info.Status}");
}
```

The query parameter accepts the same [List Filter](/list-filter) syntax used for Workflow Visibility. Example: `"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`.

## Count Standalone Activities

`client.CountActivitiesAsync()` returns the total count of executions (running, completed, failed, etc.) — **not** the number of queued tasks.

```csharp
using Temporalio.Client;
using Temporalio.Common.EnvConfig;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions();
connectOptions.TargetHost ??= "localhost:7233";
var client = await TemporalClient.ConnectAsync(connectOptions);

var resp = await client.CountActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'");
Console.WriteLine($"Total activities: {resp.Count}");
```

## Run with Temporal Cloud

`ClientEnvConfig.LoadClientConnectOptions()` makes the same code work against Temporal Cloud — configure the connection via env vars or a TOML profile.

mTLS:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

API key:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

## Common mistakes

1. **Calling `client.ExecuteActivityAsync` / `StartActivityAsync` from inside a Workflow Definition.** These are for application code. Inside a Workflow, use `Workflow.ExecuteActivityAsync` (see `references/dotnet/dotnet.md`).
2. **Omitting `Id`, `TaskQueue`, or both timeouts on `StartActivityOptions`.** All three constraints are required.
3. **Mixing the lambda overload with positional args for a different overload.** The lambda overload (`() => MyActivities.ComposeGreetingAsync(...)`) is type-safe; the string-name overload (`ExecuteActivityAsync<TResult>("Name", new object?[] { ... }, options)`) is not. Don't mix shapes.
4. **Expecting `ListActivitiesAsync` / `CountActivitiesAsync` to include Workflow-driven Activities.** They don't.

