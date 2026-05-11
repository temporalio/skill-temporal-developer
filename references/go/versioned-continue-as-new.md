# Versioned Continue-as-New (Go)

Go SDK usage of the upgrade-on-Continue-as-New feature for Worker Versioning. For the cross-SDK concepts, inheritance semantics, and limitations, see `references/core/versioned-continue-as-new.md`.

## Public Preview

This feature is in Public Preview as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New; the upgrade is opt-in via the SDK option shown below. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-554 -->

## The flag and the option

Three distinct names are used by this feature:

- `target_worker_deployment_version_changed` — the prose field name surfaced by the Temporal Server when a new Target Version becomes available. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:559 -->
- `GetTargetWorkerDeploymentVersionChanged` — the Go accessor on the Workflow info handle. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:583 -->
- **Target Worker Deployment Version** — the conceptual version your Workflow will upgrade to next; this could be the Deployment's Current Version or the Ramping Version. <!-- docs/encyclopedia/workers/worker-versioning.mdx:79 -->

## Example

The following example is taken verbatim from the docs. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 -->

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

## Walkthrough

### Workflow signature and the V1/V2 split

Both Workflow definitions take `attempt int` as a chain-bookkeeping argument. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:564,601 --> The V1 implementation enters its check loop only on the first attempt (`attempt > 0` short-circuits to `"v1.0"`); V2 returns immediately with `"v2.0"`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:566-568,599-603 --> V2 only executes once the new run has started on the new version.

### Reading the flag

`workflow.GetInfo(ctx)` returns the info handle, and the Go accessor `info.GetTargetWorkerDeploymentVersionChanged()` reports whether a new Target Version is available. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:582-583 --> The accessor is refreshed after each WFT completes. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570-571 -->

### The artificial sleep

The `workflow.Sleep(ctx, 10*time.Millisecond)` in the loop exists only because this is a test workflow doing no real work; the timer firing produces a WFT that refreshes the flag. In a real Workflow that regularly does non-sleep Workflow Tasks, you do not need to artificially trigger a WFT to refresh the flag. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:573-577 -->

### Continuing as new with the upgrade option

When the flag is true, the example returns:

```go
workflow.NewContinueAsNewErrorWithOptions(
  ctx,
  workflow.ContinueAsNewErrorOptions{
    InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade,
  },
  "ContinueAsNewWithVersionUpgrade",
  attempt+1,
)
```

- The constructor is `workflow.NewContinueAsNewErrorWithOptions` — the options form of the Continue-as-New error. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584 -->
- The options struct is `workflow.ContinueAsNewErrorOptions`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:586 -->
- The field is `InitialVersioningBehavior`, set to `workflow.ContinueAsNewVersioningBehaviorAutoUpgrade`. With this value, the new run starts with AutoUpgrade behavior and uses the Target Version of its Worker Deployment. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587-590 -->

<!-- VERIFY: Does the Go SDK expose a `ContinueAsNewVersioningBehaviorPinned` value or any other variant of InitialVersioningBehavior? The docs only show ContinueAsNewVersioningBehaviorAutoUpgrade. -->

<!-- VERIFY: Does InitialVersioningBehavior have a default value when omitted? The docs do not state one. -->

## Where to check the flag

You could check `GetTargetWorkerDeploymentVersionChanged` periodically, or before accepting updates, starting activities, or starting child workflows. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:575-577 -->

For idle Workflows: detection is **lazy moving only** — Workflows must be invoked by executing a step to receive the Target-Version-Changed information. Sleeping Workflows will not proactively get that information; to wake them up so they can check the flag, send them a Signal. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

## See also

- `references/core/versioned-continue-as-new.md` — cross-SDK concepts, inheritance semantics, and the full limitations list (including interface-compatibility caveats across runs).
- `references/go/versioning.md` — general Worker Versioning usage in Go.
- `references/go/patterns.md` — general Continue-as-New patterns in Go.
