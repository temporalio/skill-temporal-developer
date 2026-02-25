# TypeScript References Correctness Check

## Task Prompt (for session recovery)

**Goal:** Verify correctness of every factual statement and code example in TypeScript reference files.

**Workflow for each section:**

1. Read the section from the reference file
2. Query documentation sources to verify:
   - Use `mcp__context7__query-docs` with `libraryId: "/temporalio/sdk-typescript"` for SDK-specific API verification
   - Use `mcp__temporal-docs__search_temporal_knowledge_sources` for conceptual/pattern verification
3. Compare the code example against official documentation
4. Update this tracking file:
   - Update the table row with status and sources consulted
   - Update the detailed notes section with verification details and any needed edits
5. If edits are needed, apply them to the source file after documenting here

**Status values:**
- `unchecked` - Not yet verified
- `all good` - Verified correct, no changes needed
- `FIXED` - Issues found and corrected

**Resume instructions:** Find the first `unchecked` section in any table and continue from there.

---

## patterns.md

**File:** `references/typescript/patterns.md`

### Tracking

| # | Section | Status | Fix Applied | Sources |
|---|---------|--------|-------------|---------|
| 1 | Signals | all good | | context7 sdk-typescript, temporal-docs |
| 2 | Dynamic Signal Handlers | FIXED | Used `setDefaultSignalHandler` | context7 sdk-typescript, temporal-docs |
| 3 | Queries | all good | | context7 sdk-typescript |
| 4 | Dynamic Query Handlers | FIXED | Used `setDefaultQueryHandler` | temporal-docs |
| 5 | Updates | all good | | context7 sdk-typescript, temporal-docs |
| 6 | Child Workflows | all good | | context7 sdk-typescript, temporal-docs |
| 7 | Child Workflow Options | all good | | context7 sdk-typescript, temporal-docs |
| 8 | Handles to External Workflows | all good | | context7 sdk-typescript |
| 9 | Parallel Execution | all good | | context7 sdk-typescript |
| 10 | Continue-as-New | all good | | context7 sdk-typescript |
| 11 | Saga Pattern | all good | | temporal-docs, samples-typescript |
| 12 | Cancellation Scopes | all good | | context7 sdk-typescript, temporal-docs |
| 13 | Triggers (Promise-like Signals) | all good | | temporal-docs api reference |
| 14 | Wait Condition with Timeout | all good | | context7 sdk-typescript, temporal-docs |
| 15 | Waiting for All Handlers to Finish | FIXED | Simplified to `await condition(allHandlersFinished)` | temporal-docs api reference |
| 16 | Activity Heartbeat Details | all good | | context7 sdk-typescript, temporal-docs |
| 17 | Timers | all good | | context7 sdk-typescript |
| 18 | Local Activities | FIXED | Wrong import: `executeLocalActivity` → `proxyLocalActivities` | context7 sdk-typescript |

### Detailed Notes

#### 1. Signals
**Status:** all good

**Verified:**
- `defineSignal`, `setHandler`, `condition` imports from `@temporalio/workflow` ✓
- `defineSignal<[boolean]>('approve')` syntax with type parameter as array of arg types ✓
- `setHandler(signal, handler)` pattern ✓
- `await condition(() => approved)` for waiting on state ✓

---

#### 2. Dynamic Signal Handlers
**Status:** FIXED

**Issue:** The current code uses a non-existent predicate-based `setHandler` API. The TypeScript SDK uses `setDefaultSignalHandler` for handling signals with unknown names.

**Before:**
```typescript
setHandler(
  (signalName: string) => true, // This API doesn't exist
  (signalName: string, ...args: unknown[]) => { ... }
);
```

**After:**
```typescript
import { setDefaultSignalHandler, condition } from '@temporalio/workflow';

export async function dynamicSignalWorkflow(): Promise<Record<string, unknown[]>> {
  const signals: Record<string, unknown[]> = {};

  setDefaultSignalHandler((signalName: string, ...args: unknown[]) => {
    if (!signals[signalName]) {
      signals[signalName] = [];
    }
    signals[signalName].push(args);
  });

  await condition(() => signals['done'] !== undefined);
  return signals;
}
```

**Source:** https://typescript.temporal.io/api/namespaces/workflow#setdefaultsignalhandler

---

#### 3. Queries
**Status:** all good

**Verified:**
- `defineQuery`, `setHandler` imports from `@temporalio/workflow` ✓
- `defineQuery<string>('status')` - return type as type parameter ✓
- `setHandler(query, () => value)` - synchronous handler returning value ✓
- Query handlers must be synchronous (not async) ✓

---

#### 4. Dynamic Query Handlers
**Status:** FIXED

**Issue:** Same as Dynamic Signal Handlers - uses non-existent predicate-based API.

**Correct API:** `setDefaultQueryHandler`

```typescript
setDefaultQueryHandler((queryName: string, ...args: any[]) => {
  // return value
});
```

**Source:** https://typescript.temporal.io/api/namespaces/workflow#setdefaultqueryhandler

---

#### 5. Updates
**Status:** all good

**Verified:**
- `defineUpdate<Ret, Args>('name')` syntax - return type first, then args as tuple type ✓
- `setHandler(update, handler, { validator })` pattern matches official docs ✓
- Validator is synchronous, throws error to reject ✓
- Handler can be sync or async, returns a value ✓
- Imports `defineUpdate`, `setHandler`, `condition` from `@temporalio/workflow` ✓

