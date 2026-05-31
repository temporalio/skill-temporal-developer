# Rust SDK Data Handling

## Overview

Temporal payloads are recorded in Event History. In Rust, Workflow inputs, Activity inputs, handler inputs, and return values should use serializable data types. Prefer small, explicit structs with `serde` derives.

The Rust SDK is Public Preview, so verify advanced data converter APIs against current `docs.rs` before implementing custom conversion.

## Serializable Inputs and Results

Use structs instead of long argument lists:

```rust
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GreetingInput {
    pub greeting: String,
    pub name: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GreetingOutput {
    pub message: String,
}
```

This makes payload evolution easier. Adding an optional field to a struct is less disruptive than changing a Workflow or Activity signature.

## Payload Limits

Be mindful of Temporal payload limits:

- A single payload argument is limited to 2 MB by default.
- The total gRPC message size has a hard 4 MB limit.
- Payloads are stored in Event History, so large payloads make replay and Worker performance worse.

For large data, store it outside Temporal, such as S3, GCS, a database, or object storage, and pass a durable reference in the Workflow payload.

## Default Data Converter

The default Rust data converter handles common serde-serializable values. Use the same serializable types across Workflow, Activity, and Client boundaries.

Avoid passing:

- Open file handles
- Database connections
- HTTP clients
- Runtime handles
- Non-serializable closures or trait objects

Those belong in Activity implementer state or Worker setup, not in Workflow payloads.

## Activity Heartbeat Details

Activities can record progress as payload details:

```rust
use temporalio_common::protos::coresdk::AsJsonPayloadExt;

ctx.record_heartbeat(vec![step.as_json_payload()?]);
```

On retry, read heartbeat details and resume from the last checkpoint:

```rust
let start_step: u32 = ctx
    .heartbeat_details()
    .first()
    .and_then(|payload| serde_json::from_slice(&payload.data).ok())
    .unwrap_or(0);
```

Use this for long-running, chunked Activities.

## Search Attributes

Search Attributes are indexed Visibility fields. They are useful for operators and lookup, not for large application state.

From a Workflow:

```rust
use temporalio_common::protos::coresdk::AsJsonPayloadExt;

ctx.upsert_search_attributes([
    (
        "CustomKeywordField".to_string(),
        "updated-value".as_json_payload()?,
    ),
    ("CustomIntField".to_string(), 42i64.as_json_payload()?),
]);
```

From a Client start request, pass initial Search Attributes through `WorkflowStartOptions`.

Keep Search Attribute names and types aligned with the Namespace configuration.

## Memo

Workflow memo is non-indexed metadata. Use it for small descriptive fields that should travel with Workflow descriptions but do not need Visibility queries.

Do not put secrets in memo or Search Attributes.

## Payload Codecs and Encryption

Temporal can apply payload codecs for compression or encryption. Rust client environment config supports codec endpoint configuration through variables such as `TEMPORAL_CODEC_ENDPOINT` and `TEMPORAL_CODEC_AUTH`, and through `temporal.toml` codec profiles.

When using codecs:

1. Keep keys and auth out of source control.
2. Confirm Web UI and CLI visibility expectations; encoded payloads may need a codec server for decoding.
3. Test that Workers, Clients, and operational tools use compatible codec configuration.

## Best Practices

1. Use one input struct per Workflow or Activity once inputs may evolve.
2. Keep payloads small and store large blobs externally.
3. Derive `Serialize` and `Deserialize` on boundary types.
4. Use Search Attributes only for queryable operational fields.
5. Treat payload codecs as a cross-process compatibility feature; validate all clients and workers together.
