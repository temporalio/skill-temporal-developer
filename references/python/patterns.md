# Python SDK Patterns

## Signals

### WHY: Use signals to send data or commands to a running workflow from external sources
### WHEN:
- **Order approval workflows** - Wait for human approval before proceeding
- **Live configuration updates** - Change workflow behavior without restarting
- **Fire-and-forget communication** - Notify workflow of external events
- **Workflow coordination** - Allow workflows to communicate with each other

**Signals vs Queries vs Updates:**
- Signals: Fire-and-forget, no response, can modify state
- Queries: Read-only, returns data, cannot modify state
- Updates: Synchronous, returns response, can modify state

```python
@workflow.defn
class OrderWorkflow:
    def __init__(self):
        self._approved = False
        self._items = []

    @workflow.signal
    async def approve(self) -> None:
        self._approved = True

    @workflow.signal
    async def add_item(self, item: str) -> None:
        self._items.append(item)

    @workflow.run
    async def run(self) -> str:
        # Wait for approval
        await workflow.wait_condition(lambda: self._approved)
        return f"Processed {len(self._items)} items"
```

### Dynamic Signal Handlers

For handling signals with names not known at compile time:

```python
@workflow.defn
class DynamicSignalWorkflow:
    def __init__(self):
        self._signals: dict[str, list[Any]] = {}

    @workflow.signal(dynamic=True)
    async def handle_signal(self, name: str, args: Sequence[RawValue]) -> None:
        if name not in self._signals:
            self._signals[name] = []
        self._signals[name].append(workflow.payload_converter().from_payload(args[0]))
```

## Queries

### WHY: Read workflow state without affecting execution - queries are read-only
### WHEN:
- **Progress tracking dashboards** - Display workflow progress to users
- **Status endpoints** - Check workflow state for API responses
- **Debugging** - Inspect internal workflow state
- **Health checks** - Verify workflow is functioning correctly

**Important:** Queries must NOT modify workflow state or have side effects.

```python
@workflow.defn
class StatusWorkflow:
    def __init__(self):
        self._status = "pending"
        self._progress = 0

    @workflow.query
    def get_status(self) -> str:
        return self._status

    @workflow.query
    def get_progress(self) -> int:
        return self._progress

    @workflow.run
    async def run(self) -> str:
        self._status = "running"
        for i in range(100):
            self._progress = i
            await workflow.execute_activity(
                process_item, i,
                schedule_to_close_timeout=timedelta(minutes=1)
            )
        self._status = "completed"
        return "done"
```

### Dynamic Query Handlers

```python
@workflow.query(dynamic=True)
def handle_query(self, name: str, args: Sequence[RawValue]) -> Any:
    if name == "get_field":
        field_name = workflow.payload_converter().from_payload(args[0])
        return getattr(self, f"_{field_name}", None)
```

## Child Workflows

### WHY: Break complex workflows into smaller, manageable units with independent failure domains
### WHEN:
- **Failure domain isolation** - Child failures don't automatically fail parent
- **Different retry policies** - Each child can have its own retry configuration
- **Reusability** - Share workflow logic across multiple parent workflows
- **Independent scaling** - Child workflows can run on different task queues
- **History size management** - Each child has its own event history

**Use activities instead when:** Operation is short-lived, doesn't need its own failure domain, or doesn't need independent retry policies.

```python
@workflow.run
async def run(self, orders: list[Order]) -> list[str]:
    results = []
    for order in orders:
        result = await workflow.execute_child_workflow(
            ProcessOrderWorkflow.run,
            order,
            id=f"order-{order.id}",
            # Control what happens to child when parent completes
            parent_close_policy=workflow.ParentClosePolicy.ABANDON,
        )
        results.append(result)
    return results
```

## External Workflows

### WHY: Interact with workflows that are not children of the current workflow
### WHEN:
- **Cross-workflow coordination** - Coordinate between independent workflows
- **Signaling existing workflows** - Send signals to workflows started elsewhere
- **Cancellation of other workflows** - Cancel workflows from a coordinating workflow

