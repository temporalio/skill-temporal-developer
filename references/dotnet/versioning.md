# .NET SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## Patching API

### The Patched() Method

The `Workflow.Patched()` method checks whether a Workflow should run new or old code:

```csharp
[Workflow]
public class ShippingWorkflow
{
    [WorkflowRun]
    public async Task RunAsync()
    {
        if (Workflow.Patched("send-email-instead-of-fax"))
        {
            // New code path
            await Workflow.ExecuteActivityAsync(
                (ShippingActivities a) => a.SendEmailAsync(),
                new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });
        }
        else
        {
            // Old code path (for replay of existing workflows)
            await Workflow.ExecuteActivityAsync(
                (ShippingActivities a) => a.SendFaxAsync(),
                new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });
        }
    }
}
```

**How it works:**
- For new executions: `Patched()` returns `true` and records a marker in the Workflow history
- For replay with the marker: `Patched()` returns `true` (history includes this patch)
- For replay without the marker: `Patched()` returns `false` (history predates this patch)

### Three-Step Patching Process

**Warning:** Failing to follow this process correctly will result in non-determinism errors for in-flight workflows.

**Step 1: Patch in New Code**

```csharp
[WorkflowRun]
public async Task<string> RunAsync(Order order)
{
    if (Workflow.Patched("add-fraud-check"))
    {
        await Workflow.ExecuteActivityAsync(
            (OrderActivities a) => a.CheckFraudAsync(order),
            new() { StartToCloseTimeout = TimeSpan.FromMinutes(2) });
    }

    return await Workflow.ExecuteActivityAsync(
        (OrderActivities a) => a.ProcessPaymentAsync(order),
        new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });
}
```

**Step 2: Deprecate the Patch**

Once all pre-patch Workflow Executions have completed:

```csharp
[WorkflowRun]
public async Task<string> RunAsync(Order order)
{
    Workflow.DeprecatePatch("add-fraud-check");

    await Workflow.ExecuteActivityAsync(
        (OrderActivities a) => a.CheckFraudAsync(order),
        new() { StartToCloseTimeout = TimeSpan.FromMinutes(2) });

    return await Workflow.ExecuteActivityAsync(
        (OrderActivities a) => a.ProcessPaymentAsync(order),
        new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });
}
```

**Step 3: Remove the Patch**

After all workflows with the deprecated patch marker have completed, remove the `DeprecatePatch()` call entirely.

## Workflow Type Versioning

For incompatible changes, create a new Workflow Type instead of using patches:

```csharp
[Workflow("PizzaWorkflow")]
public class PizzaWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(PizzaOrder order)
    {
        return await ProcessOrderV1Async(order);
    }
}

[Workflow("PizzaWorkflowV2")]
public class PizzaWorkflowV2
{
    [WorkflowRun]
    public async Task<string> RunAsync(PizzaOrder order)
    {
        return await ProcessOrderV2Async(order);
    }
}
```

Register both with the Worker:

```csharp
var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("pizza-task-queue")
        .AddWorkflow<PizzaWorkflow>()
        .AddWorkflow<PizzaWorkflowV2>()
        .AddAllActivities(new PizzaActivities()));
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Configuring Workers for Versioning

```csharp
using Temporalio.Worker;

var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
    {
        DeploymentOptions = new WorkerDeploymentOptions(
            DeploymentName: "my-service",
            BuildId: Environment.GetEnvironmentVariable("BUILD_ID") ?? "dev"),
        UseWorkerVersioning = true,
    }
    .AddWorkflow<MyWorkflow>()
    .AddAllActivities(new MyActivities()));
```

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED**: Workflows stay locked to their original Worker version.

```csharp
[Workflow(VersioningBehavior = VersioningBehavior.Pinned)]
public class StableWorkflow { /* ... */ }
```

**AUTO_UPGRADE**: Workflows can move to newer versions. Still needs patching for compatibility.

```csharp
[Workflow(VersioningBehavior = VersioningBehavior.AutoUpgrade)]
public class UpgradableWorkflow { /* ... */ }
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive patch IDs** that explain the change (e.g., "add-fraud-check" not "patch-1")
3. **Deploy patches incrementally**: patch, deprecate, remove
4. **Use PINNED for short workflows** to simplify version management
5. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
6. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
7. **Avoid rolling deployments** for high-availability services with long-running workflows
