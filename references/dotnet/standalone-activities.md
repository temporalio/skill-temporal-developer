# Standalone Activities — .NET SDK

## Overview

Standalone Activities are Activities that run independently, without being orchestrated by a
Workflow. Instead of starting an Activity from within a Workflow Definition, you start a Standalone
Activity directly from a Temporal Client. The way you write the Activity and register it with a
Worker is identical to a Workflow Activity — the only difference is that you execute the Standalone
Activity directly from the Client.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:29 -->
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:33 -->

## Support stage and minimum SDK version

- Support stage: **Public Preview**.
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:24 -->
- Temporal .NET SDK: **v1.12.0 or higher**.
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:62 -->
- Runtime: **.NET 8.0+**.
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:60 -->
- Temporal CLI: **v1.7.0 or higher** (for the CLI flows shown below).
  <!-- docs/develop/dotnet/activities/standalone-activities.mdx:64 -->

## Define the Activity

An Activity in the .NET SDK is a method decorated with the `[Activity]` attribute. A Standalone
Activity is written exactly the same as a Workflow Activity — in fact the same Activity can be
executed both ways.
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

Running a Worker for Standalone Activities is identical to running a Worker for Workflow
Activities: construct a `TemporalWorker`, register the Activity with
`TemporalWorkerOptions(taskQueue).AddActivity(...)`, and run it. The Worker doesn't need to know
whether the Activity will be invoked from a Workflow or as a Standalone Activity.
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

## Execute a Standalone Activity

Use `client.ExecuteActivityAsync()` to execute a Standalone Activity and wait for the result. Call
this from your application code — not from inside a Workflow Definition. It durably enqueues the
Activity in the Temporal Server, waits for it to be executed on your Worker, and returns the result.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:199 -->

### Lambda (type-safe) form

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

### String Activity-type name form

```csharp
var result = await client.ExecuteActivityAsync<string>(
    "ComposeGreeting",
    new object?[] { new ComposeGreetingInput("Hello", "World") },
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:237 -->

## `StartActivityOptions` required fields

`StartActivityOptions` requires:

- `Id`
- `TaskQueue`
- At least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`

In the constructor shorthand `new("standalone-activity-id", "standalone-activity-sample") { ... }`,
the two positional arguments are the Activity `Id` and the `TaskQueue`. See the
`Temporalio.Client.StartActivityOptions` API reference for the full set of options.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:246 -->

## Start a Standalone Activity without waiting for the result

Use `client.StartActivityAsync()` to start a Standalone Activity and get a handle back without
waiting for the result. Use `handle.Id` to inspect the Activity ID; call
`await handle.GetResultAsync()` to await the result later.
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

## Get a handle to an existing Standalone Activity

Use `client.GetActivityHandle()` to create a handle to a previously started Standalone Activity.
The typed overload `client.GetActivityHandle<T>(...)` carries a known result type so
`GetResultAsync()` returns `T` directly.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:321 -->

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:323 -->

The handle can be used to wait for the result, describe, cancel, or terminate the Activity.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:331 -->

## Wait for the result of a Standalone Activity

`client.ExecuteActivityAsync()` is equivalent to calling `client.StartActivityAsync()` to durably
enqueue the Activity and then calling `await handle.GetResultAsync()` to wait for it to be executed
and return the result.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:335 -->

```csharp
var result = await handle.GetResultAsync();
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:339 -->

## List Standalone Activities

Use `client.ListActivitiesAsync()` with a [List Filter] query to list Standalone Activity
Executions. The result is an `IAsyncEnumerable` that yields `ActivityExecution` entries. This API
returns **only Standalone Activity Executions** — Activities running inside Workflows are not
included.
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

The query parameter uses the same List Filter syntax as Workflow visibility — for example,
`"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:388 -->

## Count Standalone Activities

Use `client.CountActivitiesAsync()` with a List Filter query to count Standalone Activity
Executions. It returns a response whose `.Count` is the total count of executions (running,
completed, failed, etc.) — not the number of queued tasks.
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

## CLI parity

The Temporal CLI exposes equivalent operations for Standalone Activities. None of these subcommands
takes `--workflow-id` for Standalone Activities.

### Execute (start and wait)

```bash
temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:263 -->

### Start (without waiting)

```bash
temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:310 -->

### Wait for a result by Activity ID

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:345 -->

### List

```bash
temporal activity list
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:384 -->

### Count

```bash
temporal activity count
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:422 -->

## Connect via environment config (and Temporal Cloud)

All samples on this page use
[`ClientEnvConfig.LoadClientConnectOptions()`](https://dotnet.temporal.io/api/Temporalio.Common.EnvConfig.ClientEnvConfig.html)
to configure the Temporal Client connection. It responds to environment variables and TOML
configuration files, so the same code works against a local dev server and Temporal Cloud without
changes.
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:91 -->
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:428 -->

### Connect with mTLS

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:440 -->

### Connect with an API key

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:451 -->

[List Filter]: https://docs.temporal.io/list-filter
