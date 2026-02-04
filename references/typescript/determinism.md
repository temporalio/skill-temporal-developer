# TypeScript SDK Determinism

## Overview

The TypeScript SDK runs workflows in an isolated V8 sandbox that automatically provides determinism.

## Why Determinism Matters

Temporal provides durable execution through **History Replay**. When a Worker needs to restore workflow state (after a crash, cache eviction, or to continue after a long timer), it re-executes the workflow code from the beginning.

**The Critical Rule**: A Workflow is deterministic if every execution of its code produces the same Commands, in the same sequence, given the same input.

During replay, the Worker:
1. Re-executes your workflow code
2. Compares generated Commands to Events in the history
3. Uses stored results from history instead of re-executing Activities

If the Commands don't match the history, the Worker cannot accurately restore state, causing a **non-deterministic error**.

### Example of Non-Determinism

```typescript
// WRONG - Non-deterministic!
export async function badWorkflow(): Promise<string> {
  await importData();

  // Random value changes on each execution
  if (Math.random() > 0.5) {  // Would be a problem without sandbox
    await sleep('30 minutes');
  }

  return await sendReport();
}
```

Without the sandbox, if the random number was 0.8 on first run (timer started) but 0.3 on replay (no timer), the Worker would see a `StartTimer` command that doesn't match history, causing a non-deterministic error.

**Good news**: The TypeScript sandbox automatically makes `Math.random()` deterministic, so this specific code actually works. But the concept is important for understanding WHY the sandbox exists.

## Automatic Replacements

The sandbox replaces non-deterministic APIs with deterministic versions:

| Original | Replacement |
|----------|-------------|
| `Math.random()` | Seeded PRNG per workflow |
| `Date.now()` | Workflow task start time |
| `Date` constructor | Deterministic time |
| `setTimeout` | Workflow timer |

## Safe Operations

```typescript
import { sleep } from '@temporalio/workflow';

// These are all safe in workflows:
Math.random();          // Deterministic
Date.now();             // Deterministic
new Date();             // Deterministic
await sleep('1 hour');  // Durable timer

// Object iteration is deterministic in JavaScript
for (const key in obj) { }
Object.keys(obj).forEach(k => { });
```

## Forbidden Operations

```typescript
// DO NOT do these in workflows:
import fs from 'fs';           // Node.js modules
fetch('https://...');          // Network I/O
console.log();                 // Side effects (use workflow.log)
```

## Type-Only Activity Imports

```typescript
// CORRECT - type-only import
import type * as activities from './activities';

const { myActivity } = proxyActivities<typeof activities>({
  startToCloseTimeout: '5 minutes',
});

// WRONG - actual import brings in implementation
import * as activities from './activities';
```

## Workflow Bundling

Workflows are bundled by the worker using Webpack. The bundled code runs in isolation.

```typescript
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),  // Gets bundled
  activities,  // Not bundled, runs in Node.js
  taskQueue: 'my-queue',
});
```

## Patching for Versioning

Use `patched()` to safely change workflow code while maintaining compatibility with running workflows:

```typescript
import { patched, deprecatePatch } from '@temporalio/workflow';

export async function myWorkflow(): Promise<string> {
  if (patched('my-change')) {
    // New code path
    return await newImplementation();
  } else {
    // Old code path (for replay)
    return await oldImplementation();
  }
}

// Later, after all old workflows complete:
export async function myWorkflow(): Promise<string> {
  deprecatePatch('my-change');
  return await newImplementation();
}
```

## Best Practices

1. Use type-only imports for activities in workflow files
2. Match all @temporalio package versions
3. Use `sleep()` from workflow package, never `setTimeout` directly
4. Keep workflows focused on orchestration
5. Test with replay to verify determinism
6. Use `patched()` when changing workflow logic for running workflows
