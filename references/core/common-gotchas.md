# Common Temporal Gotchas

Common mistakes and anti-patterns in Temporal development. Learning from these saves significant debugging time.

## Idempotency Issues

### Non-Idempotent Activities

**The Problem**: Activities may execute more than once due to retries or Worker failures. If an activity calls an external service without an idempotency key, you may charge a customer twice, send duplicate emails, or create duplicate records.

**Symptoms**:
- Duplicate side effects (double charges, duplicate notifications)
- Data inconsistencies after retries

**The Fix**: Always use idempotency keys when calling external services. Use the workflow ID, activity ID, or a domain-specific identifier (like order ID) as the key.

**Note:** Local Activities skip the task queue for lower latency, but they're still subject to retries. The same idempotency rules apply.

## Replay Safety Violations

### Side Effects & Non-Determinism in Workflow Code

**The Problem**: Code in workflow functions runs on first execution AND on every replay. Any side effect (logging, notifications, metrics, etc.) will happen multiple times and non-deterministic code (IO, current time, random numbers, threading, etc.) won't replay correctly.

**Symptoms**:
- Non-determinism errors
- Sandbox violations, depending on SDK language
- Duplicate log entries
- Multiple notifications for the same event
- Inflated metrics

**The Fix**:
- Use Temporal replay-aware managed side effects for common, non-business logic cases:
    - Temporal workflow logging
    - Temporal date time (`workflow.now()` in Python, `Date.now()` is auto-replaced in TypeScript)
    - Temporal UUID generation
    - Temporal random number generation
- Put all other side effects in Activities

See `references/core/determinism.md` for more info.

## Worker Management Issues

### Multiple Workers with Different Code

**The Problem**: If Worker A runs part of a workflow with code v1, then Worker B (with code v2) picks it up, replay may produce different Commands.

**Symptoms**:
- Non-determinism errors after deploying new code
- Errors mentioning "command mismatch" or "unexpected command"

**The Fix**:
- Use Worker Versioning for production deployments
- During development: kill old workers before starting new ones
- Ensure all workers run identical code

### Stale Workflows During Development

**The Problem**: Workflows started with old code continue running after you change the code.

**Symptoms**:
- Workflows behave unexpectedly after code changes
- Non-determinism errors on previously-working workflows

**The Fix**:
- Terminate stale workflows: `temporal workflow terminate --workflow-id <id>`
- Use `find-stalled-workflows.sh` to detect stuck workflows
- In production, use versioning for backward compatibility

## Workflow Design Anti-Patterns

### The Mega Workflow

**The Problem**: Putting too much logic in a single workflow.

**Issues**:
- Hard to test and maintain
- Event history grows unbounded
- Single point of failure
- Difficult to reason about

**The Fix**:
- Keep workflows focused on a single responsibility
- Use Child Workflows for sub-processes
- Use Continue-as-New for long-running workflows

### Failing Too Quickly

**The Problem**: Using aggressive retry policies that give up too easily.

**Symptoms**:
- Workflows failing on transient errors
- Unnecessary workflow failures during brief outages

**The Fix**: Use appropriate retry policies. Let Temporal handle transient failures with exponential backoff. Reserve `maximum_attempts=1` for truly non-retryable operations.

## Query Handler Mistakes

### Modifying State in Queries

**The Problem**: Queries are read-only. Modifying state in a query handler causes non-determinism on replay because queries don't generate history events.

**Symptoms**:
- State inconsistencies after workflow replay
- Non-determinism errors

**The Fix**: Queries must only read state. Use Updates for operations that need to modify state AND return a result.

### Blocking in Queries

**The Problem**: Queries must return immediately. They cannot await activities, child workflows, timers, or conditions.

**Symptoms**:
- Query timeouts
- Deadlocks

**The Fix**: Queries return current state only. Use Signals or Updates to trigger async operations.

### Query vs Signal vs Update

| Operation | Modifies State? | Returns Result? | Can Block? | Use For |
|-----------|-----------------|-----------------|------------|---------|
| **Query** | No | Yes | No | Read current state |
| **Signal** | Yes | No | Yes | Fire-and-forget mutations |
| **Update** | Yes | Yes | Yes | Mutations needing results |

**Key rule**: Query to peek, Signal to push, Update to pop.

## File Organization Issues

Each SDK has specific requirements for how workflow and activity code should be organized. Mixing them incorrectly causes sandbox issues, bundling problems, or performance degradation.

See language-specific gotchas for details.

## Testing Mistakes

### Only Testing Happy Paths

**The Problem**: Not testing what happens when things go wrong.

**Questions to answer**:
- What happens when an Activity exhausts all retries?
- What happens when a workflow is cancelled mid-execution?
- What happens during a Worker restart?

**The Fix**: Test failure scenarios explicitly. Mock activities to fail, test cancellation handling, use replay testing.

### Not Testing Replay Compatibility

**The Problem**: Changing workflow code without verifying existing workflows can still replay.

**Symptoms**:
- Non-determinism errors after deployment
- Stuck workflows that can't make progress

**The Fix**: Use replay testing against saved histories from production or staging.

## Error Handling Mistakes

### Swallowing Errors

**The Problem**: Catching errors without proper handling hides failures.

**Symptoms**:
- Silent failures
- Workflows completing "successfully" despite errors
- Difficult debugging

**The Fix**: Log errors and make deliberate decisions. Either re-raise, use a fallback, or explicitly document why ignoring is safe.

### Wrong Retry Classification

**The Problem**: Marking transient errors as non-retryable, or permanent errors as retryable.

**Symptoms**:
- Workflows failing on temporary network issues (if marked non-retryable)
- Infinite retries on invalid input (if marked retryable)

**The Fix**:
- **Retryable**: Network errors, timeouts, rate limits, temporary unavailability
- **Non-retryable**: Invalid input, authentication failures, business rule violations, resource not found

## Language-Specific Gotchas

- [Python Gotchas](../python/gotchas.md)
- [TypeScript Gotchas](../typescript/gotchas.md)
