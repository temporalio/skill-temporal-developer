# Determinism in Temporal Workflows

## Overview

Temporal workflows must be deterministic because of **history replay** - the mechanism that enables durable execution.

## Why Determinism Matters

### The Replay Mechanism

When a Worker needs to restore workflow state (after crash, cache eviction, or continuing after a long timer), it **re-executes the workflow code from the beginning**. But instead of re-running external actions, it uses results stored in the Event History.

```
Initial Execution:
  Code runs → Generates Commands → Server stores as Events

Replay (Recovery):
  Code runs again → Generates Commands → SDK compares to Events
  If match: Use stored results, continue
  If mismatch: NondeterminismError!
```

### Commands and Events

Every workflow operation generates a Command that becomes an Event, here are some examples:

| Workflow Code | Command Generated | Event Stored |
|--------------|-------------------|--------------|
| Execute activity | `ScheduleActivityTask` | `ActivityTaskScheduled` |
| Sleep/timer | `StartTimer` | `TimerStarted` |
| Child workflow | `StartChildWorkflowExecution` | `ChildWorkflowExecutionStarted` |
| Complete workflow | `CompleteWorkflowExecution` | `WorkflowExecutionCompleted` |

### Non-Determinism Example

```
First Run (11:59 AM):
  if datetime.now().hour < 12:  → True
    execute_activity(morning_task)  → Command: ScheduleActivityTask("morning_task")

Replay (12:01 PM):
  if datetime.now().hour < 12:  → False
    execute_activity(afternoon_task)  → Command: ScheduleActivityTask("afternoon_task")

Result: Commands don't match history → NondeterminismError
```

## Sources of Non-Determinism

### Time-Based Operations
- `datetime.now()`, `time.time()`, `Date.now()`
- Different value on each execution

### Random Values
- `random.random()`, `Math.random()`, `uuid.uuid4()`
- Different value on each execution

### External State
- Reading files, environment variables, databases
- State may change between executions

### Non-Deterministic Iteration
- Map/dict iteration order (in some languages)
- Set iteration order

### Threading/Concurrency
- Race conditions produce different outcomes
- Non-deterministic ordering

## SDK Protection Mechanisms

### Python Sandbox
The Python SDK runs workflows in a sandbox that:
- Intercepts non-deterministic calls
- Raises errors for forbidden operations
- Requires explicit pass-through for libraries

```python
# Python: Use SDK alternatives
workflow.now()      # Instead of datetime.now()
workflow.random()   # Instead of random
workflow.uuid4()    # Instead of uuid.uuid4()
```

### TypeScript V8 Isolation
The TypeScript SDK runs workflows in an isolated V8 context that:
- Automatically replaces `Date.now()`, `Math.random()` with deterministic versions
- Prevents access to Node.js APIs
- Bundles workflow code separately from activities

```typescript
// TypeScript: Auto-replaced to be deterministic
Date.now()      // Returns workflow task start time
Math.random()   // Returns seeded PRNG value
new Date()      // Deterministic
```

### Go `workflowcheck` static analyzer
The Go SDK provides a workflowcheck CLI tool that:
- Statically analyzes registered Workflow Definitions and their call graph
- Flags common sources of non-determinism (e.g., time.Now, time.Sleep, goroutines, channels, map iteration, global math/rand, stdio)
- Helps catch invalid constructs early in development, but cannot detect all issues (e.g., global var mutation, some reflection)

```bash
# Install
go install go.temporal.io/sdk/contrib/tools/workflowcheck@latest

# Run from your module root to scan all packages
workflowcheck ./...

# Optional: configure overrides / skips in workflowcheck.config.yaml
# (e.g., mark a function as deterministic or skip files)
workflowcheck -config workflowcheck.config.yaml ./...
```

## Detecting Non-Determinism

### During Execution
- `NondeterminismError` raised when Commands don't match Events
- Workflow becomes blocked until code is fixed

### Testing with Replay
Export workflow history and replay against new code:

```python
# Python
from temporalio.worker import Replayer
replayer = Replayer(workflows=[MyWorkflow])
await replayer.replay_workflow(history)  # Raises if incompatible
```

```typescript
// TypeScript
import { Worker } from '@temporalio/worker';
await Worker.runReplayHistory({
  workflowsPath: require.resolve('./workflows'),
  history,
});
```

## Recovery from Non-Determinism

### Accidental Change
If you accidentally introduced non-determinism:
1. Revert code to match what's in history
2. Restart worker
3. Workflow auto-recovers

### Intentional Change
If you need to change workflow logic:
1. Use the **Patching API** to support both old and new code paths
2. Or terminate old workflows and start new ones with updated code

See `versioning.md` for patching details.

## Best Practices

1. **Use SDK-provided alternatives** for time, random, UUID
2. **Move I/O to activities** - workflows should only orchestrate
3. **Test with replay** before deploying workflow changes
4. **Use patching** for intentional changes to running workflows
5. **Keep workflows focused** - complex logic increases non-determinism risk
