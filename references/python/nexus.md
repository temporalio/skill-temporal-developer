# Temporal Nexus — Python SDK

> See `references/core/nexus.md` for cross-SDK concepts (lifecycle, retries, circuit breaker, timeouts, etc.). This file documents Python-specific identifiers only.

Support stage: Generally Available. <!-- docs/develop/python/nexus/feature-guide.mdx:22 -->

Recommended versions: Temporal CLI `v1.3.0` or higher <!-- docs/develop/python/nexus/feature-guide.mdx:52 -->, Python SDK `v1.14.1` or higher. <!-- docs/develop/python/nexus/feature-guide.mdx:53 -->

## Modules and identifiers

Two separate packages are involved:

- `nexusrpc` (separate package from `temporalio`):
  - `@nexusrpc.service` <!-- docs/develop/python/nexus/feature-guide.mdx:119 --> — decorator on the service contract class.
  - `nexusrpc.Operation[InputType, OutputType]` <!-- docs/develop/python/nexus/feature-guide.mdx:121 --> — type for each operation attribute on the contract class.
  - `nexusrpc.OperationError` <!-- docs/develop/python/nexus/feature-guide.mdx:334 --> — raise in a handler to fail without retry.
  - `nexusrpc.HandlerError` <!-- docs/develop/python/nexus/feature-guide.mdx:335 --> with `nexusrpc.HandlerErrorType` <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->.

- `nexusrpc.handler`:
  - `@nexusrpc.handler.service_handler(service=...)` <!-- docs/develop/python/nexus/feature-guide.mdx:146 --> — decorator on the handler implementation class.
  - `@nexusrpc.handler.sync_operation` <!-- docs/develop/python/nexus/feature-guide.mdx:148 --> — decorator for a synchronous operation method.
  - `nexusrpc.handler.StartOperationContext` <!-- docs/develop/python/nexus/feature-guide.mdx:150 --> — context passed to a sync operation.

- `temporalio.nexus`, imported as `from temporalio import nexus` <!-- docs/develop/python/nexus/feature-guide.mdx:173 -->:
  - `@nexus.workflow_run_operation` <!-- docs/develop/python/nexus/feature-guide.mdx:209 --> — decorator that exposes a Workflow as an async operation.
  - `nexus.WorkflowRunOperationContext` <!-- docs/develop/python/nexus/feature-guide.mdx:211 --> — context for workflow-run operations; provides `start_workflow`.
  - `nexus.WorkflowHandle[OutputType]` <!-- docs/develop/python/nexus/feature-guide.mdx:212 --> — return type of a workflow-run operation handler.
  - `nexus.client()` <!-- docs/develop/python/nexus/feature-guide.mdx:167 --> — access the Worker's Client from inside an operation handler.
  - `nexus.info()` <!-- docs/develop/python/nexus/feature-guide.mdx:194 --> — info about the currently-executing Nexus Operation including its Task Queue.

- `temporalio.exceptions.NexusOperationError` <!-- docs/develop/python/nexus/feature-guide.mdx:336 --> — raised inside a Workflow when a Nexus operation fails.

- `temporalio.workflow.create_nexus_client(service=..., endpoint=...)` <!-- docs/develop/python/nexus/feature-guide.mdx:300 --> — used inside a caller Workflow to obtain a client bound to a service and endpoint.

## Define the Nexus Service contract

A service contract names the service and its operations along with input/output types. <!-- docs/develop/python/nexus/feature-guide.mdx:90 -->

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
<!-- docs/develop/python/nexus/feature-guide.mdx:103-123 -->

## Develop operation handlers

The `nexusrpc.handler` and `temporalio.nexus` modules have utilities to help create Nexus Operations: <!-- docs/develop/python/nexus/feature-guide.mdx:132 -->

- `nexusrpc.handler.sync_operation` — create a synchronous operation handler. <!-- docs/develop/python/nexus/feature-guide.mdx:134 -->
- `nexus.workflow_run_operation` — create an asynchronous operation handler that starts a Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:135 -->

### Synchronous operation handler

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
<!-- docs/develop/python/nexus/feature-guide.mdx:143-153 -->

A synchronous operation handler must return quickly (less than `10s`). <!-- docs/develop/python/nexus/feature-guide.mdx:156 --> Handlers should be reliable to avoid tripping the circuit breaker. <!-- docs/develop/python/nexus/feature-guide.mdx:157 -->

