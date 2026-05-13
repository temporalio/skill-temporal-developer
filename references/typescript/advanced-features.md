# TypeScript SDK Advanced Features

## Schedules

Create recurring workflow executions.

```typescript
import { Client, ScheduleOverlapPolicy } from '@temporalio/client';

const client = new Client();

// Create a schedule
const schedule = await client.schedule.create({
  scheduleId: 'daily-report',
  spec: {
    intervals: [{ every: '1 day' }],
  },
  action: {
    type: 'startWorkflow',
    workflowType: 'dailyReportWorkflow',
    taskQueue: 'reports',
    args: [],
  },
  policies: {
    overlap: ScheduleOverlapPolicy.SKIP,
  },
});

// Manage schedules
const handle = client.schedule.getHandle('daily-report');
await handle.pause('Maintenance window');
await handle.unpause();
await handle.trigger();  // Run immediately
await handle.delete();
```

## Async Activity Completion

Complete an activity asynchronously from outside the activity function. Useful when the activity needs to wait for an external event.

**In the activity - return the task token:**

```typescript
import { CompleteAsyncError, activityInfo } from '@temporalio/activity';

export async function doSomethingAsync(): Promise<string> {
  const taskToken: Uint8Array = activityInfo().taskToken;
  setTimeout(() => doSomeWork(taskToken), 1000);
  throw new CompleteAsyncError();
}
```

**External completion (from another process, machine, etc.):**

```typescript
import { Client } from '@temporalio/client';

async function doSomeWork(taskToken: Uint8Array): Promise<void> {
  const client = new Client();
  // does some work...
  await client.activity.complete(taskToken, "Job's done!");
}
```

**When to use:**

- Waiting for human approval
- Waiting for external webhook callback
- Long-polling external systems

## Worker Tuning

Configure worker capacity for production workloads:

```typescript
import { Worker, NativeConnection } from '@temporalio/worker';

const worker = await Worker.create({
  connection: await NativeConnection.connect({ address: 'temporal:7233' }),
  taskQueue: 'my-queue',
  workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }, // Pre-bundled for production
  activities,

  // Workflow execution concurrency (default: 40)
  maxConcurrentWorkflowTaskExecutions: 100,

  // Activity execution concurrency (default: 100)
  maxConcurrentActivityTaskExecutions: 200,

  // Graceful shutdown timeout (default: 0)
  shutdownGraceTime: '30 seconds',

  // Max cached workflows (memory vs latency tradeoff)
  maxCachedWorkflows: 1000,
});
```

**Key settings:**

- `maxConcurrentWorkflowTaskExecutions`: Max workflows running simultaneously (default: 40)
- `maxConcurrentActivityTaskExecutions`: Max activities running simultaneously (default: 100)
- `shutdownGraceTime`: Time to wait for in-progress work before forced shutdown
- `maxCachedWorkflows`: Number of workflows to keep in cache (reduces replay on cache hit)

## Worker Connection Replacement

Available since `@temporalio/worker` **v1.15.0**. <!-- sdk-typescript: releases v1.15.0, PR #1902 -->

A running `Worker` exposes its underlying service connection as a property. Assigning a new `NativeConnection` to that property swaps the connection in place — the Worker keeps running, and **subsequent** calls it makes to Temporal use the new connection. <!-- sdk-typescript: packages/worker/src/worker.ts, JSDoc on `set connection` -->

### API

```typescript
class Worker {
  // Returns undefined for replay workers (workers created without a connection).
  get client(): Client | undefined;          // <!-- sdk-typescript: packages/worker/src/worker.ts -->
  get connection(): NativeConnection | undefined;  // <!-- sdk-typescript: packages/worker/src/worker.ts -->

  // Replace the connection. The Worker must have been created with one.
  set connection(newConnection: NativeConnection);  // <!-- sdk-typescript: packages/worker/src/worker.ts:1286 -->
}
```

