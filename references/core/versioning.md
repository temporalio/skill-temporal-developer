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

- Add both old and new code paths.
- New executions take the new path; histories that predate the patch replay the old path.

**Phase 2: Deprecate**

- Wait until executions that can return the retired version have left retention before removing that branch or raising the minimum supported version.
- Keep the Workflow's deprecation/version marker at the same deterministic location for history compatibility.

**Phase 3: Remove**

- Removing the final marker is a separate operation with patching-API-specific rules beyond branch retirement.
- Retire the patch/change identifier permanently when the patching API requires it; do not reuse an identifier whose first marker call was removed.

See the language-specific versioning reference for exact marker, visibility, retention, and replay rules.

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

## Upgrading on Continue-as-New

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

Long-running Pinned Workflows that use Continue-as-New can upgrade to newer Worker Deployment Versions at the Continue-as-New boundary without patching.

This pattern is for:

- Entity Workflows that run for months or years
- Batch processing Workflows that checkpoint with Continue-as-New
- AI agent Workflows with long sleeps waiting for user input

### How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the upgrade option enabled:

1. Each Workflow run remains pinned to its version (no patching needed during a run).
2. The Temporal Server tells the Workflow when a new **Target Version** becomes available — that is, when the Workflow's Worker Deployment gets a new Current or Ramping Version that the Workflow would move to next.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

### Detection flag

Active Workflows detect a Target Version change by checking a per-Workflow flag exposed on `WorkflowInfo` (called `target_worker_deployment_version_changed` in the docs).  The flag is refreshed after each Workflow Task completes; check it from code that runs as part of a Workflow Task (for example, before accepting an Update, starting an Activity, or starting a child Workflow). See the per-language `references/{your_language}/versioning.md` for the SDK-specific call.

### Triggering the new run

When the flag is set, return a Continue-as-New error with the new run's initial Versioning Behavior set to `AutoUpgrade`. This makes the new run start on the Target Version of its Worker Deployment.  The Workflow Type itself retains its Pinned annotation; only the *initial* behavior of the *new* run is overridden so it picks up the Target Version. Once the new run is on the new version, the per-Workflow-type annotation continues to apply on subsequent CaN.

### Limitations

- **Lazy moving only — sleeping Workflows do not auto-upgrade.** Send a Signal to wake an idle Workflow so it can check the flag.
- **Interface compatibility is your responsibility.** When continuing as new to a different version, the previous version's Workflow input must be compatible with the new version's Workflow definition. If incompatible, the new run may fail on its first Workflow Task.
- **Pinned Workflows only.** Auto-Upgrade Workflows already move to the Target Version at Workflow Task boundaries; this pattern adds nothing for them.

### When to use this pattern

- Workflow Type is Pinned **and**
- Workflow runs longer than your Worker Deployment Version lifetime **and**
- Workflow already uses Continue-as-New to bound Event History size.

For long-running Workflows that cannot use Continue-as-New (e.g., compliance audits that need full history), use `AUTO_UPGRADE` with patching instead.

## Choosing an Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small change, few running workflows | Patching API |
| Major rewrite | Workflow Type Versioning |
| Many short workflows, frequent deploys | Worker Versioning (PINNED) |
| Long-running workflows, uses Continue-as-New | Worker Versioning (PINNED) + upgrade on Continue-as-New  |
| Long-running workflows, no Continue-as-New | Worker Versioning (AUTO_UPGRADE) + Patching  |
| Quick fix, can wait for completion | Wait for workflows to complete |

## Best Practices

1. **Wait for affected executions to leave retention** before removing old code
2. **Use descriptive patch IDs** (e.g., "add-fraud-check" not "patch-1")
3. **Deploy incrementally**: patch → deprecate → remove
4. **Test replay compatibility** before deploying changes
5. **Monitor old workflow counts** during migration

## Finding Workflows by Version

Different patching APIs encode `TemporalChangeVersion` values differently. A pre-patch execution has no marker for that patch, but marker absence can also mean an optional patch site has not executed. Follow the language-specific guide to query and classify the old-version population rather than guessing a marker value.

Worker Deployment versions use a separate Search Attribute:

```bash
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0"'
```

## Common Mistakes

1. **Removing old code too early** - Breaks replaying workflows
2. **Treating branch removal and final marker removal as identical changes** - Both can have retention gates, while final marker removal can also retire the identifier permanently
3. **Treating marker absence as proof of an old branch** - Optional patch sites and other markers make absence ambiguous
4. **Not testing with replay** - Replay catches compatibility failures before production
5. **Patching non-Command changes** - Unnecessary complexity
6. **Forgetting to deprecate** - Accumulates dead code
