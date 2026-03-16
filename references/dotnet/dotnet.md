# Temporal .NET SDK Reference

## Overview

The Temporal .NET SDK provides a high-performance, type-safe approach to building durable workflows using C# and .NET. Workflows use attributes (`[Workflow]`, `[WorkflowRun]`) and lambda expressions for type-safe invocations. .NET 6.0+ required.

**CRITICAL**: The .NET SDK has **no sandbox**. Developers must be careful to avoid non-deterministic code in workflows. See the Determinism Rules section below and `references/dotnet/determinism.md`.

## Understanding Replay

Temporal workflows are durable through history replay. For details on how this works, see `references/core/determinism.md`.

## Quick Start

**Add Dependency:** Install the Temporal SDK NuGet package:
```bash
dotnet add package Temporalio
```

**Activities.cs** - Activity definitions (separate file for clarity):
```csharp
using Temporalio.Activities;

public class MyActivities
{
    [Activity]
    public string Greet(string name)
    {
        return $"Hello, {name}!";
    }
}
```

**GreetingWorkflow.cs** - Workflow definition:
```csharp
using Temporalio.Workflows;

[Workflow]
public class GreetingWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(string name)
    {
        return await Workflow.ExecuteActivityAsync(
            (MyActivities a) => a.Greet(name),
            new() { StartToCloseTimeout = TimeSpan.FromSeconds(30) });
    }
}
```

**Worker (Program.cs)** - Worker setup:
```csharp
using Temporalio.Client;
using Temporalio.Worker;

var client = await TemporalClient.ConnectAsync(new("localhost:7233"));

using var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
        .AddWorkflow<GreetingWorkflow>()
        .AddAllActivities(new MyActivities()));

await worker.ExecuteAsync();
```

**Start the dev server:** Start `temporal server start-dev` in the background.

**Start the worker:** Run `dotnet run` in the worker project.

**Starter (Program.cs)** - Start a workflow execution:
```csharp
using Temporalio.Client;

var client = await TemporalClient.ConnectAsync(new("localhost:7233"));

var result = await client.ExecuteWorkflowAsync(
    (GreetingWorkflow wf) => wf.RunAsync("my name"),
    new(id: $"greeting-{Guid.NewGuid()}", taskQueue: "my-task-queue"));

Console.WriteLine($"Result: {result}");
```

**Run the workflow:** Run `dotnet run` in the starter project. Should output: `Result: Hello, my name!`.

## Key Concepts

### Workflow Definition
- Use `[Workflow]` attribute on class
- Use `[WorkflowRun]` on the async entry point method
- Must return `Task` or `Task<T>`
- Use `[WorkflowSignal]`, `[WorkflowQuery]`, `[WorkflowUpdate]` for handlers

### Activity Definition
- Use `[Activity]` attribute on methods
- Can be sync or async
- Instance methods support dependency injection
- Static methods are also supported

### Worker Setup
- Connect client, create `TemporalWorker` with workflows and activities
- Use `AddWorkflow<T>()` and `AddAllActivities(instance)` or `AddActivity(method)`

### Determinism

**Workflow code must be deterministic!** The .NET SDK has no sandbox. See the Determinism Rules section below and `references/core/determinism.md` and `references/dotnet/determinism.md`.

## File Organization Best Practice

**Keep Workflow definitions in separate files from Activity definitions.** While not as critical as Python (no sandbox reloading), separation improves clarity and testability.

```
MyTemporalApp/
├── Workflows/
│   └── GreetingWorkflow.cs    # Only Workflow classes
├── Activities/
│   └── TranslateActivities.cs # Only Activity classes
├── Models/
│   └── OrderInput.cs          # Shared data models
├── Worker/
│   └── Program.cs             # Worker setup
└── Starter/
    └── Program.cs             # Client code to start workflows
```

## Determinism Rules

The .NET SDK has **no sandbox** like Python or TypeScript. Developers must avoid non-deterministic operations manually.

**Do NOT use in workflows:**
- `Task.Run` — use `Workflow.RunTaskAsync`
- `Task.Delay` / `Thread.Sleep` — use `Workflow.DelayAsync`
- `Task.WhenAny` — use `Workflow.WhenAnyAsync`
- `Task.WhenAll` — use `Workflow.WhenAllAsync`
- `ConfigureAwait(false)` — use `ConfigureAwait(true)` or omit
- `DateTime.Now` / `DateTime.UtcNow` — use `Workflow.UtcNow`
- `Random` — use `Workflow.Random`
- `Guid.NewGuid()` — use `Workflow.NewGuid()`
- `System.Threading.Mutex` / `Semaphore` — use `Temporalio.Workflows.Mutex` / `Semaphore`
- Iterating `Dictionary<TKey, TValue>` (unordered) — use `SortedDictionary` or sort first

See `references/dotnet/determinism.md` and `references/dotnet/determinism-protection.md` for detailed rules.

## Common Pitfalls

1. **Using `Task.Run` in workflows** — Uses default scheduler, breaks determinism. Use `Workflow.RunTaskAsync`.
2. **Using `Task.Delay` in workflows** — Uses system timer. Use `Workflow.DelayAsync`.
3. **`ConfigureAwait(false)` in workflows** — Leaves the deterministic scheduler. Never use in workflows.
4. **Non-`ApplicationFailureException` in workflows** — Other exceptions retry the workflow task forever instead of failing the workflow.
5. **Dictionary iteration in workflows** — `Dictionary<TKey, TValue>` has no guaranteed order. Use `SortedDictionary`.
6. **Forgetting to heartbeat** — Long-running activities need `ActivityExecutionContext.Current.Heartbeat()` calls.
7. **Using `CancellationTokenSource.CancelAsync`** — Use `CancellationTokenSource.Cancel` instead.
8. **Logging with `Console.WriteLine` in workflows** — Use `Workflow.Logger` for replay-safe logging.

## Writing Tests

See `references/dotnet/testing.md` for info on writing tests.

## Additional Resources

### Reference Files
- **`references/dotnet/patterns.md`** — Signals, queries, child workflows, saga pattern, etc.
- **`references/dotnet/determinism.md`** — Essentials of determinism in .NET
- **`references/dotnet/gotchas.md`** — .NET-specific mistakes and anti-patterns
- **`references/dotnet/error-handling.md`** — ApplicationFailureException, retry policies, non-retryable errors
- **`references/dotnet/observability.md`** — Logging, metrics, tracing
- **`references/dotnet/testing.md`** — WorkflowEnvironment, time-skipping, activity mocking
- **`references/dotnet/advanced-features.md`** — Schedules, worker tuning, dependency injection
- **`references/dotnet/data-handling.md`** — Data converters, payload encryption, etc.
- **`references/dotnet/versioning.md`** — Patching API, workflow type versioning, Worker Versioning
- **`references/dotnet/determinism-protection.md`** — Runtime task detection, .NET Task determinism rules