```python
@workflow.run
async def run(self, target_workflow_id: str) -> None:
    # Get handle to external workflow
    handle = workflow.get_external_workflow_handle(target_workflow_id)

    # Signal the external workflow
    await handle.signal(TargetWorkflow.data_ready, data_payload)

    # Or cancel it
    await handle.cancel()
```

## Parallel Execution

### WHY: Execute multiple independent operations concurrently for better throughput
### WHEN:
- **Batch processing** - Process multiple items simultaneously
- **Fan-out patterns** - Distribute work across multiple activities
- **Independent operations** - Operations that don't depend on each other's results

```python
@workflow.run
async def run(self, items: list[str]) -> list[str]:
    # Execute activities in parallel
    tasks = [
        workflow.execute_activity(
            process_item, item,
            schedule_to_close_timeout=timedelta(minutes=5)
        )
        for item in items
    ]
    return await asyncio.gather(*tasks)
```

### Deterministic Alternatives to asyncio

Use Temporal's deterministic alternatives for safer concurrent operations:

```python
# workflow.wait() - like asyncio.wait()
done, pending = await workflow.wait(
    futures,
    return_when=workflow.WaitConditionResult.FIRST_COMPLETED
)

# workflow.as_completed() - like asyncio.as_completed()
for future in workflow.as_completed(futures):
    result = await future
    # Process each result as it completes
```

## Continue-as-New

### WHY: Prevent unbounded event history growth in long-running or infinite workflows
### WHEN:
- **Event history approaching 10,000+ events** - Temporal recommends continue-as-new before hitting limits
- **Infinite/long-running workflows** - Polling, subscription, or daemon-style workflows
- **Memory optimization** - Reset workflow state to reduce memory footprint

**Recommendation:** Check history length periodically and continue-as-new around 10,000 events.

```python
@workflow.run
async def run(self, state: WorkflowState) -> str:
    while True:
        state = await process_batch(state)

        if state.is_complete:
            return "done"

        # Continue with fresh history before hitting limits
        if workflow.info().get_current_history_length() > 10000:
            workflow.continue_as_new(args=[state])
```

## Saga Pattern (Compensations)

### WHY: Implement distributed transactions with compensating actions for rollback
### WHEN:
- **Multi-step transactions** - Operations that span multiple services
- **Eventual consistency** - When you can't use traditional ACID transactions
- **Rollback requirements** - When partial failures require undoing previous steps

**Important:** Compensation activities should be idempotent - they may be retried.

```python
@workflow.run
async def run(self, order: Order) -> str:
    compensations: list[Callable[[], Awaitable[None]]] = []

    try:
        await workflow.execute_activity(
            reserve_inventory, order,
            schedule_to_close_timeout=timedelta(minutes=5)
        )
        compensations.append(lambda: workflow.execute_activity(
            release_inventory, order,
            schedule_to_close_timeout=timedelta(minutes=5)
        ))

        await workflow.execute_activity(
            charge_payment, order,
            schedule_to_close_timeout=timedelta(minutes=5)
        )
        compensations.append(lambda: workflow.execute_activity(
            refund_payment, order,
            schedule_to_close_timeout=timedelta(minutes=5)
        ))

        await workflow.execute_activity(
            ship_order, order,
            schedule_to_close_timeout=timedelta(minutes=5)
        )

        return "Order completed"

    except Exception as e:
        workflow.logger.error(f"Order failed: {e}, running compensations")
        for compensate in reversed(compensations):
            try:
                await compensate()
            except Exception as comp_err:
                workflow.logger.error(f"Compensation failed: {comp_err}")
        raise
```

## Cancellation Handling

### WHY: Gracefully handle workflow cancellation requests and perform cleanup
### WHEN:
- **Graceful shutdown** - Clean up resources when workflow is cancelled
- **External cancellation** - Respond to cancellation requests from clients
- **Cleanup activities** - Run cleanup logic even after cancellation

```python
@workflow.run
async def run(self) -> str:
    try:
        await workflow.execute_activity(
            long_running_activity,
            schedule_to_close_timeout=timedelta(hours=1),
        )
        return "completed"
    except asyncio.CancelledError:
        # Workflow was cancelled - perform cleanup
        workflow.logger.info("Workflow cancelled, running cleanup")
        # Cleanup activities still run even after cancellation
        await workflow.execute_activity(
            cleanup_activity,
            schedule_to_close_timeout=timedelta(minutes=5),
        )
        raise  # Re-raise to mark workflow as cancelled
```