### Use the Temporal Client from a sync handler

Use `nexus.client()` to get the Client the Worker was initialized with. <!-- docs/develop/python/nexus/feature-guide.mdx:167 --> A common pattern is to use it from inside a sync handler to Signal, Query, or Update a Workflow, or to Signal-With-Start or Update-With-Start. <!-- docs/develop/python/nexus/feature-guide.mdx:161-162 --> All calls must complete within the Nexus request timeout; Updates should be short-lived. <!-- docs/develop/python/nexus/feature-guide.mdx:163 -->

```python
from temporalio import nexus

def get_workflow_id(user_id: str) -> str:
    return f"{WORKFLOW_ID_PREFIX}{user_id}"

@nexusrpc.handler.service_handler(service=NexusGreetingService)
class NexusGreetingServiceHandler:

    def _get_workflow_handle(
        self, user_id: str
    ) -> WorkflowHandle[GreetingWorkflow, str]:
        return nexus.client().get_workflow_handle_for(
            GreetingWorkflow.run, get_workflow_id(user_id)
        )
```
<!-- docs/develop/python/nexus/feature-guide.mdx:172-188 -->

In addition to `nexus.client()`, use `nexus.info()` to access information about the currently-executing Nexus Operation including its Task Queue. <!-- docs/develop/python/nexus/feature-guide.mdx:194 -->

### Asynchronous workflow-run operation handler

Use the `@nexus.workflow_run_operation` decorator — the easiest way to expose a Workflow as an operation. <!-- docs/develop/python/nexus/feature-guide.mdx:199 -->

```python
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
<!-- docs/develop/python/nexus/feature-guide.mdx:203-218 -->

Workflow IDs should typically be business-meaningful and are used to dedupe Workflow starts. The ID should generally be passed in the Operation input as part of the Service contract. <!-- docs/develop/python/nexus/feature-guide.mdx:220 -->

### Map a Nexus Operation input to multiple Workflow arguments

A Nexus Operation can only take one input parameter. To start a Workflow that takes multiple arguments, use `ctx.start_workflow` with the `args=` keyword. <!-- docs/develop/python/nexus/feature-guide.mdx:230 -->

```python
@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexus.workflow_run_operation
    async def hello(
        self, ctx: nexus.WorkflowRunOperationContext, input: HelloInput
    ) -> nexus.WorkflowHandle[HelloOutput]:
        return await ctx.start_workflow(
            HelloHandlerWorkflow.run,
            args=[
                input.name,
                input.language,
            ],
            id=f"hello-multi-args-{input.name}-{input.language}",
        )
```
<!-- docs/develop/python/nexus/feature-guide.mdx:235-258 -->

## Register the service handler in a Worker

Pass instances of the handler class via `nexus_service_handlers=`. <!-- docs/develop/python/nexus/feature-guide.mdx:279 --> Arguments needed by the handler can be passed to its `__init__`. <!-- docs/develop/python/nexus/feature-guide.mdx:268 -->

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
<!-- docs/develop/python/nexus/feature-guide.mdx:273-281 -->

## Caller-side: invoke an operation from a Workflow

Import the service definition and input/output types under `workflow.unsafe.imports_passed_through()`. <!-- docs/develop/python/nexus/feature-guide.mdx:293-294 -->

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
        # Start and wait for the result in one go.
        wf_result = await nexus_client.execute_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name),
        )
        # Or obtain a handle and await it to get the result.
        sync_operation_handle = await nexus_client.start_operation(
            MyNexusService.my_sync_operation,
            MyInput(name),
        )
        sync_result = await sync_operation_handle
        return sync_result, wf_result
```
<!-- docs/develop/python/nexus/feature-guide.mdx:290-317 -->

Notes:

- `workflow.create_nexus_client(service=..., endpoint=...)` takes both as keyword arguments. <!-- docs/develop/python/nexus/feature-guide.mdx:300-303 -->
- `execute_operation` and `start_operation` take the operation REFERENCE (the attribute on the service class such as `MyNexusService.my_workflow_run_operation`), not a string. <!-- docs/develop/python/nexus/feature-guide.mdx:305-313 -->
- `start_operation` returns an awaitable handle; `await sync_operation_handle` returns the operation result. <!-- docs/develop/python/nexus/feature-guide.mdx:311-315 -->

