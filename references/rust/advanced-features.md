# Rust SDK Advanced Features

## Schedules

The Rust Client includes schedule APIs for creating, listing, triggering, and deleting schedules.

```rust
use temporalio_client::schedules::{
    CreateScheduleOptions, ScheduleAction, ScheduleOverlapPolicy, ScheduleSpec,
};

let handle = client
    .create_schedule(
        "demo-schedule",
        CreateScheduleOptions::builder()
            .action(ScheduleAction::start_workflow(
                "ScheduledWorkflow",
                "schedules",
                "scheduled-workflow",
            ))
            .spec(ScheduleSpec::from_interval(std::time::Duration::from_secs(10)))
            .trigger_immediately(true)
            .build(),
    )
    .await?;

handle.trigger(ScheduleOverlapPolicy::Unspecified).await?;
handle.delete().await?;
```

Use schedules for recurring Workflow starts. Keep schedule IDs stable and include cleanup commands for local demos.

## Local Activities

Local Activities run on the same Worker as the Workflow and avoid a full server round trip. Use them for short, idempotent operations where server-side Activity durability is not required.

```rust
ctx.start_local_activity(
    MyActivities::quick_operation,
    input,
    LocalActivityOptions {
        schedule_to_close_timeout: Some(Duration::from_secs(5)),
        ..Default::default()
    },
)?
.await?;
```

Do not use Local Activities for long-running work or operations that need normal Activity scheduling semantics.

## Worker Tuning

`WorkerOptions` exposes knobs for cache size, poller behavior, rate limits, graceful shutdown, deployment options, and nondeterminism detection.

```rust
let worker_options = WorkerOptions::new("task-queue")
    .max_cached_workflows(1000)
    .graceful_shutdown_period(Duration::from_secs(30))
    .detect_nondeterministic_futures(true)
    .register_activities(my_activities)
    .register_workflow::<MyWorkflow>()?
    .build();
```

Tune from actual metrics. Increasing concurrency or cache size without observing latency, CPU, memory, and task backlog can hide the real bottleneck.

## Activity Interceptors

Activity inbound interceptors can inspect typed Activity inputs and outputs around Activity execution.

Use interceptors for cross-cutting concerns such as logging, metrics, and validation. Keep them small and avoid changing business semantics in hidden layers.

```rust
worker.add_activity_inbound_interceptor(LoggingActivityInterceptor);
```

## Shared Activity State

Activity implementers can hold shared state. Use `Arc<Self>` Activity methods when an Activity needs access to shared clients or semaphores.

```rust
#[activity]
pub async fn increment(self: Arc<Self>, _ctx: ActivityContext) -> Result<u32, ActivityError> {
    Ok(self.counter.fetch_add(1, Ordering::Relaxed) as u32)
}
```

Do not put non-durable Workflow state in Activity structs. Activity state is process-local and can disappear on Worker restart.

## Nexus

The Rust docs include a Nexus feature guide and the SDK exposes Workflow APIs for starting Nexus operations. Treat Nexus details as fast-moving and verify current official docs before implementing.

```rust
let started = ctx.start_nexus_operation(options).await?;
```

## WASM Workflows

The SDK repo contains WASM Workflow examples used by integration tests. Use them only when you are intentionally working with WASM Workflow components; normal Rust Temporal apps should start with native Workflow structs and Workers.

## Temporal Cloud Connections

Use environment configuration or `temporal.toml` profiles for local and Cloud connections. Cloud connections require Namespace/account endpoint details plus API key or mTLS configuration.

Never commit API keys, certificate private keys, or machine-specific credential paths.

## Best Practices

1. Reach for normal Activities and Workflows before advanced features.
2. Keep Worker tuning tied to measured bottlenecks.
3. Use Local Activities only for short, local, idempotent work.
4. Treat Public Preview APIs as subject to change and verify exact names.
5. Keep cross-cutting interceptors simple and observable.
