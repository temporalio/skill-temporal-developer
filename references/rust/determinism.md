# Rust SDK Determinism

## Overview

Rust Workflow code must be deterministic because Temporal can replay Workflow code from the beginning to reconstruct state. During replay, Activity results, timer firings, child Workflow results, Signals, Queries, and Updates are read from Event History instead of being recomputed.

If replayed Workflow code emits different Commands than the stored History, the Workflow can become blocked by a nondeterminism error until compatible code is deployed.

## Why Determinism Matters: History Replay

Workflow code should describe orchestration, not directly perform side effects. The Rust SDK re-runs Workflow code during recovery, cache eviction, long timers, or Worker restarts. Any value that changes between executions can cause replay to diverge.

Safe mental model:

```
Workflow code decides what durable Command to request.
Temporal records the resulting Event.
Replay re-runs the Workflow and verifies it asks for the same Command sequence.
```

## Forbidden Operations in Workflows

Do not do these directly in Workflow code:

- Network, filesystem, database, subprocess, or environment access
- `std::time::SystemTime::now()` or other direct wall-clock reads
- Random generation such as `rand::random()` or random UUIDs
- `tokio::time::sleep`, `tokio::spawn`, `tokio::select!`, `tokio::sync` channels, or raw async I/O
- `futures::select!` without deterministic polling order
- Shared mutable global state
- Thread spawning or cross-thread wakeups

Put those operations in Activities. Activity results are stored in Workflow History and can be replayed safely.

## Safe Builtin Alternatives

Use Rust SDK Workflow APIs instead:

| Need | Use in Workflow |
| --- | --- |
| Sleep or timer | `ctx.timer(duration).await` |
| Current Workflow time | `ctx.workflow_time()` |
| Wait for state change | `ctx.wait_condition(|state| ...)` |
| Activity execution | `ctx.start_activity(...)` |
| Local Activity | `ctx.start_local_activity(...)` |
| Child Workflow | `ctx.start_child_workflow(...)` |
| Cancellation | `ctx.cancelled()` |
| Deterministic select | `temporalio_sdk::workflows::select!` |
| Deterministic join | `temporalio_sdk::workflows::join!` or `join_all` |

Example:

```rust
use std::time::Duration;
use temporalio_sdk::workflows::select;

select! {
    _ = ctx.timer(Duration::from_secs(60)) => {
        // Timer fired.
    }
    reason = ctx.cancelled() => {
        return Ok(format!("cancelled: {reason}"));
    }
};
```

## Workflow State Access

Workflow structs hold durable Workflow state. Read and mutate state through SDK-supported APIs:

```rust
let count = ctx.state(|s| s.count);
ctx.state_mut(|s| s.count += 1);
ctx.wait_condition(|s| s.count >= 10).await;
```

Synchronous Signal and Update handlers can mutate state directly through `&mut self`. Async handlers should use `ctx.state(...)` and `ctx.state_mut(...)`.

## Runtime Nondeterminism Detection

The Rust SDK includes a runtime detector for nondeterministic async wake sources. It is enabled by default through `WorkerOptions::detect_nondeterministic_futures(true)`.

The detector catches many async mistakes, including:

- `tokio::time::sleep` and `tokio::time::interval`
- `tokio::net`, `tokio::fs`, and other async I/O
- `tokio::spawn`
- `std::thread::spawn` when it wakes Workflow futures
- Direct `tokio::sync` channels

It does not catch every possible issue. Purely synchronous nondeterminism such as `SystemTime::now()` or `rand::random()` must still be avoided by convention and review.

## Testing Replay Compatibility

For application code, cover deterministic behavior in three layers:

1. Unit-test pure helper functions and Activities without Temporal where possible.
2. Run integration tests or a local worker/starter loop against `temporal server start-dev`.
3. Before changing deployed Workflow logic, test replay or use patching so existing histories can follow their original Command sequence.

When working inside the upstream Rust SDK repo, use its command surface: `cargo test`, `cargo integ-test`, `cargo lint`, and `cargo +nightly fmt`.

## Best Practices

1. Keep Workflow code small and orchestration-focused.
2. Put side effects and unstable values in Activities.
3. Use SDK workflow primitives instead of raw `tokio` or `futures` primitives.
4. Prefer input structs for Workflows and Activities so payload shape can evolve safely.
5. Use `ctx.patched(...)` or a new Workflow Type for intentional changes to running Workflows.
