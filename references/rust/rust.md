# Temporal Rust SDK Reference

> [!NOTE]
> Rust support in this developer skill is in Public Preview. Inform the user when using this part of the skill.

## Overview

The Temporal Rust SDK (`temporalio-sdk`) is generally available as of v1.0.0 and provides native Rust APIs for Workflows, Activities, Workers, and Clients. Check exact crate versions and method signatures against the official docs when upgrading.

Rust Workflows are structs with macro-decorated methods. Activities are async methods on an `impl` block. Workers register Workflow and Activity types, then poll a Task Queue.

## Official References

- [Rust SDK developer guide](https://docs.temporal.io/develop/rust) - Rust documentation hub.
- [Rust SDK Quickstart](https://docs.temporal.io/develop/rust/quickstart) - setup, dependencies, local dev server, and a complete hello-world example.
- [Workflow basics](https://docs.temporal.io/develop/rust/workflows/basics) - Workflow structs, `#[run]`, optional `#[init]`, and message handlers.
- [Activity basics](https://docs.temporal.io/develop/rust/activities/basics) - Activity macros, parameters, and Activity boundaries.
- [Worker processes](https://docs.temporal.io/develop/rust/workers/worker-process) - Worker setup, registration, and Task Queue polling.
- [Temporal Client](https://docs.temporal.io/develop/rust/client/temporal-client) - connecting to Temporal Service, starting Workflows, and fetching results.
- [docs.rs temporalio-sdk](https://docs.rs/temporalio-sdk/latest/temporalio_sdk/) - generated Rust API documentation.
- [sdk-rust examples](https://github.com/temporalio/sdk-rust/tree/main/crates/sdk/examples) - current example programs from the SDK repository.

## Quick Demo of Temporal

**Add dependencies:** Follow the [official Rust SDK Quickstart](https://docs.temporal.io/develop/rust/quickstart) for the current `Cargo.toml` dependencies.

Use edition 2024 and Rust 1.92 or later. The macros require `temporalio-workflow` and `futures` as direct dependencies, even when your code does not name them:

```toml
[dependencies]
temporalio-sdk = "1.1.2"
temporalio-client = "1.1.2"
temporalio-common = "1.1.2"
temporalio-macros = "1.1.2"
temporalio-workflow = "1.1.2"
futures = "0.3"
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
```

**src/greeting_input.rs** - Shared input struct:

```rust
use serde::{Deserialize, Serialize};

#[derive(Clone, Deserialize, Serialize)]
pub struct GreetingInput {
    pub first_name: String,
    pub last_name: String,
}
```

**src/activities.rs** - Activity definition:

```rust
use temporalio_macros::activities;
use temporalio_sdk::activities::{ActivityContext, ActivityError};
use crate::greeting_input::GreetingInput;

pub struct MyActivities;

#[activities]
impl MyActivities {
    #[activity]
    pub async fn greet(_ctx: ActivityContext, input: GreetingInput) -> Result<String, ActivityError> {
        Ok(format!("Hello, {} {}!", input.first_name, input.last_name))
    }
}
```

**src/workflows.rs** - Workflow definition:

```rust
use temporalio_macros::{workflow, workflow_methods};
use temporalio_sdk::{ActivityOptions, WorkflowContext, WorkflowContextView, WorkflowResult};
use std::time::Duration;

use crate::activities::MyActivities;
use crate::greeting_input::GreetingInput;

#[workflow]
pub struct GreetingWorkflow {
    input: GreetingInput,
}

#[workflow_methods]
impl GreetingWorkflow {
    #[init]
    fn new(_ctx: &WorkflowContextView, input: GreetingInput) -> Self {
        Self { input }
    }

    #[run]
    pub async fn run(ctx: &mut WorkflowContext<Self>) -> WorkflowResult<String> {
        let input = ctx.state(|s| s.input.clone());

        // Execute an activity
        let greeting = ctx.execute_activity(
            MyActivities::greet,
            input,
            ActivityOptions::start_to_close_timeout(Duration::from_secs(30)),
        ).await?;

        println!("{}", greeting);
        Ok(greeting)
    }
}
```

Both `ctx.execute_activity()` and `client.start_workflow()` take one Rust input value.
When an Activity declares multiple parameters, pass a tuple to
`ctx.execute_activity()`; the SDK converts it into separate argument payloads.
For `client.start_workflow()`, a plain tuple is one composite input serialized
as a JSON array. To start a Workflow that expects multiple argument payloads,
declare its input as `temporalio_common::data_converters::MultiArgs2` (or the
matching arity) and pass that type to `client.start_workflow()`.

**src/main.rs** - Worker setup:

```rust
use temporalio_client::{Client, ClientOptions, Connection};
use temporalio_common::envconfig::LoadClientConfigProfileOptions;
use temporalio_sdk::{Runtime, Worker, WorkerOptions};

mod workflows;
mod activities;
mod greeting_input;

use crate::workflows::GreetingWorkflow;
use crate::activities::MyActivities;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = Runtime::from_current_tokio(Default::default())?;

    // Set up client connection options, loading from config if available
    let (connection_options, client_options) = ClientOptions::load_from_config(
        LoadClientConfigProfileOptions::default(),
    )?;

    let connection = Connection::connect(connection_options).await?;
    let client = Client::new(connection, client_options)?;

    let worker_options = WorkerOptions::new("my-task-queue")
        .register_activities(MyActivities)
        .register_workflow::<GreetingWorkflow>()?
        .build();

    Worker::new(&runtime, client, worker_options)?.run().await?;

    Ok(())
}
```

**Run locally:**

1. Start the dev server with `temporal server start-dev`.
2. Run the Worker with `cargo run`.
3. Start a Workflow Execution with the CLI:

```sh
temporal workflow start \
  --type GreetingWorkflow \
  --task-queue my-task-queue \
  --input '{"first_name":"Ada","last_name":"Lovelace"}'
```

## Key Concepts

### Workflow Definition

- Define a struct and annotate it with `#[workflow]`.
- Put Workflow methods in a `#[workflow_methods]` impl block.
- Use `#[run]` for the main Workflow logic, and optionally use `#[init]`, `#[signal]`, `#[query]`, and `#[update]`.

### Activity Definition

- Put Activity methods in a `#[activities]` impl block.
- Annotate each Activity method with `#[activity]`.
- Activities can perform I/O, call services, use system time, and do other non-deterministic work.

### Evolving Inputs and Results

Prefer one `serde`-serializable struct for Workflow and Activity inputs that may grow, and a result struct when needed. Give new fields deserialization defaults, such as `#[serde(default)]`; changing an existing scalar input to a struct requires a migration because old payloads remain in history.

### Worker Setup

- A Worker registers Workflow and Activity types, then polls one Task Queue.
- Workers polling the same Task Queue should register the same Workflow and Activity types.
- Keep Worker runtime, client, config, secrets, and logging setup outside Workflow code.

### Temporal Client

- Use the Rust client outside Workflow code to start Workflows and send Signals, Queries, and Updates.
- Do not create or use a Temporal Client inside Workflow code.
- A Client can be used inside an Activity when the Activity needs to interact with Temporal Service.

## File Organization Best Practice

Keep Workflow definitions, Activity implementations, Worker setup, and starter/client code separate. This makes the determinism boundary easy to inspect.

```text
my_temporal_app/
|-- src/
|   |-- greeting_input.rs # Shared input struct
|   |-- activities.rs   # Activity implementations and side effects
|   |-- workflows.rs    # Workflow definitions and orchestration
|   `-- main.rs         # Worker process in the Quickstart
`-- Cargo.toml
```

## Common Pitfalls

1. **Calling I/O from a Workflow** - Put network, database, filesystem, process calls, and other side effects in Activities.
2. **Mixing Worker and Workflow concerns** - Runtime setup, clients, secrets, environment config, and external logging sinks belong outside Workflow code.
3. **Missing macro dependencies** - Include `temporalio-workflow` and `futures` directly; macro expansion references them.

## Rust-Specific References Status

Beyond this guide, use the official Rust SDK docs, docs.rs, and [`sdk-rust` examples](https://github.com/temporalio/sdk-rust/tree/main/crates/sdk/examples) for child Workflows, Continue-as-New, message handlers, cancellation, timers, timeouts, Nexus, and Serverless Workers. For SDK-neutral Temporal concepts, use the core references under `references/core/`.

## Standalone Activities

Rust SDK v1.0.0+ supports Standalone Activities (GA). Use Temporal CLI v1.9.1+ and Temporal Server v1.32.0+ or Temporal Cloud. Define and register Activities as usual, then invoke them from non-Workflow Client code. See the [Rust Standalone Activities guide](https://docs.temporal.io/develop/rust/activities/standalone-activities) and [core concepts](../core/standalone-activities.md).
