# TypeScript determinism.md Edits

## Status: DONE

---

## Content to ADD

### 1. uuid4() Utility

**Location:** After "Temporal's V8 Sandbox" section, before "Forbidden Operations"

**Add this section:**
```markdown
## Deterministic UUID Generation

Generate deterministic UUIDs safe to use in workflows. Uses the workflow seeded PRNG, so the same UUID is generated during replay.

```typescript
import { uuid4 } from '@temporalio/workflow';

export async function workflowWithIds(): Promise<void> {
  const childWorkflowId = uuid4();
  await executeChild(childWorkflow, {
    workflowId: childWorkflowId,
    args: [input],
  });
}
```

**When to use:**
- Generating unique IDs for child workflows
- Creating idempotency keys
- Any situation requiring unique identifiers in workflow code
```

---

## Content to DELETE

None.

---

## Content to FIX

None.

---

## Order Changes

None - order is aligned.
