# Python SDK Advanced Features

## Continue-as-New

Use continue-as-new to prevent unbounded history growth in long-running workflows.

```python
@workflow.defn
class BatchProcessingWorkflow:
    @workflow.run
    async def run(self, state: ProcessingState) -> str:
        while not state.is_complete:
            # Process next batch
            state = await workflow.execute_activity(
                process_batch, state,
                schedule_to_close_timeout=timedelta(minutes=5),
            )

            # Check history size and continue-as-new if needed
            if workflow.info().get_current_history_length() > 10000:
                workflow.continue_as_new(args=[state])

        return "completed"
```

### Continue-as-New with Different Arguments

```python
# Continue with modified state
workflow.continue_as_new(args=[new_state])

# Continue with memo and search attributes
workflow.continue_as_new(
    args=[new_state],
    memo={"last_processed": item_id},
    search_attributes=SearchAttributes.from_pairs([
        (BATCH_NUMBER, state.batch + 1),
    ]),
)
```

## Workflow Updates

Updates allow synchronous interaction with running workflows.

### Defining Update Handlers

```python
@workflow.defn
class OrderWorkflow:
    def __init__(self):
        self._items: list[str] = []

    @workflow.update
    async def add_item(self, item: str) -> int:
        """Add item and return new count."""
        self._items.append(item)
        return len(self._items)

    @workflow.update
    async def add_item_with_validation(self, item: str) -> int:
        """Update with validation."""
        # This runs before the update is accepted
        if not item:
            raise ValueError("Item cannot be empty")
        self._items.append(item)
        return len(self._items)

    # Validator runs in the handler but before main logic
    @add_item_with_validation.validator
    def validate_add_item(self, item: str) -> None:
        if len(self._items) >= 100:
            raise ValueError("Order is full")
```

### Calling Updates from Client

```python
handle = client.get_workflow_handle("order-123")

# Execute update and wait for result
count = await handle.execute_update(
    OrderWorkflow.add_item,
    "new-item",
)
print(f"Order now has {count} items")
```

## Schedules

Create recurring workflow executions.

```python
from temporalio.client import (
    Schedule,
    ScheduleActionStartWorkflow,
    ScheduleSpec,
    ScheduleIntervalSpec,
)

# Create a schedule
schedule_id = "daily-report"
await client.create_schedule(
    schedule_id,
    Schedule(
        action=ScheduleActionStartWorkflow(
            DailyReportWorkflow.run,
            id="daily-report",
            task_queue="reports",
        ),
        spec=ScheduleSpec(
            intervals=[ScheduleIntervalSpec(every=timedelta(days=1))],
        ),
    ),
)

# Manage schedules
schedule = client.get_schedule_handle(schedule_id)
await schedule.pause("Maintenance window")
await schedule.unpause()
await schedule.trigger()  # Run immediately
await schedule.delete()
```

## Interceptors

Interceptors allow cross-cutting concerns like logging, metrics, and auth.

### Creating a Custom Activity Interceptor

The interceptor pattern uses a chain of interceptors. You create an `Interceptor` class that returns specialized inbound interceptors for activities and workflows.

```python
from temporalio.worker import (
    Interceptor,
    ActivityInboundInterceptor,
    ExecuteActivityInput,
)
from typing import Any

class LoggingActivityInboundInterceptor(ActivityInboundInterceptor):
    async def execute_activity(self, input: ExecuteActivityInput) -> Any:
        activity.logger.info(f"Activity starting: {input.fn.__name__}")
        try:
            # Delegate to next interceptor in chain
            result = await self.next.execute_activity(input)
            activity.logger.info(f"Activity completed: {input.fn.__name__}")
            return result
        except Exception as e:
            activity.logger.error(f"Activity failed: {e}")
            raise

class LoggingInterceptor(Interceptor):
    def intercept_activity(
        self,
        next: ActivityInboundInterceptor,
    ) -> ActivityInboundInterceptor:
        # Return our interceptor wrapping the next one
        return LoggingActivityInboundInterceptor(next)

# Apply to worker
worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    interceptors=[LoggingInterceptor()],
)
```

### Creating a Custom Workflow Interceptor

```python
from temporalio.worker import (
    Interceptor,
    WorkflowInboundInterceptor,
    WorkflowInterceptorClassInput,
    ExecuteWorkflowInput,
)

class LoggingWorkflowInboundInterceptor(WorkflowInboundInterceptor):
    async def execute_workflow(self, input: ExecuteWorkflowInput) -> Any:
        workflow.logger.info(f"Workflow starting: {input.type}")
        try:
            result = await self.next.execute_workflow(input)
            workflow.logger.info(f"Workflow completed: {input.type}")
            return result
        except Exception as e:
            workflow.logger.error(f"Workflow failed: {e}")
            raise

class LoggingInterceptor(Interceptor):
    def workflow_interceptor_class(
        self,
        input: WorkflowInterceptorClassInput,
    ) -> type[WorkflowInboundInterceptor] | None:
        return LoggingWorkflowInboundInterceptor
```

