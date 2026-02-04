# Python Gotchas

Python-specific mistakes and anti-patterns. See also [Common Gotchas](../core/common-gotchas.md) for language-agnostic concepts.

## Idempotency

```python
# BAD - May charge customer multiple times on retry
@activity.defn
async def charge_payment(order_id: str, amount: float) -> str:
    return await payment_api.charge(customer_id, amount)

# GOOD - Safe for retries
@activity.defn
async def charge_payment(order_id: str, amount: float) -> str:
    return await payment_api.charge(
        customer_id,
        amount,
        idempotency_key=f"order-{order_id}"
    )
```

## Replay Safety

### Side Effects in Workflows

```python
# BAD - Prints on every replay, notification runs in workflow
@workflow.defn
class NotificationWorkflow:
    @workflow.run
    async def run(self):
        print("Starting workflow")  # Runs on replay too
        send_slack_notification("Started")  # Side effect in workflow!
        await workflow.execute_activity(...)

# GOOD - Replay-safe
@workflow.defn
class NotificationWorkflow:
    @workflow.run
    async def run(self):
        workflow.logger.info("Starting workflow")  # Only logs on first execution
        await workflow.execute_activity(send_notification, "Started")
```

### Time-Based Logic

```python
# BAD - Different time on replay
if datetime.now() > deadline:
    await cancel_order()

# GOOD - Consistent across replays
if workflow.now() > deadline:
    await cancel_order()
```

### Other Non-Deterministic Operations

```python
# BAD - Different values on replay
random_id = str(uuid.uuid4())
random_value = random.random()

# GOOD - Deterministic alternatives
random_id = workflow.uuid4()
random_value = workflow.random().random()
```

## Query Handlers

### Modifying State

```python
# BAD - Query modifies state
@workflow.defn
class QueueWorkflow:
    def __init__(self):
        self._queue = []

    @workflow.query
    def get_next_item(self) -> str | None:
        if self._queue:
            return self._queue.pop(0)  # Mutates state!
        return None

# GOOD - Query reads, Update modifies
@workflow.defn
class QueueWorkflow:
    def __init__(self):
        self._queue = []

    @workflow.query
    def peek(self) -> str | None:
        return self._queue[0] if self._queue else None

    @workflow.update
    def dequeue(self) -> str | None:
        if self._queue:
            return self._queue.pop(0)
        return None
```

### Blocking in Queries

```python
# BAD - Queries cannot await
@workflow.query
async def get_data_with_refresh(self) -> dict:
    if self._data is None:
        self._data = await workflow.execute_activity(fetch_data, ...)
    return self._data

# GOOD - Query returns state, signal triggers refresh
@workflow.signal
async def refresh_data(self):
    self._data = await workflow.execute_activity(fetch_data, ...)

@workflow.query
def get_data(self) -> dict | None:
    return self._data
```

## File Organization

### Importing Activities into Workflow Files

**The Problem**: The Python sandbox reloads workflow files on every task. Importing heavy activity modules slows down workers.

```python
# BAD - activities.py gets reloaded constantly
# workflows.py
from activities import my_activity

@workflow.defn
class MyWorkflow:
    pass

# GOOD - Pass-through import
# workflows.py
from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from activities import my_activity

@workflow.defn
class MyWorkflow:
    pass
```

### Mixing Workflows and Activities

```python
# BAD - Everything in one file
# app.py
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self):
        await workflow.execute_activity(my_activity, ...)

@activity.defn
async def my_activity():
    # Heavy imports, I/O, etc.
    pass

# GOOD - Separate files
# workflows.py
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self):
        await workflow.execute_activity(my_activity, ...)

# activities.py
@activity.defn
async def my_activity():
    pass
```

## Async vs Sync Activities

### Blocking in Async Activities

```python
# BAD - Blocks the event loop
@activity.defn
async def process_file(path: str) -> str:
    with open(path) as f:  # Blocking I/O in async!
        return f.read()

# GOOD Option 1 - Use sync activity with executor
@activity.defn
def process_file(path: str) -> str:
    with open(path) as f:
        return f.read()

# Register with executor in worker
Worker(
    client,
    task_queue="my-queue",
    activities=[process_file],
    activity_executor=ThreadPoolExecutor(max_workers=10),
)

# GOOD Option 2 - Use async I/O
@activity.defn
async def process_file(path: str) -> str:
    async with aiofiles.open(path) as f:
        return await f.read()
```

