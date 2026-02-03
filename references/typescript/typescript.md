# Temporal TypeScript SDK Reference

## Overview

The Temporal TypeScript SDK provides a modern async/await approach to building durable workflows. Workflows run in an isolated V8 sandbox for automatic determinism protection.

**CRITICAL**: All `@temporalio/*` packages must have the same version number.

## How Temporal Works: History Replay

Understanding how Temporal achieves durable execution is essential for writing correct workflows.

### The Replay Mechanism

When a Worker executes workflow code, it creates **Commands** (requests for operations like starting an Activity or Timer) and sends them to the Temporal Cluster. The Cluster maintains an **Event History** - a durable log of everything that happened during the workflow execution.

**Key insight**: During replay, the Worker re-executes your workflow code but uses the Event History to restore state instead of re-executing Activities. When it encounters an Activity call that has a corresponding `ActivityTaskCompleted` event in history, it returns the stored result instead of scheduling a new execution.

This is why **determinism matters**: The Worker validates that Commands generated during replay match the Events in history. A mismatch causes a non-deterministic error because the Worker cannot reliably restore state.

### Commands and Events

| Workflow Code | Command Generated | Resulting Event |
|--------------|-------------------|-----------------|
| Activity call | `ScheduleActivityTask` | `ActivityTaskScheduled` |
| `sleep()` | `StartTimer` | `TimerStarted` |
| Child workflow | `StartChildWorkflowExecution` | `ChildWorkflowExecutionStarted` |
| Return/complete | `CompleteWorkflowExecution` | `WorkflowExecutionCompleted` |

### When Replay Occurs

- Worker crashes and recovers
- Worker's cache fills and evicts workflow state
- Workflow continues after long timer
- Testing with replay histories

## Quick Start

```typescript
// activities.ts
export async function greet(name: string): Promise<string> {
  return `Hello, ${name}!`;
}

// workflows.ts
import { proxyActivities } from '@temporalio/workflow';
import type * as activities from './activities';

const { greet } = proxyActivities<typeof activities>({
  startToCloseTimeout: '1 minute',
});

export async function greetingWorkflow(name: string): Promise<string> {
  return await greet(name);
}

// worker.ts
import { Worker } from '@temporalio/worker';
import * as activities from './activities';

async function run() {
  const worker = await Worker.create({
    workflowsPath: require.resolve('./workflows'),
    activities,
    taskQueue: 'greeting-queue',
  });
  await worker.run();
}
```

## Key Concepts

### Workflow Definition
- Async functions exported from workflow file
- Use `proxyActivities()` with type-only imports
- Use `defineSignal()`, `defineQuery()`, `setHandler()` for handlers

### Activity Definition
- Regular async functions
- Can perform I/O, network calls, etc.
- Use `heartbeat()` for long operations

### Worker Setup
- Use `Worker.create()` with workflowsPath
- Import activities directly (not via proxy)

## Determinism Rules

The TypeScript SDK runs workflows in an isolated V8 sandbox.

**Automatic replacements:**
- `Math.random()` → deterministic seeded PRNG
- `Date.now()` → workflow start time
- `setTimeout` → deterministic timer

**Safe to use:**
- `sleep()` from `@temporalio/workflow`
- `condition()` for waiting
- Standard JavaScript operations

See `determinism.md` for detailed rules.

## Common Pitfalls

1. **Importing activities without `type`** - Use `import type * as activities`
2. **Version mismatch** - All @temporalio packages must match
3. **Direct I/O in workflows** - Use activities for external calls
4. **Missing `proxyActivities`** - Required to call activities from workflows
5. **Forgetting to bundle workflows** - Worker needs workflowsPath

## Additional Resources

### Reference Files
- **`determinism.md`** - V8 sandbox, bundling, safe operations, WHY determinism matters
- **`error-handling.md`** - ApplicationFailure, retry policies, idempotency keys
- **`testing.md`** - TestWorkflowEnvironment, time-skipping
- **`patterns.md`** - Signals, queries, cancellation scopes
- **`observability.md`** - Replay-aware logging, metrics, OpenTelemetry, debugging
- **`advanced-features.md`** - Interceptors, sinks, updates, schedules
- **`data-handling.md`** - Search attributes, workflow memo, data converters
- **`versioning.md`** - Patching API, workflow type versioning, Worker Versioning
