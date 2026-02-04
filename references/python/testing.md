# Python SDK Testing

## Overview

The Python SDK provides `WorkflowEnvironment` for testing workflows with time-skipping support and `ActivityEnvironment` for isolated activity testing.

## Time-Skipping Test Environment

```python
import pytest
from temporalio.testing import WorkflowEnvironment
from temporalio.worker import Worker

@pytest.mark.asyncio
async def test_workflow():
    async with await WorkflowEnvironment.start_time_skipping() as env:
        async with Worker(
            env.client,
            task_queue="test-queue",
            workflows=[MyWorkflow],
            activities=[my_activity],
        ):
            result = await env.client.execute_workflow(
                MyWorkflow.run,
                "input",
                id="test-workflow-id",
                task_queue="test-queue",
            )
            assert result == "expected"
```

## Local Test Environment

For tests that don't need time-skipping:

```python
async with await WorkflowEnvironment.start_local() as env:
    # Real-time execution
    pass
```

## Activity Testing

```python
from temporalio.testing import ActivityEnvironment

@pytest.mark.asyncio
async def test_activity():
    env = ActivityEnvironment()

    # Optionally customize activity info
    # env.info = ActivityInfo(...)

    result = await env.run(my_activity, "arg1", "arg2")
    assert result == "expected"
```

## Mocking Activities

```python
async def mock_activity(input: str) -> str:
    return "mocked result"

@pytest.mark.asyncio
async def test_with_mock():
    async with await WorkflowEnvironment.start_time_skipping() as env:
        async with Worker(
            env.client,
            task_queue="test-queue",
            workflows=[MyWorkflow],
            activities=[mock_activity],  # Use mock
        ):
            result = await env.client.execute_workflow(...)
```

## Workflow Replay Testing

```python
from temporalio.worker import Replayer

async def test_replay():
    replayer = Replayer(workflows=[MyWorkflow])

    # From JSON file
    await replayer.replay_workflow(
        WorkflowHistory.from_json("workflow-id", history_json)
    )
```

## Testing Signals and Queries

```python
@pytest.mark.asyncio
async def test_signals():
    async with await WorkflowEnvironment.start_time_skipping() as env:
        async with Worker(...):
            handle = await env.client.start_workflow(
                MyWorkflow.run,
                id="test-wf",
                task_queue="test-queue",
            )

            # Send signal
            await handle.signal(MyWorkflow.my_signal, "data")

            # Query state
            status = await handle.query(MyWorkflow.get_status)
            assert status == "expected"

            # Wait for completion
            result = await handle.result()
```

## Best Practices

1. Use time-skipping for workflows with timers
2. Mock external dependencies in activities
3. Test replay compatibility when changing workflow code
4. Test signal/query handlers explicitly
5. Use unique workflow IDs per test to avoid conflicts