### Missing Executor for Sync Activities

```python
# BAD - Sync activity without executor blocks worker
@activity.defn
def slow_computation(data: str) -> str:
    return heavy_cpu_work(data)

Worker(
    client,
    task_queue="my-queue",
    activities=[slow_computation],
    # Missing activity_executor!
)

# GOOD - Provide executor
Worker(
    client,
    task_queue="my-queue",
    activities=[slow_computation],
    activity_executor=ThreadPoolExecutor(max_workers=10),
)
```

## Error Handling

### Swallowing Errors

```python
# BAD - Error is hidden
@workflow.defn
class SilentFailureWorkflow:
    @workflow.run
    async def run(self):
        try:
            await workflow.execute_activity(...)
        except Exception:
            pass  # Error is lost!

# GOOD - Handle appropriately
@workflow.defn
class ProperErrorHandlingWorkflow:
    @workflow.run
    async def run(self):
        try:
            await workflow.execute_activity(...)
        except ActivityError as e:
            workflow.logger.error(f"Activity failed: {e}")
            raise  # Or use fallback, compensate, etc.
```

### Wrong Retry Classification

```python
# BAD - Network errors should be retried
@activity.defn
async def call_api():
    try:
        return await http_client.get(url)
    except ConnectionError:
        raise ApplicationError("Connection failed", non_retryable=True)

# GOOD - Only permanent failures are non-retryable
@activity.defn
async def call_api():
    try:
        return await http_client.get(url)
    except ConnectionError:
        raise  # Let Temporal retry
    except InvalidCredentialsError:
        raise ApplicationError("Invalid API key", non_retryable=True)
```

## Retry Policies

### Too Aggressive

```python
# BAD - Gives up too easily
result = await workflow.execute_activity(
    flaky_api_call,
    schedule_to_close_timeout=timedelta(seconds=30),
    retry_policy=RetryPolicy(maximum_attempts=1),
)

# GOOD - Resilient to transient failures
result = await workflow.execute_activity(
    flaky_api_call,
    schedule_to_close_timeout=timedelta(minutes=10),
    retry_policy=RetryPolicy(
        initial_interval=timedelta(seconds=1),
        maximum_interval=timedelta(minutes=1),
        backoff_coefficient=2.0,
        maximum_attempts=10,
    ),
)
```

## Heartbeating

### Forgetting to Heartbeat Long Activities

```python
# BAD - No heartbeat, can't detect stuck activities
@activity.defn
async def process_large_file(path: str):
    for chunk in read_chunks(path):
        process(chunk)  # Takes hours, no heartbeat

# GOOD - Regular heartbeats with progress
@activity.defn
async def process_large_file(path: str):
    for i, chunk in enumerate(read_chunks(path)):
        activity.heartbeat(f"Processing chunk {i}")
        process(chunk)
```

### Heartbeat Timeout Too Short

```python
# BAD - Heartbeat timeout shorter than processing time
await workflow.execute_activity(
    process_chunk,
    start_to_close_timeout=timedelta(minutes=30),
    heartbeat_timeout=timedelta(seconds=10),  # Too short!
)

# GOOD - Heartbeat timeout allows for processing variance
await workflow.execute_activity(
    process_chunk,
    start_to_close_timeout=timedelta(minutes=30),
    heartbeat_timeout=timedelta(minutes=2),
)
```

## Testing

### Not Testing Failures

```python
# Test failure scenarios
@pytest.mark.asyncio
async def test_activity_failure_handling():
    async with await WorkflowEnvironment.start_time_skipping() as env:
        # Create activity that always fails
        @activity.defn
        async def failing_activity() -> str:
            raise ApplicationError("Simulated failure", non_retryable=True)

        async with Worker(
            env.client,
            task_queue="test",
            workflows=[MyWorkflow],
            activities=[failing_activity],
        ):
            with pytest.raises(WorkflowFailureError):
                await env.client.execute_workflow(
                    MyWorkflow.run,
                    id="test-failure",
                    task_queue="test",
                )
```

### Not Testing Replay

```python
from temporalio.worker import Replayer

async def test_replay_compatibility():
    replayer = Replayer(workflows=[MyWorkflow])

    # Load history from file (captured from production/staging)
    with open("workflow_history.json") as f:
        history = WorkflowHistory.from_json("workflow-id", f.read())

    # Fails if current code is incompatible with history
    await replayer.replay_workflow(history)
```
