# Nexus — Python SDK

Temporal Python SDK support for Nexus is Generally Available <!-- docs/develop/python/nexus/feature-guide.mdx:22 -->. Nexus connects Temporal Applications within and across Namespaces using a Nexus Endpoint, a Nexus Service contract, and Nexus Operations <!-- docs/develop/python/nexus/feature-guide.mdx:26 -->. For cross-SDK concepts (lifecycle, timeouts, retries, circuit breaking, Endpoints, Registry), see `references/core/nexus.md`.

## Prerequisites

- Temporal CLI `v1.3.0` or higher recommended <!-- docs/develop/python/nexus/feature-guide.mdx:52 -->.
- Temporal Python SDK `v1.14.1` or higher <!-- docs/develop/python/nexus/feature-guide.mdx:53 -->.

Start the dev server with `temporal server start-dev` <!-- docs/develop/python/nexus/feature-guide.mdx:58 -->.

## Define the Service contract

A Nexus Service contract declares Service and Operation names along with input/output types so caller Workflows can use the Nexus Endpoint <!-- docs/develop/python/nexus/feature-guide.mdx:94 -->. The contract typically lives in a shared package imported by both caller and handler.

The `@nexusrpc.service` decorator declares a service with typed operations <!-- docs/develop/python/nexus/feature-guide.mdx:119 --> <!-- docs/develop/python/nexus/quickstart.mdx:78-80 -->. Operations are declared as class attributes of type `nexusrpc.Operation[InputType, OutputType]` <!-- docs/develop/python/nexus/feature-guide.mdx:121 -->.

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

A Nexus Operation can only take one input parameter <!-- docs/develop/python/nexus/feature-guide.mdx:230 -->. To start a Workflow whose `run` method takes multiple arguments, pass `args=[...]` to `ctx.start_workflow` from the handler (see below).

The default Data Converter encodes payloads in the order Null, Byte array, Protobuf JSON, JSON; the samples use Python dataclasses serialized as JSON <!-- docs/develop/python/nexus/feature-guide.mdx:96-99 -->.

## Synchronous Operation handler

The `@nexusrpc.handler.sync_operation` decorator exposes simple RPC handlers <!-- docs/develop/python/nexus/feature-guide.mdx:134 --> <!-- docs/develop/python/nexus/feature-guide.mdx:139 -->. The service handler class is annotated with `@nexusrpc.handler.service_handler(service=MyNexusService)` <!-- docs/develop/python/nexus/feature-guide.mdx:146 -->. The handler method receives a `nexusrpc.handler.StartOperationContext` plus the input <!-- docs/develop/python/nexus/feature-guide.mdx:150 -->.

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

A synchronous operation handler must return quickly (less than `10s`) <!-- docs/develop/python/nexus/feature-guide.mdx:156 -->. Handlers should be reliable to avoid tripping the circuit breaker, which trips after 5 consecutive retryable errors and blocks all Operations from the caller to that Endpoint <!-- docs/develop/python/nexus/feature-guide.mdx:130 --> <!-- docs/develop/python/nexus/feature-guide.mdx:157 -->.

### Using the Temporal Client (Signal, Query, Update)

A common pattern is to use the Temporal Client from within a sync handler to Signal, Query, or Update a Workflow; Signal-With-Start or Update-With-Start ensure the Workflow is started <!-- docs/develop/python/nexus/feature-guide.mdx:161-162 -->. All calls must complete within the Nexus request timeout <!-- docs/develop/python/nexus/feature-guide.mdx:163 -->.

`nexus.client()` returns the Client the Worker was initialized with <!-- docs/develop/python/nexus/feature-guide.mdx:167 -->. `nexus.info()` provides information about the currently-executing Nexus Operation, including its Task Queue <!-- docs/develop/python/nexus/feature-guide.mdx:194 -->.

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

The `nexus_messaging` sample shows both a caller pattern (send messages to an existing Workflow) and an on-demand pattern (start a Workflow through Nexus then Signal it) <!-- docs/develop/python/nexus/feature-guide.mdx:191-192 -->.

## Asynchronous Operation handler (start a Workflow)

