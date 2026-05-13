# Temporal Nexus — Python SDK

Temporal Python SDK support for Nexus is Generally Available <!-- docs/develop/python/nexus/feature-guide.mdx:20-24 -->. This file documents Python-SDK-specific surface; for the cross-SDK conceptual reference (Endpoints, Registry, lifecycle, timeouts, observability events), see `references/core/nexus.md`. Minimum dependencies per the feature guide: Temporal CLI `v1.3.0` or higher and Temporal Python SDK `v1.14.1` or higher <!-- docs/develop/python/nexus/feature-guide.mdx:52-53 -->.

## Imports

Nexus surface is split across three packages — `nexusrpc` (the language-agnostic protocol bindings), `temporalio.nexus` (Temporal's integration with `nexusrpc`), and `temporalio.workflow` for the caller-side client.

- `nexusrpc` — `nexusrpc.service` decorator, `nexusrpc.Operation[Input, Output]` field type, `nexusrpc.OperationError`, `nexusrpc.HandlerError`, `nexusrpc.HandlerErrorType` <!-- docs/develop/python/nexus/feature-guide.mdx:119-123; docs/develop/python/nexus/feature-guide.mdx:334-336 -->.
- `nexusrpc.handler` — `nexusrpc.handler.service_handler` (class decorator), `nexusrpc.handler.sync_operation` (method decorator), `nexusrpc.handler.StartOperationContext` (context arg) <!-- docs/develop/python/nexus/feature-guide.mdx:146-153 -->.
- `temporalio.nexus` (imported as `from temporalio import nexus`) — `nexus.workflow_run_operation` decorator, `nexus.WorkflowRunOperationContext`, `nexus.WorkflowHandle[T]`, `nexus.client()`, `nexus.info()` <!-- docs/develop/python/nexus/feature-guide.mdx:173-194; docs/develop/python/nexus/feature-guide.mdx:204-218 -->.
- `temporalio.workflow` — `workflow.create_nexus_client(service=..., endpoint=...)` for invoking Operations from a Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:300-303 -->.
- `temporalio.exceptions` — `NexusOperationError` for failures surfaced inside the caller Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:336 -->.
- `temporalio.worker.Worker` — accepts a `nexus_service_handlers=[...]` constructor argument listing service handler instances to register <!-- docs/develop/python/nexus/feature-guide.mdx:275-280 -->.

## Defining the Service contract

Use Python dataclasses for input/output and a `@nexusrpc.service`-decorated class whose attributes are typed `nexusrpc.Operation[Input, Output]`. The class declares the contract; it has no implementation <!-- docs/develop/python/nexus/feature-guide.mdx:103-123 -->.

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

## Synchronous Operation handlers

Decorate a class with `@nexusrpc.handler.service_handler(service=MyNexusService)` and decorate each sync operation method with `@nexusrpc.handler.sync_operation`. The method signature is `async def my_op(self, ctx: nexusrpc.handler.StartOperationContext, input: MyInput) -> MyOutput` <!-- docs/develop/python/nexus/feature-guide.mdx:139-153 -->.

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

A synchronous operation handler must return quickly (less than `10s`) <!-- docs/develop/python/nexus/feature-guide.mdx:156 -->.

Inside a sync handler, use `nexus.client()` to access the Temporal Client that the Worker was initialized with — for example, to Signal, Query, or Update a Workflow, or to do Signal-With-Start or Update-With-Start <!-- docs/develop/python/nexus/feature-guide.mdx:161-189 -->. Use `nexus.info()` to access information about the currently-executing Nexus Operation including its Task Queue <!-- docs/develop/python/nexus/feature-guide.mdx:194 -->.

```python
from temporalio import nexus

@nexusrpc.handler.service_handler(service=NexusGreetingService)
class NexusGreetingServiceHandler:

    def _get_workflow_handle(
        self, user_id: str
    ) -> WorkflowHandle[GreetingWorkflow, str]:
        return nexus.client().get_workflow_handle_for(
            GreetingWorkflow.run, get_workflow_id(user_id)
        )
```

## Asynchronous Operation handlers (Workflow-Run Operations)

Use `@nexus.workflow_run_operation` on a method of a `@nexusrpc.handler.service_handler`-decorated class to expose a Workflow as an asynchronous Operation. The method signature is `async def my_op(self, ctx: nexus.WorkflowRunOperationContext, input: MyInput) -> nexus.WorkflowHandle[MyOutput]`, and the body returns `await ctx.start_workflow(...)` <!-- docs/develop/python/nexus/feature-guide.mdx:199-218 -->.

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

Workflow IDs should typically be business-meaningful and are used to dedupe Workflow starts; in general, pass the ID through the Operation input as part of the Nexus Service contract <!-- docs/develop/python/nexus/feature-guide.mdx:220 -->.

## Multi-argument Workflows

A Nexus Operation can only take one input parameter. To start a Workflow that takes multiple arguments, unpack the single input object into `ctx.start_workflow(..., args=[...])` <!-- docs/develop/python/nexus/feature-guide.mdx:228-261 -->.

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

## Registering the Service handler on a Worker

Pass instances of your service handler classes in the `nexus_service_handlers` list when constructing the `Worker`. You can pass any arguments you need to your service handler's `__init__` method <!-- docs/develop/python/nexus/feature-guide.mdx:265-282 -->.

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

## Calling Nexus Operations from a Workflow

Inside a Workflow, create a Nexus client bound to a service contract and an endpoint with `workflow.create_nexus_client(service=..., endpoint=...)` <!-- docs/develop/python/nexus/feature-guide.mdx:300-303 -->. Two call forms are available:

- `await nexus_client.execute_operation(...)` — start the Nexus operation and wait for the result in one go <!-- docs/develop/python/nexus/feature-guide.mdx:304-308 -->.
- `await nexus_client.start_operation(...)` — obtain an operation handle and then `await` it for the result; this is what you need when you want the handle (for example, to cancel) <!-- docs/develop/python/nexus/feature-guide.mdx:309-315 -->.

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
        # Fire-and-wait.
        wf_result = await nexus_client.execute_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name),
        )
        # Or obtain the handle, then await it.
        sync_operation_handle = await nexus_client.start_operation(
            MyNexusService.my_sync_operation,
            MyInput(name),
        )
        sync_result = await sync_operation_handle
        return sync_result, wf_result
