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

The test environment automatically skips time when the workflow is waiting on timers, making tests fast.

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

## Testing Failure Cases

Test that workflows handle errors correctly:

```typescript
import { TestWorkflowEnvironment } from '@temporalio/testing';
import { Worker } from '@temporalio/worker';
import assert from 'assert';

describe('Failure handling', () => {
  let testEnv: TestWorkflowEnvironment;

  before(async () => {
    testEnv = await TestWorkflowEnvironment.createLocal();
  });

  after(async () => {
    await testEnv?.teardown();
  });

  it('handles activity failure', async () => {
    const { client, nativeConnection } = testEnv;

    const worker = await Worker.create({
      connection: nativeConnection,
      taskQueue: 'test',
      workflowsPath: require.resolve('./workflows'),
      activities: {
        // Mock activity that always fails
        myActivity: async () => {
          throw new Error('Activity failed');
        },
      },
    });

    await worker.runUntil(async () => {
      try {
        await client.workflow.execute(myWorkflow, {
          workflowId: 'test-failure',
          taskQueue: 'test',
        });
        assert.fail('Expected workflow to fail');
      } catch (err) {
        assert(err instanceof WorkflowFailedError);
      }
    });
  });
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

## Activity Testing

Test activities in isolation without running a workflow:

```typescript
import { MockActivityEnvironment } from '@temporalio/testing';
import { myActivity } from './activities';
import assert from 'assert';

describe('Activity tests', () => {
  it('completes successfully', async () => {
    const env = new MockActivityEnvironment();
    const result = await env.run(myActivity, 'input');
    assert.equal(result, 'expected output');
  });

  it('handles cancellation', async () => {
    const env = new MockActivityEnvironment({ cancelled: true });
    try {
      await env.run(longRunningActivity, 'input');
      assert.fail('Expected cancellation');
    } catch (err) {
      assert(err instanceof CancelledFailure);
    }
  });
});
```

**Note:** `MockActivityEnvironment` provides `heartbeat()` and cancellation support for testing activity behavior.

## Best Practices

1. Use time-skipping for workflows with timers
2. Mock external dependencies in activities
3. Test replay compatibility when changing workflow code
4. Use unique workflow IDs per test
5. Clean up test environment after tests
