# TypeScript SDK Advanced Features

## Continue-as-New

Use continue-as-new to prevent unbounded history growth in long-running workflows.

```typescript
import { continueAsNew, workflowInfo } from '@temporalio/workflow';

export async function batchProcessingWorkflow(state: ProcessingState): Promise<string> {
  while (!state.isComplete) {
    // Process next batch
    state = await processNextBatch(state);

    // Check history size and continue-as-new if needed
    const info = workflowInfo();
    if (info.historyLength > 10000) {
      await continueAsNew<typeof batchProcessingWorkflow>(state);
    }
  }

  return 'completed';
}
```

### Continue-as-New with Options

```typescript
import { continueAsNew } from '@temporalio/workflow';

// Continue with modified options
await continueAsNew<typeof batchProcessingWorkflow>(newState, {
  memo: { lastProcessed: itemId },
  searchAttributes: { BatchNumber: [state.batch + 1] },
});
```

## Workflow Updates

Updates allow synchronous interaction with running workflows.

### Defining Update Handlers

```typescript
import { defineUpdate, setHandler, condition } from '@temporalio/workflow';

// Define the update
export const addItemUpdate = defineUpdate<number, [string]>('addItem');
export const addItemValidatedUpdate = defineUpdate<number, [string]>('addItemValidated');

export async function orderWorkflow(): Promise<string> {
  const items: string[] = [];
  let completed = false;

  // Simple update handler
  setHandler(addItemUpdate, (item: string) => {
    items.push(item);
    return items.length;
  });

  // Update handler with validator
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

  // Wait for completion signal
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
```

## Nexus Operations

### WHY: Cross-namespace and cross-cluster service communication
### WHEN:
- **Multi-namespace architectures** - Call operations across Temporal namespaces
- **Service-oriented design** - Expose workflow capabilities as reusable services
- **Cross-cluster communication** - Interact with workflows in different Temporal clusters

### Defining a Nexus Service

Define the service interface shared between caller and handler:

```typescript
// api.ts - shared service definition
import * as nexus from 'nexus-rpc';

export const helloService = nexus.service('hello', {
  // Synchronous operation
  echo: nexus.operation<EchoInput, EchoOutput>(),
  // Workflow-backed operation
  hello: nexus.operation<HelloInput, HelloOutput>(),
});

export interface EchoInput { message: string; }
export interface EchoOutput { message: string; }
export interface HelloInput { name: string; language: string; }
export interface HelloOutput { message: string; }
```

### Implementing Nexus Service Handlers

```typescript
// service/handler.ts
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';
import { helloService, EchoInput, EchoOutput, HelloInput, HelloOutput } from '../api';
import { helloWorkflow } from './workflows';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  // Synchronous operation - simple async function
  echo: async (ctx, input: EchoInput): Promise<EchoOutput> => {
    // Can access Temporal client via temporalNexus.getClient()
    return input;
  },

  // Workflow-backed operation
  hello: new temporalNexus.WorkflowRunOperationHandler<HelloInput, HelloOutput>(
    async (ctx, input: HelloInput) => {
      return await temporalNexus.startWorkflow(ctx, helloWorkflow, {
        args: [input],
        workflowId: ctx.requestId ?? crypto.randomUUID(),
      });
    },
  ),
});
```

### Calling Nexus Operations from Workflows

```typescript
// caller/workflows.ts
import * as wf from '@temporalio/workflow';
import { helloService } from '../api';

const HELLO_SERVICE_ENDPOINT = 'my-nexus-endpoint-name';

export async function callerWorkflow(name: string): Promise<string> {
  const nexusClient = wf.createNexusClient({
    service: helloService,
    endpoint: HELLO_SERVICE_ENDPOINT,
  });

  const result = await nexusClient.executeOperation(
    'hello',
    { name, language: 'en' },
    { scheduleToCloseTimeout: '10s' },
  );

  return result.message;
}
```

## Activity Cancellation and Heartbeating

### ActivityCancellationType

Control how activities respond to workflow cancellation:

