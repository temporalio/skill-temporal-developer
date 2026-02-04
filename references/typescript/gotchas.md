# TypeScript Gotchas

TypeScript-specific mistakes and anti-patterns. See also [Common Gotchas](../core/common-gotchas.md) for language-agnostic concepts.

## Idempotency

```typescript
// BAD - May charge customer multiple times on retry
export async function chargePayment(orderId: string, amount: number): Promise<string> {
  return await paymentApi.charge(customerId, amount);
}

// GOOD - Safe for retries
export async function chargePayment(orderId: string, amount: number): Promise<string> {
  return await paymentApi.charge(customerId, amount, {
    idempotencyKey: `order-${orderId}`,
  });
}
```

## Replay Safety

### Side Effects in Workflows

```typescript
// BAD - console.log runs on every replay
export async function notificationWorkflow(): Promise<void> {
  console.log('Starting workflow'); // Runs on replay too
  await sendSlackNotification('Started'); // Side effect in workflow!
  await activities.doWork();
}

// GOOD - Use workflow logger and activities for side effects
import { log } from '@temporalio/workflow';

export async function notificationWorkflow(): Promise<void> {
  log.info('Starting workflow'); // Only logs on first execution
  await activities.sendNotification('Started');
}
```

### Non-Deterministic Operations

The TypeScript SDK automatically replaces some non-deterministic operations:

```typescript
// These are SAFE - automatically replaced by SDK
const now = Date.now();           // Deterministic
const random = Math.random();     // Deterministic
const id = crypto.randomUUID();   // Deterministic (if using workflow's crypto)

// For explicit deterministic UUID, use:
import { uuid4 } from '@temporalio/workflow';
const id = uuid4();
```

## Query Handlers

### Modifying State

```typescript
// BAD - Query modifies state
const queues = new Map<string, string[]>();

export const getNextItemQuery = defineQuery<string | undefined, [string]>('getNextItem');

export async function queueWorkflow(queueId: string): Promise<void> {
  const queue: string[] = [];

  setHandler(getNextItemQuery, () => {
    return queue.shift(); // Mutates state!
  });

  await condition(() => false);
}

// GOOD - Query reads, Update modifies
export const peekQuery = defineQuery<string | undefined>('peek');
export const dequeueUpdate = defineUpdate<string | undefined>('dequeue');

export async function queueWorkflow(): Promise<void> {
  const queue: string[] = [];

  setHandler(peekQuery, () => queue[0]);

  setHandler(dequeueUpdate, () => queue.shift());

  await condition(() => false);
}
```

### Blocking in Queries

```typescript
// BAD - Queries cannot await
setHandler(getDataQuery, async () => {
  if (!data) {
    data = await activities.fetchData(); // Cannot await in query!
  }
  return data;
});

// GOOD - Query returns state, signal triggers refresh
setHandler(refreshSignal, async () => {
  data = await activities.fetchData();
});

setHandler(getDataQuery, () => data);
```

## Activity Imports

### Importing Implementations Instead of Types

**The Problem**: Importing activity implementations brings Node.js code into the V8 workflow sandbox, causing bundling errors or runtime failures.

```typescript
// BAD - Brings actual code into workflow sandbox
import * as activities from './activities';

const { greet } = proxyActivities<typeof activities>({
  startToCloseTimeout: '1 minute',
});

// GOOD - Type-only import
import type * as activities from './activities';

const { greet } = proxyActivities<typeof activities>({
  startToCloseTimeout: '1 minute',
});
```

### Importing Node.js Modules in Workflows

```typescript
// BAD - fs is not available in workflow sandbox
import * as fs from 'fs';

export async function myWorkflow(): Promise<void> {
  const data = fs.readFileSync('file.txt'); // Will fail!
}

// GOOD - File I/O belongs in activities
export async function myWorkflow(): Promise<void> {
  const data = await activities.readFile('file.txt');
}
```

## Bundling Issues

### Missing Dependencies in Workflow Bundle

```typescript
// If using external packages in workflows, ensure they're bundled

// worker.ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  bundlerOptions: {
    // Include specific packages if needed
    ignoreModules: ['some-node-only-package'],
  },
});
```

### Package Version Mismatches

All `@temporalio/*` packages must have the same version:

```json
// BAD - Version mismatch
{
  "dependencies": {
    "@temporalio/client": "1.9.0",
    "@temporalio/worker": "1.8.0",
    "@temporalio/workflow": "1.9.1"
  }
}

// GOOD - All versions match
{
  "dependencies": {
    "@temporalio/client": "1.9.0",
    "@temporalio/worker": "1.9.0",
    "@temporalio/workflow": "1.9.0"
  }
}
```

## Error Handling

### Swallowing Errors

