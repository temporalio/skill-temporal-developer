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
    client = await Client.connect("localhost:7233")
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

The Python SDK runs workflows in a sandbox to help you ensure determinism. You can customize sandbox restrictions when needed.

### Passing Through Modules

For performance and behavior reasons, you are encouraged to pass through all modules whose calls will be deterministic.

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

### Temporary Passthrough Context Manager

```python
from temporalio import workflow
from datetime import timedelta

# Mark imports inside this block as passthrough
with workflow.unsafe.imports_passed_through():
    from activities import say_hello  # your activity
    import pydantic                   # or other deterministic third‑party libs

@workflow.run
async def run(self) -> str:
    # ... use the imports here
```

**Note:** The imports, even when using `imports_passed_through`, should all be at the top of the file. Runtime imports are an anti-pattern.

### Temporary Unrestricted Sandbox

```python
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> None:
        # Normal sandboxed code here

        with workflow.unsafe.sandbox_unrestricted():
            # Code here runs without sandbox restrictions
            # e.g., a restricted os/path call or special logging
            do_something_non_sandbox_safe()
```

- Per‑block escape hatch from runtime restrictions; imports unchanged.
- Use when: You need to call something the sandbox would normally block (e.g., a restricted stdlib call) in a very small, controlled section.
- **IMPORTANT:** Use it sparingly; you lose determinism checks inside the block
- Genuinely non-deterministic code still *MUST* go into activities.


### Customizing Invalid Module Members

`invalid_module_members` includes modules that cannot be accessed.

Checks are compared against the fully qualified path to the item.

```python
import dataclasses
from temporalio.worker import Worker
from temporalio.worker.workflow_sandbox import (
  SandboxedWorkflowRunner,
  SandboxMatcher,
  SandboxRestrictions,
)

# Example 1: Remove a restriction on datetime.date.today():
restrictions = dataclasses.replace(
    SandboxRestrictions.default,
    invalid_module_members=SandboxRestrictions.invalid_module_members_default.with_child_unrestricted(
      "datetime", "date", "today",
    ),
)

# Example 2: Restrict the datetime.date class from being used
restrictions = dataclasses.replace(
    SandboxRestrictions.default,
    invalid_module_members=SandboxRestrictions.invalid_module_members_default | SandboxMatcher(
      children={"datetime": SandboxMatcher(use={"date"})},
    ),
)
```

### Import Notification Policy

Control warnings/errors for sandbox import issues. Recommended for catching potential problems:

```python
from temporalio import workflow
from temporalio.worker.workflow_sandbox import SandboxedWorkflowRunner, SandboxRestrictions

restrictions = SandboxRestrictions.default.with_import_notification_policy(
    workflow.SandboxImportNotificationPolicy.WARN_ON_DYNAMIC_IMPORT
    | workflow.SandboxImportNotificationPolicy.WARN_ON_UNINTENTIONAL_PASSTHROUGH
)

worker = Worker(
    ...,
    workflow_runner=SandboxedWorkflowRunner(restrictions=restrictions),
)
```

- `WARN_ON_DYNAMIC_IMPORT` (default) - warns on imports after initial workflow load
- `WARN_ON_UNINTENTIONAL_PASSTHROUGH` - warns when modules are imported into sandbox without explicit passthrough (not default, but highly recommended for catching missing passthroughs)
- `RAISE_ON_UNINTENTIONAL_PASSTHROUGH` - raise instead of warn

Override per-import with the context manager:

```python
with workflow.unsafe.sandbox_import_notification_policy(
    workflow.SandboxImportNotificationPolicy.SILENT
):
    import pydantic  # No warning for this import
```

### Disable Lazy sys.modules Passthrough

By default, passthrough modules are lazily added to the sandbox's `sys.modules` when accessed. To require explicit imports:

```python
import dataclasses
from temporalio.worker.workflow_sandbox import SandboxedWorkflowRunner, SandboxRestrictions

restrictions = dataclasses.replace(
    SandboxRestrictions.default,
    disable_lazy_sys_module_passthrough=True,
)

worker = Worker(
    ...,
    workflow_runner=SandboxedWorkflowRunner(restrictions=restrictions),
)
```

When `True`, passthrough modules must be explicitly imported to appear in the sandbox's `sys.modules`.

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

