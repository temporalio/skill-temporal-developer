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
                start_to_close_timeout=timedelta(minutes=5),
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

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks).
If you configure a heartbeat_timeout on this activity, the external completer is responsible for sending heartbeats via the async handle.
If you do NOT set a heartbeat_timeout, no heartbeats are required.

**Note:** If the external system that completes the asynchronous action can reliably be trusted to do the task and Signal back with the result, and it doesn't need to Heartbeat or receive Cancellation, then consider using **signals** instead.

```python
from temporalio import activity
from temporalio.client import Client

@activity.defn
async def request_approval(request_id: str) -> None:
    # Get task token for async completion
    task_token = activity.info().task_token

    # Store task token for later completion (e.g., in database)
    await store_task_token(request_id, task_token)

    # Mark this activity as waiting for external completion
    activity.raise_complete_async()

# Later, complete the activity from another process
async def complete_approval(request_id: str, approved: bool):
    client = await Client.connect("localhost:7233", namespace="default")
    task_token = await get_task_token(request_id)

    handle = client.get_async_activity_handle(task_token=task_token)

    # Optional: if a heartbeat_timeout was set, you can periodically:
    # await handle.heartbeat(progress_details)

    if approved:
        await handle.complete("approved")
    else:
        # You can also fail or report cancellation via the handle
        await handle.fail(ApplicationError("Rejected"))
```

## Sandbox Customization

The Python SDK runs workflows in a sandbox to help you ensure determinism. You can customize sandbox restrictions when needed. See `references/python/sandbox.md`

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

Use `@workflow.init` to run initialization code when a workflow is first created.

**Purpose:** Execute some setup code before signal/update happens or run is invoked.

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

Control which exceptions cause workflow task failures vs workflow failures.

- Special case: if you include temporalio.workflow.NondeterminismError (or a superclass), non-determinism errors will fail the workflow instead of leaving it in a retrying state
- **Tip for testing:** Set to `[Exception]` in tests so any unhandled exception fails the workflow immediately rather than retrying the workflow task forever. This surfaces bugs faster.

### Per-Workflow Configuration

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

### Worker-Level Configuration

```python
worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    workflow_failure_exception_types=[ValueError, CustomBusinessError],
)
```

