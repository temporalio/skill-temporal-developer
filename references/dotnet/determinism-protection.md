# .NET Determinism Protection

## Overview

Unlike Python (module restriction sandbox) and TypeScript (V8 isolate sandbox), the .NET SDK has **no sandbox**. Instead, it relies on:
1. A custom `TaskScheduler` to order workflow tasks deterministically
2. A runtime `EventListener` that detects invalid task scheduling
3. Developer discipline to avoid non-deterministic operations

## Runtime Task Detection

By default, the .NET SDK enables an `EventListener` that monitors task events. When workflow code accidentally starts a task on the wrong scheduler (e.g., via `Task.Run`), an `InvalidWorkflowOperationException` is thrown. This "pauses" the workflow by failing the workflow task, which continually retries until the code is fixed.

```csharp
// This will be detected at runtime and fail the workflow task
[Workflow]
public class BadWorkflow
{
    [WorkflowRun]
    public async Task RunAsync()
    {
        // BAD: Task.Run uses TaskScheduler.Default
        await Task.Run(() => DoSomething());
    }
}
```

To disable this detection (not recommended):
```csharp
var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
    {
        DisableWorkflowTracingEventListener = true,
    }
    .AddWorkflow<MyWorkflow>());
```

## .NET Task Determinism Rules

Many .NET `Task` APIs implicitly use `TaskScheduler.Default`, which breaks determinism. Here are the key rules:

**Do NOT use:**
- `Task.Run` — uses default scheduler. Use `Workflow.RunTaskAsync`.
- `Task.ConfigureAwait(false)` — leaves current context. Use `ConfigureAwait(true)` or omit.
- `Task.Delay` / `Task.Wait` / timeout-based `CancellationTokenSource` — uses system timers. Use `Workflow.DelayAsync` / `Workflow.WaitConditionAsync`.
- `Task.WhenAny` — use `Workflow.WhenAnyAsync`.
- `Task.WhenAll` — use `Workflow.WhenAllAsync` (technically safe currently, but wrapper is recommended).
- `CancellationTokenSource.CancelAsync` — use `CancellationTokenSource.Cancel`.
- `System.Threading.Semaphore` / `SemaphoreSlim` / `Mutex` — use `Temporalio.Workflows.Semaphore` / `Mutex`.

**Be wary of:**
- Third-party libraries that implicitly use `TaskScheduler.Default`
- `Dataflow` blocks and similar concurrency libraries with hidden default scheduler usage

## Workflow .editorconfig

Since workflows violate some standard .NET analyzer rules, consider an `.editorconfig` for workflow project files:

```ini
# Workflow-specific analyzer settings
[*.cs]
# Allow async methods without await (some workflow methods are simple)
dotnet_diagnostic.CS1998.severity = none
# Allow getter/setter patterns needed for signal/query attributes
dotnet_diagnostic.CA1024.severity = none
```

## Best Practices

1. **Always use `Workflow.*` alternatives** for Task operations in workflows
2. **Enable the `EventListener`** (default) — it catches mistakes at runtime
3. **Separate workflow and activity code** into different files/projects for clarity
4. **Use `SortedDictionary`** or sort collections before iterating — `Dictionary<TKey, TValue>` iteration order is not guaranteed
5. **Test with replay** to catch non-determinism early
6. **Review third-party library usage** in workflow code for hidden default scheduler usage
