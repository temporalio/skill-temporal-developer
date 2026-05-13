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

## Upgrade on Continue-as-New (Go)

Long-running Workflows that use Continue-as-New can opt in, on a per-call basis, to upgrade to a newer Worker Deployment Version at the Continue-as-New boundary without requiring patching. This is a Public Preview, experimental SDK-level option <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 --> documented in `Upgrading on Continue-as-New` in `documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx` (lines 530-618).

### When to use it

The decision table recommends this combination for **long-running Workflows (weeks to years) that use Continue-as-New**: register them as `PINNED` and opt in to upgrade-on-CaN, with no patching required <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 -->. Documented use cases include Customer entity Workflows and AI agent / Chatbot Workflows <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:275-276 -->.

### How it works

- By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 -->.
- Each Workflow run remains pinned to its version, so no patching is required during a run <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:552 -->.
- The Temporal Server tells the Workflow when a new Target Version becomes available <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553 -->.
- When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 -->.

### Detecting the change

The server-side concept is named `target_worker_deployment_version_changed` <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 -->. In Go, read it from `workflow.GetInfo(ctx)` via `info.GetTargetWorkerDeploymentVersionChanged()` <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:582-583 -->.

This flag is refreshed after each Workflow Task completes -- it is a per-WFT check, not a sticky boolean <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570-571 -->. You can check it periodically, or check it before accepting Updates, starting Activities, or starting Child Workflows <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:574-577 -->.

### Example

The following is the canonical Go example from the docs. To opt in to the upgrade on Continue-as-New, build a Continue-as-New error with `workflow.NewContinueAsNewErrorWithOptions` and set `InitialVersioningBehavior` on `workflow.ContinueAsNewErrorOptions` to `workflow.ContinueAsNewVersioningBehaviorAutoUpgrade`; passing that value makes the new run start with AutoUpgrade behavior and use the Target Version of its Worker Deployment <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584-594 -->.

<!-- Source: documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 -->

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
	// Trigger a WFT when timer expires, thereby refreshing the GetTargetWorkerDeploymentVersionChanged flag.
	// Since this is just a test workflow, we aren't doing any real work. In a real workflow regularly
	// doing non-sleep workflow tasks, you would not need to artificially trigger a WFT to refresh the
	// GetTargetWorkerDeploymentVersionChanged flag. You could choose to check the field periodically, or you
	// might want to check before accepting updates, starting activities, or starting child workflows.
	err := workflow.Sleep(ctx, 10*time.Millisecond)
	if err != nil {
	  return "", err
	}
	info := workflow.GetInfo(ctx)
	if info.GetTargetWorkerDeploymentVersionChanged() {
	  return "", workflow.NewContinueAsNewErrorWithOptions(
		ctx,
		workflow.ContinueAsNewErrorOptions{
		  // Pass InitialVersioningBehavior=workflow.ContinueAsNewVersioningBehaviorAutoUpgrade
		  // to make the new run start with AutoUpgrade behavior and use the Target Version of
		  // its Worker Deployment.
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

### Limitations

- **Lazy moving only.** Workflows must be invoked by executing a step to receive the Target-Version-Changed information; sleeping Workflows won't be proactively notified. For idle Workflows that you want to wake up so they can check `GetTargetWorkerDeploymentVersionChanged`, send them a Signal <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->.
- **Input compatibility.** When continuing as new to a different version, ensure the Workflow input produced by the previous version's Workflow definition is compatible with the new version's Workflow definition. If incompatible, the new run may fail on its first Workflow Task <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->.

Conceptual treatment in `references/core/versioning.md` §Upgrade on Continue-as-New.
