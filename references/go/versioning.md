# Go SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## GetVersion API

[`workflow.GetVersion`](https://pkg.go.dev/go.temporal.io/sdk/workflow#GetVersion) safely performs backwards-incompatible changes to Workflow Definitions. It returns the version to branch on, recording the result as a marker in the Event History.

```go
v := workflow.GetVersion(ctx, "changeID", workflow.DefaultVersion, maxSupported)
```

- `changeID`: unique string identifying the change
- `minSupported`: oldest version still supported (`workflow.DefaultVersion` is `-1`)
- `maxSupported`: current/newest version
- Returns `maxSupported` for new executions; returns the recorded version on replay

### Retirement Lifecycle

Treat `GetVersion` cleanup as replay-safety work, not ordinary dead-code removal. Removing an old branch and deleting the first marker call are separate changes with different gates.

#### Step 1: Add `GetVersion` with both code paths

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

For new executions, `GetVersion` returns `1` and records a marker. For replay of pre-change workflows with no marker for `Step1`, it returns `workflow.DefaultVersion` (`-1`). **`DefaultVersion` is not version `0`**; do not search for `Step1-0` unless the code actually recorded version `0`.

#### Step 2: Inventory and prove the old version has left retention

Before raising `minSupported`, record enough context to review each change independently:

| Field | Example |
|---|---|
| Workflow type | `OrderWorkflow` |
| Change ID | `Step1` |
| Old version | `workflow.DefaultVersion`, `0`, or `1` |
| Retained version | `1` |
| Branch effect | Activity, child workflow, timer, signal/update flow |
| Call location | Startup, loop, selector, or handler |

For a recorded integer version, query the exact old `changeID-version` value across open and closed executions still in retention. For example, when retiring version `1` after a later `1 → 2` migration:

```bash
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND TemporalChangeVersion = "Step1-1"'
```

A nonzero result means version `1` has not left retention. Keep that branch. In the initial `workflow.DefaultVersion → 1` example above, the old branch has no recorded integer value, so use the marker-absence procedure instead.

Histories from before the first `GetVersion` call have no `TemporalChangeVersion` entry for that change ID. If this is the workflow's only patch marker, find the simple pre-marker population still in retention with:

```bash
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND TemporalChangeVersion IS NULL'
```

For workflows with multiple patch markers, query all running executions of the workflow type and inspect their `TemporalChangeVersion` values for the absence of the retained marker. Do the same when the `GetVersion` call is on an optional path: absence can mean either a pre-marker history or an execution that has not reached that call.

Treat marker absence as an unverified candidate set. Before raising `minSupported`, classify every candidate using its history or establish another authoritative population bound that proves every execution which could return the old version has left retention. Representative replay is still required for compatibility evidence, but it cannot classify an unexamined population.

A zero count of running old-version executions is necessary operational evidence, but it is not the retirement gate: closed histories can still be replayed or reset while retained. Do not raise `minSupported` until executions on the old version have left retention. A replay test can show whether selected histories are compatible; it does not prove that the old-version population has left retention.

#### Step 3: Remove the old branch but keep the first marker call

After executions on the old version have left retention, raise `minSupported` and collapse the branch:

```go
_ = workflow.GetVersion(ctx, "Step1", 1, 1)
err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
```

Keep the first `GetVersion` call for the change ID at the same deterministic point in the Workflow. Moving it across other Commands can itself break replay. The pinned call causes an older unsupported history to fail at the version boundary instead of continuing with the wrong behavior, and it leaves a safe place to add a later version.

Only the first call for a change ID needs to be retained. Subsequent calls with that same change ID return the recorded value and can be removed once their surrounding branches are gone.

Deploy and replay representative open and closed histories before making another retirement change.

#### Step 4: Optionally remove the first marker call

Deleting the first `GetVersion` call is stricter than removing an old branch. Do it only when:

1. All executions with older versions have left retention.
2. Replay verification covers the retained behavior.
3. You will permanently retire that change ID.

After deleting the call, you **must never reuse** `Step1`. A future change at the same code location needs a new change ID and must start again from `workflow.DefaultVersion`:

```go
v := workflow.GetVersion(ctx, "Step1-activity-d", workflow.DefaultVersion, 1)
if v == workflow.DefaultVersion {
	err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
} else {
	err = workflow.ExecuteActivity(ctx, ActivityD, data).Get(ctx, &result1)
}
```

When in doubt, leave the pinned marker call in place. It is small, explicit replay-safety state.

#### Further changes before final marker removal

To replace `ActivityC` with `ActivityD` while retaining `Step1`, bump `maxSupported`:

```go
v := workflow.GetVersion(ctx, "Step1", 1, 2)
if v == 1 {
	err = workflow.ExecuteActivity(ctx, ActivityC, data).Get(ctx, &result1)
} else {
	err = workflow.ExecuteActivity(ctx, ActivityD, data).Get(ctx, &result1)
}
```

After executions on version `1` have left retention, collapse again while preserving the first call:

```go
_ = workflow.GetVersion(ctx, "Step1", 2, 2)
err = workflow.ExecuteActivity(ctx, ActivityD, data).Get(ctx, &result1)
```

#### Replay verification checklist

Before raising `minSupported` or deleting a marker call:

- Replay saved histories for every known version, including `DefaultVersion` when applicable.
- Replay both open and closed histories, especially long-running and error-path executions.
- Disable test caching so the evidence comes from the current code.
- Inspect targeted histories when marker absence is ambiguous.
- Record the visibility query, result count, replay command, and code version in the change review.

Replay and visibility answer different questions: replay tests compatibility for the histories selected, while visibility helps estimate whether an old-version population still exists. Use both; neither substitutes for the other.

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

## Upgrading on Continue-as-New

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

For long-running Pinned Workflows that use Continue-as-New, detect a new Target Worker Deployment Version on `WorkflowInfo` and continue-as-new with `ContinueAsNewVersioningBehaviorAutoUpgrade` so the new run starts on the Target Version. See `references/core/versioning.md` for the conceptual model.

### Detecting the Target Version change

`workflow.GetInfo(ctx).GetTargetWorkerDeploymentVersionChanged()` returns `true` when a new Current or Ramping Version is available for this Workflow's Worker Deployment.  The flag is refreshed after each Workflow Task completes.

Check the flag from code that runs as part of a Workflow Task — for example, before accepting an Update, starting an Activity, or starting a child Workflow.

### Continue-as-new with upgrade

When the flag is set, return `workflow.NewContinueAsNewErrorWithOptions` with `InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade` so the new run starts on the Target Version of its Worker Deployment.

```go
// At a natural Workflow Task boundary, e.g. before accepting Updates,
// starting Activities, starting child Workflows, etc.:
if workflow.GetInfo(ctx).GetTargetWorkerDeploymentVersionChanged() {
  return "", workflow.NewContinueAsNewErrorWithOptions(
    ctx,
    workflow.ContinueAsNewErrorOptions{
      InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade,
    },
    "ContinueAsNewWithVersionUpgrade",
    nextInput,
  )
}
```

> [!IMPORTANT]
> Don't busy-poll the flag on a timer. Check it at a natural Workflow Task boundary — before accepting Updates, starting Activities, starting child Workflows, etc. For idle Workflows, send a Signal to wake them so they can check it (see Limitations).

### Limitations

- **Lazy moving only — idle Workflows do not upgrade.** Send a Signal to wake an idle Workflow so it can check `GetTargetWorkerDeploymentVersionChanged`.
- **Workflow input must remain compatible across versions.** The new version's Workflow definition must accept the previous version's input; otherwise the new run may fail on its first Workflow Task.
- **Pinned Workflow Types only.** Auto-Upgrade Workflows move at Workflow Task boundaries already; the upgrade-on-CaN pattern adds nothing for them.

## Best Practices

1. **Keep the first `GetVersion` call** when collapsing to a single branch unless the final retention and change-ID retirement gates are satisfied
2. **Query the exact recorded value** using `changeID-version`:
   ```bash
   temporal workflow list --query \
     'WorkflowType = "MyWorkflow" AND TemporalChangeVersion = "Step1-1"'
   ```
3. **Treat `DefaultVersion` as marker absence, not version `0`**, and inspect histories when absence is ambiguous
4. **Test with replay** before removing old branches or marker calls, while remembering that sampled replay does not prove a version has left retention
5. **Prefer Worker Versioning** for large-scale deployments to avoid accumulating patching branches
