# Rust SDK Error Handling

## Overview

Rust Temporal code has three main error surfaces:

- Activities return `Result<T, ActivityError>`.
- Workflows return `WorkflowResult<T>`.
- Clients and Workers return normal Rust `Result` values from async calls and setup APIs.

Classify failures carefully. Retriable infrastructure failures should usually be Activities errors. Permanent business failures should be non-retryable application failures or explicit Workflow results.

## Application Failures

Use `ApplicationFailure` when an Activity needs to fail with Temporal-aware metadata:

```rust
use temporalio_sdk::{ApplicationFailure, activities::ActivityError};

return Err(ActivityError::application(
    ApplicationFailure::non_retryable(anyhow::anyhow!("invalid input")),
));
```

Use retryable failures for temporary problems:

```rust
return Err(ApplicationFailure::builder(anyhow::anyhow!("service unavailable"))
    .next_retry_delay(std::time::Duration::from_secs(5))
    .build()
    .into());
```

Use non-retryable failures for validation errors, unsupported states, or business rules that retrying cannot fix.

## Handling Activity Errors in Workflows

Activity execution returns a result to the Workflow. Handle expected Activity failures in Workflow code when compensation, alternate paths, or typed business outcomes are needed.

```rust
match ctx
    .start_activity(
        BookingActivities::reserve_car,
        request,
        ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
    )
    .await
{
    Ok(booking_id) => Ok(booking_id),
    Err(err) => {
        // Decide whether to compensate, return a business result, or fail the Workflow.
        Err(err.into())
    }
}
```

Do not catch and swallow errors only to mark the Workflow successful. If the external operation did not complete, preserve that fact in the Workflow result or failure.

## Retry Configuration

Activities use Retry Policies together with Activity timeouts. Configure retries in `ActivityOptions` when scheduling the Activity:

```rust
let result = ctx.start_activity(
    MyActivities::call_service,
    input,
    ActivityOptions::with_start_to_close_timeout(Duration::from_secs(30))
        .retry_policy(RetryPolicy {
            maximum_attempts: 5,
            non_retryable_error_types: vec!["ValidationError".to_string()],
            ..Default::default()
        })
        .build(),
);
```

Keep retry boundaries idempotent. If an Activity performs an external write, use a business idempotency key such as Workflow ID plus a stable operation name.

## Timeout Configuration

Every Activity Execution must set at least one of:

- Start-To-Close Timeout
- Schedule-To-Close Timeout

Temporal strongly recommends Start-To-Close for most Activities because it bounds each attempt and helps detect lost Activity Tasks.

```rust
ActivityOptions::start_to_close_timeout(Duration::from_secs(30))
```

For long-running Activities, set a Heartbeat Timeout and heartbeat from the Activity:

```rust
let opts = ActivityOptions::with_start_to_close_timeout(Duration::from_secs(300))
    .heartbeat_timeout(Duration::from_secs(5))
    .build();
```

## Cancellation

Workflow cancellation is cooperative. Race Workflow work against `ctx.cancelled()` when cleanup matters.

Activity cancellation is observable through `ActivityContext`:

```rust
if ctx.is_cancelled() {
    return Err(ActivityError::cancelled());
}
```

Long-running Activities should heartbeat regularly so cancellation and progress details can be delivered promptly.

## Workflow Failure

Return `Err(...)` from `WorkflowResult<T>` only when the whole Workflow Execution should fail. Many business outcomes are better modeled as successful Workflow results with explicit status fields.

Use a Saga/compensation pattern when the Workflow has already completed earlier side effects and a later step fails. See `references/rust/patterns.md`.

## Best Practices

1. Put retryable I/O in Activities, not Workflows.
2. Make Activities idempotent before enabling broad retries.
3. Mark validation and business-rule failures non-retryable.
4. Set Activity timeouts deliberately; do not rely on defaults.
5. Preserve failure semantics in Workflow results instead of logging and continuing silently.
