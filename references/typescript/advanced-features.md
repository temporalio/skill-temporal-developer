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

export async function asyncActivity(): Promise<string> {
  const taskToken = activityInfo().taskToken;

  // Store taskToken somewhere (database, queue, etc.)
  await saveTaskToken(taskToken);

  // Throw to indicate async completion
  throw new CompleteAsyncError();
}
```

**External completion (from another process):**
```typescript
import { AsyncCompletionClient } from '@temporalio/client';

async function completeActivity(taskToken: Uint8Array, result: string) {
  const client = new AsyncCompletionClient();

  await client.complete(taskToken, result);
  // Or for failure:
  // await client.fail(taskToken, new Error('Failed'));
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
  workflowsPath: require.resolve('./workflows'),
  activities,

  // Workflow execution concurrency (default: 40)
  maxConcurrentWorkflowTaskExecutions: 100,

  // Activity execution concurrency (default: 100)
  maxConcurrentActivityTaskExecutions: 100,

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
  workflowsPath: require.resolve('./workflows'),
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
