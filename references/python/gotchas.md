# Python Gotchas

Python-specific mistakes and anti-patterns. See also [Common Gotchas](references/core/common-gotchas.md) for language-agnostic concepts.

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

`references/python/sandbox.md` contains more info about the Python sandbox.

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

The Temporal Python SDK supports both async and sync activities. See `references/python/sync-vs-async.md` to understand which to choose. Below are important anti-patterns for both aysnc and sync activities.

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
# BAD - Sync activity REQUIRES executor
@activity.defn
def slow_computation(data: str) -> str:
    return heavy_cpu_work(data)

Worker(
    client,
    task_queue="my-queue",
    activities=[slow_computation],
    # Missing activity_executor! --> THIS IMMEDIATELY RAISES AN EXCEPTION!
)

# GOOD - Provide executor
Worker(
    client,
    task_queue="my-queue",
    activities=[slow_computation],
    activity_executor=ThreadPoolExecutor(max_workers=10),
)
```

## Wrong Retry Classification

**Example:** Transient networks errors should be retried. Authentication errors should not be.
See `references/python/error-handling.md` to understand how to classify errors.

## Heartbeating

### Forgetting to Heartbeat Long Activities

```python
# BAD - No heartbeat, can't detect stuck activities
@activity.defn
async def process_large_file(path: str):
    async for chunk in read_chunks(path):
        process(chunk)  # Takes hours, no heartbeat

# GOOD - Regular heartbeats with progress
@activity.defn
async def process_large_file(path: str):
    async for i, chunk in enumerate(read_chunks(path)):
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

Below shows an example of how to test failure cases:

```python
# Test failure scenarios
@pytest.mark.asyncio
async def test_activity_failure_handling():
    async with await WorkflowEnvironment.start_local() as env:
        # An example activity that always fails
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

Replay tests let you test that you do not have hidden sources of non-determinism bugs in your workflow code:

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
