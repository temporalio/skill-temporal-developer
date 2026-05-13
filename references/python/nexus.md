# Nexus — Python SDK

Python-specific programming model for Temporal Nexus. For lifecycle, timeouts,
retries, circuit breaking, cancellation vs termination, deployment, security,
debugging, and metrics, see `references/core/nexus.md` — this file only covers
the Python API surface.

## Support status

Temporal Python SDK support for Nexus is **Generally Available**.

Recommended versions: Temporal CLI `v1.3.0` or higher, Temporal Python SDK
`v1.14.1` or higher.

The Python Nexus API is split across two modules:

- `nexusrpc` (third-party package) — Service contract definitions, handler
  decorators, exception types.
- `temporalio.nexus` (imported as `from temporalio import nexus`) — Temporal-
  specific helpers: `workflow_run_operation`, `WorkflowRunOperationContext`,
  `WorkflowHandle`, `client()`, `info()`.

## Defining the Service contract

Use `@nexusrpc.service` on a class whose attributes are
`nexusrpc.Operation[Input, Output]` annotations. Inputs and outputs are
typically `@dataclass` types so they round-trip cleanly through the default
data converter (JSON).

```python
from dataclasses import dataclass
import nexusrpc

@dataclass
class MyInput:
    name: str

@dataclass
class MyOutput:
    message: str

@nexusrpc.service
class MyNexusService:
    my_sync_operation: nexusrpc.Operation[MyInput, MyOutput]
    my_workflow_run_operation: nexusrpc.Operation[MyInput, MyOutput]
```

A Nexus Operation can only take **one input parameter**. To start a Workflow
that takes multiple arguments, use a single composite input dataclass and
unpack it inside the handler (see the multi-arg recipe below).

## Handler basics

Implement the contract by decorating a class with
`@nexusrpc.handler.service_handler(service=MyNexusService)`. Each Operation in
the contract becomes a method on this class, decorated as either a sync
operation or a Workflow-run operation.

```python
import nexusrpc

@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    ...
```

## Synchronous Operation handler

Use `@nexusrpc.handler.sync_operation` for simple RPC-style handlers. The
method is `async def`, takes a
`ctx: nexusrpc.handler.StartOperationContext` and the typed `input`, and
returns the output directly.

```python
import nexusrpc

@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexusrpc.handler.sync_operation
    async def my_sync_operation(
        self, ctx: nexusrpc.handler.StartOperationContext, input: MyInput
    ) -> MyOutput:
        return MyOutput(message=f"Hello {input.name} from sync operation!")
```

Sync handlers must return in **less than 10s**. They must also be reliable to
avoid tripping the circuit breaker (5 consecutive retryable errors blocks all
Operations on the Endpoint). See `references/core/nexus.md` for the broader
rules.

## Using the Temporal Client from a sync handler

Inside a sync handler you can drive an existing or new Workflow via Signals,
Queries, Updates, Signal-With-Start, or Update-With-Start. Import the
Temporal-side helpers and call `nexus.client()` to get the same Client the
Worker was initialized with.

```python
from temporalio import nexus

@nexusrpc.handler.service_handler(service=NexusGreetingService)
class NexusGreetingServiceHandler:
    def _get_workflow_handle(self, user_id: str):
        return nexus.client().get_workflow_handle_for(
            GreetingWorkflow.run, get_workflow_id(user_id)
        )
```

All such calls must complete within the **Nexus request timeout**. Updates in
particular should be short-lived to stay within that deadline.

You can also call `nexus.info()` to access information about the
currently-executing Nexus Operation, including its Task Queue.

## Asynchronous Workflow-Run Operation handler

Use `@nexus.workflow_run_operation` to expose a Workflow as a long-running
Nexus Operation. The method takes a
`ctx: nexus.WorkflowRunOperationContext` plus the typed `input`, and returns
`nexus.WorkflowHandle[Output]`. Inside, call `ctx.start_workflow(...)` to
start the backing Workflow.

```python
import uuid
import nexusrpc
from temporalio import nexus

@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexus.workflow_run_operation
    async def my_workflow_run_operation(
        self, ctx: nexus.WorkflowRunOperationContext, input: MyInput
    ) -> nexus.WorkflowHandle[MyOutput]:
        return await ctx.start_workflow(
            WorkflowStartedByNexusOperation.run,
            input,
            id=str(uuid.uuid4()),
        )
```

Workflow IDs should be **business-meaningful** and are used to dedupe Workflow
starts. In general, pass the desired ID via the Operation input as part of
the Service contract.

To attach multiple Nexus callers to the same handler Workflow, use a Conflict
Policy of Use-Existing (see `references/core/nexus.md`).

### Map one Operation input to multiple Workflow arguments

When the backing Workflow takes multiple positional arguments, pass them via
the `args=[...]` keyword to `ctx.start_workflow`.

```python
@nexus.workflow_run_operation
async def hello(
    self, ctx: nexus.WorkflowRunOperationContext, input: HelloInput
) -> nexus.WorkflowHandle[HelloOutput]:
    return await ctx.start_workflow(
        HelloHandlerWorkflow.run,
        args=[input.name, input.language],
        id=f"hello-multi-args-{input.name}-{input.language}",
    )
```

