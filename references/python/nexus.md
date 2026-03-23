# Python SDK Nexus

## Overview

Temporal Nexus connects Temporal Applications across Namespace boundaries through well-defined service contracts, with built-in retries, circuit breaking, and load balancing. Operations can be synchronous (low-latency, <10s) or asynchronous (long-running, backed by workflows).

## Service Contract

Define a shared service contract using dataclasses for input/output and `@nexusrpc.service`. This contract is imported by both caller and handler code.

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

## Synchronous Operation Handler

Use `@nexusrpc.handler.sync_operation` for operations that return within 10 seconds.

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

Sync handlers can use `nexus.client()` to get the Temporal client for executing Signals, Updates, or Queries against existing workflows, and `nexus.info()` to access operation metadata.

```python
import nexusrpc
from temporalio import nexus


@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexusrpc.handler.sync_operation
    async def my_sync_operation(
        self, ctx: nexusrpc.handler.StartOperationContext, input: MyInput
    ) -> MyOutput:
        client = nexus.client()
        # Use the client to query or signal an existing workflow
        handle = client.get_workflow_handle(input.name)
        result = await handle.query(MyWorkflow.get_status)
        return MyOutput(message=f"Status: {result}")
```

## Asynchronous Operation Handler (Workflow Run)

Use `@nexus.workflow_run_operation` to expose a workflow as a Nexus operation. The operation starts the workflow and Nexus tracks it to completion.

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

**Note:** In production, prefer deterministic workflow IDs derived from business data for deduplication safety. `uuid.uuid4()` is shown for simplicity.

### Mapping Multiple Workflow Arguments

When the underlying workflow takes multiple arguments, map from a single Nexus input:

```python
@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexus.workflow_run_operation
    async def hello(
        self, ctx: nexus.WorkflowRunOperationContext, input: HelloInput
    ) -> nexus.WorkflowHandle[HelloOutput]:
        return await ctx.start_workflow(
            HelloHandlerWorkflow.run,
            args=[input.name, input.language],
            id=str(uuid.uuid4()),
        )
```

## Worker Registration

Register Nexus service handlers on the handler worker using `nexus_service_handlers`. The caller worker only needs the caller workflow registered normally.

```python
from temporalio.client import Client
from temporalio.worker import Worker


# Handler worker - runs in the target namespace
async def run_handler_worker():
    client = await Client.connect("localhost:7233", namespace="my-target-namespace")
    worker = Worker(
        client,
        task_queue="my-handler-task-queue",
        workflows=[WorkflowStartedByNexusOperation],
        nexus_service_handlers=[MyNexusServiceHandler()],
    )
    await worker.run()


# Caller worker - runs in the caller namespace
async def run_caller_worker():
    client = await Client.connect("localhost:7233", namespace="my-caller-namespace")
    worker = Worker(
        client,
        task_queue="my-caller-task-queue",
        workflows=[CallerWorkflow],
    )
    await worker.run()
```

## Calling Nexus Operations from a Workflow

Use `workflow.create_nexus_client()` to call operations. Two patterns: `execute_operation` (start and wait) and `start_operation` (start, get handle, await later).

```python
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from my_app.service import MyInput, MyNexusService, MyOutput


@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str) -> tuple[MyOutput, MyOutput]:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )

        # Execute and wait for result in one call
        wf_result = await nexus_client.execute_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name),
        )

        # Or start and handle separately
        sync_handle = await nexus_client.start_operation(
            MyNexusService.my_sync_operation,
            MyInput(name),
        )
        sync_result = await sync_handle

        return sync_result, wf_result
```

## Error Handling

Nexus introduces three exception types. See also `references/python/error-handling.md`.

### In Operation Handlers

```python
import nexusrpc

# OperationError - the operation itself failed (non-retryable by default)
raise nexusrpc.OperationError(
    "Order not found",
    state=nexusrpc.OperationErrorState.FAILED,
)

# HandlerError - handler-level error with explicit retryability
raise nexusrpc.HandlerError(
    "Service temporarily unavailable",
    type=nexusrpc.HandlerErrorType.INTERNAL,
    retryable_override=True,
)
```

### In Caller Workflows

```python
from temporalio import workflow
from temporalio.exceptions import NexusOperationError


@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str) -> str:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )
        try:
            result = await nexus_client.execute_operation(
                MyNexusService.my_workflow_run_operation,
                MyInput(name),
            )
            return result.message
        except NexusOperationError as e:
            workflow.logger.error(f"Nexus operation failed: {e}")
            # Access the underlying cause
            if e.__cause__:
                workflow.logger.error(f"Caused by: {e.__cause__}")
            raise
```

## Cancellation

```python
@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str) -> str:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )

        # Start an async operation
        operation_handle = await nexus_client.start_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name),
        )

        # Cancel the operation
        operation_handle.cancel()
```

### Cancellation Types

Control cancellation behavior via `cancellation_type`:

- **`WAIT_COMPLETED`** (default) - Wait for the operation to fully complete after cancellation
- **`WAIT_REQUESTED`** - Wait for cancellation to be acknowledged by the handler
- **`TRY_CANCEL`** - Request cancellation and immediately report as cancelled
- **`ABANDON`** - Do not send a cancellation request

```python
from temporalio.workflow import NexusOperationCancellationType

result = await nexus_client.execute_operation(
    MyNexusService.my_workflow_run_operation,
    MyInput(name),
    cancellation_type=NexusOperationCancellationType.TRY_CANCEL,
)
```

## Best Practices

1. Keep service contracts in a shared module importable by both caller and handler code
2. Use business-meaningful workflow IDs in workflow run operations for deduplication safety
3. Use sync operations only for work that completes within 10 seconds; use workflow run operations for anything longer
4. Register Nexus service handlers and their backing workflows on the same worker
5. Use `execute_operation` when you just need the result; use `start_operation` when you need to cancel or manage the operation handle
6. For multi-level Nexus calls (Workflow A → Nexus → Workflow B → Nexus → Workflow C), each hop adds its own retry and fault isolation
