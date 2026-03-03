# TypeScript Gotchas

TypeScript-specific mistakes and anti-patterns. See also [Common Gotchas](../core/gotchas.md) for language-agnostic concepts.

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

### Using workflowsPath in Production

`workflowsPath` runs the bundler at Worker startup, which is slow and not suitable for production. Use `workflowBundle` with pre-bundled code instead.

```typescript
// OK for development/testing, BAD for production - bundles at startup
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  // ...
});

// GOOD for production - use pre-bundled code
import { bundleWorkflowCode } from '@temporalio/worker';

// Build step (run once at build time)
const bundle = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
});
await fs.promises.writeFile('./workflow-bundle.js', bundle.code);

// Worker startup (fast, no bundling)
const worker = await Worker.create({
  workflowBundle: {
    codePath: require.resolve('./workflow-bundle.js'),
  },
  // ...
});
```

### Missing Dependencies in Workflow Bundle

```typescript
// If using external packages in workflows, ensure they're bundled

// worker.ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  bundlerOptions: {
    // Exclude Node.js-only packages that cause bundling errors
    // WARNING: Modules listed here will be completely unavailable
    // at workflow runtime - any imports will fail
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

## Wrong Retry Classification

A common mistake is treating transient errors as permanent (or vice versa):

- **Transient errors** (retry): network timeouts, temporary service unavailability, rate limits
- **Permanent errors** (don't retry): invalid input, authentication failure, resource not found

```typescript
// BAD: Retrying a permanent error
throw ApplicationFailure.create({ message: 'User not found' });
// This will retry indefinitely!

// GOOD: Mark permanent errors as non-retryable
throw ApplicationFailure.nonRetryable('User not found');
```

For detailed guidance on error classification and retry policies, see `error-handling.md`.

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
import * as fs from 'fs';

test('replay compatibility', async () => {
  const history = JSON.parse(await fs.promises.readFile('./fixtures/workflow_history.json', 'utf8'));

  // Fails if current code is incompatible with history
  await Worker.runReplayHistory(
    {
      workflowsPath: require.resolve('./workflows'),
    },
    history,
  );
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
