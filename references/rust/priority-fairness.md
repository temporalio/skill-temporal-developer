# Task Queue Priority and Fairness in Rust

> [!NOTE]
> The Temporal Rust SDK is in Public Preview. Verify the crate version and API signatures against current `docs.rs` documentation.

Read `references/core/priority-fairness.md` first for the cross-SDK behavior, configuration, and limitations.

Rust represents Priority and Fairness metadata with `temporalio_common::Priority`. Its fields are optional and inherit independently. Set only `priority_key` for Priority-only use, or only the Fairness fields to use the default Priority.

```rust
use temporalio_common::Priority;

let tenant_priority = Priority {
    priority_key: Some(1),
    fairness_key: Some("tenant-123".to_string()),
    fairness_weight: Some(2.0),
};
```

## Start a Workflow

Set Priority in `WorkflowStartOptions`:

```rust
use temporalio_client::WorkflowStartOptions;

let handle = client
    .start_workflow(
        MyWorkflow::run,
        "input".to_string(),
        WorkflowStartOptions::new("my-task-queue", "my-workflow-id")
            .priority(tenant_priority.clone())
            .build(),
    )
    .await?;
```

## Override an Activity

Set Priority in `ActivityOptions`:

```rust
use std::time::Duration;
use temporalio_sdk::ActivityOptions;

let result = ctx
    .start_activity(
        MyActivities::process_order,
        "order-123".to_string(),
        ActivityOptions::with_start_to_close_timeout(Duration::from_secs(30))
            .priority(tenant_priority.clone())
            .build(),
    )
    .await?;
```

## Override a Child Workflow

Set Priority in `ChildWorkflowOptions`:

```rust
use temporalio_sdk::ChildWorkflowOptions;

let started = ctx
    .start_child_workflow(
        MyChildWorkflow::run,
        "input".to_string(),
        ChildWorkflowOptions {
            workflow_id: "my-child-workflow-id".to_string(),
            priority: Some(tenant_priority),
            ..Default::default()
        },
    )
    .await?;

let result = started.result().await?;
```

If an Activity or Child Workflow omits Priority, it inherits the parent Workflow's values.