## Registering the Service handler with a Worker

Pass instances of your handler class via `nexus_service_handlers=[...]` when
constructing the `Worker`. The Worker still needs its normal `workflows=` and
`task_queue=` arguments for any Workflows the handler starts locally.

```python
async def main():
    client = await Client.connect("localhost:7233", namespace=NAMESPACE)
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[WorkflowStartedByNexusOperation],
        nexus_service_handlers=[MyNexusServiceHandler()],
    )
    await worker.run()
```

You can pass any arguments you need through the handler's `__init__` method.

## Caller Workflow

Inside a Workflow on the caller side, build a Nexus client with
`workflow.create_nexus_client(service=..., endpoint=...)`. Import the Service
module under `workflow.unsafe.imports_passed_through()` so the sandbox lets
the contract types through.

```python
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from hello_nexus.service import MyInput, MyNexusService, MyOutput

@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str) -> tuple[MyOutput, MyOutput]:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint=NEXUS_ENDPOINT,
        )
        # Start + wait in one call.
        wf_result = await nexus_client.execute_operation(
            MyNexusService.my_workflow_run_operation, MyInput(name),
        )
        # Or: start, keep the handle (useful for cancel), then await it.
        sync_handle = await nexus_client.start_operation(
            MyNexusService.my_sync_operation, MyInput(name),
        )
        sync_result = await sync_handle
        return sync_result, wf_result
```

The caller Workflow is registered and started exactly like any other
Workflow — `client.start_workflow()` or `client.execute_workflow()`.

## Exceptions

Three Python exception classes matter for Nexus:

- **`nexusrpc.OperationError`** — raise inside a handler to signal an
  application-level failure that should **not** be retried.
- **`nexusrpc.HandlerError`** — raise with a specific
  `nexusrpc.HandlerErrorType`. The error is marked retryable or non-retryable
  according to the type, per the Nexus spec.
- **`temporalio.exceptions.NexusOperationError`** — raised inside the caller
  Workflow when a Nexus operation fails for any reason. Walk the cause chain
  via `__cause__` to find the underlying failure.

Handler-error types:

| Retryable           | Non-retryable     |
| ------------------- | ----------------- |
| `RESOURCE_EXHAUSTED`| `BAD_REQUEST`     |
| `INTERNAL`          | `UNAUTHENTICATED` |
| `UNAVAILABLE`       | `UNAUTHORIZED`    |
| `UPSTREAM_TIMEOUT`  | `NOT_FOUND`       |
|                     | `NOT_IMPLEMENTED` |

```python
import nexusrpc

raise nexusrpc.HandlerError(
    "downstream returned 503",
    type=nexusrpc.HandlerErrorType.UNAVAILABLE,
)
```

## Cancellation

Call `handle.cancel()` on the operation handle returned by
`start_operation(...)` to cancel a running Nexus Operation. Only **async**
operations can be canceled — cancellation is delivered via the operation
token. The handler Workflow or other backing resource may choose to ignore
the request, in which case the operation can still reach a terminal state.

Cancellation types, passed as `cancellation_type` to `start_operation` or
`execute_operation`:

- `ABANDON` — do not request cancellation of the operation.
- `TRY_CANCEL` — initiate a cancellation request and immediately report
  cancellation to the caller. Delivery is not guaranteed if the caller exits
  first.
- `WAIT_REQUESTED` — request cancellation and wait for confirmation that the
  request was received. Does not wait for actual cancellation.
- `WAIT_COMPLETED` — wait for operation completion. The operation may or may
  not complete as canceled. **Default.**

Once the caller Workflow completes, the caller's Nexus Machinery makes no
further attempts to cancel operations that are still running. To guarantee
delivery, `await` all pending operation handles before the caller Workflow
exits.

## Quick recipe: wrap an existing Workflow

End-to-end flow against a local dev server:

1. `temporal server start-dev` to launch the dev server with Nexus enabled.
2. Create caller and handler Namespaces with
   `temporal operator namespace create --namespace ...`.
3. Create the Endpoint with
   `temporal operator nexus endpoint create --name ... --target-namespace ... --target-task-queue ...`.
4. Define the contract (`@nexusrpc.service`), implement the handler
   (`@nexusrpc.handler.service_handler` + `@nexus.workflow_run_operation`),
   and run a Worker registered with `nexus_service_handlers=[...]`.
5. In the caller Namespace, run a Worker for the caller Workflow and start it
   with `client.start_workflow()`.

The full feature guide walks through each step; this file just names the
Python tokens involved.

## Cross-Namespace in Temporal Cloud

Use `tcld` to create the Endpoint and build the caller allowlist:

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --allow-namespace <my-caller-namespace.account> \
  --description-file path/to/description.md
```

Each `--allow-namespace` flag adds one caller Namespace to the Endpoint's
Runtime Access Control allowlist. Creating the Endpoint requires a Developer
account role or higher plus NamespaceAdmin permission on
`--target-namespace`.
