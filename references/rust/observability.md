# Rust SDK Observability

## Overview

Rust Temporal observability usually combines SDK telemetry, Rust `tracing`, Activity heartbeats, Search Attributes, and Temporal Web UI/CLI inspection.

Keep the determinism boundary in mind: Workflow code should not perform arbitrary logging side effects for business observability. Prefer Worker-level tracing, Activity logging, Search Attributes, and explicit Workflow state.

## Telemetry Setup

Create the Core runtime with telemetry options:

```rust
use temporalio_common::telemetry::TelemetryOptions;
use temporalio_sdk_core::{CoreRuntime, RuntimeOptions};

let runtime = CoreRuntime::new_assume_tokio(
    RuntimeOptions::builder()
        .telemetry_options(TelemetryOptions::builder().build())
        .build()?,
)?;
```

The `temporalio-sdk` crate enables Prometheus support by default and has an optional OpenTelemetry feature. Verify exact exporter configuration against current `docs.rs` before wiring production telemetry.

## Logging

Use normal Rust logging and `tracing` in Worker setup and Activity code. Activities are the right place to log external calls, retryable errors, and integration details.

Avoid relying on `println!` in Workflow code for durable business state. Workflow code can replay, and replay-related behavior can make naive logs noisy or misleading.

## Activity Heartbeats

Heartbeats are both failure-detection and observability signals for long-running Activities.

```rust
ctx.record_heartbeat(vec![step.as_json_payload()?]);
```

Use heartbeat details for progress checkpoints that can resume after retry:

```rust
let start_step: u32 = ctx
    .heartbeat_details()
    .first()
    .and_then(|payload| serde_json::from_slice(&payload.data).ok())
    .unwrap_or(0);
```

Heartbeat details should be small and safe to store in Event History.

## Search Attributes

Use Search Attributes for operational query fields:

```rust
ctx.upsert_search_attributes([
    (
        "CustomKeywordField".to_string(),
        "updated-value".as_json_payload()?,
    ),
]);
```

Good Search Attributes:

- Tenant ID
- Order ID
- Region
- Current business status
- Small categorical fields used for support or dashboards

Bad Search Attributes:

- Secrets
- Large documents
- High-cardinality debug blobs
- Data that does not need Visibility queries

## Worker Identity and Task Queues

Set a clear Worker identity when it helps operations distinguish processes. Task Queue names should be stable and meaningful.

WorkerOptions also controls cache size, poller behavior, rate limits, and graceful shutdown. These settings affect operational metrics and should be tuned with real Worker telemetry.

## Temporal Web UI and CLI

Use the Web UI and CLI to inspect:

- Workflow status
- Event History
- Activity attempts
- Timeouts and retry state
- Pending Signals, Updates, or cancellations
- Search Attributes and memo

For CLI command patterns, read `references/core/cli-workflow-commands.md`.

## Best Practices

1. Put detailed external-call logging in Activities.
2. Use Search Attributes for operator queries, not as a data store.
3. Heartbeat long Activities with compact progress details.
4. Avoid secrets in logs, memo, Search Attributes, and heartbeat details.
5. Tune WorkerOptions from observed throughput, latency, and retry behavior.
