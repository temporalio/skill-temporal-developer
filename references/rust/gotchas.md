# Rust Gotchas

## Public Preview API Drift

The Rust SDK is in Public Preview. Examples in old issues, blog posts, or generated answers may use outdated names such as older Workflow option types.

**Fix:** Check the current official Rust docs, current `docs.rs`, and the `temporalio/sdk-rust` examples before copying API details.

## Workflow Async Primitives

### Using Tokio in Workflow Code

Do not use raw Tokio primitives in Workflows:

```rust
// BAD
tokio::time::sleep(Duration::from_secs(1)).await;
tokio::spawn(async move { do_work().await });
```

Use SDK primitives:

```rust
// GOOD
ctx.timer(Duration::from_secs(1)).await;
```

Use `temporalio_sdk::workflows::select!`, `join!`, and `join_all` instead of raw concurrency helpers.

## Non-Deterministic Operations

### Time and Randomness

Avoid this in Workflows:

```rust
// BAD
let now = std::time::SystemTime::now();
let id = uuid::Uuid::new_v4();
```

Use Workflow-safe APIs or move the operation to an Activity:

```rust
// GOOD
let now = ctx.workflow_time();
```

### External I/O

Workflows should not call databases, HTTP APIs, files, environment variables, or Temporal Clients. Put that work in Activities.

## Activity Timeouts

### Missing Required Timeout

Activity Execution requires Start-To-Close or Schedule-To-Close timeout.

Prefer close-timeout constructors when scheduling Activities:

```rust
ctx.start_activity(
    MyActivities::greet,
    name,
    ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
);
```

## Activity Idempotency

Activities are retried. Any external write must tolerate duplicate attempts.

**Fix:** Use idempotency keys based on stable Workflow data, such as Workflow ID plus an operation name or business record ID.

## Heartbeating

### Forgetting to Heartbeat Long Activities

Long-running Activities that do not heartbeat cannot report progress, resume from checkpoints, or receive cancellation promptly.

```rust
// GOOD
ctx.record_heartbeat(vec![step.as_json_payload()?]);
if ctx.is_cancelled() {
    return Err(ActivityError::cancelled());
}
```

Set a Heartbeat Timeout when scheduling the Activity.

## Payload Shape

### Passing Too Many Arguments

Temporal has payload and argument limits, and changing multiple positional parameters is brittle.

**Fix:** Use a single serializable input struct:

```rust
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ProcessPaymentInput {
    pub order_id: String,
    pub amount_cents: u64,
}
```

## Worker Registration

### Inconsistent Task Queue Registrations

Workers polling the same Task Queue should register the same Workflow and Activity types. If a Worker receives a Task for an unknown type, that Task fails.

**Fix:** Keep Task Queue names and registration code centralized enough that all replicas use the same WorkerOptions.

## Workflow State

### Hiding State in Globals

Process-global state is not durable Workflow state and may differ on replay or on another Worker.

**Fix:** Store Workflow progress in the Workflow struct and mutate it through SDK state APIs or handlers.

## Error Classification

### Retrying Permanent Failures

If an Activity returns a normal retryable failure for invalid input, Temporal may retry needlessly.

**Fix:** Use `ApplicationFailure::non_retryable(...)` for permanent business errors.

## Versioning

### Changing Workflow Command Order Without Patching

Adding, removing, or reordering Activity calls, timers, Child Workflows, or Continue-As-New can break open Workflow Executions.

**Fix:** Use `ctx.patched(...)`, a new Workflow Type, or drain old executions before deploying incompatible changes.

## Testing

### Only Testing Activities

Activity unit tests do not prove Workflow replay behavior.

**Fix:** Run an integration path with a Worker and Client against a Temporal dev server. For Workflow changes in production systems, use replay tests or patching.
