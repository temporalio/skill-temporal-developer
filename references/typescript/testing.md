# TypeScript SDK Testing

## Overview

The TypeScript SDK provides `TestWorkflowEnvironment` for testing workflows with time-skipping and activity mocking support.

## Test Environment Setup

```typescript
import { TestWorkflowEnvironment } from '@temporalio/testing';
import { Worker } from '@temporalio/worker';

describe('Workflow', () => {
  let testEnv: TestWorkflowEnvironment;

  before(async () => {
    testEnv = await TestWorkflowEnvironment.createLocal();
  });

  after(async () => {
    await testEnv?.teardown();
  });

  it('runs workflow', async () => {
    const { client, nativeConnection } = testEnv;

    const worker = await Worker.create({
      connection: nativeConnection,
      taskQueue: 'test',
      workflowsPath: require.resolve('./workflows'),
      activities: require('./activities'),
    });

    await worker.runUntil(async () => {
      const result = await client.workflow.execute(greetingWorkflow, {
        taskQueue: 'test',
        workflowId: 'test-workflow',
        args: ['World'],
      });
      expect(result).toEqual('Hello, World!');
    });
  });
});
```

## Time Skipping

```typescript
// Create time-skipping environment
const testEnv = await TestWorkflowEnvironment.createTimeSkipping();

// Time automatically advances when workflows wait
await worker.runUntil(async () => {
  const result = await client.workflow.execute(longRunningWorkflow, {
    taskQueue: 'test',
    workflowId: 'test-workflow',
  });
  // Even if workflow has 1-hour timer, test completes instantly
});

// Manual time advancement
await testEnv.sleep('1 day');
```

## Activity Mocking

```typescript
const worker = await Worker.create({
  connection: nativeConnection,
  taskQueue: 'test',
  workflowsPath: require.resolve('./workflows'),
  activities: {
    // Mock activity implementation
    greet: async (name: string) => `Mocked: ${name}`,
  },
});
```

## Replay Testing

```typescript
import { Worker } from '@temporalio/worker';

describe('Replay', () => {
  it('replays workflow history', async () => {
    const history = await fetchWorkflowHistory('workflow-id');

    await Worker.runReplayHistory(
      {
        workflowsPath: require.resolve('./workflows'),
      },
      history
    );
  });
});
```

## Testing Signals and Queries

```typescript
it('handles signals and queries', async () => {
  await worker.runUntil(async () => {
    const handle = await client.workflow.start(approvalWorkflow, {
      taskQueue: 'test',
      workflowId: 'approval-test',
    });

    // Query current state
    const status = await handle.query('getStatus');
    expect(status).toEqual('pending');

    // Send signal
    await handle.signal('approve');

    // Wait for completion
    const result = await handle.result();
    expect(result).toEqual('Approved!');
  });
});
```

## Best Practices

1. Use time-skipping for workflows with timers
2. Mock external dependencies in activities
3. Test replay compatibility when changing workflow code
4. Use unique workflow IDs per test
5. Clean up test environment after tests
