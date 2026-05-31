# Rust SDK Patterns

## Signals

Signals are asynchronous messages that mutate a running Workflow. Define them as methods in the `#[workflow_methods]` impl block.

```rust
use temporalio_sdk::SyncWorkflowContext;

#[signal]
pub fn increment(&mut self, _ctx: &mut SyncWorkflowContext<Self>, amount: i32) {
    self.counter += amount;
}
```

Send a Signal from a Client:

```rust
handle
    .signal(
        MessagePassingWorkflow::increment,
        5,
        WorkflowSignalOptions::default(),
    )
    .await?;
```

## Queries

Queries synchronously read Workflow state and must not mutate it.

```rust
#[query]
pub fn get_counter(&self, _ctx: &WorkflowContextView) -> i32 {
    self.counter
}
```

Send a Query from a Client:

```rust
let counter = handle
    .query(
        MessagePassingWorkflow::get_counter,
        (),
        WorkflowQueryOptions::default(),
    )
    .await?;
```

## Updates

Updates are trackable messages that can mutate state and return a result. Add validators for preconditions that should reject the Update before it is accepted.

```rust
#[update_validator(set_counter)]
fn validate_set_counter(
    &self,
    _ctx: &WorkflowContextView,
    value: &i32,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    if *value < 0 {
        Err("counter must be non-negative".into())
    } else {
        Ok(())
    }
}

#[update]
pub fn set_counter(&mut self, _ctx: &mut SyncWorkflowContext<Self>, value: i32) -> i32 {
    let old = self.counter;
    self.counter = value;
    old
}
```

Send an Update from a Client:

```rust
let old = handle
    .execute_update(
        MessagePassingWorkflow::set_counter,
        10,
        WorkflowExecuteUpdateOptions::default(),
    )
    .await?;
```

## Wait Conditions

Use `ctx.wait_condition(...)` to block Workflow progress until state changes through a Signal or Update.

```rust
#[run]
pub async fn run(ctx: &mut WorkflowContext<Self>, target: i32) -> WorkflowResult<i32> {
    ctx.wait_condition(|s| s.counter >= target).await;
    Ok(ctx.state(|s| s.counter))
}
```

This is preferred over channels or raw async synchronization in Workflow code.

## Timers

Use `ctx.timer(...)` for durable sleep:

```rust
ctx.timer(Duration::from_secs(60)).await;
```

Timers survive Worker restarts and Temporal Service downtime.

## Parallel Execution

Use Temporal's deterministic workflow helpers, not raw `tokio::join!` or `tokio::select!`.

```rust
use temporalio_sdk::workflows::join;

let greeting = ctx.start_activity(
    MyActivities::greet,
    name,
    ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
);

let language = ctx.start_activity(
    MyActivities::detect_language,
    input,
    ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
);

let (greeting_res, language_res) = join!(greeting, language);
```

## Child Workflows

Start Child Workflows when a unit of work needs independent history, cancellation, retry, or ownership boundaries.

```rust
let started = ctx
    .start_child_workflow(
        GreetingChildWorkflow::run,
        name.clone(),
        ChildWorkflowOptions {
            workflow_id: format!("greeting-child-{i}"),
            ..Default::default()
        },
    )
    .await?;

let greeting = started.result().await?;
```

Register child Workflow types on Workers that may execute them.

## Continue-As-New

Use Continue-As-New to keep long-running Workflow histories bounded.

```rust
ctx.continue_as_new(
    &(current_iteration + 1, max_iterations),
    ContinueAsNewOptions::default(),
)?;
```

Pass every piece of state the next run needs. Do not rely on process memory surviving.

## Cancellation

Race work against `ctx.cancelled()` when cleanup is needed:

```rust
let mut activity_fut = ctx.start_activity(
    CancellationActivities::long_running_activity,
    (),
    activity_opts(),
);

temporalio_sdk::workflows::select! {
    result = &mut activity_fut => result.map_err(|e| anyhow::anyhow!("{e}")),
    reason = ctx.cancelled() => {
        activity_fut.cancel();
        let cleanup = ctx
            .start_activity(
                CancellationActivities::cleanup,
                (),
                ActivityOptions::start_to_close_timeout(Duration::from_secs(10)),
            )
            .await?;
        Ok(format!("cancelled: {reason}, {cleanup}"))
    }
}
```

Long-running Activities should heartbeat so cancellation and progress are delivered.

## Saga Pattern

For multi-step side effects, record compensations after successful steps and run them in reverse order on failure.

```rust
let hotel = saga
    .step(
        BookingActivities::book_hotel,
        trip_id.clone(),
        BookingActivities::cancel_hotel,
    )
    .await?;
```

Compensations should be Activities too. Make them idempotent; a compensation may be retried.

## Activity Heartbeat Details

Use heartbeats for long-running Activities:

- Record progress with `ctx.record_heartbeat(...)`.
- Check `ctx.is_cancelled()`.
- On retry, read `ctx.heartbeat_details()` to resume.

## Best Practices

1. Prefer Signals for async external events, Queries for reads, and Updates for validated mutations.
2. Use `ctx.wait_condition(...)` for state coordination.
3. Use deterministic workflow concurrency helpers.
4. Use Child Workflows for independently owned sub-processes.
5. Keep compensation and cancellation paths idempotent.
