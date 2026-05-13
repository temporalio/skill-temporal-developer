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

## Upgrading on Continue-as-New

Long-running Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) can move onto newer Worker
Deployment Versions at each Continue-as-New (CaN) boundary, without requiring patches in the per-run code. The Workflow
stays Pinned within a single run (so its event history replays deterministically on its original version) and only
"jumps" versions when it deliberately performs a CaN.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:530-533 — "Long-running Workflows that use Continue-as-New can upgrade to newer Worker Deployment Versions at Continue-as-New boundaries without requiring patching." -->

This feature is in **Public Preview** as an experimental SDK-level option, so the exact API surface may evolve.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 — ":::note Public Preview ... This feature is in Public Preview as an experimental SDK-level option." -->

### When to use it

This pattern is ideal for:

- **Entity Workflows** that run for months or years
- **Batch processing** Workflows that checkpoint with Continue-as-New
- **AI agent Workflows** with long sleeps waiting for user input

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:535-540 — "This pattern is ideal for: Entity Workflows ... Batch processing ... AI agent Workflows with long sleeps waiting for user input" -->

### Decision logic

The Decision Guide pairs Workflow duration and CaN usage with a recommended behavior:

- **Long-running + uses CaN** → `PINNED` plus upgrade-on-CaN; **no patching** is required because each run stays Pinned and only the next run inherits the newer Target Version.
- **Long-running + does not use CaN** → `AUTO_UPGRADE` plus patching; the run itself migrates across versions and must use the Patching API to stay deterministic.
- **Short** → `PINNED` (completes before next deploy, never needs patching).
- **Medium + no CaN** → `AUTO_UPGRADE` with patching.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:261-266 — Decision Guide table mapping (Long, Yes CaN) → "PINNED + upgrade on CaN, Never" and (Long, No CaN) → "AUTO_UPGRADE + patching, Yes" -->

### How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the
upgrade option enabled:

1. Each Workflow run remains pinned to its original version, so no patching is needed for code that executes within a run.
2. The Temporal Server notifies the Workflow when a new [Target Version](/worker-versioning#versioning-definitions) becomes available for its Worker Deployment.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:548-555 — "1. Each Workflow run remains pinned to its version ... 2. The Temporal Server tells the workflow when a new Target Version becomes available ... 3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version" -->

### Detection is lazy

The "Target Version changed" signal is delivered only when a Workflow Task completes, so a Workflow that is sleeping or
otherwise idle will not notice a new Target Version on its own. If you have idle Workflows that you want to wake up to
check whether they should Continue-as-New onto a newer version, send them a Signal (or otherwise trigger a Workflow
Task) to force a refresh.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 — "Lazy moving only: Workflows must be invoked by executing a step to receive the Target-Version-Changed information. Sleeping Workflows won't be proactively get the Target-Version-Changed information. If you have idle workflows that you want to wake up ... you can send them a Signal." -->

### Input compatibility across versions

When a Workflow performs Continue-as-New onto a new version, the previous version's Workflow definition writes the
input that the new version's Workflow definition will receive. Make sure those inputs are compatible across versions:
if the new run's definition can't deserialize or accept the input shape produced by the old definition, the new run may
fail on its very first Workflow Task.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 — "Interface compatibility: When continuing as new to a different version, ensure your Workflow input provided by the previous version's workflow definition is compatible with the new version's workflow definition. If incompatible, the new run may fail on its first Workflow Task." -->

### Continue-as-New inheritance semantics

By default, the Continue-as-New chain of a Pinned Workflow inherits the Pinned version:

- When the original Workflow is **Pinned**, the Pinned version is inherited across the Continue-as-New chain. If the
  new run's Task Queue isn't in the same Worker Deployment as the original, no inheritance occurs and the new run
  starts on the Current Version of its Task Queue.
- When the original Workflow is **Auto-upgrade**, no version inheritance occurs at Continue-as-New.

Upgrade-on-CaN is the opt-in way for a Pinned chain to deliberately break that inheritance at a chosen boundary and
land the next run on the latest Target Version of the deployment.

<!-- Source: documentation/docs/encyclopedia/workers/worker-versioning.mdx:128-137 — "Continue-As-New ... When Original Workflow is Pinned: The Pinned version is inherited across the Continue-As-New chain ... When Original Workflow is Auto-upgrade: No version inheritance occurs" -->

### .NET API status

As of 2026-05, the Temporal documentation site documents the upgrade-on-CaN tokens (the "Target Version changed" check
on Workflow info, and the per-CaN "initial versioning behavior" option) with a worked example **only in Go**. The .NET
SDK names for these knobs are not yet captured in the docs that this skill is built from, so this section does not
include a C# code snippet for the feature.

For a concrete, end-to-end example of the polling-then-CaN-with-upgrade pattern, see the Go reference:
[`references/go/versioning.md` § Upgrading on Continue-as-New](../go/versioning.md#upgrading-on-continue-as-new). The
conceptual rules above (decision logic, lazy detection, input compatibility, CaN inheritance) apply identically to
.NET. For canonical product documentation, see the upstream guide:
[`docs/production-deployment/worker-deployments/worker-versioning.mdx`](/production-deployment/worker-deployments/worker-versioning#upgrade-on-continue-as-new).

When wiring this up in C#, use your standard .NET Continue-as-New entry point (throwing the exception created via
`Workflow.CreateContinueAsNewException`, as shown in the .NET Continue-as-New guide) and confirm the exact
upgrade-on-CaN option names against the .NET SDK source or release notes before merging.

<!-- VERIFY: .NET SDK token names for upgrade-on-CaN — docs only document Go as of 2026-05; consult .NET SDK source or release notes -->

