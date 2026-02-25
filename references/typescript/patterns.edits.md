# TypeScript patterns.md Edits

## Status: PENDING

---

## Content to FIX

### 1. Queries - Add "Important" note

**Location:** After the `## Queries` header, before the code block

**Add this note:**
```markdown
**Important:** Queries must NOT modify workflow state or have side effects.
```

---

### 2. Saga Pattern - Add idempotency note

**Location:** After the `## Saga Pattern` header, before the code block

**Add this note:**
```markdown
**Important:** Compensation activities should be idempotent.
```

---

### 3. Saga Pattern - Add compensation comments

**Location:** Inside the saga workflow code example

**Current code (simplified):**
```typescript
await reserveInventory(order);
compensations.push(() => releaseInventory(order));
```

**Change to:**
```typescript
// IMPORTANT: Save compensation BEFORE calling the activity
// If activity fails after completing but before returning,
// compensation must still be registered
await reserveInventory(order);
compensations.push(() => releaseInventory(order));
```

---

## BUGS to FIX

### 4. Saga Pattern - Replace console.log with workflow logger

**Location:** Inside the catch block of the saga workflow

**Current code:**
```typescript
} catch (compErr) {
  console.log('Compensation failed', compErr);
}
```

**Change to:**
```typescript
import { log } from '@temporalio/workflow';

// ... in catch block:
} catch (compErr) {
  log.warn('Compensation failed', { error: compErr });
}
```

**WHY:** `console.log` is not replay-safe. Use `log` from `@temporalio/workflow` for replay-aware logging in workflows.

---

## Content to DELETE

None.

---

## Content to ADD

None.

---

## Order Changes

None - order is already aligned.