The `@nexus.workflow_run_operation` decorator (from `temporalio` import `nexus`) is the easiest way to expose a Workflow as an Operation <!-- docs/develop/python/nexus/feature-guide.mdx:135 --> <!-- docs/develop/python/nexus/feature-guide.mdx:199 -->. The handler receives a `nexus.WorkflowRunOperationContext` and returns a `nexus.WorkflowHandle[OutputType]` produced by `ctx.start_workflow(...)` <!-- docs/develop/python/nexus/feature-guide.mdx:211-217 -->.

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

Workflow IDs should be business-meaningful and are typically passed in the Operation input as part of the Service contract <!-- docs/develop/python/nexus/feature-guide.mdx:220 -->.

### Multiple Workflow arguments

To bridge a single Nexus input to a Workflow that takes multiple positional arguments, pass `args=[...]` to `ctx.start_workflow` <!-- docs/develop/python/nexus/feature-guide.mdx:230 --> <!-- docs/develop/python/nexus/feature-guide.mdx:251-258 -->:

```python
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

## Register the Service handler in a Worker

Pass instances of your service handlers to `Worker(...)` via `nexus_service_handlers=[...]` <!-- docs/develop/python/nexus/feature-guide.mdx:279 --> <!-- docs/develop/python/nexus/quickstart.mdx:147 -->. You can pass any arguments you need to the handler's `__init__` <!-- docs/develop/python/nexus/feature-guide.mdx:268 -->.

```python
from temporalio.client import Client
from temporalio.worker import Worker

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

## Call a Nexus Operation from a caller Workflow

Import the Service definition and input/output types under `workflow.unsafe.imports_passed_through()` <!-- docs/develop/python/nexus/feature-guide.mdx:293 -->. Inside the Workflow, build a client with `workflow.create_nexus_client(service=..., endpoint=...)` <!-- docs/develop/python/nexus/feature-guide.mdx:300 -->.

Two call styles:

- `nexus_client.execute_operation(...)` — start and await the result in one call <!-- docs/develop/python/nexus/feature-guide.mdx:305 -->.
- `nexus_client.start_operation(...)` — obtain an operation handle that you `await` later for the result <!-- docs/develop/python/nexus/feature-guide.mdx:311-315 -->.

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
        wf_result = await nexus_client.execute_operation(
            MyNexusService.my_workflow_run_operation,
            MyInput(name),
        )
        sync_operation_handle = await nexus_client.start_operation(
            MyNexusService.my_sync_operation,
            MyInput(name),
        )
        sync_result = await sync_operation_handle
        return sync_result, wf_result
