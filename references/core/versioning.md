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

## Choosing an Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small change, few running workflows | Patching API |
| Major rewrite | Workflow Type Versioning |
| Many short workflows, frequent deploys | Worker Versioning (PINNED) |
| Long-running workflows needing updates | Worker Versioning (AUTO_UPGRADE) + Patching |
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

## Upgrading on Continue-as-New

Pinned Workflows normally complete on the Worker Deployment Version where they started, so a Workflow that runs for months or years would never see newer code without a manual move. The "upgrade on Continue-as-New" pattern lets a long-running Pinned Workflow that already uses [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) to manage history size hand off to its Worker Deployment's Target Version at the CaN boundary, without introducing patching inside the Workflow body. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532 --> This feature is in **Public Preview as an experimental SDK-level option**. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:543 -->

### When to use it

The pattern is intended for workloads that combine long wall-clock lifetimes with a natural CaN checkpoint:

- **Entity Workflows** that run for months or years <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:537 -->
- **Batch processing** Workflows that checkpoint with Continue-as-New <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:538 -->
- **AI agent Workflows** with long sleeps waiting for user input <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:539 -->

### Decision: which long-running path?

The Decision Guide distinguishes two long-running cases by whether the Workflow already uses CaN:

- **Long-running and uses CaN** → `PINNED` + upgrade-on-CaN; **patching never required**. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 -->
- **Long-running and does NOT use CaN** → `AUTO_UPGRADE` + patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:266 -->

Upgrade-on-CaN is not a drop-in replacement for Auto-Upgrade. Without a CaN boundary there is no point at which the Workflow can safely cut over, so a long Workflow that cannot use CaN must accept Auto-Upgrade and use the patching API for any Command-shape changes between deploys.

### How it works

The mechanics rest on three pieces working together: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:548 -->

1. **Each run stays pinned.** A single CaN run executes entirely on the Version it started on, so no patching is needed inside a run. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:552 -->
2. **The server signals when a new Target Version is available.** When a different Worker Deployment Version becomes Current or Ramping for the Workflow's Task Queue, the server marks the Workflow's Target Version as changed. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558 -->
3. **CaN with the upgrade option moves to the Target Version.** When the Workflow issues Continue-as-New with the upgrade option set, the new run starts on the Target Version instead of inheriting the previous run's pinned version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 -->

### Detection is lazy — sleeping Workflows must be woken

The Target-Version-Changed flag is exposed through an SDK accessor (Go names it `GetTargetWorkerDeploymentVersionChanged`) that the Workflow code polls during its normal execution. The flag's value is refreshed when a Workflow Task completes, which means a Workflow that is currently sleeping or otherwise idle will not observe a change until something causes it to wake up and run a Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:612 --> If you need an idle Workflow to react promptly, send it a Signal to force a Workflow Task; do not assume the server will deliver a proactive notification. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:613 -->

Practical checkpoints — before accepting an Update, before starting an Activity, before starting a Child Workflow, or as part of a periodic loop — are reasonable places to inspect the flag. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:576 -->

### Cross-CaN inheritance and where it stops

Without the upgrade option, a Pinned Workflow's Version is inherited across the CaN chain. <!-- docs/encyclopedia/workers/worker-versioning.mdx:131 --> Inheritance stops if the new run's Task Queue is not in the same Worker Deployment as the original Workflow — in that case the new run starts on the Current Version of its Task Queue instead. <!-- docs/encyclopedia/workers/worker-versioning.mdx:132 --> Auto-Upgrade Workflows do not inherit versions across CaN at all. <!-- docs/encyclopedia/workers/worker-versioning.mdx:134 --> <!-- docs/encyclopedia/workers/worker-versioning.mdx:136 --> Cron jobs are a separate category and **never inherit** versioning behavior or version, so this pattern does not apply to them. <!-- docs/encyclopedia/workers/worker-versioning.mdx:152 -->

### Input compatibility across the boundary

CaN passes arguments from the old run to the new run, and the two runs may now be executing different code. The docs are explicit: when continuing as new to a different version, ensure the Workflow input produced by the previous version is compatible with the new version's Workflow definition. If it is not, the new run can fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:615 --> <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:616 --> Treat the CaN input schema as a public contract between adjacent versions: only make additive changes, or stage a compatible intermediate version before the breaking one.

### Per-language code

For the worked example (currently Go-only in the docs) and per-SDK code, see `references/{your_language}/versioning.md`. The canonical docs example lives in `docs/production-deployment/worker-deployments/worker-versioning.mdx`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:556 -->
