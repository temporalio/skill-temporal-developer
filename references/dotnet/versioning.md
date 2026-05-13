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
[Workflow]
public class OrderWorkflow
{
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
}
```

**Step 2: Deprecate the Patch**

Once all pre-patch Workflow Executions have completed:

```csharp
[Workflow]
public class OrderWorkflow
{
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
}
```

**Step 3: Remove the Patch**

After all workflows with the deprecated patch marker have completed, remove the `DeprecatePatch()` call entirely:

```csharp
[Workflow]
public class OrderWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(Order order)
    {
        await Workflow.ExecuteActivityAsync(
            (OrderActivities a) => a.CheckFraudAsync(order),
            new() { StartToCloseTimeout = TimeSpan.FromMinutes(2) });

        return await Workflow.ExecuteActivityAsync(
            (OrderActivities a) => a.ProcessPaymentAsync(order),
            new() { StartToCloseTimeout = TimeSpan.FromMinutes(5) });
    }
}
```

### Query Filters for Finding Workflows by Version

Use List Filters to find workflows with specific patch versions:

```bash
# Find running workflows with a specific patch
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "add-fraud-check"'

# Find running workflows without any patch (pre-patch versions)
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL'
```

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

Update client code to start new workflows with the new type:

```csharp
// Old workflows continue on PizzaWorkflow
// New workflows use PizzaWorkflowV2
var handle = await client.StartWorkflowAsync(
    (PizzaWorkflowV2 wf) => wf.RunAsync(order),
    new(id: $"pizza-{order.Id}", taskQueue: "pizza-task-queue"));
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "loan-processor"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., "loan-processor:v1.0" or "loan-processor:abc123").

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

**Configuration parameters:**

- `UseWorkerVersioning`: Enables Worker Versioning
- `DeploymentOptions`: Identifies the Worker Deployment Version (deployment name + build ID)
- Build ID: Typically a git commit hash, version number, or timestamp

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED Behavior**

Workflows stay locked to their original Worker version:

```csharp
[Workflow(VersioningBehavior = VersioningBehavior.Pinned)]
public class StableWorkflow { /* ... */ }
```

**When to use PINNED:**

- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions:

```csharp
[Workflow(VersioningBehavior = VersioningBehavior.AutoUpgrade)]
public class UpgradableWorkflow { /* ... */ }
```

**When to use AUTO_UPGRADE:**

- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using patching APIs for version transitions

**Important:** AUTO_UPGRADE workflows still need patching to handle version transitions safely since they can move between Worker versions.

### Worker Configuration with Default Behavior

```csharp
var worker = new TemporalWorker(
    client,
    new TemporalWorkerOptions("my-task-queue")
    {
        DeploymentOptions = new WorkerDeploymentOptions(
            DeploymentName: "order-service",
            BuildId: Environment.GetEnvironmentVariable("BUILD_ID") ?? "dev")
        {
            DefaultVersioningBehavior = VersioningBehavior.Pinned,
        },
        UseWorkerVersioning = true,
    }
    .AddWorkflow<OrderWorkflow>()
    .AddAllActivities(new OrderActivities()));
```

### Deployment Strategies

**Blue-Green Deployments**

Maintain two environments and switch traffic between them:

1. Deploy new code to idle environment
2. Run tests and validation
3. Switch traffic to new environment
4. Keep old environment for instant rollback

**Rainbow Deployments**

Multiple versions run simultaneously:

- New workflows use latest version
- Existing workflows complete on their original version
- Add new versions alongside existing ones
- Gradually sunset old versions as workflows complete

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive patch IDs** that explain the change (e.g., "add-fraud-check" not "patch-1")
3. **Deploy patches incrementally**: patch, deprecate, remove
4. **Use PINNED for short workflows** to simplify version management
5. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
6. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
7. **Avoid rolling deployments** for high-availability services with long-running workflows

## Upgrade on Continue-as-New (.NET)

Long-running Pinned Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) can adopt newer Worker Deployment Versions at Continue-as-New boundaries without requiring patching.

This feature is in Public Preview as an experimental SDK-level option, so treat APIs and identifiers as subject to change and consult your SDK's release notes for the current .NET names.

### When to use it

Use upgrade on Continue-as-New for `PINNED` Workflows that already use Continue-as-New and are expected to outlive your Deployment Versions, for example long-running Customer entity Workflows or AI agent / Chatbot Workflows with long sleeps.

If your Workflow does not use Continue-as-New, this pattern does not apply; choose `AUTO_UPGRADE` + patching instead.

### How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New.  When you opt in to the upgrade behavior on a specific Continue-as-New call, the mechanic is:

1. Each Workflow run remains pinned to its Version, so no patching is needed inside a run.
2. The Temporal Server informs the Workflow when a new Target Worker Deployment Version becomes available.
3. When the Workflow then performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

### Detecting that a new Target Version is available

The Workflow detects an available Target Version through a Workflow-info flag conceptually named `target_worker_deployment_version_changed`.

This flag is refreshed after each Workflow Task completes, so it is not a one-shot sticky boolean — its value reflects the most recent Workflow Task.  A Workflow that is regularly performing non-sleep Workflow Tasks will see the updated value naturally; a Workflow that is idle (for example, sleeping for a long time) will not.

Reasonable places to check the flag in your Workflow code include:

- Periodically between units of work
- Before accepting an Update
- Before starting an Activity or Child Workflow

### Opting in on a specific Continue-as-New call

The opt-in is **per Continue-as-New call**, not a Worker-level toggle. When the flag indicates a new Target Version is available, the Workflow issues a Continue-as-New configured with an option that makes the new run start with `AUTO_UPGRADE` behavior so it adopts the Target Version of its Worker Deployment.

The Temporal docs currently illustrate this opt-in only in the Go SDK; the .NET SDK exposes equivalent functionality, but the docs do not name the exact .NET identifiers for the flag accessor, the Continue-as-New error / options type, or the initial-versioning-behavior enum value.  Consult the .NET SDK release notes and API reference for the current names, and use the Go example in `references/go/versioning.md` as the canonical shape of the pattern (flag check, then Continue-as-New with an `AUTO_UPGRADE` initial versioning behavior).

### Limitations

- **Lazy moving only.** Workflows learn about a new Target Version only when they execute a Workflow Task. Sleeping or otherwise idle Workflows are not proactively notified; to nudge them, send a Signal so they wake up and re-check the flag.
- **Input compatibility across versions.** When continuing as new into a different Version, the Workflow input emitted by the previous Version's definition must be compatible with the new Version's definition. If the inputs are incompatible, the new run may fail on its first Workflow Task.

### See also

Conceptual treatment in `references/core/versioning.md` §Upgrade on Continue-as-New. Canonical worked example (Go) in `references/go/versioning.md`.
