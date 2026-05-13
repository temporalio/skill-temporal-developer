# Go SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## GetVersion API

`workflow.GetVersion` safely performs backwards-incompatible changes to Workflow Definitions. It returns the version to branch on, recording the result as a marker in the Event History.

```go
v := workflow.GetVersion(ctx, "changeID", workflow.DefaultVersion, maxSupported)
```

- `changeID`: unique string identifying the change
- `minSupported`: oldest version still supported (`workflow.DefaultVersion` is `-1`)
- `maxSupported`: current/newest version
- Returns `maxSupported` for new executions; returns the recorded version on replay

### Three-Step Lifecycle

**Step 1: Add GetVersion with both code paths**

Original code calls `ActivityA`. You want to replace it with `ActivityC`:

```go
v := workflow.GetVersion(ctx, "Step1", workflow.DefaultVersion, 1)
if v == workflow.DefaultVersion {
	// Old code path (for replay of existing workflows)
	err = workflow.ExecuteActivity(ctx, ActivityA, data).Get(ctx, &result1)
} else {
	// New code path
	err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
}
```

For new executions, `GetVersion` returns `1` and records a marker. For replay of pre-change workflows (no marker), it returns `DefaultVersion` (`-1`).

**Step 2: Remove old branch (increase minSupported)**

After all `DefaultVersion` Workflow Executions have completed:

```go
v := workflow.GetVersion(ctx, "Step1", 1, 1)
// Only the new code path remains
err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
```

Keep the `GetVersion` call even with a single branch. This ensures:

1. If an older execution replays on this code, it fails fast instead of proceeding incorrectly
2. If you need further changes, you just bump `maxSupported`

**Step 3: Further changes (bump maxSupported)**

Later, replace `ActivityC` with `ActivityD`:

```go
v := workflow.GetVersion(ctx, "Step1", 1, 2)
if v == 1 {
	err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
} else {
	err = workflow.ExecuteActivity(ctx, ActivityD, data).Get(ctx, &result1)
}
```

After all version-1 executions complete, collapse again:

```go
_ = workflow.GetVersion(ctx, "Step1", 2, 2)
err = workflow.ExecuteActivity(ctx, ActivityD, data).Get(ctx, &result1)
```

### Using GetVersion in Loops

The return value for a given `changeID` is immutable once recorded. In loops, append the iteration number to the `changeID`:

```go
for i := 0; i < 10; i++ {
	v := workflow.GetVersion(ctx, fmt.Sprintf("myChange-%d", i), workflow.DefaultVersion, 1)
	if v == workflow.DefaultVersion {
		// old path
	} else {
		// new path
	}
}
```

## Workflow Type Versioning

Create a new Workflow Type for incompatible changes:

```go
// Original
func MyWorkflow(ctx workflow.Context, input Input) (string, error) {
	// v1 implementation
}

// New version
func MyWorkflowV2(ctx workflow.Context, input Input) (string, error) {
	// v2 implementation
}
```

Register both with the Worker:

```go
w := worker.New(c, "my-task-queue", worker.Options{})
w.RegisterWorkflow(MyWorkflow)
w.RegisterWorkflow(MyWorkflowV2)
```

Route new executions to the new type. Old workflows continue on the old type. Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "MyWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "loan-processor"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., "loan-processor:v1.0" or "loan-processor:abc123").

### Configuring Workers for Versioning

```go
w := worker.New(c, "my-task-queue", worker.Options{
	DeploymentOptions: worker.DeploymentOptions{
		UseVersioning: true,
		Version: worker.WorkerDeploymentVersion{
			DeploymentName: "my-service",
			BuildId:        "v1.0.0", // or git commit hash
		},
		DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
	},
})
```

**Configuration fields:**

- `UseVersioning`: enables Worker Versioning
- `Version`: identifies the Worker Deployment Version (deployment name + build ID)
- `DefaultVersioningBehavior`: `VersioningBehaviorPinned` or `VersioningBehaviorAutoUpgrade`
- Build ID: typically a git commit hash, version number, or timestamp

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED Behavior**

Workflows stay locked to their original Worker version.

**When to use PINNED:**

- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions.

**When to use AUTO_UPGRADE:**

- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using GetVersion for version transitions

**Important:** AUTO_UPGRADE workflows still need GetVersion to handle version transitions safely since they can move between Worker versions.

### Worker Configuration with Default Behavior

```go
// For short-running workflows, prefer PINNED
w := worker.New(c, "orders-task-queue", worker.Options{
	DeploymentOptions: worker.DeploymentOptions{
		UseVersioning: true,
		Version: worker.WorkerDeploymentVersion{
			DeploymentName: "order-service",
			BuildId:        os.Getenv("BUILD_ID"),
		},
		DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
	},
})
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

This works well with Kubernetes where you manage multiple ReplicaSets running different Worker versions.

Deploy a new version, then set it as current:

```bash
temporal worker deployment set-current-version \
  --deployment-name my-service \
  --build-id v2.0.0