```

## Exceptions in Nexus Operations

Three Nexus-specific exception classes <!-- docs/develop/python/nexus/feature-guide.mdx:329-336 -->:

- **`nexusrpc.OperationError`** — raise inside a Nexus Operation to mark it failed by application logic; the failure is not retried <!-- docs/develop/python/nexus/feature-guide.mdx:334 -->.
- **`nexusrpc.HandlerError`** — raise inside a Nexus Operation with a specific `nexusrpc.HandlerErrorType`. The error is marked retryable or non-retryable per the type, following the Nexus spec. Non-retryable types: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`. Retryable types: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT` <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->.
- **`temporalio.exceptions.NexusOperationError`** — raised inside a Workflow when a Nexus operation fails for any reason. Use the `__cause__` attribute on the exception to access the cause chain <!-- docs/develop/python/nexus/feature-guide.mdx:336 -->.

## Cancelling a Nexus Operation

Call `handle.cancel()` on an operation handle to cancel from within a Workflow. Only asynchronous operations can be canceled, since cancellation is sent using an operation token; the Workflow or other resources backing the operation may choose to ignore the cancellation request, and if ignored, the operation may enter a terminal state <!-- docs/develop/python/nexus/feature-guide.mdx:340-342 -->.

When starting an operation, the caller can specify a `cancellation_type` that controls how the caller reacts to cancellation <!-- docs/develop/python/nexus/feature-guide.mdx:344-351 -->:

- `ABANDON` — Do not request cancellation of the operation.
- `TRY_CANCEL` — Initiate a cancellation request and immediately report cancellation to the caller. Note that this type doesn't guarantee that cancellation is delivered to the operation handler if the caller exits before the delivery is done.
- `WAIT_REQUESTED` — Request cancellation of the operation and wait for confirmation that the request was received. Doesn't wait for actual cancellation.
- `WAIT_COMPLETED` — Wait for operation completion. Operation may or may not complete as cancelled.

The default is `WAIT_COMPLETED` <!-- docs/develop/python/nexus/feature-guide.mdx:351 -->. Set a different value via the `cancellation_type` argument when starting or executing an operation <!-- docs/develop/python/nexus/feature-guide.mdx:351 -->.

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations that are still running; to ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:353-355 -->.

## Worker development against a local server

Start a local dev server, create caller/target Namespaces, and create a Nexus Endpoint that routes from caller to handler <!-- docs/develop/python/nexus/feature-guide.mdx:57-86 -->:

```
temporal server start-dev

temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace

temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

## See also

- `references/core/nexus.md` — cross-SDK concepts: Endpoints, Registry, lifecycle, timeouts, observability events.
- `samples-python` Nexus sample: `https://github.com/temporalio/samples-python/tree/main/hello_nexus` <!-- docs/develop/python/nexus/feature-guide.mdx:44 -->.
