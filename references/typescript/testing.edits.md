# TypeScript testing.md Edits

## Status: DONE

---

## Content to DELETE

### 1. Time Skipping section (as dedicated section)

**Location:** Entire "Time Skipping" section

**Action:** DELETE as a dedicated section.

**Reason:** Python mentions time skipping inline in the Test Environment Setup section. TypeScript should do the same for consistency.

**Alternative:** Add a brief mention in Test Environment Setup:
```markdown
The test environment automatically skips time when the workflow is waiting on timers, making tests fast.
```

---

## Content to ADD

### 2. Testing Failure Cases section

**Location:** After "Activity Mocking" section, before "Replay Testing"

**Add this section:**
```markdown
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
```

---

### 3. Activity Testing section

**Location:** After "Replay Testing" section, before "Best Practices"

**Add this section:**
```markdown
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
```

---

## Order Changes

**Current order:**
1. Overview
2. Test Environment Setup
3. Time Skipping
4. Activity Mocking
5. Testing Signals and Queries (TS#6)
6. Replay Testing (TS#5)
7. Best Practices

**Target order (matching Python, after edits):**
1. Overview
2. Test Environment Setup (with inline time skipping mention)
3. Activity Mocking
4. Testing Signals and Queries
5. Testing Failure Cases (new)
6. Replay Testing
7. Activity Testing (new)
8. Best Practices

**Action:** Reorder "Testing Signals and Queries" to come before "Replay Testing" (matching Python order).

---

## Content to FIX

None.
