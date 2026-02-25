# TypeScript advanced-features.md Edits

## Status: DONE

---

## Content to DELETE

### 1. Continue-as-New section

**Location:** Entire "Continue-as-New" section

**Action:** DELETE this entire section.

**Reason:** DUPLICATE - Already exists in patterns.md (TS#10). Remove from advanced-features.md.

---

### 2. Workflow Updates section

**Location:** Entire "Workflow Updates" section

**Action:** DELETE this entire section.

**Reason:** DUPLICATE - Already exists in patterns.md (TS#5 "Updates"). Remove from advanced-features.md.

---

### 3. Nexus Operations section

**Location:** Entire "Nexus Operations" section (includes service definition, handlers, workflow calling)

**Action:** DELETE this entire section.

**Reason:** Too advanced for reference docs. Users needing Nexus should consult official Temporal documentation.

---

### 4. Activity Cancellation and Heartbeating section

**Location:** Entire "Activity Cancellation and Heartbeating" section (includes ActivityCancellationType, Heartbeat Details)

**Action:** DELETE this entire section.

**Reason:**
- Heartbeat Details already in patterns.md (TS#16)
- ActivityCancellationType coverage not needed per user decision

---

### 5. CancellationScope Patterns section

**Location:** Entire "CancellationScope Patterns" section

**Action:** DELETE this entire section.

**Reason:** DUPLICATE - Already exists in patterns.md (TS#12 "Cancellation Scopes"). Remove from advanced-features.md.

---

### 6. Best Practices section

**Location:** Entire "Best Practices" section at the end

**Action:** DELETE this entire section.

**Reason:** Best practices are covered in individual sections throughout the reference docs. A generic list here is redundant.

---

## Content to ADD

### 7. Async Activity Completion section

**Location:** After "Schedules" section

**Add this section:**
```markdown
## Async Activity Completion

Complete an activity asynchronously from outside the activity function. Useful when the activity needs to wait for an external event.

**In the activity - return the task token:**
```typescript
import { Context } from '@temporalio/activity';

export async function asyncActivity(): Promise<string> {
  const ctx = Context.current();
  const taskToken = ctx.info.taskToken;

  // Store taskToken somewhere (database, queue, etc.)
  await saveTaskToken(taskToken);

  // Throw to indicate async completion
  throw Context.current().createAsyncCompletionHandle();
}
```

**External completion (from another process):**
```typescript
import { Client } from '@temporalio/client';

async function completeActivity(taskToken: Uint8Array, result: string) {
  const client = new Client();

  await client.activity.complete(taskToken, result);
  // Or for failure:
  // await client.activity.fail(taskToken, new Error('Failed'));
}
```

**When to use:**
- Waiting for human approval
- Waiting for external webhook callback
- Long-polling external systems
```

---

### 8. Worker Tuning section

**Location:** After "Async Activity Completion" section

**Add this section:**
```markdown
## Worker Tuning

Configure worker capacity for production workloads:

```typescript
import { Worker, NativeConnection } from '@temporalio/worker';

const worker = await Worker.create({
  connection: await NativeConnection.connect({ address: 'temporal:7233' }),
  taskQueue: 'my-queue',
  workflowsPath: require.resolve('./workflows'),
  activities,

  // Workflow execution concurrency
  maxConcurrentWorkflowTaskExecutions: 100,

  // Activity execution concurrency
  maxConcurrentActivityTaskExecutions: 100,

  // Graceful shutdown timeout
  shutdownGraceTime: '30 seconds',

  // Enable sticky workflow cache (default: true)
  enableStickyQueues: true,

  // Max cached workflows (memory vs latency tradeoff)
  maxCachedWorkflows: 1000,
});
```

**Key settings:**
- `maxConcurrentWorkflowTaskExecutions`: Max workflows running simultaneously
- `maxConcurrentActivityTaskExecutions`: Max activities running simultaneously
- `shutdownGraceTime`: Time to wait for in-progress work before forced shutdown
- `maxCachedWorkflows`: Number of workflows to keep in cache (reduces replay on cache hit)
```

---

## Order Changes

After deletions and additions, the sections should be:
1. Schedules
2. Async Activity Completion (new)
3. Worker Tuning (new)
4. Sinks (TS-specific, keep)

This provides a focused advanced-features file matching the pattern of Python's version.