```

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Best Practices

1. **Keep GetVersion calls** even when only a single branch remains -- it guards against stale replays and simplifies future changes
2. **Use `TemporalChangeVersion` search attribute** to find Workflows running on old versions:
   ```bash
   temporal workflow list --query \
     'WorkflowType = "MyWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "Step1"'
   ```
3. **Test with replay** before removing old branches to verify determinism is preserved
4. **Prefer Worker Versioning** for large-scale deployments to avoid accumulating patching branches

## Upgrading on Continue-as-New

Long-running Pinned Workflows that already use Continue-as-New can upgrade to newer Worker Deployment Versions at the CaN boundary without requiring patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532 --> Each run stays pinned to its original version, the Server signals when a new Target Version becomes available, and the next CaN starts on that Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 --> This feature is in Public Preview as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541 -->

### When to use it

- **Entity Workflows** that run for months or years. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:537 -->
- **Batch processing** Workflows that checkpoint with Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:538 -->
- **AI agent Workflows** with long sleeps waiting for user input. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:539 -->

### Pinning the decision logic

The [Decision Guide](/worker-versioning#decision-guide) is unambiguous for long-running Workflows: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:261 -->

- Long (weeks to years) **+ uses CaN** -> `PINNED` + upgrade-on-CaN; patching is never required. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 -->
- Long (weeks to years) **+ does NOT use CaN** -> `AUTO_UPGRADE` + patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:266 -->

### API surface (Go)

Two Workflow APIs implement the pattern:

- `workflow.GetInfo(ctx).GetTargetWorkerDeploymentVersionChanged()` returns `true` when the Worker Deployment now has a new Target Version (a different version has become Current or Ramping). The flag is refreshed after each WFT completes, so a Workflow that is asleep or otherwise idle will not observe the change until its next Workflow Task runs. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:571 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:583 -->
- `workflow.NewContinueAsNewErrorWithOptions(ctx, workflow.ContinueAsNewErrorOptions{ InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade }, workflowType, args...)` returns a Continue-as-New error whose new run starts with AutoUpgrade behavior, so it lands on the Worker Deployment's Target Version. The options struct is passed before the positional `workflowType` and `args...`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:586 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:590 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:592 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:593 -->

The only documented field on `workflow.ContinueAsNewErrorOptions` is `InitialVersioningBehavior`, and the only documented value is `workflow.ContinueAsNewVersioningBehaviorAutoUpgrade`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:586 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:590 -->

### Worked example

The Workflow Definition below ships a V1 that checks the target-version flag and continues-as-new into V2 when a new Target Version is detected. V1 represents your currently-deployed code; V2 represents the next Worker Deployment Version. The `attempt` argument is purely to demonstrate the upgrade hop in tests -- in production code, you check `GetTargetWorkerDeploymentVersionChanged` whenever your Workflow is awake (between activity calls, on Update or Signal handler entry, after a periodic timer fires, etc.) rather than on every iteration.

```go
func (w *Workflows) ContinueAsNewWithVersionUpgradeV1(
  ctx workflow.Context,
  attempt int,
) (string, error) {
  if attempt > 0 {
    return "v1.0", nil
  }

  // Check GetTargetWorkerDeploymentVersionChanged periodically.
  // GetTargetWorkerDeploymentVersionChanged is refreshed after each WFT completes.
  for {
    // Trigger a WFT when the timer expires, thereby refreshing the
    // GetTargetWorkerDeploymentVersionChanged flag. In a real workflow that is
    // already running activities, child workflows, or message handlers, you
    // would not need to artificially trigger a WFT -- you could check the
    // field periodically, or before accepting Updates, starting Activities, or
    // starting Child Workflows.
    err := workflow.Sleep(ctx, 10*time.Millisecond)
    if err != nil {
      return "", err
    }
    info := workflow.GetInfo(ctx)
    if info.GetTargetWorkerDeploymentVersionChanged() {
      return "", workflow.NewContinueAsNewErrorWithOptions(
        ctx,
        workflow.ContinueAsNewErrorOptions{
          // Pass InitialVersioningBehavior=ContinueAsNewVersioningBehaviorAutoUpgrade
          // so the new run starts with AutoUpgrade behavior and lands on the
          // Target Version of its Worker Deployment.
          InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade,
        },
        "ContinueAsNewWithVersionUpgrade",
        attempt+1,
      )
    }
  }
}

func (w *Workflows) ContinueAsNewWithVersionUpgradeV2(
  ctx workflow.Context,
  attempt int,
) (string, error) {
  return "v2.0", nil
}
```

### The lazy-moving constraint

The Target-Version-Changed information only propagates when the Workflow executes a step. A Workflow sleeping on a multi-hour or multi-day timer will not see the change until that timer fires, an Activity completes, or a Signal/Update arrives. The documented escape hatch for idle Workflows is to send them a Signal to wake them up so they can check `GetTargetWorkerDeploymentVersionChanged`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:612 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:613 --> For Entity or AI-agent shapes, this typically means scheduling a periodic timer that exists solely to refresh the flag, or checking `info.GetTargetWorkerDeploymentVersionChanged()` at the top of each Update/Signal handler and at activity boundaries.

### Input compatibility across versions

When the new run is built from a different Workflow Definition, the input passed by the previous version must be deserializable by the new version's signature. If incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:615 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:616 --> If you are designing for upgrade-on-CaN, keep the CaN-input struct additive-only: add fields with safe zero-value defaults, never rename or remove them, and never change their types.

### Continue-as-New inheritance reminder

Pinned Workflows pass their version across the Continue-as-New chain by default, so without the upgrade option a Pinned CaN run stays on the original version forever. If the new run's Task Queue is not in the same Worker Deployment as the original, no inheritance occurs and the new run starts on the Current Version of its Task Queue. <!-- docs/encyclopedia/workers/worker-versioning.mdx:129 --> <!-- docs/encyclopedia/workers/worker-versioning.mdx:130 --> <!-- docs/encyclopedia/workers/worker-versioning.mdx:132 --> Auto-Upgrade Workflows never inherit versions across CaN. <!-- docs/encyclopedia/workers/worker-versioning.mdx:136 --> Cron jobs never inherit versioning behavior or version. <!-- docs/encyclopedia/workers/worker-versioning.mdx:152 -->
