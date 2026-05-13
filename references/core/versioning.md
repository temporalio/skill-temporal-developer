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

## Upgrade on Continue-as-New

> Public Preview — this is an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

Long-running Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) and are marked `PINNED` can upgrade to a newer Worker Deployment Version at the Continue-as-New boundary — without patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532-533 -->

This is the "Pinned + upgrade on CaN" row of the decision table for long-running Workflows: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 -->

| Workflow Duration | Uses Continue-as-New? | Recommended Behavior | Patching Required? |
|---|---|---|---|
| Long (weeks to years) | Yes | `PINNED` + upgrade on CaN | Never |
| Long (weeks to years) | No  | `AUTO_UPGRADE` + patching | Yes |

Typical fits: **Customer entity Workflows** (months–years) and **AI agent / Chatbot Workflows** (weeks, with long sleeps for user input). <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:275-276 -->

### How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 --> With the upgrade option enabled per CaN call, three things happen: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:551-554 -->

1. Each Workflow run remains pinned to its version during the run (no patching needed within a run).
2. The Temporal Server tells the Workflow when a new **Target Worker Deployment Version** becomes available — that is, when a new Current Version or Ramping Version exists for the Worker Deployment. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:105-110 -->
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

### Detecting the change

Active Workflows detect a new Target Version through a per-run flag conceptually named `target_worker_deployment_version_changed`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 --> This flag is **refreshed after each Workflow Task completes** — describe it as a per-WFT check, not a sticky one-time boolean. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570-571 -->

You can check the flag periodically inside the Workflow, or before a logical checkpoint such as accepting an Update, starting an Activity, or starting a Child Workflow. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:576-577 --> When the flag is set, the Workflow can Continue-as-New and pass an SDK-specific "initial versioning behavior" option that requests Auto-Upgrade behavior for the new run, so the new run starts on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584-594 -->

The opt-in is **per Continue-as-New call** — there is no Worker-level toggle for upgrade-on-CaN documented. The Workflow code decides, run by run, whether to opt in.

For the concrete worked example, see `references/go/versioning.md` (the canonical documentation example is in Go). For Python, Java, TypeScript, and .NET, the conceptual mechanic is the same; the per-SDK API names are not yet in the canonical docs section — see your language's `references/{language}/versioning.md` and your SDK's release notes for the exact identifiers. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:556-605 (Go-only code) -->

### Limitations

**Lazy moving only.** Workflows must be invoked by executing a step to receive the Target-Version-Changed information. Sleeping Workflows won't proactively receive it. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 --> If you have idle Workflows that you want to wake up so they can check the flag, send them a Signal.

**Interface compatibility across versions.** When continuing as new to a different version, the Workflow input produced by the previous version's Workflow definition must be compatible with the new version's Workflow definition. If incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

### When to use it

- Your Workflow is marked `PINNED` and is expected to live longer than your Worker Deployment Versions exist.
- The Workflow uses Continue-as-New (typically to manage history size).
- You want to avoid patching to handle code changes at version boundaries.

If your Workflow does **not** use Continue-as-New but is still long-running, use `AUTO_UPGRADE` + patching instead — upgrade-on-CaN doesn't apply. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:266 -->
