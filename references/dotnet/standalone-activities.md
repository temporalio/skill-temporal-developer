# Standalone Activities — .NET SDK

Standalone Activities run independently, without being orchestrated by a Workflow. You start them directly from a Temporal Client. Support in the Temporal .NET SDK is at **Public Preview**.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:24 -->

The way you write the Activity and register it with a Worker is identical to a Workflow Activity — the same Activity Function can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:33 -->
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:127 -->

## Prerequisites

- **.NET 8.0+**
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:60 -->
- **Temporal .NET SDK v1.12.0 or higher**
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:62 -->
- **Temporal CLI v1.7.0 or higher**
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:64 -->
- **Temporal Server v1.31.0 or higher**
  <!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->

Start a local development server (the Temporal Dev Server has Standalone Activities enabled by default):

```bash
temporal server start-dev
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:82 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:138 -->

### Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview but are scheduled for GA.
- The `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet.
<!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

## Define your Activity

An Activity in the .NET SDK is a method decorated with the `[Activity]` attribute. The way you write a Standalone Activity is identical to how you write an Activity orchestrated by a Workflow — the same Activity can be executed both as a Standalone Activity and as a Workflow Activity.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:126 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:132 -->

## Run a Worker with the Activity registered

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — create a Worker, register the Activity, and run the Worker. The Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:149 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:157 -->

The samples use `ClientEnvConfig.LoadClientConnectOptions()` so the same code works against a local dev server and Temporal Cloud — see [Run with Temporal Cloud](#run-with-temporal-cloud) below.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:91 -->

## Execute a Standalone Activity (wait for the result)

Use `client.ExecuteActivityAsync()` to execute a Standalone Activity and wait for the result. Call this from your application code, not from inside a Workflow Definition. It durably enqueues the Activity in the Temporal Server, waits for it to be executed on your Worker, and returns the result.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:199 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:207 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:227 -->

`StartActivityOptions` requires `Id`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`. See the [`StartActivityOptions`](https://dotnet.temporal.io/api/Temporalio.Client.StartActivityOptions.html) API reference for the full set of options.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:246 -->

## Start a Standalone Activity without waiting for the result

Use `client.StartActivityAsync()` to start a Standalone Activity and get a handle without waiting for the result:
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:274 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:280 -->

### Conflict policy and reuse policy

Standalone Activities support deduplication via conflict policy (e.g. `USE_EXISTING`) and reuse policy (e.g. `REJECT_DUPLICATES`). Note that during Public Preview, `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy are not supported yet.
<!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

<!-- VERIFY: The .NET doc does not show explicit code for setting conflict policy / reuse policy on StartActivityOptions; only the encyclopedia lists the policy values conceptually. Specific .NET option property names are not in the doc, so no code snippet is provided. -->

## Get a handle to an existing Standalone Activity

Use `client.GetActivityHandle()` to create a handle to a previously started Standalone Activity:
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:321 -->

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:323 -->

You can use the handle to wait for the result, describe, cancel, or terminate the Activity.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:331 -->

## Wait for the result of a Standalone Activity

Calling `client.ExecuteActivityAsync()` is equivalent to calling `client.StartActivityAsync()` to durably enqueue the Standalone Activity, then `await handle.GetResultAsync()` to wait for the Activity to be executed and return the result:
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:335 -->

```csharp
var result = await handle.GetResultAsync();
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:339 -->

## List Standalone Activities

Use `client.ListActivitiesAsync()` to list Standalone Activity Executions that match a List Filter query. The result is an `IAsyncEnumerable` that yields `ActivityExecution` entries.

These APIs return only Standalone Activity Executions. Activities running inside Workflows are not included.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:351 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:360 -->

The query parameter accepts the same List Filter syntax used for Workflow Visibility — for example, `"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:388 -->

## Count Standalone Activities

Use `client.CountActivitiesAsync()` to count Standalone Activity Executions that match a List Filter query. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. It works the same way as counting Workflow Executions.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:393 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:401 -->

## Run with Temporal Cloud

The code samples use `ClientEnvConfig.LoadClientConnectOptions()`, so the same code works against Temporal Cloud — just configure the connection via environment variables or a TOML profile. No code changes are needed.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:428 -->

### Connect with mTLS

Set these environment variables with values from your Temporal Cloud Namespace settings:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:440 -->

### Connect with an API key

Set these environment variables with values from your Temporal Cloud API key settings:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:451 -->

Then run the Worker and starter code as shown in the earlier sections.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:457 -->
