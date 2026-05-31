# Rust SDK Versioning

## Overview

Temporal Workflow versioning protects open Workflow Executions from code changes that would make replay emit a different Command sequence. In Rust, use patching for in-place Workflow logic changes, new Workflow Types for incompatible rewrites, and Worker deployment versioning for controlled Worker rollout.

## Patching API

Use `ctx.patched(...)` to introduce a new code path while preserving the old path for histories that started before the patch.

```rust
if ctx.patched("use-new-fraud-check") {
    ctx.start_activity(
        FraudActivities::new_check,
        input,
        ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
    )
    .await?;
} else {
    ctx.start_activity(
        FraudActivities::old_check,
        input,
        ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
    )
    .await?;
}
```

Use stable, descriptive patch IDs. Do not reuse a patch ID for a different change.

## Three-Step Patching Process

1. **Deploy both branches**: Old histories follow the old branch; new histories can take the patched branch.
2. **Wait for old histories to complete or Continue-As-New**: Use Visibility queries and operational knowledge to confirm no old branch histories remain.
3. **Remove the old branch**: Keep the patch marker or follow the SDK's current deprecation/removal guidance from `docs.rs` and official docs.

Because the Rust SDK is Public Preview, verify the exact removal API before deleting patch branches.

## When Patching Is Needed

Use patching when changing Workflow code that affects Commands, such as:

- Adding, removing, or reordering Activity calls
- Changing Activity Type names
- Adding, removing, or reordering timers
- Adding Child Workflows
- Changing cancellation or Continue-As-New control flow
- Changing code before an existing Command in a way that changes whether it is reached

Patching is usually not needed for Activity implementation changes because Activity code is not replayed as Workflow code. Still preserve Activity idempotency and payload compatibility.

## Workflow Type Versioning

For major rewrites, create a new Workflow Type instead of patching a large branch:

```rust
#[workflow(name = "order-workflow-v2")]
pub struct OrderWorkflowV2;
```

Use this when:

- The new logic is easier to understand as a new type.
- Old executions can finish on the old Worker code.
- Client routing can choose v1 or v2 explicitly.
- Payload or state shape changes are broad.

Keep old Workers available until old Workflow Executions complete or are migrated.

## Continue-As-New as a Migration Boundary

Long-running Workflows can use Continue-As-New to adopt new code at clean boundaries. Pass all durable state in the Continue-As-New input.

```rust
ctx.continue_as_new(&next_input, ContinueAsNewOptions::default())?;
```

This is useful for loops, polling, batch processing, and Workflows that naturally checkpoint.

## Worker Deployment Versioning

The Rust SDK exposes worker deployment configuration through Worker deployment options. Use Worker deployment versioning when you need the Temporal service to route Workflow Tasks according to Worker build/deployment compatibility.

At the Worker layer, treat build IDs and deployment names as operational API. Configure them intentionally, document rollout steps, and verify current server-side requirements before relying on them in production.

## Payload Compatibility

Version payload structs conservatively:

- Prefer adding optional fields.
- Avoid renaming or removing required fields used by open histories.
- Keep enum changes backward compatible.
- Treat Activity and Workflow handler input structs as durable contracts.

## Best Practices

1. Assume open Workflow histories will replay on new code.
2. Use small patch IDs for small changes; use new Workflow Types for broad rewrites.
3. Keep old Workers available until old executions are drained.
4. Query Visibility before removing compatibility branches.
5. Test replay or run integration coverage for both old and new branches before deploy.
