# .NET: Standalone Activities

Standalone Activities run independently — without a Workflow orchestrating them. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:29 --> Instead of starting an Activity from inside a Workflow Definition, you start it directly from a Temporal Client. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:30 --> The way you author and register the Activity is identical to a Workflow Activity; only the invocation site differs. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:33 -->

For conceptual background, version compatibility, the full CLI inventory, and limitations, see `references/core/standalone-activities.md`.

## Prerequisites

- **.NET 8.0+** <!-- docs/develop/dotnet/activities/standalone-activities.mdx:60 -->
- **Temporal .NET SDK v1.12.0 or higher** <!-- docs/develop/dotnet/activities/standalone-activities.mdx:62 -->
- **Temporal CLI v1.7.0 or higher** <!-- docs/develop/dotnet/activities/standalone-activities.mdx:64 -->
- Release stage: **Public Preview** <!-- docs/develop/dotnet/activities/standalone-activities.mdx:24-25 -->

Start a local dev server with `temporal server start-dev`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:83 -->

## Define an Activity

An Activity is a method decorated with the `[Activity]` attribute. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:126 --> The same Activity definition can be executed both as a Standalone Activity and as a Workflow Activity. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:128 -->

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
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:132-145 -->

## Run a Worker

Worker setup for Standalone Activities is identical to Worker setup for Workflow Activities — the Worker doesn't need to know which invocation path will be used. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:149-152 -->

```csharp
using Microsoft.Extensions.Logging;
using Temporalio.Client;
using Temporalio.Common.EnvConfig;
using Temporalio.Worker;
using TemporalioSamples.StandaloneActivity;

var connectOptions = ClientEnvConfig.LoadClientConnectOptions(); // <!-- docs/develop/dotnet/activities/standalone-activities.mdx:164 -->
connectOptions.TargetHost ??= "localhost:7233";
var client = await TemporalClient.ConnectAsync(connectOptions); // <!-- docs/develop/dotnet/activities/standalone-activities.mdx:170 -->

const string taskQueue = "standalone-activity-sample";

using var tokenSource = new CancellationTokenSource();

using var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions(taskQueue).
        AddActivity(MyActivities.ComposeGreetingAsync)); // <!-- docs/develop/dotnet/activities/standalone-activities.mdx:181-184 -->

await worker.ExecuteAsync(tokenSource.Token); // <!-- docs/develop/dotnet/activities/standalone-activities.mdx:186 -->
```

## Execute a Standalone Activity

Use `client.ExecuteActivityAsync()` to enqueue a Standalone Activity and wait for the result. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:199-203 --> Call it from application code, not from inside a Workflow Definition. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:201-202 -->

You can pass the Activity as either a lambda expression (type-safe) or a string Activity type name. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:225 -->

```csharp
// Lambda expression (type-safe)
var result = await client.ExecuteActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });

// String type name
var result = await client.ExecuteActivityAsync<string>(
    "ComposeGreeting",
    new object?[] { new ComposeGreetingInput("Hello", "World") },
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:227-244 -->

`StartActivityOptions` requires `Id`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:246-247 -->

## Start without waiting for the result

Use `client.StartActivityAsync()` to enqueue a Standalone Activity and get a handle back immediately. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:273-276 -->

```csharp
var handle = await client.StartActivityAsync(
    () => MyActivities.ComposeGreetingAsync(new ComposeGreetingInput("Hello", "World")),
    new("standalone-activity-id", "standalone-activity-sample")
    {
        ScheduleToCloseTimeout = TimeSpan.FromSeconds(10),
    });
Console.WriteLine($"Started activity: {handle.Id}");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:289-295 -->

## Get a handle to an existing Standalone Activity

Use `client.GetActivityHandle()` to create a handle to a previously started Standalone Activity. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:321 -->

```csharp
// Without a known result type
var handle = client.GetActivityHandle("my-activity-id", runId: "the-run-id");

// With a known result type
var typedHandle = client.GetActivityHandle<string>("my-activity-id", runId: "the-run-id");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:323-329 -->

You can use the handle to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:331 -->

## Wait for the result

Calling `client.ExecuteActivityAsync()` is equivalent to `client.StartActivityAsync()` followed by `await handle.GetResultAsync()`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:335-337 -->

```csharp
var result = await handle.GetResultAsync();
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:340 -->

## List Standalone Activities

Use `client.ListActivitiesAsync()` to list Standalone Activity Executions matching a List Filter query. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:351-354 --> The result is an `IAsyncEnumerable` that yields `ActivityExecution` entries. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:353-354 -->

**These APIs return only Standalone Activity Executions. Activities running inside Workflows are not included.** <!-- docs/develop/dotnet/activities/standalone-activities.mdx:356 -->

```csharp
await foreach (var info in client.ListActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'"))
{
    Console.WriteLine(
        $"ActivityID: {info.ActivityId}, Type: {info.ActivityType}, Status: {info.Status}");
}
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:368-373 -->

The query parameter accepts the same List Filter syntax used for Workflow Visibility — for example, `"ActivityType = 'ComposeGreeting' AND Status = 'Running'"`. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:388-389 -->

## Count Standalone Activities

Use `client.CountActivitiesAsync()` to count Standalone Activity Executions matching a List Filter query. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:393-396 --> This returns the total count of executions (running, completed, failed, etc.) — **not the number of queued tasks**. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:396-397 -->

```csharp
var resp = await client.CountActivitiesAsync(
    "TaskQueue = 'standalone-activity-sample'");
Console.WriteLine($"Total activities: {resp.Count}");
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:409-411 -->

## CLI equivalents

The Temporal CLI mirrors these client methods. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:261-270 -->

```bash
temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:264-270 -->

```bash
temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-sample \
  --schedule-to-close-timeout 10s \
  --input '{"Greeting": "Hello", "Name": "World"}'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:311-317 -->

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:346 -->

```bash
temporal activity list
temporal activity count
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:385,423 -->

## Temporal Cloud

The code samples on this page use `ClientEnvConfig.LoadClientConnectOptions()`, which responds to environment variables and TOML configuration files — so the same code works against a local dev server and Temporal Cloud without changes. <!-- docs/develop/dotnet/activities/standalone-activities.mdx:92-97 --> <!-- docs/develop/dotnet/activities/standalone-activities.mdx:428-430 -->

### Connect with mTLS

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:441-445 -->

### Connect with an API key

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/dotnet/activities/standalone-activities.mdx:452-454 -->

## See also

- `references/core/standalone-activities.md` — concepts, version compatibility, CLI inventory, and limitations (including operations that do **not** apply to Standalone Activities).
