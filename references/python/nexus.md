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
    language: str


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

The following snippets show alternative implementations of the synchronous method. Include one in a complete service handler alongside `my_workflow_run_operation`, as shown below.

```python
import nexusrpc


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
import nexusrpc
from temporalio import nexus
from temporalio.common import WorkflowIDConflictPolicy, WorkflowIDReusePolicy


@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexusrpc.handler.sync_operation
    async def my_sync_operation(
        self, ctx: nexusrpc.handler.StartOperationContext, input: MyInput
    ) -> MyOutput:
        return MyOutput(message=f"Hello {input.name} from sync operation!")

    @nexus.workflow_run_operation
    async def my_workflow_run_operation(
        self, ctx: nexus.WorkflowRunOperationContext, input: MyInput
    ) -> nexus.WorkflowHandle[MyOutput]:
        return await ctx.start_workflow(
            WorkflowStartedByNexusOperation.run,
            input,
            id=f"my-workflow-{ctx.request_id}",
            id_conflict_policy=WorkflowIDConflictPolicy.USE_EXISTING,
            id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
        )
```

**Note:** `ctx.request_id` stays the same when Nexus retries a start request, so this ID targets the same backing Workflow on every attempt. `USE_EXISTING` attaches to an already-running execution; `REJECT_DUPLICATE` prevents starting a new execution with a completed ID within the Namespace's retention period. To deduplicate separate Nexus calls for the same business work, carry a business identifier in the service contract and derive the Workflow ID from it. Generate a fresh ID only for distinct work, rather than on every handler attempt.

### Mapping Multiple Workflow Arguments

When `WorkflowStartedByNexusOperation.run` accepts `name` and `language` as separate arguments instead of a single `MyInput`, use this alternative handler. It implements the same two operations declared by `MyNexusService`:

```python
@nexusrpc.handler.service_handler(service=MyNexusService)
class MyNexusServiceHandler:
    @nexusrpc.handler.sync_operation
    async def my_sync_operation(
        self, ctx: nexusrpc.handler.StartOperationContext, input: MyInput
    ) -> MyOutput:
        return MyOutput(message=f"Hello {input.name} from sync operation!")

    @nexus.workflow_run_operation
    async def my_workflow_run_operation(
        self, ctx: nexus.WorkflowRunOperationContext, input: MyInput
    ) -> nexus.WorkflowHandle[MyOutput]:
        return await ctx.start_workflow(
            WorkflowStartedByNexusOperation.run,
            args=[input.name, input.language],
            id=f"my-workflow-{ctx.request_id}",
            id_conflict_policy=WorkflowIDConflictPolicy.USE_EXISTING,
            id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
        )
```

## Worker Registration

Register Nexus service handlers on the handler worker using `nexus_service_handlers`. The caller worker only needs the caller workflow registered normally.

### Handler

The handler team runs this Worker in the target Namespace. Register both operation methods shown above on `MyNexusServiceHandler`.

```python
from temporalio.client import Client
from temporalio.worker import Worker


async def run_handler_worker():
    client = await Client.connect("localhost:7233", namespace="my-target-namespace")
    worker = Worker(
        client,
        task_queue="my-handler-task-queue",
        workflows=[WorkflowStartedByNexusOperation],
        nexus_service_handlers=[MyNexusServiceHandler()],
    )
    await worker.run()
```

Keeping the handler and backing Workflow on this Worker is a convenient default because `ctx.start_workflow()` uses the handler's Task Queue when `task_queue` is omitted. For separate deployments, set `task_queue` explicitly when starting the Workflow and register its definition on a Worker polling that queue in the handler Namespace.

### Caller

The caller team runs its own Worker in the caller Namespace.

```python
from temporalio.client import Client
from temporalio.worker import Worker


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

Both patterns work with synchronous and asynchronous operations. This example waits directly for the synchronous result and obtains a handle for the longer-running Workflow operation.

```python
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from my_app.service import MyInput, MyNexusService, MyOutput


@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str, language: str) -> tuple[MyOutput, MyOutput]:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )

        # Execute the synchronous operation and wait for its result
        sync_result = await nexus_client.execute_operation(
            MyNexusService.my_sync_operation,
            MyInput(name, language),
        )

        # Or start the asynchronous operation and await its handle separately
        workflow_handle = await nexus_client.start_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name, language),
        )
        wf_result = await workflow_handle

        return sync_result, wf_result
```

## Error Handling

Nexus introduces three exception types. Handlers raise `nexusrpc.OperationError` for terminal operation outcomes or `nexusrpc.HandlerError` for request-processing failures. The Nexus Machinery retries retryable handler failures until the operation's Schedule-to-Close timeout; a caller Workflow receives `NexusOperationError` when the operation ultimately fails. Inspect its cause to distinguish business failures from infrastructure failures. See also the [Python error handling guide](error-handling.md).

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
    async def run(self, name: str, language: str) -> str:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )
        try:
            result = await nexus_client.execute_operation(
                MyNexusService.my_workflow_run_operation,
                MyInput(name, language),
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

After requesting cancellation, await the operation handle so the caller stays alive while the default `WAIT_COMPLETED` behavior waits for the operation to finish. Handle a confirmed cancellation and re-raise other operation failures. An operation can also finish normally if completion races with cancellation.

```python
from temporalio import workflow
from temporalio.exceptions import CancelledError, NexusOperationError


@workflow.defn
class CallerWorkflow:
    @workflow.run
    async def run(self, name: str, language: str) -> str:
        nexus_client = workflow.create_nexus_client(
            service=MyNexusService,
            endpoint="my-nexus-endpoint-name",
        )

        # Start an async operation
        operation_handle = await nexus_client.start_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name, language),
        )

        # Request cancellation and wait for the operation to finish
        operation_handle.cancel()
        try:
            result = await operation_handle
            return result.message
        except NexusOperationError as e:
            if isinstance(e.cause, CancelledError):
                return "Operation canceled"
            raise
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
    MyInput(name, language),
    cancellation_type=NexusOperationCancellationType.TRY_CANCEL,
)
```

## Best Practices

1. Keep service contracts in a shared module importable by both caller and handler code
2. Derive Workflow IDs from `ctx.request_id` for retry safety, or from a business identifier to deduplicate separate calls for the same work; choose explicit conflict and reuse policies
3. Use sync operations only for work that completes within 10 seconds; use workflow run operations for anything longer
4. Start with service handlers and backing Workflows on the same Worker so the default Task Queue has the Workflow registered; set `task_queue` explicitly and register the Workflow on a separate Worker when deploying them independently
5. Use `execute_operation` when you just need the result; use `start_operation` when you need to cancel or manage the operation handle
6. Deploy independently owned handlers in separate Namespaces with their own Workers, and scale or roll out each handler independently of callers
