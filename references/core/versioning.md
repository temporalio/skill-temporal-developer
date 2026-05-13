# Workflow Versioning Concepts

This document provides core conceptual explanations of workflow versioning in Temporal. For language-specific implementation details see `references/{your_language}/versioning.md`, for the language you are working in.

## Overview

Workflow versioning allows safe deployment of code changes without breaking running workflows. Three approaches available:

1. **Patching API** - Code-level version branching
2. **Workflow Type Versioning** - New workflow types for incompatible changes
3. **Worker Versioning** - Deployment-level control with Build IDs

## Why Versioning is Needed

When workers restart after deployment, they resume open workflows through history replay. If updated code produces different Commands than the original code, it causes non-determinism errors.

```
Original Code (recorded in history):
  await activity_a()
  await activity_b()

Updated Code (during replay):
  await activity_a()
  await activity_c()  ← Different! NondeterminismError
```

## Approach 1: Patching API

### Concept

The patching API lets you branch code based on whether a workflow was started before or after a code change.

```
if patched("my-change"):
    // New code path (for new and replaying new workflows)
else:
    // Old code path (for replaying old workflows)
```

### Three-Phase Lifecycle

**Phase 1: Patch In**

- Add both old and new code paths
- New workflows take new path, old workflows take old path

**Phase 2: Deprecate**

- After all old workflows complete, remove old code
- Keep deprecation marker for history compatibility

**Phase 3: Remove**

- After all deprecated workflows complete
- Remove patch entirely, only new code remains

### When to Use

- Adding, removing, or reordering activities/child workflows
- Changing which activity/child workflow is called
- Any change that alters the Command sequence

### When NOT to Use

