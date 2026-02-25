# Python versioning.md Edits

## Status: DONE

---

## Content to ADD

### 1. Choosing a Strategy section

**Location:** After "Worker Versioning" section, before "Best Practices"

**Add this section:**
```markdown
## Choosing a Strategy

| Scenario | Recommended Approach |
|----------|---------------------|
| Minor bug fix, compatible change | Patching API (`patched()`) |
| Major logic change, incompatible | Workflow Type Versioning (new workflow name) |
| Infrastructure change, gradual rollout | Worker Versioning (Build ID) |
| Need to query/signal old workflows | Patching (keeps same workflow type) |
| Clean break, no backward compatibility | Workflow Type Versioning |

**Decision factors:**
- **Patching API**: Best for incremental changes where you need to maintain the same workflow type and can gradually migrate
- **Workflow Type Versioning**: Best for major changes where a clean break is acceptable
- **Worker Versioning**: Best for infrastructure-level changes or when you need fine-grained deployment control
```

---

## Content to DELETE

None.

---

## Content to FIX

None.

---

## Order Changes

None - Python versioning.md order is already the reference order.
