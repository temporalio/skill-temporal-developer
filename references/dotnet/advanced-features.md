# .NET SDK Advanced Features

## Schedules

Create recurring workflow executions.

```csharp
using Temporalio.Client.Schedules;

var scheduleId = "daily-report";
await client.CreateScheduleAsync(
    scheduleId,
    new Schedule(
        action: ScheduleActionStartWorkflow.Create(
            (DailyReportWorkflow wf) => wf.RunAsync(),
            new(id: "daily-report", taskQueue: "reports")),
        spec: new ScheduleSpec
        {
            Intervals = new List<ScheduleIntervalSpec>
            {
                new(Every: TimeSpan.FromDays(1)),
            },
        }));

// Manage schedules
var handle = client.GetScheduleHandle(scheduleId);
await handle.PauseAsync("Maintenance window");
await handle.UnpauseAsync();
await handle.TriggerAsync(); // Run immediately
await handle.DeleteAsync();
```

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks).

**Note:** If the external system can reliably Signal back with the result, consider using **signals** instead.

```csharp
using Temporalio.Activities;
using Temporalio.Client;

[Activity]
public async Task RequestApprovalAsync(string requestId)
{
    var taskToken = ActivityExecutionContext.Current.Info.TaskToken;

    // Store task token for later completion (e.g., in database)
    await StoreTaskTokenAsync(requestId, taskToken);

    // Mark this activity as waiting for external completion
    throw new CompleteAsyncException();
}

// Later, complete the activity from another process
public async Task CompleteApprovalAsync(string requestId, bool approved)
{
    var client = await TemporalClient.ConnectAsync(new("localhost:7233"));
    var taskToken = await GetTaskTokenAsync(requestId);

    var handle = client.GetAsyncActivityHandle(taskToken);

    if (approved)
        await handle.CompleteAsync("approved");
    else
        await handle.FailAsync(new ApplicationFailureException("Rejected"));
}
```

## Worker Tuning

Configure worker performance settings.

```csharp
var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
    {
        // Workflow task concurrency
        MaxConcurrentWorkflowTasks = 100,
        // Activity task concurrency
        MaxConcurrentActivities = 100,
        // Graceful shutdown timeout
        GracefulShutdownTimeout = TimeSpan.FromSeconds(30),
    }
    .AddWorkflow<MyWorkflow>()
    .AddAllActivities(new MyActivities()));
```

## Workflow Failure Exception Types

Control which exceptions cause workflow failures vs workflow task retries.

**Default behavior:** Only `ApplicationFailureException` fails a workflow. All other exceptions retry the workflow task forever (treated as bugs to fix with a code deployment).

**Tip for testing:** Set `WorkflowFailureExceptionTypes` to include `Exception` so any unhandled exception fails the workflow immediately rather than retrying the workflow task forever. This surfaces bugs faster.

### Worker-Level Configuration

```csharp
var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
    {
        // These exception types will fail the workflow execution (not just the task)
        WorkflowFailureExceptionTypes = new[] { typeof(ArgumentException), typeof(InvalidOperationException) },
    }
    .AddWorkflow<MyWorkflow>()
    .AddAllActivities(new MyActivities()));
```

## Dependency Injection

The .NET SDK supports dependency injection via the `Temporalio.Extensions.Hosting` package, which integrates with .NET's generic host.

### Worker as Generic Host

```csharp
using Temporalio.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddTemporalClient(options =>
{
    options.TargetHost = "localhost:7233";
    options.Namespace = "default";
});

builder.Services.AddHostedTemporalWorker("my-task-queue")
    .AddWorkflow<MyWorkflow>()
    .AddScopedActivities<MyActivities>();

var host = builder.Build();
await host.RunAsync();
```

### Activity Dependency Injection

Activities registered with `AddScopedActivities<T>()` or `AddSingletonActivities<T>()` are created via DI, allowing constructor injection:

```csharp
public class MyActivities
{
    private readonly ILogger<MyActivities> _logger;
    private readonly IOrderRepository _repository;

    public MyActivities(ILogger<MyActivities> logger, IOrderRepository repository)
    {
        _logger = logger;
        _repository = repository;
    }

    [Activity]
    public async Task<Order> GetOrderAsync(string orderId)
    {
        _logger.LogInformation("Fetching order {OrderId}", orderId);
        return await _repository.GetAsync(orderId);
    }
}
```

**Note:** Dependency injection is NOT available in workflows — workflows must be self-contained for determinism.