```typescript
// BAD - Error is hidden
export async function riskyWorkflow(): Promise<void> {
  try {
    await activities.riskyOperation();
  } catch {
    // Error is lost!
  }
}

// GOOD - Handle appropriately
import { log } from '@temporalio/workflow';

export async function riskyWorkflow(): Promise<void> {
  try {
    await activities.riskyOperation();
  } catch (err) {
    log.error('Activity failed', { error: err });
    throw err; // Or use fallback, compensate, etc.
  }
}
```

### Wrong Retry Classification

```typescript
// BAD - Network errors should be retried
export async function callApi(): Promise<Response> {
  try {
    return await fetch(url);
  } catch (err) {
    throw ApplicationFailure.nonRetryable('Connection failed');
  }
}

// GOOD - Only permanent failures are non-retryable
export async function callApi(): Promise<Response> {
  try {
    return await fetch(url);
  } catch (err) {
    if (err instanceof InvalidCredentialsError) {
      throw ApplicationFailure.nonRetryable('Invalid API key');
    }
    throw err; // Let Temporal retry network errors
  }
}
```

## Retry Policies

### Too Aggressive

```typescript
// BAD - Gives up too easily
const result = await activities.flakyApiCall({
  scheduleToCloseTimeout: '30 seconds',
  retry: { maximumAttempts: 1 },
});

// GOOD - Resilient to transient failures
const result = await activities.flakyApiCall({
  scheduleToCloseTimeout: '10 minutes',
  retry: {
    initialInterval: '1 second',
    maximumInterval: '1 minute',
    backoffCoefficient: 2,
    maximumAttempts: 10,
  },
});
```

## Cancellation

### Not Handling Cancellation

```typescript
// BAD - Cleanup doesn't run on cancellation
export async function workflowWithCleanup(): Promise<void> {
  await activities.acquireResource();
  await activities.doWork();
  await activities.releaseResource(); // Never runs if cancelled!
}

// GOOD - Use CancellationScope for cleanup
import { CancellationScope } from '@temporalio/workflow';

export async function workflowWithCleanup(): Promise<void> {
  await activities.acquireResource();
  try {
    await activities.doWork();
  } finally {
    // Run cleanup even on cancellation
    await CancellationScope.nonCancellable(async () => {
      await activities.releaseResource();
    });
  }
}
```

## Heartbeating

### Forgetting to Heartbeat Long Activities

```typescript
// BAD - No heartbeat, can't detect stuck activities
export async function processLargeFile(path: string): Promise<void> {
  for await (const chunk of readChunks(path)) {
    await processChunk(chunk); // Takes hours, no heartbeat
  }
}

// GOOD - Regular heartbeats with progress
import { heartbeat } from '@temporalio/activity';

export async function processLargeFile(path: string): Promise<void> {
  let i = 0;
  for await (const chunk of readChunks(path)) {
    heartbeat(`Processing chunk ${i++}`);
    await processChunk(chunk);
  }
}
```

### Heartbeat Timeout Too Short

```typescript
// BAD - Heartbeat timeout shorter than processing time
const { processChunk } = proxyActivities<typeof activities>({
  startToCloseTimeout: '30 minutes',
  heartbeatTimeout: '10 seconds', // Too short!
});

// GOOD - Heartbeat timeout allows for processing variance
const { processChunk } = proxyActivities<typeof activities>({
  startToCloseTimeout: '30 minutes',
  heartbeatTimeout: '2 minutes',
});
```

## Testing

### Not Testing Failures

```typescript
import { TestWorkflowEnvironment } from '@temporalio/testing';
import { Worker } from '@temporalio/worker';

test('handles activity failure', async () => {
  const env = await TestWorkflowEnvironment.createTimeSkipping();

  const worker = await Worker.create({
    connection: env.nativeConnection,
    taskQueue: 'test',
    workflowsPath: require.resolve('./workflows'),
    activities: {
      // Activity that always fails
      riskyOperation: async () => {
        throw ApplicationFailure.nonRetryable('Simulated failure');
      },
    },
  });

  await worker.runUntil(async () => {
    await expect(
      env.client.workflow.execute(riskyWorkflow, {
        workflowId: 'test-failure',
        taskQueue: 'test',
      })
    ).rejects.toThrow('Simulated failure');
  });

  await env.teardown();
});
```

### Not Testing Replay

```typescript
import { Worker } from '@temporalio/worker';

test('replay compatibility', async () => {
  const history = await import('./fixtures/workflow_history.json');

  // Fails if current code is incompatible with history
  await Worker.runReplayHistory({
    workflowsPath: require.resolve('./workflows'),
    history,
  });
});
```

## Timers and Sleep

### Using JavaScript setTimeout

```typescript
// BAD - setTimeout is not durable
export async function delayedWorkflow(): Promise<void> {
  await new Promise(resolve => setTimeout(resolve, 60000)); // Not durable!
  await activities.doWork();
}

// GOOD - Use workflow sleep
import { sleep } from '@temporalio/workflow';

export async function delayedWorkflow(): Promise<void> {
  await sleep('1 minute'); // Durable, survives restarts
  await activities.doWork();
}
```
