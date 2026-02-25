# Python gotchas.md Edits

## Status: PENDING

---

## Content to ADD

### 1. Timers and Sleep section

**Location:** After "Testing" section (at the end of file)

**Add this section:**
```markdown
## Timers and Sleep

### Using asyncio.sleep

```python
# BAD: asyncio.sleep is not deterministic during replay
import asyncio

@workflow.defn
class BadWorkflow:
    @workflow.run
    async def run(self) -> None:
        await asyncio.sleep(60)  # Non-deterministic!
```

```python
# GOOD: Use workflow.sleep for deterministic timers
from temporalio import workflow
from datetime import timedelta

@workflow.defn
class GoodWorkflow:
    @workflow.run
    async def run(self) -> None:
        await workflow.sleep(timedelta(seconds=60))  # Deterministic
        # Or with string duration:
        await workflow.sleep("1 minute")
```

**Why this matters:** `asyncio.sleep` uses the system clock, which differs between original execution and replay. `workflow.sleep` creates a durable timer in the event history, ensuring consistent behavior during replay.
```

---

## Content to DELETE

None.

---

## Content to FIX

None.

---

## Order Changes

None - Python gotchas.md order is the reference order.
