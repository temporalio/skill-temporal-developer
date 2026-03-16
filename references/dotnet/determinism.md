# .NET SDK Determinism

## Overview

The .NET SDK has **no sandbox** for workflow code. Determinism is enforced through developer discipline, runtime task detection via an `EventListener`, and safe API alternatives provided by the SDK.

## Why Determinism Matters: History Replay

Temporal provides durable execution through **History Replay**. When a Worker needs to restore workflow state (after a crash, cache eviction, or to continue after a long timer), it re-executes the workflow code from the beginning, which requires the workflow code to be **deterministic**.

## SDK Protection

The .NET SDK uses a custom `TaskScheduler` to order workflow tasks deterministically. It also enables a runtime `EventListener` that detects when workflow code accidentally uses the default scheduler. When detected, an `InvalidWorkflowOperationException` is thrown, which "pauses" the workflow (fails the workflow task) until the code is fixed.

This is a **runtime-only** check — there is no compile-time sandbox. See `references/dotnet/determinism-protection.md` for details.

## Forbidden Operations

```csharp
// DO NOT do these in workflows:
await Task.Run(() => { });              // Uses default scheduler
await Task.Delay(TimeSpan.FromSeconds(1)); // System timer
var now = DateTime.UtcNow;              // System clock
var r = new Random().Next();            // Non-deterministic
var id = Guid.NewGuid();               // Non-deterministic
File.ReadAllText("file.txt");           // I/O
await httpClient.GetAsync("...");       // Network I/O
```

Most non-determinism and side effects should be wrapped in Activities.

## Safe Builtin Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `DateTime.Now` / `DateTime.UtcNow` | `Workflow.UtcNow` |
| `Random` | `Workflow.Random` |
| `Guid.NewGuid()` | `Workflow.NewGuid()` |
| `Task.Delay` | `Workflow.DelayAsync` |
| `Thread.Sleep` | `Workflow.DelayAsync` |
| `Task.Run` | `Workflow.RunTaskAsync` |
| `Task.WhenAll` | `Workflow.WhenAllAsync` |
| `Task.WhenAny` | `Workflow.WhenAnyAsync` |
| `System.Threading.Mutex` | `Temporalio.Workflows.Mutex` |
| `System.Threading.Semaphore` | `Temporalio.Workflows.Semaphore` |
| `CancellationTokenSource.CancelAsync` | `CancellationTokenSource.Cancel` |

## Testing Replay Compatibility

Use `WorkflowReplayer` to verify your code changes are compatible with existing histories. See the Workflow Replay Testing section of `references/dotnet/testing.md`.

## Best Practices

1. Use `Workflow.UtcNow` for all time operations
2. Use `Workflow.Random` for random values
3. Use `Workflow.NewGuid()` for unique identifiers
4. Use `Workflow.DelayAsync` instead of `Task.Delay`
5. Use `Workflow.WhenAllAsync` / `Workflow.WhenAnyAsync` for task combinators
6. Never use `ConfigureAwait(false)` in workflows
7. Use `SortedDictionary` or sort before iterating collections
8. Test with replay to catch non-determinism
9. Keep workflows focused on orchestration, delegate I/O to activities
10. Use `Workflow.Logger` for replay-safe logging
