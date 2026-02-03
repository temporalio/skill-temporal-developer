# TypeScript SDK Patterns

## Signals

**WHY**: Signals allow external clients or other workflows to send data to a running workflow asynchronously. Unlike queries (read-only), signals can mutate workflow state.

**WHEN to use**:
- Sending events to a running workflow (e.g., approval, cancellation request)
- Adding items to a workflow's queue or collection
- Notifying a workflow about external state changes
- Implementing human-in-the-loop workflows

```typescript
import { defineSignal, setHandler, condition } from '@temporalio/workflow';

const approveSignal = defineSignal<[boolean]>('approve');
const addItemSignal = defineSignal<[string]>('addItem');

export async function orderWorkflow(): Promise<string> {
  let approved = false;
  const items: string[] = [];

  setHandler(approveSignal, (value) => {
    approved = value;
  });

  setHandler(addItemSignal, (item) => {
    items.push(item);
  });

  await condition(() => approved);
  return `Processed ${items.length} items`;
}
```

## Queries

**WHY**: Queries provide a synchronous, read-only way to inspect workflow state. They execute instantly without modifying workflow state or history.

**WHEN to use**:
- Exposing workflow progress or status to external systems
- Building dashboards or monitoring UIs
- Debugging workflow state during development
- Implementing "get current state" endpoints

```typescript
import { defineQuery, setHandler } from '@temporalio/workflow';

const statusQuery = defineQuery<string>('status');
const progressQuery = defineQuery<number>('progress');

export async function progressWorkflow(): Promise<void> {
  let status = 'running';
  let progress = 0;

  setHandler(statusQuery, () => status);
  setHandler(progressQuery, () => progress);

  for (let i = 0; i < 100; i++) {
    progress = i;
    await doWork();
  }
  status = 'completed';
}
```

## Updates

**WHY**: Updates combine the state mutation capability of signals with the synchronous response of queries. The caller waits for the update handler to complete and receives a return value.

**WHEN to use**:
- Operations that modify state AND need to return a result (e.g., "add item and return new count")
- Validation before accepting a change (use validators to reject invalid updates)
- Synchronous request-response patterns within a workflow
- Replacing signal+query combos where you signal then immediately query

### Defining Update Handlers

```typescript
import { defineUpdate, setHandler, condition } from '@temporalio/workflow';

// Define the update - specify return type and argument types
export const addItemUpdate = defineUpdate<number, [string]>('addItem');
export const addItemValidatedUpdate = defineUpdate<number, [string]>('addItemValidated');

export async function orderWorkflow(): Promise<string> {
  const items: string[] = [];
  let completed = false;

  // Simple update handler - returns new item count
  setHandler(addItemUpdate, (item: string) => {
    items.push(item);
    return items.length;
  });

  // Update handler with validator - rejects invalid input before execution
  setHandler(
    addItemValidatedUpdate,
    (item: string) => {
      items.push(item);
      return items.length;
    },
    {
      validator: (item: string) => {
        if (!item) throw new Error('Item cannot be empty');
        if (items.length >= 100) throw new Error('Order is full');
      },
    }
  );

  await condition(() => completed);
  return `Order with ${items.length} items completed`;
}
```

### Calling Updates from Client

```typescript
import { Client } from '@temporalio/client';
import { addItemUpdate } from './workflows';

const client = new Client();
const handle = client.workflow.getHandle('order-123');

// Execute update and wait for result
const count = await handle.executeUpdate(addItemUpdate, { args: ['new-item'] });
console.log(`Order now has ${count} items`);

// Start update and get handle for later result retrieval
const updateHandle = await handle.startUpdate(addItemUpdate, {
  args: ['another-item'],
  waitForStage: 'ACCEPTED',
});
const result = await updateHandle.result();
```

## Signal-with-Start

**WHY**: Atomically starts a workflow and sends it a signal in a single operation. Avoids race conditions where the workflow might complete before receiving the signal.