## Wait Condition with Timeout

### WHY: Wait for a condition with a deadline
### WHEN:
- **Approval workflows with deadlines** - Auto-reject if not approved in time
- **Conditional waits with timeouts** - Proceed with default after timeout

```python
@workflow.run
async def run(self) -> str:
    self._approved = False

    # Wait for approval with 24-hour timeout
    try:
        await workflow.wait_condition(
            lambda: self._approved,
            timeout=timedelta(hours=24)
        )
        return "approved"
    except asyncio.TimeoutError:
        return "auto-rejected due to timeout"
```

## Waiting for All Handlers to Finish

### WHY: Ensure all signal/update handlers complete before workflow exits
### WHEN:
- **Workflows with async handlers** - Prevent data loss from in-flight handlers
- **Before continue-as-new** - Ensure handlers complete before resetting

```python
@workflow.run
async def run(self) -> str:
    # ... main workflow logic ...

    # Before exiting, wait for all handlers to finish
    await workflow.wait_condition(workflow.all_handlers_finished)
    return "done"
```

## Activity Heartbeat Details

### WHY: Resume activity progress after worker failure
### WHEN:
- **Long-running activities** - Track progress for resumability
- **Checkpointing** - Save progress periodically

```python
@activity.defn
async def process_large_file(file_path: str) -> str:
    # Get heartbeat details from previous attempt (if any)
    heartbeat_details = activity.info().heartbeat_details
    start_line = heartbeat_details[0] if heartbeat_details else 0

    with open(file_path) as f:
        for i, line in enumerate(f):
            if i < start_line:
                continue  # Skip already processed lines

            process_line(line)

            # Heartbeat with progress
            activity.heartbeat(i + 1)

    return "completed"
```

## Versioning with Patching

### WHY: Safely deploy workflow code changes without breaking running workflows
### WHEN:
- **Adding new steps** - New code path for new executions, old path for replays
- **Changing activity calls** - Modify activity parameters or logic
- **Deprecating features** - Gradually remove old code paths

```python
@workflow.run
async def run(self) -> str:
    if workflow.patched("new-greeting"):
        # New implementation
        greeting = await workflow.execute_activity(
            new_greet_activity,
            schedule_to_close_timeout=timedelta(minutes=1)
        )
    else:
        # Old implementation (for replay)
        greeting = await workflow.execute_activity(
            old_greet_activity,
            schedule_to_close_timeout=timedelta(minutes=1)
        )

    return greeting
```

## Timers

### WHY: Schedule delays or deadlines within workflows in a durable way
### WHEN:
- **Scheduled delays** - Wait for a specific duration before continuing
- **Deadlines** - Set timeouts for operations
- **Reminder patterns** - Schedule future notifications

```python
@workflow.run
async def run(self) -> str:
    # Wait for 1 hour
    await asyncio.sleep(3600)

    # Or with workflow-specific API
    await workflow.sleep(timedelta(hours=1))

    return "Timer fired"
```

## Local Activities

### WHY: Reduce latency for short, lightweight operations by skipping the task queue
### WHEN:
- **Short operations** - Activities completing in milliseconds/seconds
- **High-frequency calls** - When task queue overhead is significant
- **Low-latency requirements** - When you can't afford task queue round-trip

**Note:** Local activities are experimental in Python SDK.

```python
@workflow.run
async def run(self) -> str:
    result = await workflow.execute_local_activity(
        quick_lookup,
        "key",
        schedule_to_close_timeout=timedelta(seconds=5),
    )
    return result
```

## Using Pydantic Models

```python
from pydantic import BaseModel
from temporalio.contrib.pydantic import pydantic_data_converter

class OrderInput(BaseModel):
    order_id: str
    items: list[str]
    total: float

@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, input: OrderInput) -> str:
        return f"Processed order {input.order_id}"

# Client setup with Pydantic support
client = await Client.connect(
    "localhost:7233",
    data_converter=pydantic_data_converter,
)
```
