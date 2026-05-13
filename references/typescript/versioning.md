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

Worker Versioning routes Workflows to specific Worker Deployment Versions so that pinned Workflows complete on the version they started on and you can run multiple versions side-by-side without code-level patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:23-39 -->

> **Note:** The legacy Worker Versioning API (the pre-2025 `useVersioning` / top-level `buildId` shape on `WorkerOptions`) will be removed from Temporal Server in March 2026. <!-- docs/develop/typescript/workflows/versioning.mdx:36-38 -->

### Key Concepts

- **Worker Deployment**: A logical service that groups Workers across versions for unified management. <!-- docs/encyclopedia/workers/worker-versioning.mdx:30-32 -->
- **Worker Deployment Version**: An iteration of a Worker Deployment, identified by the deployment name plus a Build ID. <!-- docs/encyclopedia/workers/worker-versioning.mdx:36-40 -->
- **Workflow Pinning**: A Pinned Workflow is guaranteed to complete on a single Worker Deployment Version. <!-- docs/encyclopedia/workers/worker-versioning.mdx:48-50 -->

### Configuring a Worker

The TypeScript SDK exposes three Worker Versioning parameters under `workerDeploymentOptions`. The docs describe them as: `useWorkerVersioning` (the toggle that turns the feature on), `version` (deployment name + Build ID), and an **optional** `defaultVersioningBehavior` — if `defaultVersioningBehavior` is unset, each Workflow Type must declare its own behavior. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:141-149 -->

```typescript
import { Worker } from '@temporalio/worker';

const myWorker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue,
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: { buildId: '1.0', deploymentName: 'llm_srv' },
  },
  connection: nativeConnection,
});
```
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:209-219 -->

**Option summary:**

- `useWorkerVersioning` — enables versioned routing for this Worker. Without it, Worker Versioning is off for the Worker. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:144 -->
- `version` — `{ buildId, deploymentName }`. Together they identify the Worker Deployment Version this Worker reports as. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:145-146, :215 -->
- `defaultVersioningBehavior` — **optional**. Provides a Worker-level default (`'PINNED'` or `'AUTO_UPGRADE'`) used when a Workflow Type does not declare its own behavior. The docs suggest *not* providing it when your Worker and Workflows are new, so each Workflow Type is annotated explicitly. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:147-149, :287-296 -->

For the per-Workflow declaration (the value `defaultVersioningBehavior` falls back to when omitted), the TypeScript form is `setWorkflowOptions({ versioningBehavior: 'PINNED' }, helloWorld)` in the Workflow file. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:407-415 -->

### Build ID identity vs. enabling Worker Versioning

`useWorkerVersioning` and `version` are documented as independent parameters: one is the toggle, the other is the identity. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:141-146 -->

For the modern `workerDeploymentOptions` API, the documented and canonical configuration enables versioning by setting `useWorkerVersioning: true` together with `version`. The docs do not show an explicit TypeScript example of supplying `version` while leaving `useWorkerVersioning` unset purely to report a Build ID without enrolling in versioned routing.
<!-- VERIFY: docs/production-deployment/worker-deployments/worker-versioning.mdx shows only the `useWorkerVersioning: true` shape. If you want to set `workerDeploymentOptions.version` without enabling versioning purely to surface a Build ID, confirm the supported shape against the @temporalio/worker types before relying on it. -->

The legacy (pre-2025, scheduled for March 2026 removal) TypeScript API kept the two concerns separate at the top level of `WorkerOptions`:

```typescript
// LEGACY API — for reference only; removed March 2026
const worker = await Worker.create({
  taskQueue: 'your_task_queue_name',
  buildId: buildId,
  useVersioning: true,
});
```
<!-- docs/develop/typescript/worker-versioning-legacy.mdx:35-44 -->

In the legacy shape, `buildId` was a top-level field and `useVersioning` was a separate boolean. Do not import that shape into the modern `workerDeploymentOptions` form; the field names and nesting differ. <!-- docs/develop/typescript/worker-versioning-legacy.mdx:17-22, :35-44 -->

### Deployment Workflow

1. Deploy a new Worker with a new `buildId` under the same `deploymentName`.
2. Use the Temporal CLI to set the new version as current:
   ```bash
   temporal worker deployment set-current-version \
       --deployment-name YourDeploymentName --build-id YourBuildID
   ```
   <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:332-335 -->
3. New Workflows route to the new version; existing Pinned Workflows continue on their original version until they complete. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:38-39, :92-95 -->
4. Once the old version reaches the `Drained` status (no open Pinned Workflows remain), you can decommission its Workers. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:622-632 -->

`temporal worker deployment set-current-version` and `set-ramping-version` also accept `--unversioned` (mutually exclusive with `--build-id`) to target unversioned Workers as the current/ramping target. <!-- docs/cli/worker.mdx:373-388, :437-442 -->

### When to use Worker Versioning

Worker Versioning is the default recommendation for deploying Workflow code changes in production if you can run versioned Worker deployments; prefer it over patching. It pairs especially well with blue-green and rainbow deployments, supports gradual ramping, instant rollback, and Workflow Pinning. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:23-42, :117-126 -->

For long-running Workflows, Temporal also supports an experimental "Upgrade on Continue-as-New" pattern, which lets Pinned Workflows advance to a newer version at Continue-as-New boundaries without patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-555 -->

## Best Practices

1. Use descriptive `patchId` names that explain the change
2. Follow the three-step patching process completely before removing patches
3. Use List Filters to verify no running Workflows before removing version support
4. Keep Worker Deployment names consistent across all versions
5. Use unique, traceable Build IDs (git hashes, semver, timestamps)
6. Test version transitions with replay tests before deploying