```typescript
import { proxyActivities, ActivityCancellationType, isCancellation, log } from '@temporalio/workflow';
import type * as activities from './activities';

const { longRunningActivity } = proxyActivities<typeof activities>({
  startToCloseTimeout: '60s',
  heartbeatTimeout: '3s',
  // TRY_CANCEL (default): Request cancellation, resolve/reject immediately
  // WAIT_CANCELLATION_COMPLETED: Wait for activity to acknowledge cancellation
  // WAIT_CANCELLATION_REQUESTED: Wait for cancellation request to be delivered
  // ABANDON: Don't request cancellation
  cancellationType: ActivityCancellationType.WAIT_CANCELLATION_COMPLETED,
});

export async function workflowWithCancellation(): Promise<void> {
  try {
    await longRunningActivity();
  } catch (err) {
    if (isCancellation(err)) {
      log.info('Workflow cancelled along with its activity');
      // Use CancellationScope.nonCancellable for cleanup
    }
    throw err;
  }
}
```

### Activity Heartbeat Details for Resumption

Use heartbeat details to resume long-running activities from where they left off:

```typescript
// activities.ts
import { activityInfo, log, sleep, CancelledFailure, heartbeat } from '@temporalio/activity';

export async function processWithProgress(sleepIntervalMs = 1000): Promise<void> {
  try {
    // Resume from last heartbeat on retry
    const startingPoint = activityInfo().heartbeatDetails || 1;
    log.info('Starting activity at progress', { startingPoint });

    for (let progress = startingPoint; progress <= 100; ++progress) {
      log.info('Progress', { progress });
      await sleep(sleepIntervalMs);
      // Heartbeat with progress - allows resuming on retry
      heartbeat(progress);
    }
  } catch (err) {
    if (err instanceof CancelledFailure) {
      log.warn('Activity cancelled', { message: err.message });
      // Cleanup code here
    }
    throw err;
  }
}
```

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

## Interceptors

Interceptors allow cross-cutting concerns like logging, metrics, and auth.

### Creating a Custom Interceptor

```typescript
import {
  ActivityInboundCallsInterceptor,
  ActivityExecuteInput,
  Next,
} from '@temporalio/worker';

class LoggingActivityInterceptor implements ActivityInboundCallsInterceptor {
  async execute(
    input: ActivityExecuteInput,
    next: Next<ActivityInboundCallsInterceptor, 'execute'>
  ): Promise<unknown> {
    console.log(`Activity starting: ${input.activity.name}`);
    try {
      const result = await next(input);
      console.log(`Activity completed: ${input.activity.name}`);
      return result;
    } catch (err) {
      console.error(`Activity failed: ${input.activity.name}`, err);
      throw err;
    }
  }
}

// Apply to worker
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities,
  taskQueue: 'my-queue',
  interceptors: {
    activity: [() => new LoggingActivityInterceptor()],
  },
});
```

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

## CancellationScope Patterns

Advanced cancellation control within workflows.

```typescript
import {
  CancellationScope,
  CancelledFailure,
  sleep,
} from '@temporalio/workflow';

export async function workflowWithCancellation(): Promise<string> {
  // Non-cancellable scope - runs to completion even if workflow cancelled
  const criticalResult = await CancellationScope.nonCancellable(async () => {
    return await criticalActivity();
  });

  // Cancellable scope with timeout
  try {
    await CancellationScope.cancellable(async () => {
      await Promise.race([
        longRunningActivity(),
        sleep('5 minutes').then(() => {
          CancellationScope.current().cancel();
        }),
      ]);
    });
  } catch (err) {
    if (err instanceof CancelledFailure) {
      // Handle cancellation
      await cleanupActivity();
    }
    throw err;
  }

  return criticalResult;
}
```

## Dynamic Workflows and Activities

Handle workflows/activities not known at compile time.

```typescript
// Dynamic workflow registration
import { proxyActivities } from '@temporalio/workflow';

export async function dynamicWorkflow(
  workflowType: string,
  args: unknown[]
): Promise<unknown> {
  switch (workflowType) {
    case 'order':
      return handleOrderWorkflow(args);
    case 'refund':
      return handleRefundWorkflow(args);
    default:
      throw new Error(`Unknown workflow type: ${workflowType}`);
  }
}
```

## Best Practices

1. Use continue-as-new for long-running workflows to prevent history growth
2. Prefer updates over signals when you need a response
3. Use sinks with `callDuringReplay: false` for logging
4. Use CancellationScope.nonCancellable for critical cleanup operations
5. Configure interceptors for cross-cutting concerns like tracing
6. Use `ActivityCancellationType.WAIT_CANCELLATION_COMPLETED` when cleanup is important
7. Store progress in heartbeat details for resumable long-running activities
8. Use Nexus for cross-namespace service communication