- Changing activity implementations (activities aren't replayed)
- Changing arguments passed to activities or child workflows
- Changing retry policies
- Changing timer durations
- Adding new signal/query/update handlers (additive changes are safe)
- Bug fixes that don't change Command sequence

Unnecessary patching adds complexity and can make workflow code unmanageable.

## Approach 2: Workflow Type Versioning

### Concept

Create a new workflow type (e.g., `OrderWorkflowV2`) instead of patching.

```
// Old: OrderWorkflow
// New: OrderWorkflowV2 (completely new implementation)
```

### When to Use

- Major incompatible changes
- Complete rewrites
- When patching would be too complex
- When you want clean separation

### Process

1. Create new workflow type with new name
2. Register both with worker
3. Start new workflows with new type
4. Wait for old workflows to complete
5. Remove old workflow type

## Approach 3: Worker Versioning

### Concept

Manage versions at deployment level using Build IDs. Multiple worker versions can run simultaneously.

```
Worker v1.0 (Build ID: abc123)
  └── Handles workflows started on this version

Worker v2.0 (Build ID: def456)
  └── Handles new workflows
  └── Can also handle upgraded old workflows
```

### Key Concepts

**Worker Deployment**: Logical service grouping (e.g., "order-service")

**Build ID**: Specific code version (e.g., git commit hash)

**Versioning Behaviors**:

- `PINNED` - Workflows stay on original worker version
- `AUTO_UPGRADE` - Workflows can move to newer versions

### When to Use PINNED

- Short-running workflows (minutes to hours)
- Consistency is critical
- Want simplest development experience
- Building new applications

### When to Use AUTO_UPGRADE

- Long-running workflows (weeks or months)
- Workflows need bug fixes during execution
- Still requires patching for version transitions

## Versioned Continue-as-New (Upgrade-on-CaN)

> **Public Preview.** This is an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

A Pinned Workflow that uses Continue-as-New can opt to upgrade onto a newer Worker Deployment Version at the Continue-as-New boundary, without requiring patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-533 -->

### Why this exists

By default, when a Pinned Workflow performs Continue-as-New, the new run inherits the Pinned Worker Deployment Version of the previous run — the version is carried across the entire Continue-as-New chain. <!-- docs/encyclopedia/workers/worker-versioning.mdx:129-132 --> That's the right default for safety, but it traps long-running entity / batch / agent workflows on whichever version they were first started on.

The upgrade-on-CaN mechanism lets such a Workflow detect that a new Target Worker Deployment Version is available and start its next CaN run on that Target Version instead — escaping the inheritance chain at a clean boundary.

### When to use it

Documented use cases <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:535-539 -->:

- **Entity Workflows** that run for months or years.
- **Batch processing** Workflows that already checkpoint with Continue-as-New.
- **AI agent Workflows** with long sleeps waiting for user input.

This is a **Pinned-Workflow** pattern. Auto-Upgrade Workflows already follow the Target Worker Deployment Version automatically; per the inheritance rules, they do not inherit a version across CaN. <!-- docs/encyclopedia/workers/worker-versioning.mdx:105,134-136 -->

### How it works

Three pieces of state, all server-driven <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:547-554 -->:

1. Each Workflow run remains pinned to its version for its lifetime — no patching needed inside a run.
2. When a new Target Worker Deployment Version becomes available, the Temporal Server marks the Workflow Task as carrying that information.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Worker Deployment Version (Current or Ramping, depending on Ramp Percentage and Workflow ID <!-- docs/encyclopedia/workers/worker-versioning.mdx:79 -->).

### Detecting a target-version change

The SDK exposes a per-Workflow-Info flag — documented in the docs as `target_worker_deployment_version_changed`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 --> The flag is **refreshed only when a Workflow Task completes**. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:571 --> Reading it does not poll the server in real time — the Workflow must execute a Workflow Task for the value to refresh.

The docs example checks the flag periodically, but the recommended places to check it are <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:576-577 -->:

- Before accepting Updates.
- Before starting Activities.
- Before starting Child Workflows.

### Choosing the new run's behavior

When the Workflow calls Continue-as-New with the upgrade option, it also chooses the new run's initial versioning behavior. The docs example uses Auto-Upgrade behavior so the new run lands on the Target Worker Deployment Version of its Worker Deployment. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587-591 --> The choice is the user's — the new run is not Auto-Upgrade automatically.

### Limitations (current)

Two limitations are called out under the Public Preview caution <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:607-618 -->:

- **Lazy moving only.** A Workflow must execute a Workflow Task to learn about the new Target Version. Sleeping Workflows will not be proactively notified. If you have idle Workflows that should check for an upgrade, send them a Signal to wake them up.
- **Interface compatibility.** The new version's Workflow definition must accept the previous version's Continue-as-New input. If it doesn't, the new run may fail on its first Workflow Task.

### Per-SDK details

- Go has a documented example (verbatim API tokens). See `references/go/versioning.md` §Versioned Continue-as-New.
- Python, TypeScript, Java, and .NET each expose this feature, but the local documentation only contains the Go example. See the corresponding per-SDK `versioning.md` for the concept-level guidance and pointers to upstream SDK references.

## Choosing an Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small change, few running workflows | Patching API |
| Major rewrite | Workflow Type Versioning |
| Many short workflows, frequent deploys | Worker Versioning (PINNED) |
| Long-running workflows needing updates | Worker Versioning (AUTO_UPGRADE) + Patching |
| Long-running Pinned workflows that already use Continue-as-New | Versioned Continue-as-New (Public Preview) |
| Quick fix, can wait for completion | Wait for workflows to complete |

## Best Practices

1. **Check for open executions** before removing old code
2. **Use descriptive patch IDs** (e.g., "add-fraud-check" not "patch-1")
3. **Deploy incrementally**: patch → deprecate → remove
4. **Test replay compatibility** before deploying changes
5. **Monitor old workflow counts** during migration

## Finding Workflows by Version

```bash
# Find workflows with specific patch
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND TemporalChangeVersion = "add-fraud-check"'

# Find pre-patch workflows
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND TemporalChangeVersion IS NULL'

# Find workflows on specific worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0"'
```

## Common Mistakes

1. **Removing old code too early** - Breaks replaying workflows
2. **Not testing with replay** - Catches issues before production
3. **Patching non-Command changes** - Unnecessary complexity
4. **Forgetting to deprecate** - Accumulates dead code
