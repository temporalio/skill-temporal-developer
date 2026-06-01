> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are Activities run independently of any Workflow, started directly from a Temporal Client — useful when you need a single durable, retryable task (job-queue style) and not multi-step orchestration. See the [cross-SDK concept page](references/core/standalone-activities.md). The same Activity method can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.

Standalone Activities are conceptually the same across all SDKs. Read the [cross-SDK concept file](references/core/standalone-activities.md) if you have not already, and then see below for the .NET SDK specific APIs for calling Standalone Activities.

## Hard guardrail — do not call from inside a Workflow

Don't call `client.ExecuteActivityAsync` / `client.StartActivityAsync` or any other Standalone Activity APIs from inside a Workflow Definition — use Workflow-side activity invocation (`Workflow.ExecuteActivityAsync`) instead.

## Prerequisites

- Temporal .NET SDK v1.12.0 or higher.
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](references/core/install_cli.md) if needed. Dev server includes Standalone Activities support.
- For production, Temporal Server v1.31.0 or higher (or Temporal Cloud).

## Define the Activity

An Activity is a method decorated with `[Activity]`; nothing about Standalone Activities changes how you write or register it.

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

## Worker setup

Worker registration is identical to a Workflow-Activity worker — create a `TemporalWorker`, register the Activity, run the Worker.

```csharp
using var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions(taskQueue).
        AddActivity(MyActivities.ComposeGreetingAsync));

await worker.ExecuteAsync(tokenSource.Token);
```

## Execute (wait for result)

Use `client.ExecuteActivityAsync(...)` to durably enqueue the Activity, wait for it to run on a Worker, and return the result.

Lambda form (type-safe):

```csharp
var result = await client.ExecuteActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
```

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

## `StartActivityOptions` requirements

`StartActivityOptions` requires `Id`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`.  This is a hard constraint — there is no workaround; you must supply all three.

The options type is `Temporalio.Client.StartActivityOptions`.

## Start (do not wait)

Use `client.StartActivityAsync(...)` to enqueue the Activity and get a handle back without blocking on the result.

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

## Get an existing handle

Use `client.GetActivityHandle(...)` to rebind a handle to a previously started Standalone Activity.

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```

The handle can be used to wait for the result, describe, cancel, or terminate the Activity.

## Await result later

Calling `client.ExecuteActivityAsync()` is equivalent to `client.StartActivityAsync()` followed by `await handle.GetResultAsync()`.

```csharp
var result = await handle.GetResultAsync();
```

## List

Use `client.ListActivitiesAsync(query)` — it returns an `IAsyncEnumerable<ActivityExecution>`.  Only Standalone Activity Executions are returned; Activities running inside Workflows are not included.

```csharp
await foreach (var info in client.ListActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'"))
{
    Console.WriteLine(
        $"ActivityID: {info.ActivityId}, Type: {info.ActivityType}, Status: {info.Status}");
}
```

The `query` argument uses [List Filter](/list-filter) syntax — e.g. `"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`.

## Count

Use `client.CountActivitiesAsync(query)`; the response exposes `Count` (total executions matching the filter — running, completed, failed, etc.; not queued tasks).

```csharp
var resp = await client.CountActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'");
Console.WriteLine($"Total activities: {resp.Count}");
```