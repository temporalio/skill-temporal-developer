# TypeScript typescript.md (top-level) Edits

## Status: DONE

---

## BUGS to FIX

### 1. Additional Resources - Wrong file paths

**Location:** "Additional Resources" section at the end of the file

**Current paths (WRONG):**
```markdown
- **`references/python/patterns.md`** - ...
- **`references/python/determinism.md`** - ...
- **`references/python/gotchas.md`** - ...
- **`references/python/error-handling.md`** - ...
- **`references/python/observability.md`** - ...
- **`references/python/testing.md`** - ...
- **`references/python/advanced-features.md`** - ...
- **`references/python/data-handling.md`** - ...
- **`references/python/versioning.md`** - ...
- **`references/python/determinism-protection.md`** - ...
```

**Change to (CORRECT):**
```markdown
- **`references/typescript/patterns.md`** - Signals, queries, child workflows, saga pattern, etc.
- **`references/typescript/determinism.md`** - Essentials of determinism in TypeScript
- **`references/typescript/gotchas.md`** - TypeScript-specific mistakes and anti-patterns
- **`references/typescript/error-handling.md`** - ApplicationFailure, retry policies, non-retryable errors
- **`references/typescript/observability.md`** - Logging, metrics, tracing
- **`references/typescript/testing.md`** - TestWorkflowEnvironment, time-skipping, activity mocking
- **`references/typescript/advanced-features.md`** - Schedules, worker tuning, and more
- **`references/typescript/data-handling.md`** - Data converters, payload encryption, etc.
- **`references/typescript/versioning.md`** - Patching API, workflow type versioning, Worker Versioning
- **`references/typescript/determinism-protection.md`** - V8 sandbox and bundling
```

---

## Content to DELETE

### 2. How Temporal Works: History Replay section

**Location:** Entire "How Temporal Works: History Replay" section (includes subsections: The Replay Mechanism, Commands and Events table, When Replay Occurs)

**Action:** DELETE this entire section.

**Reason:** This content belongs in core/determinism.md, not in the language-specific top-level file. Both Python and TypeScript should reference the Core conceptual content.

**Replace with a brief reference (optional):**
```markdown
## Understanding Replay

Temporal workflows are durable through history replay. For details on how this works, see `core/determinism.md`.
```

---

## Content to ADD

### 3. File Organization Best Practice section

**Location:** After "Key Concepts" section, before "Determinism Rules"

**Add this section:**
```markdown
## File Organization Best Practice

**Keep Workflow definitions in separate files from Activity definitions.** The TypeScript SDK bundles workflow files separately. Minimizing workflow file contents improves Worker startup time.

```
my_temporal_app/
├── workflows/
│   └── greeting.ts      # Only Workflow functions
├── activities/
│   └── translate.ts     # Only Activity functions
├── worker.ts            # Worker setup, imports both
└── client.ts            # Client code to start workflows
```

**In the Workflow file, use type-only imports for activities:**
```typescript
// workflows/greeting.ts
import { proxyActivities } from '@temporalio/workflow';
import type * as activities from '../activities/translate';

const { translate } = proxyActivities<typeof activities>({
  startToCloseTimeout: '1 minute',
});
```
```

---

### 4. Expand Quick Start section

**Location:** "Quick Start" section

**Current state:** Just 3 code blocks with minimal context.

**Target state (matching Python "Quick Demo"):**

```markdown
## Quick Start

**Add Dependencies:** Install the Temporal SDK packages:
```bash
npm install @temporalio/client @temporalio/worker @temporalio/workflow @temporalio/activity
```

**activities.ts** - Activity definitions (separate file for bundling performance):
```typescript
export async function greet(name: string): Promise<string> {
  return `Hello, ${name}!`;
}
```

**workflows.ts** - Workflow definition (use type-only imports for activities):
```typescript
import { proxyActivities } from '@temporalio/workflow';
import type * as activities from './activities';

const { greet } = proxyActivities<typeof activities>({
  startToCloseTimeout: '1 minute',
});

export async function greetingWorkflow(name: string): Promise<string> {
  return await greet(name);
}
```

**worker.ts** - Worker setup (imports activities and workflows, runs indefinitely):
```typescript
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

run().catch(console.error);
```

**Start the dev server:** Start `temporal server start-dev` in the background.

**Start the worker:** Run `npx ts-node worker.ts` in the background.

**client.ts** - Start a workflow execution:
```typescript
import { Client } from '@temporalio/client';
import { greetingWorkflow } from './workflows';
import { v4 as uuid } from 'uuid';

async function run() {
  const client = new Client();

  const result = await client.workflow.execute(greetingWorkflow, {
    workflowId: uuid(),
    taskQueue: 'greeting-queue',
    args: ['my name'],
  });

  console.log(`Result: ${result}`);
}

run().catch(console.error);
```

**Run the workflow:** Run `npx ts-node client.ts`. Should output: `Result: Hello, my name!`.
```

---

### 5. Common Pitfalls - Add missing items

**Location:** "Common Pitfalls" section

**Add these items:**
```markdown
6. **Forgetting to heartbeat** - Long-running activities need `heartbeat()` calls
7. **Using console.log in workflows** - Use `log` from `@temporalio/workflow` for replay-safe logging
```

---

## Order Changes

After edits, the order should be:
1. Overview
2. Quick Start (expanded)
3. Key Concepts
4. File Organization Best Practice (new)
5. Determinism Rules
6. Common Pitfalls (expanded)
7. Writing Tests
8. Additional Resources (fixed paths)
