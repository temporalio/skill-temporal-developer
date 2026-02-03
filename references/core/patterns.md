# Temporal Workflow Patterns

## Overview

Common patterns for building robust Temporal workflows. For language-specific implementations, see the Python or TypeScript references.

## Signals

**Purpose**: Send data to a running workflow asynchronously (fire-and-forget).

**When to Use**:
- Human approval workflows
- Adding items to a workflow's queue
- Notifying workflow of external events
- Live configuration updates

**Characteristics**:
- Asynchronous - sender doesn't wait for response
- Can mutate workflow state
- Durable - signals are persisted in history
- Can be sent before workflow starts (signal-with-start)

**Example Flow**:
```
Client                    Workflow
  │                          │
  │──── signal(approve) ────▶│
  │                          │ (updates state)
  │                          │
  │◀──── (no response) ──────│
```

## Queries

**Purpose**: Read workflow state synchronously without modifying it.

**When to Use**:
- Building dashboards showing workflow progress
- Health checks and monitoring
- Debugging workflow state
- Exposing current status to external systems

**Characteristics**:
- Synchronous - caller waits for response
- Read-only - must not modify state
- Not recorded in history
- Executes on the worker, not persisted

**Example Flow**:
```
Client                    Workflow
  │                          │
  │──── query(status) ──────▶│
  │                          │ (reads state)
  │◀──── "processing" ───────│
```

## Updates

**Purpose**: Modify workflow state and receive a response synchronously.

**When to Use**:
- Operations that need confirmation (add item, return count)
- Validation before accepting changes
- Replace signal+query combinations
- Request-response patterns within workflow

**Characteristics**:
- Synchronous - caller waits for completion
- Can mutate state AND return values
- Supports validators to reject invalid updates
- Recorded in history

**Example Flow**:
```
Client                    Workflow
  │                          │
  │──── update(addItem) ────▶│
  │                          │ (validates, modifies state)
  │◀──── {count: 5} ─────────│
```

## Child Workflows

**Purpose**: Break complex workflows into smaller, reusable pieces.

**When to Use**:
- Prevent history from growing too large
- Isolate failure domains (child can fail without failing parent)
- Reuse workflow logic across multiple parents
- Different retry policies for different parts

**Characteristics**:
- Own history (doesn't bloat parent)
- Independent lifecycle options (ParentClosePolicy)
- Can be cancelled independently
- Results returned to parent

**Parent Close Policies**:
- `TERMINATE` - Child terminated when parent closes (default)
- `ABANDON` - Child continues running independently
- `REQUEST_CANCEL` - Cancellation requested but not forced

## Continue-as-New

**Purpose**: Prevent unbounded history growth by "restarting" with fresh history.

**When to Use**:
- Long-running workflows (entity workflows, subscriptions)
- Workflows with many iterations
- When history approaches 10,000+ events
- Periodic cleanup of accumulated state

**How It Works**:
```
Workflow (history: 10,000 events)
    │
    │ continueAsNew(currentState)
    ▼
New Workflow Execution (history: 0 events)
    │ (same workflow ID, fresh history)
    │ (receives currentState as input)
```

**Best Practice**: Check `historyLength` or `continueAsNewSuggested` periodically.

## Saga Pattern

**Purpose**: Distributed transactions with compensation for failures.

**When to Use**:
- Multi-step operations that span services
- Operations requiring rollback on failure
- Financial transactions, order processing
- Booking systems with multiple reservations

**How It Works**:
```
Step 1: Reserve inventory
  └─ Compensation: Release inventory

Step 2: Charge payment
  └─ Compensation: Refund payment

Step 3: Ship order
  └─ Compensation: Cancel shipment

On failure at step 3:
  Execute: Refund payment (step 2 compensation)
  Execute: Release inventory (step 1 compensation)
```

**Implementation Pattern**:
1. Track compensation actions as you complete each step
2. On failure, execute compensations in reverse order
3. Handle compensation failures gracefully (log, alert, manual intervention)

## Parallel Execution

**Purpose**: Run multiple independent operations concurrently.

**When to Use**:
- Processing multiple items that don't depend on each other
- Calling multiple APIs simultaneously
- Fan-out/fan-in patterns
- Reducing total workflow duration

**Patterns**:
- `Promise.all()` / `asyncio.gather()` - Wait for all
- Partial failure handling - Continue with successful results

## Entity Workflow Pattern

**Purpose**: Model long-lived entities as workflows that handle events.

**When to Use**:
- Subscription management
- User sessions
- Shopping carts
- Any stateful entity receiving events over time

**How It Works**:
```
Entity Workflow (user-123)
    │
    ├── Receives signal: AddItem
    │   └── Updates state
    │
    ├── Receives signal: UpdateQuantity
    │   └── Updates state
    │
    ├── Receives query: GetCart
    │   └── Returns current state
    │
    └── continueAsNew when history grows
```

## Timer Patterns

**Purpose**: Durable delays that survive worker restarts.

**Use Cases**:
- Scheduled reminders
- Timeout handling
- Delayed actions
- Polling with intervals

**Characteristics**:
- Timers are durable (persisted in history)
- Can be cancelled
- Combine with cancellation scopes for timeouts

## Polling Pattern

**Purpose**: Repeatedly check external state until condition met.

**Implementation**:
```
while not condition_met:
    result = await check_activity()
    if result.done:
        break
    await sleep(poll_interval)
```

**Best Practice**: Use exponential backoff for polling intervals.

## Choosing Between Patterns

| Need | Pattern |
|------|---------|
| Send data, don't need response | Signal |
| Read state, no modification | Query |
| Modify state, need response | Update |
| Break down large workflow | Child Workflow |
| Prevent history growth | Continue-as-New |
| Rollback on failure | Saga |
| Process items concurrently | Parallel Execution |
| Long-lived stateful entity | Entity Workflow |
