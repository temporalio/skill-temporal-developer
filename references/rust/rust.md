# Temporal Rust SDK Reference

## Overview

The Temporal Rust SDK (`temporalio-sdk`) provides a native Rust API for building Workflows, Activities, Workers, and Clients. The SDK is in Public Preview, so prefer the [current official docs](https://docs.temporal.io/develop/rust) and [docs.rs](https://docs.rs/temporalio-sdk/latest/temporalio_sdk/) when exact method names matter.

Rust Workflows are structs plus macro-decorated methods. Activities are async methods on an `impl` block. Workers register Workflow and Activity types, then poll a Task Queue.

## Quick Start

**Add dependencies:** The [official quickstart](https://docs.temporal.io/develop/rust/quickstart) currently uses the `0.4.0` crate family.

```toml
[dependencies]
anyhow = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
temporalio-client = "0.4.0"
temporalio-common = "0.4.0"
temporalio-macros = "0.4.0"
temporalio-sdk = "0.4.0"
temporalio-sdk-core = "0.4.0"
tokio = { version = "1", features = ["full"] }
```

**activities.rs** - Activity definitions:

```rust
use temporalio_macros::activities;
use temporalio_sdk::activities::{ActivityContext, ActivityError};

pub struct GreetingActivities;

#[activities]
impl GreetingActivities {
    #[activity]
    pub async fn greet(_ctx: ActivityContext, name: String) -> Result<String, ActivityError> {
        Ok(format!("Hello, {name}!"))
    }
}
```

**workflows.rs** - Workflow definition:

```rust
use std::time::Duration;
use temporalio_macros::{workflow, workflow_methods};
use temporalio_sdk::{ActivityOptions, WorkflowContext, WorkflowResult};

use crate::activities::GreetingActivities;

#[workflow]
#[derive(Default)]
pub struct HelloWorldWorkflow;

#[workflow_methods]
impl HelloWorldWorkflow {
    #[run]
    pub async fn run(ctx: &mut WorkflowContext<Self>, name: String) -> WorkflowResult<String> {
        let greeting = ctx
            .start_activity(
                GreetingActivities::greet,
                name,
                ActivityOptions::start_to_close_timeout(Duration::from_secs(10)),
            )
            .await?;
        Ok(greeting)
    }
}
```

**worker.rs** - Worker setup:

```rust
mod activities;
mod workflows;

use activities::GreetingActivities;
use temporalio_client::{
    Client, ClientOptions, Connection, envconfig::LoadClientConfigProfileOptions,
};
use temporalio_common::telemetry::TelemetryOptions;
use temporalio_sdk::{Worker, WorkerOptions};
use temporalio_sdk_core::{CoreRuntime, RuntimeOptions};
use workflows::HelloWorldWorkflow;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = CoreRuntime::new_assume_tokio(
        RuntimeOptions::builder()
            .telemetry_options(TelemetryOptions::builder().build())
            .build()?,
    )?;
    let (conn_opts, client_opts) =
        ClientOptions::load_from_config(LoadClientConfigProfileOptions::default())?;
    let connection = Connection::connect(conn_opts).await?;
    let client = Client::new(connection, client_opts)?;

    let worker_options = WorkerOptions::new("hello-world")
        .register_workflow::<HelloWorldWorkflow>()?
        .register_activities(GreetingActivities)
        .build();

    let mut worker = Worker::new(&runtime, client, worker_options)?;
    worker.run().await?;
    Ok(())
}
```

**starter.rs** - Start a Workflow Execution:

```rust
mod workflows;

use temporalio_client::{
    Client, ClientOptions, Connection, WorkflowGetResultOptions, WorkflowStartOptions,
    envconfig::LoadClientConfigProfileOptions,
};
use workflows::HelloWorldWorkflow;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (conn_opts, client_opts) =
        ClientOptions::load_from_config(LoadClientConfigProfileOptions::default())?;
    let connection = Connection::connect(conn_opts).await?;
    let client = Client::new(connection, client_opts)?;

    let handle = client
        .start_workflow(
            HelloWorldWorkflow::run,
            "Temporal".to_string(),
            WorkflowStartOptions::new("hello-world", "hello-world-workflow-id").build(),
        )
        .await?;

    let result = handle
        .get_result(WorkflowGetResultOptions::default())
        .await?;
    println!("Workflow result: {result}");
    Ok(())
}
```

**Run locally:** Start `temporal server start-dev`, then run the Worker and starter in separate terminals.

## Key Concepts

### Workflow Definition

- Define a struct and annotate it with `#[workflow]`.
- Put Workflow methods in a `#[workflow_methods]` impl block.
- `#[run]` is required and contains the main async Workflow logic.
- `#[init]` is optional and initializes state from Workflow input.
- `#[signal]`, `#[query]`, and `#[update]` expose message handlers.
- Workflow inputs, state, and return values should be serializable with `serde`.

### Activity Definition

- Put Activity methods in a `#[activities]` impl block.
- Each Activity method is annotated with `#[activity]`.
- Activity methods are async, take `ActivityContext` first, and return `Result<T, ActivityError>`.
- Activities can perform I/O, call services, use system time, and do other non-deterministic work.
- Use a single input struct for arguments that may evolve over time.

### Worker Setup

- Load connection settings with `ClientOptions::load_from_config(...)` or build explicit options.
- Create a `CoreRuntime`.
- Create a `Client`, build `WorkerOptions`, register Workflows and Activities, then call `Worker::run().await`.
- All Workers polling the same Task Queue should register the same Workflow and Activity types.

### Temporal Client

- Use `temporalio-client` outside Workflow code to start Workflows and send Signals, Queries, and Updates.
- Do not create or use a Temporal Client inside Workflow code.
- A Client can be used inside an Activity when the Activity needs to interact with Temporal Service.

## File Organization Best Practice

Keep Workflow definitions, Activity implementations, Worker setup, and starter/client code separate. This makes the determinism boundary easy to inspect.

```
my_temporal_app/
|-- src/
|   |-- activities.rs   # Activity implementations and side effects
|   |-- workflows.rs    # Workflow definitions and orchestration
|   |-- worker.rs       # Worker process
|   `-- starter.rs      # Client code that starts workflows
`-- Cargo.toml
```

## Common Pitfalls

1. **Using `tokio` primitives in Workflow code** - Use Temporal workflow primitives such as `ctx.timer()` and `temporalio_sdk::workflows::select!`.
2. **Calling I/O from a Workflow** - Put network, database, filesystem, and process calls in Activities.
3. **Skipping Activity timeouts** - Set `start_to_close_timeout` or `schedule_to_close_timeout` for each Activity Execution.
4. **Forgetting `serde` derives** - Workflow and Activity payload types must serialize and deserialize correctly.
5. **Mixing Worker and Workflow concerns** - Runtime setup, clients, secrets, logging sinks, and environment config belong outside Workflow code.
