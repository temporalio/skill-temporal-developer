# Task Queue Priority and Fairness in TypeScript

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

TypeScript supplies Priority and Fairness metadata through the `priority` option. Its fields inherit independently. Omit `fairnessKey` and `fairnessWeight` for Priority-only use, or omit `priorityKey` for Fairness at the default Priority.

```ts
const tenantPriority = {
  priorityKey: 1,
  fairnessKey: 'tenant-123',
  fairnessWeight: 2.0,
};
```

## Start a Workflow

Set `priority` in `WorkflowClient.start` options:

```ts
const handle = await client.workflow.start(myWorkflow, {
  args: ['input'],
  taskQueue: 'my-task-queue',
  workflowId: 'my-workflow-id',
  priority: tenantPriority,
});
```

## Override an Activity

Set `priority` in the Activity proxy options:

```ts
import { proxyActivities } from '@temporalio/workflow';
import type * as activities from './activities';

const { processOrder } = proxyActivities<typeof activities>({
  startToCloseTimeout: '30 seconds',
  priority: tenantPriority,
});

const result = await processOrder('order-123');
```

## Override a Child Workflow

Set `priority` in `executeChild` or `startChild` options:

```ts
import { executeChild } from '@temporalio/workflow';

const result = await executeChild(myChildWorkflow, {
  args: ['input'],
  workflowId: 'my-child-workflow-id',
  priority: tenantPriority,
});
```

If an Activity or Child Workflow omits `priority`, it inherits the parent Workflow's values.