### Register and start the caller Workflow

Register the caller Workflow with a Worker, then start it with `client.start_workflow()` or `client.execute_workflow()`. These steps are the same as for any normal Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:321-326 -->

## Exceptions in Nexus operations

There are three Nexus-specific exception classes in Python: <!-- docs/develop/python/nexus/feature-guide.mdx:332 -->

- `nexusrpc.OperationError` — raise inside a Nexus operation to indicate it has failed per its own application logic and should not be retried. <!-- docs/develop/python/nexus/feature-guide.mdx:334 -->
- `nexusrpc.HandlerError` with a specific `nexusrpc.HandlerErrorType`. The error is retryable or not according to the type, following the Nexus spec: <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->
  - Non-retryable types: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`. <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->
  - Retryable types: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`. <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->
- `temporalio.exceptions.NexusOperationError` — raised inside a Workflow when a Nexus operation fails for any reason. Use the `__cause__` attribute to walk the cause chain. <!-- docs/develop/python/nexus/feature-guide.mdx:336 -->

## Cancellation

Call `handle.cancel()` on the operation handle inside a Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:340 --> Only asynchronous operations can be canceled, since cancellation is sent using an operation token. <!-- docs/develop/python/nexus/feature-guide.mdx:340 --> The Workflow or other resources backing the operation may choose to ignore the cancellation request; if ignored, the operation may enter a terminal state. <!-- docs/develop/python/nexus/feature-guide.mdx:341-342 -->

Cancellation types — pass `cancellation_type=` when starting or executing an operation: <!-- docs/develop/python/nexus/feature-guide.mdx:351 -->

- `ABANDON` — do not request cancellation of the operation. <!-- docs/develop/python/nexus/feature-guide.mdx:346 -->
- `TRY_CANCEL` — initiate a cancellation request and immediately report cancellation to the caller. <!-- docs/develop/python/nexus/feature-guide.mdx:347 -->
- `WAIT_REQUESTED` — request cancellation and wait for confirmation the request was received. Doesn't wait for actual cancellation. <!-- docs/develop/python/nexus/feature-guide.mdx:348 -->
- `WAIT_COMPLETED` — wait for operation completion. May or may not complete as canceled. Default. <!-- docs/develop/python/nexus/feature-guide.mdx:349-351 -->

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations that are still running. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:353-355 -->

## CLI setup

Create a Nexus Endpoint that routes requests from caller to handler: <!-- docs/develop/python/nexus/feature-guide.mdx:77-79 -->

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```
<!-- docs/develop/python/nexus/feature-guide.mdx:82-86 -->

Create caller and handler Namespaces beforehand: <!-- docs/develop/python/nexus/feature-guide.mdx:67 -->

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```
<!-- docs/develop/python/nexus/feature-guide.mdx:70-71 -->

## Observability — events on the caller's Workflow history

- Synchronous Nexus Operations: `NexusOperationScheduled`, `NexusOperationCompleted`. <!-- docs/develop/python/nexus/feature-guide.mdx:462-463 --> `NexusOperationStarted` is not reported for synchronous operations. <!-- docs/develop/python/nexus/feature-guide.mdx:467 -->
- Asynchronous Nexus Operations: `NexusOperationScheduled`, `NexusOperationStarted`, `NexusOperationCompleted`. <!-- docs/develop/python/nexus/feature-guide.mdx:456-458 -->

Use `temporal workflow describe -w <ID>` to show pending Nexus Operations on the caller and any attached callbacks on the handler Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:442-446 --> Use `temporal workflow show -w <ID>` to view Nexus events in the caller's history. <!-- docs/develop/python/nexus/feature-guide.mdx:448-451 -->

## Samples

- `temporalio/samples-python/tree/main/hello_nexus` <!-- docs/develop/python/nexus/feature-guide.mdx:44 -->
- `nexus_messaging` (caller pattern and on-demand pattern for Signals/Queries/Updates via Nexus) <!-- docs/develop/python/nexus/feature-guide.mdx:165,191 -->
- `nexus_multiple_args` <!-- docs/develop/python/nexus/feature-guide.mdx:233 -->
- `nexus_cancel` <!-- docs/develop/python/nexus/feature-guide.mdx:357 -->