---

#### 6. Child Workflows
**Status:** all good

**Verified:**
- `executeChild` import from `@temporalio/workflow` ✓
- `executeChild(workflowFunc, { args, workflowId })` syntax correct ✓
- Child scheduled on same task queue as parent by default ✓

---

#### 7. Child Workflow Options
**Status:** all good

**Verified:**
- `ParentClosePolicy` values: `TERMINATE` (default), `ABANDON`, `REQUEST_CANCEL` ✓
- `ChildWorkflowCancellationType` values: `WAIT_CANCELLATION_COMPLETED` (default), `WAIT_CANCELLATION_REQUESTED`, `TRY_CANCEL`, `ABANDON` ✓
- Both imported from `@temporalio/workflow` ✓

---

#### 8. Handles to External Workflows
**Status:** all good

**Verified:**
- `getExternalWorkflowHandle(workflowId)` from `@temporalio/workflow` ✓
- Synchronous function (not async) ✓
- `handle.signal()` and `handle.cancel()` methods exist ✓

---

#### 9. Parallel Execution
**Status:** all good

**Verified:**
- `Promise.all` for parallel execution is standard pattern ✓
- Used in official examples for parallel child workflows ✓

---

#### 10. Continue-as-New
**Status:** all good

**Verified:**
- `continueAsNew`, `workflowInfo` imports from `@temporalio/workflow` ✓
- `await continueAsNew<typeof workflow>(args)` syntax correct ✓
- `workflowInfo().continueAsNewSuggested` property exists ✓
- Checking history length threshold is standard pattern ✓

---

#### 11. Saga Pattern
**Status:** all good

**Verified:**
- Array of compensation functions pattern ✓
- Try/catch with compensations in reverse order ✓
- Official samples-typescript/saga uses same pattern ✓
- No built-in Saga class in TS SDK (unlike Java), manual implementation correct ✓

---

#### 12. Cancellation Scopes
**Status:** all good

**Verified:**
- `CancellationScope` from `@temporalio/workflow` ✓
- `CancellationScope.nonCancellable(fn)` - prevents cancellation propagation ✓
- `CancellationScope.withTimeout(timeout, fn)` - auto-cancels after timeout ✓
- `new CancellationScope()` + `scope.run(fn)` + `scope.cancel()` pattern ✓

---

#### 13. Triggers (Promise-like Signals)
**Status:** all good

**Verified:**
- `Trigger` class from `@temporalio/workflow` ✓
- `new Trigger<T>()` creates a PromiseLike that exposes resolve/reject ✓
- `trigger.resolve(value)` to resolve from signal handler ✓
- `await trigger` works because Trigger implements PromiseLike ✓
- CancellationScope-aware (throws when scope cancelled) ✓

---

#### 14. Wait Condition with Timeout
**Status:** all good

**Verified:**
- `condition(fn, timeout)` with timeout returns `Promise<boolean>` ✓
- Returns `true` if condition met, `false` if timeout expires ✓
- String duration format `'24 hours'` supported (ms-formatted string) ✓
- Import of `CancelledFailure` unused in example but harmless ✓

---

#### 15. Waiting for All Handlers to Finish
**Status:** FIXED

**Issue:** Current code used overly complex condition with `workflowInfo().unsafe.isReplaying` and was missing import of `allHandlersFinished`.

**Before:**
```typescript
import { condition, workflowInfo } from '@temporalio/workflow';
// ...
await condition(() => workflowInfo().unsafe.isReplaying || allHandlersFinished());
```

**After:**
```typescript
import { condition, allHandlersFinished } from '@temporalio/workflow';
// ...
await condition(allHandlersFinished);
```

**Source:** https://typescript.temporal.io/api/namespaces/workflow#allhandlersfinished

**Notes:**
- `allHandlersFinished` is a function that returns `boolean`
- Pass it directly to `condition()` (not wrapped in a lambda)
- Official pattern: `await wf.condition(wf.allHandlersFinished)`

---

#### 16. Activity Heartbeat Details
**Status:** all good

**Verified:**
- `heartbeat`, `activityInfo` imports from `@temporalio/activity` ✓
- `activityInfo().heartbeatDetails` gets heartbeat from previous failed attempt ✓
- `heartbeat(details)` records checkpoint for resume ✓
- Pattern matches official samples-typescript/activities-cancellation-heartbeating ✓

**Notes:**
- `activityInfo()` is convenience function for `Context.current().info`
- heartbeatDetails can be any serializable value (number, object, etc.)

---

#### 17. Timers
**Status:** all good

**Verified:**
- `sleep` from `@temporalio/workflow` accepts duration strings ✓
- `CancellationScope` for cancellable timers ✓
- `scope.run()` and `scope.cancel()` pattern ✓

**Notes:**
- Example uses `setHandler` and `cancelSignal` without imports (pattern demonstration)

---

#### 18. Local Activities
**Status:** FIXED

**Issue:** Wrong import - code imported `executeLocalActivity` but used `proxyLocalActivities`.

**Before:**
```typescript
import { executeLocalActivity } from '@temporalio/workflow';
```

**After:**
```typescript
import { proxyLocalActivities } from '@temporalio/workflow';
```

**Source:** context7 sdk-typescript documentation

---