```

The quickstart additionally shows passing a Workflow-side timeout such as `schedule_to_close_timeout=timedelta(seconds=10)` to `execute_operation` <!-- docs/develop/python/nexus/quickstart.mdx:193 -->.

Register the caller Workflow with a Worker and start it via `client.start_workflow()` or `client.execute_workflow()` — the same as any normal Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:323-325 -->.

## Exceptions

Three Nexus-specific exception classes are available in Python <!-- docs/develop/python/nexus/feature-guide.mdx:332 -->:

- `nexusrpc.OperationError` — raise inside a Nexus operation to indicate it has failed according to its own application logic and should not be retried <!-- docs/develop/python/nexus/feature-guide.mdx:334 -->.
- `nexusrpc.HandlerError` — raise with a specific `HandlerErrorType`. The error is marked retryable or non-retryable per the Nexus spec <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->.
- `temporalio.exceptions.NexusOperationError` — raised inside a Workflow when a Nexus operation fails for any reason. Use the `__cause__` attribute to walk the cause chain <!-- docs/develop/python/nexus/feature-guide.mdx:336 -->.

`HandlerErrorType` values from `nexusrpc.HandlerErrorType` <!-- docs/develop/python/nexus/feature-guide.mdx:335 -->:

- Non-retryable: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`.
- Retryable: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`.

See `references/python/error-handling.md` for generic Workflow/Activity error semantics that also apply across Nexus operations.

## Cancelling an Operation

Call `handle.cancel()` on the operation handle from within the Workflow to request cancellation <!-- docs/develop/python/nexus/feature-guide.mdx:340 -->. Only asynchronous operations can be canceled, since cancellation is sent using an operation token <!-- docs/develop/python/nexus/feature-guide.mdx:340 -->. The Workflow or other resources backing the operation may choose to ignore the cancellation request; if ignored, the operation may enter a terminal state <!-- docs/develop/python/nexus/feature-guide.mdx:341-342 -->.

When starting or executing an operation, set `cancellation_type` to one of <!-- docs/develop/python/nexus/feature-guide.mdx:346-351 -->:

- `ABANDON` — Do not request cancellation of the operation.
- `TRY_CANCEL` — Initiate a cancellation request and immediately report cancellation to the caller. Cancellation may not actually be delivered if the caller exits before delivery completes.
- `WAIT_REQUESTED` — Request cancellation and wait for confirmation that the request was received. Does not wait for actual cancellation.
- `WAIT_COMPLETED` — Wait for operation completion. The operation may or may not complete as canceled.

The default is `WAIT_COMPLETED` <!-- docs/develop/python/nexus/feature-guide.mdx:351 -->.

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel still-running operations <!-- docs/develop/python/nexus/feature-guide.mdx:353 -->. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:355 -->. See the `nexus_cancel` sample <!-- docs/develop/python/nexus/feature-guide.mdx:357 -->.

## Creating the Endpoint

For a self-hosted dev server, create separate caller and target Namespaces and a Nexus Endpoint via the Temporal CLI <!-- docs/develop/python/nexus/feature-guide.mdx:70-86 -->:

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace

temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

For Temporal Cloud, use `tcld nexus endpoint create` with an `--allow-namespace` allowlist for caller Namespaces <!-- docs/develop/python/nexus/feature-guide.mdx:410-418 -->. See `references/core/nexus.md` for the full Endpoint, Registry, and Cloud (`tcld`) flow.

## Observability

Synchronous Nexus Operations appear in the caller's Workflow history with `NexusOperationScheduled` and `NexusOperationCompleted` events <!-- docs/develop/python/nexus/feature-guide.mdx:426 --> <!-- docs/develop/python/nexus/feature-guide.mdx:460-463 -->. `NexusOperationStarted` is not reported for synchronous operations <!-- docs/develop/python/nexus/feature-guide.mdx:467 -->.

Asynchronous Nexus Operations record `NexusOperationScheduled`, `NexusOperationStarted`, and `NexusOperationCompleted` in the caller's history <!-- docs/develop/python/nexus/feature-guide.mdx:433 --> <!-- docs/develop/python/nexus/feature-guide.mdx:456-458 -->.

CLI inspection:

```
temporal workflow describe -w <ID>   # pending Nexus Operations and attached callbacks
temporal workflow show -w <ID>       # full caller history including Nexus events
```

<!-- docs/develop/python/nexus/feature-guide.mdx:445 --> <!-- docs/develop/python/nexus/feature-guide.mdx:451 -->

## Samples

This documentation derives from the Python Nexus sample `samples-python/hello_nexus` <!-- docs/develop/python/nexus/feature-guide.mdx:44 -->. Related samples:

- `hello_nexus` — basic sync + async Operations <!-- docs/develop/python/nexus/feature-guide.mdx:44 -->.
- `nexus_messaging` — synchronous Operations sending Updates and Queries (caller pattern and on-demand pattern) <!-- docs/develop/python/nexus/feature-guide.mdx:165 --> <!-- docs/develop/python/nexus/feature-guide.mdx:191 -->.
- `nexus_multiple_args` — mapping a single Nexus input to a multi-arg Workflow <!-- docs/develop/python/nexus/feature-guide.mdx:233 -->.
- `nexus_cancel` — cancellation patterns <!-- docs/develop/python/nexus/feature-guide.mdx:357 -->.

## See also

- `references/core/nexus.md` — cross-SDK Nexus concepts, Endpoint/Registry, CLI/`tcld` reference, security, patterns, metrics.
- `references/python/error-handling.md` — generic Python error semantics that apply to Nexus operations.
- `references/python/observability.md` — Python logging, metrics, and tracing.
