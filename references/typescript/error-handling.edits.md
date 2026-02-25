# TypeScript error-handling.md Edits

## Status: PENDING

---

## BUGS to FIX

### 1. Handling Activity Errors - Replace console.log with workflow logger

**Location:** Inside the catch block of the activity error handling example

**Current code:**
```typescript
} catch (err) {
  console.log('Activity failed', err);
  // ...
}
```

**Change to:**
```typescript
import { log } from '@temporalio/workflow';

// ... in catch block:
} catch (err) {
  log.warn('Activity failed', { error: err });
  // ...
}
```

**WHY:** `console.log` is not replay-safe. Use `log` from `@temporalio/workflow` for replay-aware logging in workflows.

---

## Content to FIX

### 2. Retry Configuration - Add note about preferring defaults

**Location:** After the Retry Configuration code example

**Add this note:**
```markdown
**Note:** Only set retry options if you have a domain-specific reason to. The defaults are suitable for most use cases.
```

---

## Content to DELETE

### 3. Cancellation Handling in Activities

**Location:** Entire "Cancellation Handling in Activities" section

**Action:** DELETE this entire section.

**Reason:** Move to patterns.md. Python already has Cancellation Handling in patterns.md. Content should be consolidated there.

**Note:** When adding to patterns.md, it should complement the existing "Cancellation Scopes" section.

---

### 4. Idempotency Patterns

**Location:** Entire "Idempotency Patterns" section (includes WHY, Using Keys, Granular Activities subsections)

**Action:** DELETE this entire section.

**Reason:** Too detailed for error-handling.md. Replace with brief reference to core/patterns.md like Python does.

**Replace with:**
```markdown
## Idempotency

For idempotency patterns (using keys, making activities granular), see `core/patterns.md`.
```

---

## Content to ADD

### 5. Workflow Failure section

**Location:** After "Timeout Configuration" section, before "Best Practices"

**Add this section:**
```markdown
## Workflow Failure

Workflows can throw errors to indicate failure:

```typescript
import { ApplicationFailure } from '@temporalio/workflow';

export async function myWorkflow(): Promise<string> {
  if (someCondition) {
    throw ApplicationFailure.create({
      message: 'Workflow failed due to invalid state',
      type: 'InvalidStateError',
    });
  }
  return 'success';
}
```

**Warning:** Do NOT use `nonRetryable: true` for workflow failures in most cases. Unlike activities, workflow retries are controlled by the caller, not retry policies. Use `nonRetryable` only for errors that are truly unrecoverable (e.g., invalid input that will never be valid).
```

---

## Order Changes

None - order is aligned after deletions.
