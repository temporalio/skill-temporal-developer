# TypeScript SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## Patching API

The Patching API lets you change Workflow Definitions without causing non-deterministic behavior in running Workflows.

### The patched() Function

The `patched()` function takes a `patchId` string and returns a boolean:

```typescript
import { patched } from '@temporalio/workflow';

export async function myWorkflow(): Promise<void> {
  if (patched('my-change-id')) {
    // New code path
    await newImplementation();
  } else {
    // Old code path (for replay of existing executions)
    await oldImplementation();
  }
}
```

**How it works:**

- If the Workflow is running for the first time, `patched()` returns `true` and inserts a marker into the Event History
- During replay, if the history contains a marker with the same `patchId`, `patched()` returns `true`
- During replay, if no matching marker exists, `patched()` returns `false`

**TypeScript-specific behavior:** Unlike Python/.NET/Ruby, `patched()` is not memoized when it returns `false`. This means you can use `patched()` in loops. However, if a single patch requires coordinated behavioral changes at different points in your workflow, you may need to manually memoize the result:

```typescript
const useNewBehavior = patched('my-change');
// Use useNewBehavior at multiple points in workflow
```

### Three-Step Patching Process

Patching is a three-step process for safely deploying changes.

**Warning:** Failing to follow this process correctly will result in non-determinism errors for in-flight workflows.

#### Step 1: Patch in New Code

Add the patch alongside the old code:

```typescript
import { patched } from '@temporalio/workflow';

// Original code sent fax notifications
export async function shippingConfirmation(): Promise<void> {
  if (patched('changedNotificationType')) {
    await sendEmail();  // New code
  } else {
    await sendFax();    // Old code for replay
  }
  await sleep('1 day');
}
```

#### Step 2: Deprecate the Patch

Once all Workflows using the old code have completed, deprecate the patch:

```typescript
import { deprecatePatch } from '@temporalio/workflow';

export async function shippingConfirmation(): Promise<void> {
  deprecatePatch('changedNotificationType');
  await sendEmail();
  await sleep('1 day');
}
```

The `deprecatePatch()` function records a marker that does not fail replay when Workflow code does not emit it, allowing a transition period.

#### Step 3: Remove the Patch

After all Workflows using `deprecatePatch` have completed, remove it entirely:

```typescript
export async function shippingConfirmation(): Promise<void> {
  await sendEmail();
  await sleep('1 day');
}
```

### Query Filters for Versioned Workflows

Use List Filters to find Workflows by version:

```
# Find running Workflows with a specific patch
WorkflowType = "shippingConfirmation" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "changedNotificationType"

# Find running Workflows without the patch (started before patching)
WorkflowType = "shippingConfirmation" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL
```

## Workflow Type Versioning

An alternative to patching is creating new Workflow functions for incompatible changes:

```typescript
// Original Workflow
export async function pizzaWorkflow(order: PizzaOrder): Promise<OrderConfirmation> {
  // Original implementation
}

// New version with incompatible changes
export async function pizzaWorkflowV2(order: PizzaOrder): Promise<OrderConfirmation> {
  // Updated implementation
}
```

Register both Workflows with the Worker:

```typescript
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'), // Use workflowBundle for production
  taskQueue: 'pizza-queue',
});
```

Update client code to start new Workflows with the new type:

```typescript
// Start new executions with V2
await client.workflow.start(pizzaWorkflowV2, {
  workflowId: 'order-123',
  taskQueue: 'pizza-queue',
  args: [order],
});
```

Use List Filters to check for remaining V1 executions:

```
WorkflowType = "pizzaWorkflow" AND ExecutionStatus = "Running"
```

After all V1 executions complete, remove the old Workflow function.

## Worker Versioning

Worker Versioning allows multiple Worker versions to run simultaneously, routing Workflows to specific versions without code-level patching. Workflows are pinned to the Worker Deployment Version they started on.

> **Note:** Worker Versioning is currently in Public Preview. The legacy Worker Versioning API (before 2025) will be removed from Temporal Server in March 2026.

### Key Concepts

- **Worker Deployment**: A logical name for your application (e.g., "order-service")
- **Worker Deployment Version**: A specific build identified by deployment name + Build ID
- **Workflow Pinning**: Workflows complete on the Worker Deployment Version they started on

### Configuring Workers for Versioning

```typescript
import { Worker, NativeConnection } from '@temporalio/worker';

const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),  // Use workflowBundle for production
  taskQueue: 'my-queue',
  connection: await NativeConnection.connect({ address: 'temporal:7233' }),
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: {
      deploymentName: 'order-service',
      buildId: '1.0.0',  // Git hash, semver, build number, etc.
    },
  },
});
```

**Configuration options:**

- `useWorkerVersioning`: Enables Worker Versioning
- `version.deploymentName`: Logical name for your service (consistent across versions)
- `version.buildId`: Unique identifier for this build

