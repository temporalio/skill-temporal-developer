# TypeScript SDK Versioning

## Overview

The TypeScript SDK provides multiple approaches to safely change Workflow code while maintaining compatibility with running Workflows: the Patching API, Workflow Type Versioning, and Worker Versioning.

## Why Versioning Matters

Temporal provides durable execution through **History Replay**. When a Worker needs to restore Workflow state, it re-executes the Workflow code from the beginning. If you change Workflow code while executions are still running, replay can fail because the new code produces different Commands than the original history.

Versioning strategies allow you to safely deploy changes without breaking in-progress Workflow Executions.

## Workflow Versioning with the Patching API

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

### Three-Step Patching Process

Patching is a three-step process for safely deploying changes:

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

### Multiple Patches

A Workflow can have multiple patches for different changes:

```typescript
export async function shippingConfirmation(): Promise<void> {
  if (patched('sendEmail')) {
    await sendEmail();
  } else if (patched('sendTextMessage')) {
    await sendTextMessage();
  } else if (patched('sendTweet')) {
    await sendTweet();
  } else {
    await sendFax();
  }
}
```

You can use a single `patchId` for multiple changes deployed together.

### Query Filters for Versioned Workflows

Use List Filters to find Workflows by version:

```
# Find running Workflows with a specific patch
WorkflowType = "shippingConfirmation" AND ExecutionStatus = "Running" AND TemporalChangeVersion="changedNotificationType"

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
  workflowsPath: require.resolve('./workflows'),
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

Worker Versioning allows multiple Worker versions to run simultaneously, routing Workflows to specific versions without code-level patching.

### Key Concepts

- **Worker Deployment**: A logical name for your application (e.g., "order-service")
- **Worker Deployment Version**: A specific build of your code (deployment name + Build ID)

### Configuring Workers for Versioning

```typescript
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue: 'my-queue',
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: {
      deploymentName: 'order-service',
      buildId: '1.0.0',  // Or git hash, build number, etc.
    },
    defaultVersioningBehavior: 'PINNED',  // Or 'AUTO_UPGRADE'
  },
  connection: nativeConnection,
});
```

**Configuration options:**
- `useWorkerVersioning`: Enables Worker Versioning
- `version.deploymentName`: Logical name for your service (consistent across versions)
- `version.buildId`: Unique identifier for this build (git hash, semver, build number)
- `defaultVersioningBehavior`: How Workflows behave when versions change

### Versioning Behaviors

#### PINNED Behavior

Workflows are locked to the Worker version they started on:

```typescript
workerDeploymentOptions: {
  useWorkerVersioning: true,
  version: { buildId: '1.0', deploymentName: 'order-service' },
  defaultVersioningBehavior: 'PINNED',
}
```

**Characteristics:**
- Workflows run only on their assigned version
- No patching required in Workflow code
- Cannot use other versioning APIs
- Ideal for short-running Workflows where consistency matters

**Use PINNED when:**
- You want to eliminate version compatibility complexity
- Workflows are short-running
- Stability is more important than getting latest updates

#### AUTO_UPGRADE Behavior

Workflows can move to newer Worker versions:

```typescript
workerDeploymentOptions: {
  useWorkerVersioning: true,
  version: { buildId: '1.0', deploymentName: 'order-service' },
  defaultVersioningBehavior: 'AUTO_UPGRADE',
}
```

**Characteristics:**
- Workflows can be rerouted to new versions
- Once moved to a newer version, cannot return to older ones
- May require patching to handle version transitions
- Ideal for long-running Workflows that need bug fixes

**Use AUTO_UPGRADE when:**
- Workflows are long-running (weeks or months)
- You want Workflows to benefit from bug fixes
- Migrating from rolling deployments

### Deployment Strategies

#### Blue-Green Deployments

Maintain two environments and switch traffic between them:

1. Deploy new version to idle environment
2. Run validation tests
3. Switch traffic to new environment
4. Keep old environment for instant rollback

#### Rainbow Deployments

Multiple Worker versions run simultaneously:

```typescript
// Version 1.0 Workers
const worker1 = await Worker.create({
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: { buildId: '1.0', deploymentName: 'order-service' },
    defaultVersioningBehavior: 'PINNED',
  },
  // ...
});

// Version 2.0 Workers (deployed alongside 1.0)
const worker2 = await Worker.create({
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: { buildId: '2.0', deploymentName: 'order-service' },
    defaultVersioningBehavior: 'PINNED',
  },
  // ...
});
```

**Benefits:**
- Existing PINNED Workflows complete on their original version
- New Workflows use the latest version
- Add new versions without replacing existing ones
- Supports gradual traffic ramping

## Choosing a Versioning Strategy

| Strategy | Best For | Trade-offs |
|----------|----------|------------|
| Patching API | Incremental changes to long-running Workflows | Requires maintaining patch branches in code |
| Workflow Type Versioning | Major incompatible changes | Requires code duplication and client updates |
| Worker Versioning (PINNED) | Short-running Workflows, new applications | Requires infrastructure to run multiple versions |
| Worker Versioning (AUTO_UPGRADE) | Long-running Workflows, migrations | May require patching for safe transitions |

## Best Practices

1. Use descriptive `patchId` names that explain the change
2. Follow the three-step patching process completely before removing patches
3. Use List Filters to verify no running Workflows before removing version support
4. Keep Worker Deployment names consistent across all versions
5. Use unique, traceable Build IDs (git hashes, semver, timestamps)
6. Choose PINNED for new applications with short-running Workflows
7. Choose AUTO_UPGRADE when migrating from rolling deployments or for long-running Workflows
8. Test version transitions with replay tests before deploying
