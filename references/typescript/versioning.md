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

## Best Practices

1. Use descriptive `patchId` names that explain the change
2. Follow the three-step patching process completely before removing patches
3. Use List Filters to verify no running Workflows before removing version support
4. Keep Worker Deployment names consistent across all versions
5. Use unique, traceable Build IDs (git hashes, semver, timestamps)
6. Test version transitions with replay tests before deploying

## Upgrading on Continue-as-New

Long-running **Pinned** Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) can land on the latest Target Worker Deployment Version at each Continue-as-New boundary without requiring code-level patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-533 --> This feature is in **Public Preview** as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

### When to use it

This pattern is ideal for: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:535-540 -->

- **Entity Workflows** that run for months or years
- **Batch processing** Workflows that checkpoint with Continue-as-New
- **AI agent Workflows** with long sleeps waiting for user input

### Decision logic

Choose your versioning approach based on Workflow duration and whether the Workflow uses Continue-as-New: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:261-266 -->

- **Short** (completes before next deploy): `PINNED`, no patching needed
- **Medium** (spans multiple deploys), no CaN: `AUTO_UPGRADE` with patching as needed
- **Long** (weeks to years) with CaN: `PINNED` + upgrade on Continue-as-New (this section)
- **Long** (weeks to years) without CaN: `AUTO_UPGRADE` + patching

In short: if a Workflow is long-running and already structured to Continue-as-New, prefer Pinned + upgrade-on-CaN over Auto-Upgrade + patching.

### How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the upgrade option enabled: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:548-555 -->

1. Each Workflow run remains pinned to its version, so no patching is required within a run.
2. The Temporal Server notifies the Workflow when a new Target Worker Deployment Version becomes available.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

### Detection is lazy

The "Target Version changed" signal is delivered lazily. A Workflow only learns about a new Target Version when it executes a Workflow Task; Workflows that are sleeping or otherwise idle will not be proactively woken up. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

If you have idle Workflows that you want to give a chance to upgrade promptly, the documented escape hatch is to send them a Signal, which triggers a Workflow Task and gives the Workflow a chance to observe the change and call Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

In TypeScript Workflows you already use [`wf.workflowInfo().continueAsNewSuggested`](https://typescript.temporal.io/) to decide *when* to Continue-as-New based on history size. <!-- docs/develop/typescript/workflows/continue-as-new.mdx:82-83 --> Upgrade-on-CaN is a separate signal: it tells you *which version* the next run should land on, not whether to Continue-as-New at all.

### Input compatibility

When continuing-as-new onto a newer Worker Deployment Version, the input passed by the old run must be compatible with the new run's Workflow Definition. If the schemas are incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

This means upgrade-on-CaN does not eliminate the need to evolve Workflow inputs carefully across versions; it only removes the need for in-run patching.

### Continue-as-New inheritance

These inheritance rules govern what happens if you Continue-as-New *without* opting into the upgrade: <!-- docs/encyclopedia/workers/worker-versioning.mdx:128-137 -->

- **Pinned original Workflow:** the Pinned version is inherited across the Continue-as-New chain by default, so successive runs stay on the original version unless you explicitly opt into upgrading.
- **Pinned original Workflow, different Worker Deployment:** if the new run's Task Queue is not in the same Worker Deployment, no inheritance occurs and the new run starts on the Current Version of its Task Queue.
- **Auto-upgrade original Workflow:** no version inheritance occurs across Continue-as-New.

Upgrade-on-CaN is the mechanism that overrides the first bullet on demand: the new run is started with Auto-Upgrade behavior so it picks up its Worker Deployment's Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:586-591 -->

### TypeScript API status

As of 2026-05, the upgrade-on-Continue-as-New API is documented with a worked code example only in the Go SDK. The TypeScript-specific symbol names (the field on `wf.workflowInfo()` that surfaces "Target Version changed", and the option passed to `wf.continueAsNew<...>` to opt the new run into Auto-Upgrade behavior) are not given in the docs at the time of writing, so this skill does not include a TypeScript code sample for them. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:556-605 -->

For the conceptual flow and a concrete worked example, see:

- `references/go/versioning.md` § Upgrading on Continue-as-New
- [`docs/production-deployment/worker-deployments/worker-versioning.mdx`](/worker-versioning#upgrade-on-continue-as-new)

<!-- VERIFY: TypeScript SDK token names for upgrade-on-CaN — docs only document Go as of 2026-05; consult TypeScript SDK source or release notes -->

