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

## Worker Service Connection Lifecycle

A Worker's service connection is a `NativeConnection` from `@temporalio/worker` <!-- docs/develop/typescript/client/temporal-client.mdx:487 -->. Unlike the `Connection` class in `@temporalio/client`, which Clients use, `NativeConnection` is what `Worker.create({ connection })` accepts <!-- docs/develop/typescript/client/temporal-client.mdx:487-490 -->. Both classes accept the same set of connection options <!-- docs/develop/typescript/client/temporal-client.mdx:612-615 -->.

The TypeScript SDK exposes APIs to manage that connection over a Worker's lifetime: replace it wholesale, update auth credentials in place, or scope metadata/deadlines/cancellation to a single request — all without restarting the Worker.

### Replacing a Worker's connection at runtime

The `Worker.connection` accessor is a getter/setter. The setter "allows the worker to switch to a different Temporal server or update connection configuration without restarting the worker" <!-- ts-sdk: worker.Worker#connection -->. Subsequent gRPC calls (poll responses, heartbeats) use the new connection; a fresh internal client is built automatically from it <!-- ts-sdk: worker.Worker#connection -->.

```typescript
import { NativeConnection, Worker } from '@temporalio/worker';

const oldConnection = await NativeConnection.connect({ address: 'old-host:7233' });
const worker = await Worker.create({
  connection: oldConnection,
  taskQueue: 'my-queue',
  workflowsPath: require.resolve('./workflows'),
});

// ...later, fail over to a different server / cluster:
const newConnection = await NativeConnection.connect({ address: 'new-host:7233' });
worker.connection = newConnection;

// Stop or detach all Workers before closing the old connection.
await oldConnection.close();
```

**Caveats:**

- The setter throws if the Worker was created without a connection (e.g., replay Workers) <!-- ts-sdk: worker.Worker#connection -->. `worker.connection` returns `undefined` in that case <!-- ts-sdk: worker.Worker#connection -->.
- The setter throws if the connection replacement fails <!-- ts-sdk: worker.Worker#connection -->.
- **Swap first, close second.** `NativeConnection.close()` throws `IllegalStateError` if any Worker is still using the connection <!-- ts-sdk: worker.NativeConnection#close -->. Assign `worker.connection = newConnection` (or shut down the Worker) before calling `oldConnection.close()`.

### Updating auth or metadata in place

To rotate an API key without building a new connection, call `setApiKey` on the existing `NativeConnection`:

```typescript
await connection.setApiKey(newApiKey);
```

Signature: `setApiKey(apiKey: string): Promise<void>` <!-- ts-sdk: worker.NativeConnection#setApiKey -->. The new key "is only set if `metadata` doesn't already have an 'authorization' key" <!-- ts-sdk: worker.NativeConnection#setApiKey --> — if you set an explicit `authorization` header via `metadata` or `setMetadata`, that wins and `setApiKey` becomes a no-op for auth.

To replace all static gRPC metadata sent with every request, use `setMetadata`:

```typescript
await connection.setMetadata({ 'x-tenant-id': 'tenant-42' });
```

Signature: `setMetadata(metadata: Metadata): Promise<void>` <!-- ts-sdk: worker.NativeConnection#setMetadata -->. For the initial value, prefer the `metadata` option on `NativeConnection.connect(...)` <!-- ts-sdk: worker.NativeConnection#setMetadata -->.

The Client-side equivalent (`connection.setApiKey(<APIKey>)`) is documented for `Connection` in the TypeScript client guide and behaves the same way for Client connections <!-- docs/develop/typescript/client/temporal-client.mdx:473-477 -->.

### Per-request scoping: metadata, deadline, abort

When you make ad-hoc raw service calls through the connection (e.g., `connection.workflowService.*`, `connection.operatorService.*`), `NativeConnection` provides three callback-scoped helpers. Each takes a value plus a callback `fn` and applies the value only to requests made inside `fn`:

- `withMetadata<R>(metadata, fn): Promise<R>` — merges metadata with the current scope for calls in `fn` <!-- ts-sdk: worker.NativeConnection#withMetadata -->.
- `withDeadline<R>(deadline: number | Date, fn): Promise<R>` — applies a deadline; requests that don't complete by then throw a gRPC `DEADLINE_EXCEEDED` <!-- ts-sdk: worker.NativeConnection#withDeadline -->.
- `withAbortSignal<R>(abortSignal, fn): Promise<R>` — wires an `AbortSignal` to in-flight requests; cancellation surfaces as gRPC `CANCELLED` <!-- ts-sdk: worker.NativeConnection#withAbortSignal -->.

```typescript
await connection.withDeadline(Date.now() + 5_000, async () => {
  await connection.workflowService.describeNamespace({ namespace: 'default' });
});
```

These are request-scoping helpers on the connection — not Worker-wide settings. The Worker's own polling loop is governed by its own internal timeouts, not by these `with*` scopes.

### Where connection mutation belongs

Connection state changes (replacement, `setApiKey`, `setMetadata`) belong in the Worker bootstrap / supervisor layer — for example, a credential-rotation handler, a config-watcher, or a failover controller. Do **not** call them inside Workflow code: Workflow Definitions must be deterministic, and mutating outside state from a Workflow violates that contract. Activities can access an external connection if you injected one, but the rotation itself should still be driven by the supervisor that owns the Worker, not by Activity logic.

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
