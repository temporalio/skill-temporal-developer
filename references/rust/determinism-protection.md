# Rust Workflow Determinism Protection

## Overview

The Rust SDK provides runtime protection against many nondeterministic async operations in Workflow code. This protection is important because Rust Workflows are async functions, and raw async primitives can wake in orders that are not replay-safe.

The detector is enabled by default on Workers.

## Runtime Async Wake Detection

The Worker option is:

```rust
let worker_options = WorkerOptions::new("task-queue")
    .detect_nondeterministic_futures(true)
    .register_workflow::<MyWorkflow>()?
    .register_activities(MyActivities)
    .build();
```

When enabled, the SDK tracks whether Workflow future wakeups come from Temporal SDK primitives or from outside the SDK. A wake from outside the SDK fails the Workflow Task with a descriptive error.

Detection often appears on the next Workflow Task because an external wake, such as a Tokio timer firing, happens after the Workflow Task that created it.

## What It Detects

The detector is designed to catch:

- `tokio::time::sleep` and `tokio::time::interval`
- `tokio::net`, `tokio::fs`, and other async I/O
- `tokio::spawn`
- `std::thread::spawn` that wakes Workflow futures
- Raw `tokio::sync` channels such as `oneshot`, `mpsc`, or `watch`

Use SDK primitives instead:

```rust
ctx.timer(Duration::from_secs(10)).await;
ctx.wait_condition(|s| s.ready).await;

temporalio_sdk::workflows::select! {
    _ = ctx.timer(Duration::from_secs(60)) => {}
    _ = ctx.wait_condition(|s| s.done) => {}
}
```

## What It Does Not Detect

Runtime async detection is not a complete sandbox. It does not catch every deterministic hazard:

- `std::time::SystemTime::now()`
- `rand::random()`
- Random UUID generation
- Reading mutable global state
- Non-deterministic iteration order in your own data structures
- `futures::select!` poll-order issues that do not create an external wake

Review Workflow code as if no sandbox exists. The detector is a guardrail, not permission to use arbitrary APIs.

## Disabling Detection

You can disable detection:

```rust
let worker_options = WorkerOptions::new("task-queue")
    .detect_nondeterministic_futures(false)
    .register_workflow::<MyWorkflow>()?
    .build();
```

Disable it only during migration or when you have confirmed a false positive and have a separate replay-safety argument. Keep a comment near the Worker option explaining why it is safe.

## Determinism Rules

### Use SDK concurrency

Prefer:

- `temporalio_sdk::workflows::select!`
- `temporalio_sdk::workflows::join!`
- `temporalio_sdk::workflows::join_all`
- `ctx.wait_condition(...)`

Avoid raw `tokio`, raw `futures`, threads, and channels in Workflow code.

### Use Workflow time

Use `ctx.workflow_time()` when Workflow logic needs a time value. Use Activities for wall-clock decisions that depend on external systems.

### Use Activities for side effects

Activities are the boundary for I/O and nondeterminism. They may call HTTP APIs, databases, filesystem APIs, SDK clients, clocks, and random generators.

### Keep Workflow state explicit

Store durable state in the Workflow struct. Mutate it through `ctx.state_mut(...)` or synchronous handlers. Do not hide Workflow progress in process-local globals.

## Best Practices

1. Keep `detect_nondeterministic_futures` enabled.
2. Treat detector failures as Workflow-code bugs unless proven otherwise.
3. Build small Workflow helper functions that accept explicit state and return deterministic decisions.
4. Use replay tests or local integration tests before deploying Workflow changes.
5. Use patching for any intentional Command-sequence changes in Workflows with open executions.
