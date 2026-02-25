# TypeScript gotchas.md Edits

## Status: DONE

---

## Content to DELETE

### 1. Idempotency section

**Location:** Entire "Idempotency" section with BAD/GOOD code example

**Action:** DELETE this entire section.

**Reason:** Core coverage in core/gotchas.md is sufficient. No need to duplicate.

---

### 2. Replay Safety section

**Location:** Entire "Replay Safety" section (includes "Side Effects" and "Non-Deterministic Operations" subsections)

**Action:** DELETE this entire section.

**Reason:** Core coverage in core/gotchas.md is sufficient. No need to duplicate.

---

### 3. Query Handlers section

**Location:** Entire "Query Handlers" section (includes "Modifying State" and "Blocking in Queries" subsections)

**Action:** DELETE this entire section.

**Reason:** Core coverage in core/gotchas.md is sufficient. No need to duplicate.

---

### 4. Error Handling section

**Location:** Entire "Error Handling" section

**Action:** DELETE this entire section.

**Reason:** Core coverage in core/gotchas.md is sufficient. TypeScript-specific error handling is covered in error-handling.md.

---

### 5. Retry Policies section

**Location:** Entire "Retry Policies" section (includes "Too Aggressive" subsection)

**Action:** DELETE this entire section.

**Reason:** Core coverage in core/gotchas.md is sufficient. No need to duplicate.

---

## Content to ADD

### 6. Wrong Retry Classification section

**Location:** After existing sections, before Testing section

**Add this section:**
```markdown
## Wrong Retry Classification

A common mistake is treating transient errors as permanent (or vice versa):

- **Transient errors** (retry): network timeouts, temporary service unavailability, rate limits
- **Permanent errors** (don't retry): invalid input, authentication failure, resource not found

```typescript
// BAD: Retrying a permanent error
throw ApplicationFailure.create({ message: 'User not found' });
// This will retry indefinitely!

// GOOD: Mark permanent errors as non-retryable
throw ApplicationFailure.nonRetryable('User not found');
```

For detailed guidance on error classification and retry policies, see `error-handling.md`.
```

---

## Content to FIX

None.

---

## Order Changes

After deletions, the remaining sections should be:
1. Activity Imports (TS-specific)
2. Bundling Issues (TS-specific)
3. Wrong Retry Classification (new)
4. Cancellation (TS-specific)
5. Heartbeating
6. Testing
7. Timers and Sleep (TS-specific)

This provides a focused TypeScript-specific gotchas file that complements (rather than duplicates) the Core gotchas.