**WHEN to use**:
- Starting a workflow and immediately sending it data
- Idempotent "create or update" patterns
- Ensuring a signal is delivered even if the workflow needs to be started first

```typescript
import { Client } from '@temporalio/client';
import { orderSignal } from './workflows';

const client = new Client();

const handle = await client.workflow.signalWithStart('orderWorkflow', {
  workflowId: `order-${customerId}`,
  taskQueue: 'orders',
  args: [customerId],
  signal: orderSignal,
  signalArgs: [{ item: 'product-123', quantity: 2 }],
});
```

## Child Workflows

**WHY**: Child workflows decompose complex workflows into smaller, reusable units. Each child has its own history, preventing history bloat.

**WHEN to use**:
- Breaking down large workflows to prevent history growth
- Reusing workflow logic across multiple parent workflows
- Isolating failures - a child can fail without failing the parent

```typescript
import { executeChild } from '@temporalio/workflow';

export async function parentWorkflow(orders: Order[]): Promise<string[]> {
  const results: string[] = [];

  for (const order of orders) {
    const result = await executeChild(processOrderWorkflow, {
      args: [order],
      workflowId: `order-${order.id}`,
    });
    results.push(result);
  }

  return results;
}
```

### Child Workflow Options

```typescript
import { executeChild, ParentClosePolicy, ChildWorkflowCancellationType } from '@temporalio/workflow';

const result = await executeChild(childWorkflow, {
  args: [input],
  workflowId: `child-${workflowInfo().workflowId}`,

  // ParentClosePolicy - what happens to child when parent closes
  // TERMINATE (default), ABANDON, REQUEST_CANCEL
  parentClosePolicy: ParentClosePolicy.TERMINATE,

  // ChildWorkflowCancellationType - how cancellation is handled
  // WAIT_CANCELLATION_COMPLETED (default), WAIT_CANCELLATION_REQUESTED, TRY_CANCEL, ABANDON
  cancellationType: ChildWorkflowCancellationType.WAIT_CANCELLATION_COMPLETED,
});
```

## Parallel Execution

**WHY**: Running multiple operations concurrently improves workflow performance when operations are independent.

**WHEN to use**:
- Processing multiple independent items
- Calling multiple APIs that don't depend on each other
- Fan-out/fan-in patterns

```typescript
export async function parallelWorkflow(items: string[]): Promise<string[]> {
  return await Promise.all(
    items.map((item) => processItem(item))
  );
}
```

## Continue-as-New

**WHY**: Prevents unbounded history growth by completing the current workflow and starting a new run with the same workflow ID.

**WHEN to use**:
- Long-running workflows that would accumulate too much history
- Entity/subscription workflows that run indefinitely
- Batch processing with large numbers of iterations

```typescript
import { continueAsNew, workflowInfo } from '@temporalio/workflow';

export async function longRunningWorkflow(state: State): Promise<string> {
  while (true) {
    state = await processNextBatch(state);

    if (state.isComplete) {
      return 'done';
    }

    const info = workflowInfo();
    if (info.continueAsNewSuggested || info.historyLength > 10000) {
      await continueAsNew<typeof longRunningWorkflow>(state);
    }
  }
}
```

## Cancellation Scopes

**WHY**: Control how cancellation propagates to activities and child workflows. Essential for cleanup logic and timeout behavior.

**WHEN to use**:
- Ensuring cleanup activities run even when workflow is cancelled
- Implementing timeouts for activity groups
- Manual cancellation of specific operations

```typescript
import { CancellationScope, sleep } from '@temporalio/workflow';

export async function scopedWorkflow(): Promise<void> {
  // Non-cancellable scope - runs even if workflow cancelled
  await CancellationScope.nonCancellable(async () => {
    await cleanupActivity();
  });

  // Timeout scope
  await CancellationScope.withTimeout('5 minutes', async () => {
    await longRunningActivity();
  });

  // Manual cancellation
  const scope = new CancellationScope();
  const promise = scope.run(() => someActivity());
  scope.cancel();
}
```

