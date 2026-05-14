> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

<!-- docs/develop/dotnet/activities/standalone-activities.mdx:24 -->

## Overview

Standalone Activities are Activities run independently of any Workflow, started directly from a Temporal Client — useful when you need a single durable, retryable task (job-queue style) and not multi-step orchestration. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:29 --> See the cross-SDK concept page at [/standalone-activity](/standalone-activity). <!-- docs/encyclopedia/activities/standalone-activity.mdx:6 --> The same Activity method can be executed both as a Standalone Activity and as a Workflow Activity with no code changes. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:128 -->

## Hard guardrail — do not call from inside a Workflow

Don't call `client.ExecuteActivityAsync` / `client.StartActivityAsync` from inside a Workflow Definition — use Workflow-side activity invocation (`Workflow.ExecuteActivityAsync`) instead. The docs explicitly say: "Call this from your application code, not from inside a Workflow Definition." <!-- docs/develop/dotnet/activities/standalone-activities.mdx:201 -->

## Prerequisites

- .NET 8.0+ <!-- docs/develop/dotnet/activities/standalone-activities.mdx:60 -->
- Temporal .NET SDK v1.12.0 or higher. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:62 -->
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](../core/install_cli.md). <!-- docs/develop/dotnet/activities/standalone-activities.mdx:64 -->
- Temporal Server v1.31.0 or higher (the Temporal Dev Server has Standalone Activities enabled by default). <!-- docs/encyclopedia/activities/standalone-activity.mdx:115 --> <!-- docs/encyclopedia/activities/standalone-activity.mdx:139 -->

Start a local dev server with `temporal server start-dev`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:83 -->

## Define the Activity

An Activity is a method decorated with `[Activity]`; nothing about Standalone Activities changes how you write or register it. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:126 -->

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

## Worker setup

Worker registration is identical to a Workflow-Activity worker — create a `TemporalWorker`, register the Activity, run the Worker. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:149 -->

```csharp
using var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions(taskQueue).
        AddActivity(MyActivities.ComposeGreetingAsync));

await worker.ExecuteAsync(tokenSource.Token);
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:181 -->

## Execute (wait for result)

Use `client.ExecuteActivityAsync(...)` to durably enqueue the Activity, wait for it to run on a Worker, and return the result. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:200 -->

Lambda form (type-safe):

```csharp
var result = await client.ExecuteActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:229 -->

String-name form:

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

## `StartActivityOptions` requirements

`StartActivityOptions` requires `Id`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:246 --> This is a hard constraint — there is no workaround; you must supply all three.

The options type is `Temporalio.Client.StartActivityOptions`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:248 -->

## Start (do not wait)

Use `client.StartActivityAsync(...)` to enqueue the Activity and get a handle back without blocking on the result. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:275 -->

```csharp
var handle = await client.StartActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });

// Wait for the result later
var result = await handle.GetResultAsync();
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:289 -->

## Get an existing handle

Use `client.GetActivityHandle(...)` to rebind a handle to a previously started Standalone Activity. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:321 -->

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:323 -->

The handle can be used to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:331 -->

## Await result later

Calling `client.ExecuteActivityAsync()` is equivalent to `client.StartActivityAsync()` followed by `await handle.GetResultAsync()`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:335 -->

```csharp
var result = await handle.GetResultAsync();
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:340 -->

## List

Use `client.ListActivitiesAsync(query)` — it returns an `IAsyncEnumerable<ActivityExecution>`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:352 --> Only Standalone Activity Executions are returned; Activities running inside Workflows are not included. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:356 -->

```csharp
await foreach (var info in client.ListActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'"))
{
    Console.WriteLine(
        $"ActivityID: {info.ActivityId}, Type: {info.ActivityType}, Status: {info.Status}");
}
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:368 -->

The `query` argument uses [List Filter](/list-filter) syntax — e.g. `"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:388 -->

## Count

Use `client.CountActivitiesAsync(query)`; the response exposes `Count` (total executions matching the filter — running, completed, failed, etc.; not queued tasks). <!-- docs/develop/dotnet/activities/standalone-activities.mdx:394 -->

```csharp
var resp = await client.CountActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'");
Console.WriteLine($"Total activities: {resp.Count}");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:409 -->

## Temporal CLI mirror

The `temporal activity` subcommand mirrors the SDK operations. <!-- docs/encyclopedia/activities/standalone-activity.mdx:136 -->

Execute (wait for result):

```bash
temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:264 -->

Start (do not wait):

```bash
temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:311 -->

Wait for result by ID:

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:346 -->

List:

```bash
temporal activity list
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:385 -->

Count:

```bash
temporal activity count
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:423 -->

## Temporal Cloud

The same code runs against Temporal Cloud because `ClientEnvConfig.LoadClientConnectOptions()` reads environment variables and TOML profiles — no code changes needed. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:428 --> See the docs' "Connect with mTLS" and "Connect with an API key" env-var blocks for the exact `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, and `TEMPORAL_API_KEY` variables to set. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:436 --> <!-- docs/develop/dotnet/activities/standalone-activities.mdx:448 -->

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview. <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->

## Activity context inside a Standalone Activity

<!-- VERIFY: Which `Temporalio.Activities.ActivityExecutionContext` / `ActivityInfo` fields, and which `Temporalio.Converters.IPayloadConverter` / data-converter context fields, change nullability when the Activity runs as a Standalone Activity (no parent Workflow)? Docs are silent in `docs/encyclopedia/activities/standalone-activity.mdx` and `docs/develop/dotnet/activities/standalone-activities.mdx` as of this authoring pass. -->