### Deployment Workflow

1. Deploy new Worker version with a new `buildId`
2. Use the Temporal CLI to set the new version as current:
   ```bash
   temporal worker deployment set-current-version \
     --deployment-name order-service \
     --build-id 2.0.0
   ```
3. New Workflows start on the new version
4. Existing Workflows continue on their original version until completion
5. Decommission old Workers once all their Workflows complete

### When to Use Worker Versioning

Worker Versioning is best suited for:

- **Short-running Workflows**: Old Workers only need to run briefly during deployment transitions
- **Frequent deployments**: Eliminates the need for code-level patching on every change
- **Blue-green deployments**: Run old and new versions simultaneously with traffic control

For long-running Workflows, consider combining Worker Versioning with the Patching API, or use Continue-as-New to move Workflows to newer versions.

## Versioned Continue-as-New (Upgrade-on-CaN)

> **Public Preview.** Experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

A Pinned Workflow that uses Continue-as-New can opt to upgrade onto a newer Worker Deployment Version at the Continue-as-New boundary, without patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-533 --> See `references/core/versioning.md` §"Versioned Continue-as-New" for the cross-language concept.

This is a **Pinned-Workflow** pattern. Without the upgrade option, a Pinned Workflow's version is inherited across the entire Continue-as-New chain. <!-- docs/encyclopedia/workers/worker-versioning.mdx:129-132 --> Auto-Upgrade Workflows already follow the Target Worker Deployment Version on every Workflow Task; they do not use this mechanism.

### How the SDK exposes the feature

The local Temporal documentation only shows a Go example for this Public-Preview feature. The TypeScript SDK exposes equivalent capabilities, but the specific token names are not described in the docs clone — confirm them in the upstream SDK before writing production code.

The conceptual surface (verified in the docs) is <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:556-605 -->:

1. A per-Workflow-Info flag named in docs prose as `target_worker_deployment_version_changed`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 --> It becomes `true` when a new Target Worker Deployment Version is available, and it is refreshed only when a Workflow Task completes. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:571 -->
2. A Continue-as-New variant that accepts options, with an option to set the *new* run's initial versioning behavior. The Go example sets the new run to Auto-Upgrade so it lands on the Target Worker Deployment Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584-591 -->

TypeScript-side concrete names (not in the local docs):

- The Workflow-info field for the target-version-changed flag: <!-- VERIFY: exact field on `workflowInfo()` (or equivalent) in @temporalio/workflow that reports target Worker Deployment Version changes; check upstream temporalio/sdk-typescript release notes (Public Preview) -->
- The Continue-as-New option for initial versioning behavior: <!-- VERIFY: which option on `continueAsNew(...)` (or related API) accepts an initial versioning behavior, and the spelling of the AUTO_UPGRADE constant, in upstream temporalio/sdk-typescript -->

Until those are verified against the upstream SDK, write the *check* in terms of the documented concept, not a specific TS token:

```ts
// Pseudocode — token names are SDK-version-specific and not in the docs clone.
// Verify against upstream temporalio/sdk-typescript before using in production.
import { workflowInfo, continueAsNew } from '@temporalio/workflow';

export async function longRunningEntity(state: State): Promise<void> {
  while (!state.done) {
    await doUnitOfWork(state);

    // Check after each meaningful Workflow Task — the flag refreshes
    // only across Workflow Task boundaries.
    if (workflowInfo()/* <!-- VERIFY: field name --> */) {
      await continueAsNew<typeof longRunningEntity>(state /*,
        // Pass an option so the new run starts with AutoUpgrade behavior
        // and lands on its Worker Deployment's Target Version.
        // <!-- VERIFY: option name and AUTO_UPGRADE constant -->
      */);
    }
  }
}
```

When in doubt, link the user to the docs Go example (`references/go/versioning.md` §Versioned Continue-as-New) as the canonical documented form.

### Where to check the flag

The docs name these as good check points <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:576-577 -->:

- Before accepting Updates.
- Before starting Activities.
- Before starting Child Workflows.

The flag is **not** a real-time signal — it refreshes only when the SDK completes a Workflow Task.

### Limitations

From the Public Preview caution <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:607-618 -->:

- **Lazy moving only.** Idle / sleeping Workflows are not proactively notified of a Target-Version change. Send a Signal to wake them so they can re-check the flag.
- **Interface compatibility.** The new version's Workflow definition must accept the previous run's Continue-as-New input. If it doesn't, the new run may fail on its first Workflow Task.

## Best Practices

1. Use descriptive `patchId` names that explain the change
2. Follow the three-step patching process completely before removing patches
3. Use List Filters to verify no running Workflows before removing version support
4. Keep Worker Deployment names consistent across all versions
5. Use unique, traceable Build IDs (git hashes, semver, timestamps)
6. Test version transitions with replay tests before deploying