There is **no** `worker.replaceConnection(...)` method and **no** `worker.replaceClient(...)` method on the public API — assignment to the `connection` property is the entire surface. <!-- sdk-typescript: packages/worker/src/worker.ts -->

### Usage

```typescript
import { Worker, NativeConnection } from '@temporalio/worker';

const initialConnection = await NativeConnection.connect({ address: 'temporal-a:7233' });
const worker = await Worker.create({
  connection: initialConnection,
  namespace: 'default',
  taskQueue: 'my-queue',
  workflowBundle: { codePath: require.resolve('./workflow-bundle.js') },
  activities,
});

// Start the worker (do not await — runs until shutdown).
void worker.run();

// Later — swap the connection without restarting the worker.
const replacementConnection = await NativeConnection.connect({ address: 'temporal-b:7233' });
worker.connection = replacementConnection;  // <!-- sdk-typescript: packages/test/src/test-worker-connection-replacement.ts -->
```

### Behavior and constraints

- **Must be created with a connection.** Assigning to `worker.connection` throws `IllegalStateError('Cannot replace connection on a worker without a connection')` if the Worker was constructed without one (for example, a replay worker). <!-- sdk-typescript: packages/worker/src/worker.ts:1287 -->
- **Identity is a no-op.** If the new connection wraps the same underlying native client as the current one, the setter returns without doing anything. <!-- sdk-typescript: packages/worker/src/worker.ts:~1288 -->
- **Previous connection is closed only if the SDK created it.** If the previous `NativeConnection` is one the SDK created internally (an `InternalNativeConnection`), it is closed asynchronously after replacement. A user-supplied `NativeConnection` on the previous slot is **not** closed by the setter — closing it is the caller's responsibility. <!-- sdk-typescript: packages/worker/src/worker.ts:~1303 -->
- **Cached `client` is cleared.** `worker.client` is lazily constructed and cached; after replacement the cache is dropped and a new `Client` is created on the next access. <!-- sdk-typescript: packages/worker/src/worker.ts:~1300 -->
- **Errors propagate.** If the native bridge fails to swap the underlying client, the setter throws. <!-- sdk-typescript: packages/worker/src/worker.ts, JSDoc on `set connection` -->

### When to use it

This API is intended for **refreshing** a Worker's connection — for example, after a transport-level disruption or when long-lived credentials need a fresh underlying gRPC channel. Note that for API-key updates specifically, the existing `connection.setApiKey(newKey)` on the same `NativeConnection` is usually sufficient and does not require replacing the connection object. <!-- docs/develop/typescript/client/temporal-client.mdx:473 -->

Switching a Worker to a **different Temporal server** is technically possible via this API but is explicitly called out as "not a recommended use case" by the feature's introducing PR. <!-- sdk-typescript: PR #1902 description --> For server migrations, prefer shutting down the Worker and starting a new one against the new server.

## Sinks

Sinks allow workflows to emit events for side effects (logging, metrics).

```typescript
import { proxySinks, Sinks } from '@temporalio/workflow';

// Define sink interface
export interface LoggerSinks extends Sinks {
  logger: {
    info(message: string, attrs: Record<string, unknown>): void;
    error(message: string, attrs: Record<string, unknown>): void;
  };
}

// Use in workflow
const { logger } = proxySinks<LoggerSinks>();

export async function myWorkflow(input: string): Promise<string> {
  logger.info('Workflow started', { input });

  const result = await someActivity(input);

  logger.info('Workflow completed', { result });
  return result;
}

// Implement sink in worker
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'), // Use workflowBundle for production
  activities,
  taskQueue: 'my-queue',
  sinks: {
    logger: {
      info: {
        fn(workflowInfo, message, attrs) {
          console.log(`[${workflowInfo.workflowId}] ${message}`, attrs);
        },
        callDuringReplay: false,  // Don't log during replay
      },
      error: {
        fn(workflowInfo, message, attrs) {
          console.error(`[${workflowInfo.workflowId}] ${message}`, attrs);
        },
        callDuringReplay: false,
      },
    },
  },
});
```