## Saga Pattern

**WHY**: Implement distributed transactions by tracking compensation actions. If any step fails, previously completed steps are rolled back in reverse order.

**WHEN to use**:
- Multi-step business transactions that span multiple services
- Operations where partial completion requires cleanup
- Financial transactions, order processing, booking systems

```typescript
export async function sagaWorkflow(order: Order): Promise<string> {
  const compensations: Array<() => Promise<void>> = [];

  try {
    await reserveInventory(order);
    compensations.push(() => releaseInventory(order));

    await chargePayment(order);
    compensations.push(() => refundPayment(order));

    await shipOrder(order);
    return 'Order completed';
  } catch (err) {
    for (const compensate of compensations.reverse()) {
      try {
        await compensate();
      } catch (compErr) {
        console.log('Compensation failed', compErr);
      }
    }
    throw err;
  }
}
```

## Entity Workflow Pattern

**WHY**: Model a long-lived entity as a single workflow that handles events over its lifetime.

**WHEN to use**:
- Modeling stateful entities that exist for extended periods
- Subscription management, user sessions
- Any entity that receives events and must maintain consistent state

```typescript
import { defineSignal, defineQuery, setHandler, condition, continueAsNew, workflowInfo } from '@temporalio/workflow';

const eventSignal = defineSignal<[Event]>('event');
const stateQuery = defineQuery<EntityState>('state');

export async function entityWorkflow(entityId: string, initialState: EntityState): Promise<void> {
  let state = initialState;

  setHandler(stateQuery, () => state);
  setHandler(eventSignal, (event: Event) => {
    state = applyEvent(state, event);
  });

  while (!state.deleted) {
    await condition(() => state.deleted || workflowInfo().continueAsNewSuggested);
    if (workflowInfo().continueAsNewSuggested && !state.deleted) {
      await continueAsNew<typeof entityWorkflow>(entityId, state);
    }
  }
}
```

## Triggers (Promise-like Signals)

**WHY**: Triggers provide a one-shot promise that resolves when a signal is received. Cleaner than condition() for single-value signals.

**WHEN to use**:
- Waiting for a single response (approval, completion notification)
- Converting signal-based events into awaitable promises

```typescript
import { Trigger } from '@temporalio/workflow';

export async function triggerWorkflow(): Promise<string> {
  const approvalTrigger = new Trigger<boolean>();

  setHandler(approveSignal, (approved) => {
    approvalTrigger.resolve(approved);
  });

  const approved = await approvalTrigger;
  return approved ? 'Approved' : 'Rejected';
}
```

## Timers

**WHY**: Durable timers that survive worker restarts. Use sleep() for delays instead of JavaScript setTimeout.

**WHEN to use**:
- Implementing delays between steps
- Scheduling future actions
- Timeout patterns (combined with cancellation scopes)

```typescript
import { sleep, CancellationScope } from '@temporalio/workflow';

export async function timerWorkflow(): Promise<string> {
  await sleep('1 hour');

  const timerScope = new CancellationScope();
  const timerPromise = timerScope.run(() => sleep('1 hour'));

  setHandler(cancelSignal, () => {
    timerScope.cancel();
  });

  try {
    await timerPromise;
    return 'Timer completed';
  } catch {
    return 'Timer cancelled';
  }
}
```

## uuid4() Utility

**WHY**: Generate deterministic UUIDs safe to use in workflows. Uses the workflow seeded PRNG, so the same UUID is generated during replay.

**WHEN to use**:
- Generating unique IDs for child workflows
- Creating idempotency keys
- Any situation requiring unique identifiers in workflow code

```typescript
import { uuid4 } from '@temporalio/workflow';

export async function workflowWithIds(): Promise<void> {
  const childWorkflowId = uuid4();
  await executeChild(childWorkflow, {
    workflowId: childWorkflowId,
    args: [input],
  });
}
```