## Dynamic Workflows and Activities

Handle workflows/activities not known at compile time.

### Dynamic Workflow Handler

```python
@workflow.defn(dynamic=True)
class DynamicWorkflow:
    @workflow.run
    async def run(self, args: Sequence[RawValue]) -> Any:
        workflow_type = workflow.info().workflow_type
        # Route based on type
        if workflow_type == "order-workflow":
            return await self._handle_order(args)
        elif workflow_type == "refund-workflow":
            return await self._handle_refund(args)
```

### Dynamic Activity Handler

```python
@activity.defn(dynamic=True)
async def dynamic_activity(args: Sequence[RawValue]) -> Any:
    activity_type = activity.info().activity_type
    # Handle based on type
    ...
```

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks).

```python
from temporalio import activity
from temporalio.client import Client

@activity.defn
async def request_approval(request_id: str) -> None:
    # Get task token for async completion
    task_token = activity.info().task_token

    # Store task token for later completion (e.g., in database)
    await store_task_token(request_id, task_token)

    # Raise to indicate async completion
    activity.raise_complete_async()

# Later, complete the activity from another process
async def complete_approval(request_id: str, approved: bool):
    client = await Client.connect("localhost:7233")
    task_token = await get_task_token(request_id)

    if approved:
        await client.get_async_activity_handle(task_token).complete("approved")
    else:
        await client.get_async_activity_handle(task_token).fail(
            ApplicationError("Rejected")
        )
```

## Sandbox Customization

The Python SDK runs workflows in a sandbox to ensure determinism. You can customize sandbox restrictions when needed.

### Passing Through Modules

If you need to use modules that are blocked by the sandbox:

```python
from temporalio.worker import Worker
from temporalio.worker.workflow_sandbox import SandboxRestrictions

# Allow specific modules through the sandbox
restrictions = SandboxRestrictions.default.with_passthrough_modules("my_module")

worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    workflow_runner=SandboxedWorkflowRunner(
        restrictions=restrictions,
    ),
)
```

### Passing Through All Modules (Use with Caution)

```python
# Disable module restrictions entirely - use only if you trust all code
restrictions = SandboxRestrictions.default.with_passthrough_all_modules()
```

### Temporary Passthrough in Workflow Code

```python
@workflow.run
async def run(self) -> str:
    # Temporarily disable sandbox restrictions for imports
    with workflow.unsafe.imports_passed_through():
        import some_restricted_module
        # Use the module...
```

### Customizing Invalid Module Members

```python
# Allow specific members that are normally blocked
restrictions = SandboxRestrictions.default
restrictions = restrictions.with_invalid_module_member_children(
    "datetime", {"datetime": {"now"}}  # Block datetime.datetime.now
)
```

## Gevent Compatibility Warning

**The Python SDK is NOT compatible with gevent.** Gevent's monkey patching modifies Python's asyncio event loop in ways that break the SDK's deterministic execution model.

If your application uses gevent:
- You cannot run Temporal workers in the same process
- Consider running workers in a separate process without gevent
- Use a message queue or HTTP API to communicate between gevent and Temporal processes

## Worker Tuning

Configure worker performance settings.

```python
from concurrent.futures import ThreadPoolExecutor

worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    # Workflow task concurrency
    max_concurrent_workflow_tasks=100,
    # Activity task concurrency
    max_concurrent_activities=100,
    # Executor for sync activities
    activity_executor=ThreadPoolExecutor(max_workers=50),
    # Graceful shutdown timeout
    graceful_shutdown_timeout=timedelta(seconds=30),
)
```

## Workflow Init Decorator

Use `@workflow.init` to run initialization code when a workflow is first created (not on replay).

```python
@workflow.defn
class MyWorkflow:
    @workflow.init
    def __init__(self, initial_value: str) -> None:
        # This runs only on first execution, not replay
        self._value = initial_value
        self._items: list[str] = []

    @workflow.run
    async def run(self) -> str:
        # self._value and self._items are already initialized
        return self._value
```

## Workflow Failure Exception Types

Control which exceptions cause workflow task failures vs workflow failures:

```python
@workflow.defn(
    # These exception types will fail the workflow execution (not just the task)
    failure_exception_types=[ValueError, CustomBusinessError]
)
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        raise ValueError("This fails the workflow, not just the task")
```
