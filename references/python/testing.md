# Python SDK Testing

## Overview

You test Temporal Python Workflows using the Temporal testing package plus a normal Python test framework like pytest. The Temporal Python SDK provides `WorkflowEnvironment` for testing workflows in a local environment and `ActivityEnvironment` for isolated activity testing.

## Workflow Test Environment

The core pattern is:

1. Start a test WorkflowEnvironment (`WorkflowEnvironment.start_local()`).
2. Start a Worker in that environment with your Workflow and Activities registered.
3. Use the environment’s client to execute the Workflow, using a fresh UUID for the task queue name and workflow ID.
4. Assert on the result or status.

`WorkflowEnvironment.start_local` configures a ready-to-go local environment for running and testing workflows:

```python
import uuid
import pytest

from temporalio.testing import WorkflowEnvironment
from temporalio.worker import Worker

from activities import my_activity
from workflows import MyWorkflow

@pytest.mark.asyncio
async def test_workflow():
    task_queue_name = str(uuid.uuid4())
    async with await WorkflowEnvironment.start_local() as env:
        async with Worker(
            env.client,
            task_queue=task_queue_name,
            workflows=[MyWorkflow],
            activities=[my_activity],
        ):
            result = await env.client.execute_workflow(
                MyWorkflow.run,
                "input",
                id=str(uuid.uuid4()),
                task_queue=task_queue_name,
            )
```

Conveniently, the local `env` can be shared among tests, e.g. via a pytest fixture.

If your workflows / tests involve long durations (such as using Temporal timers / sleeps), then you can use the time-skipping environment, via `WorkflowEnvironment.start_time_skipping()`.
Only use time-skipping if you must. It can *not* be shared among tests.

## Mocking Activities

```python
import uuid
import pytest

from temporalio import activity
from temporalio.testing import WorkflowEnvironment
from temporalio.worker import Worker

from workflows import MyWorkflow

@activity.defn(name="compose_greeting")
async def compose_greeting_mocked(input: str) -> str:
    return "mocked result"

@pytest.mark.asyncio
async def test_with_mock():
    task_queue_name = str(uuid.uuid4())
    async with await WorkflowEnvironment.start_local() as env:
        async with Worker(
            env.client,
            task_queue=task_queue_name,
            workflows=[MyWorkflow],
            activities=[compose_greeting_mocked],
        ):
            result = await env.client.execute_workflow(...)
```

## Testing Signals and Queries

```python
@pytest.mark.asyncio
async def test_signals():
    async with await WorkflowEnvironment.start_local() as env:
        async with Worker(...):
            handle = await env.client.start_workflow(...) # same arguments as to execute_workflow

            # Send signal
            await handle.signal(MyWorkflow.my_signal, "data")

            # Query state
            status = await handle.query(MyWorkflow.get_status)
            assert status == "expected"

            # Wait for completion
            result = await handle.result()
```

## Testing Failure Cases

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

        async with Worker(...):
            with pytest.raises(WorkflowFailureError):
                await env.client.execute_workflow(...)
```

## Workflow Replay Testing

```python
import json
import pytest
import uuid
from temporalio.client import WorkflowHistory
from temporalio.worker import Replayer

from workflows import MyWorkflow

@pytest.mark.asyncio
async def test_replay():
    with open("example-history.json", "r") as f:
        history_json = json.load(f)

    replayer = Replayer(workflows=[MyWorkflow])

    # From JSON file
    await replayer.replay_workflow(
        WorkflowHistory.from_json(str(uuid.uuid4()), history_json)
    )
```

## Activity Testing

```python
import pytest

from temporalio.testing import ActivityEnvironment

@pytest.mark.asyncio
async def test_activity():
    env = ActivityEnvironment()
    result = await env.run(my_activity, "arg1", "arg2")
    assert result == "expected"
```

### Customize Activity Info

`ActivityEnvironment()` populates `env.info` with a default `temporalio.activity.Info` on construction, so activity code that calls `activity.info()` works out of the box. When your test needs specific values (e.g. asserting on `info.activity_id`, exercising `attempt`-aware retry logic, or simulating a Standalone Activity), build a new `Info` from the helper:

- `ActivityEnvironment.default_info()` is a `@staticmethod` taking no arguments. It returns a fresh `temporalio.activity.Info` populated with sentinel test values: `activity_id="test"`, `task_queue="test"`, `workflow_id="test"`, `workflow_run_id="test-run"`, `workflow_type="test"`, `namespace="default"`, `workflow_namespace="default"`, `attempt=1`, `start_to_close_timeout=timedelta(seconds=1)`, `schedule_to_close_timeout=timedelta(seconds=1)`, `activity_run_id=None`, `retry_policy=None`, `heartbeat_timeout=None`.
- Customize by passing the result through `dataclasses.replace`, then assigning to `env.info` **before** calling `env.run`:

```python
import dataclasses
from temporalio.testing import ActivityEnvironment

env = ActivityEnvironment()
env.info = dataclasses.replace(
    ActivityEnvironment.default_info(),
    activity_id="order-1234",
    attempt=3,
)
await env.run(my_activity, "arg")
```

For Standalone Activities ([see `references/python/standalone-activities.md`](standalone-activities.md)), the `activity_run_id` field on `Info` is `None` for Workflow-orchestrated Activities; set it to a string and clear the `workflow_*` fields (each is `Optional[str]`) to test Standalone-flavoured code paths:

```python
env.info = dataclasses.replace(
    ActivityEnvironment.default_info(),
    activity_run_id="standalone-run-id",
    workflow_id=None,
    workflow_run_id=None,
    workflow_type=None,
    workflow_namespace=None,
)
```

Common mistakes:

- Calling `default_info()` as a module-level function (e.g. `activity.default_info()`); it lives on `temporalio.testing.ActivityEnvironment` as a static method.
- Passing fields directly to `default_info(...)`; it accepts no arguments. Use `dataclasses.replace` on the returned `Info`.
- Mutating `env.info` after `env.run` has started — the activity has already captured the context.

## Best Practices

1. Use the `WorkflowEnvironment.start_local` environment for most testing
2. Use time-skipping environment for workflows with durable timers / durable sleeps.
3. Mock external dependencies in activities
4. Test replay compatibility, especially when changing workflow code
5. Test signal/query handlers explicitly
6. Use unique workflow IDs and task queues per test to avoid conflicts. Easiest is a `uuid.uuid4()`
