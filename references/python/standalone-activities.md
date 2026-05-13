# Standalone Activities — Python SDK

Read `references/core/standalone-activities.md` first for the concept, CLI inventory, prerequisites, and Public Preview limitations. This file covers the Python SDK API.

Python SDK support for Standalone Activities is at **Public Preview**.

## Prerequisites

- **Python 3.9+**.
- **`temporalio` v1.23.0 or higher.**
- **Temporal CLI v1.7.0 or higher.**

Install the SDK:

```bash
uv add temporalio
```

Start the local dev server (creates the `default` Namespace, uses an in-memory database — not for production):

```bash
temporal server start-dev
```

The Temporal Server is then on `localhost:7233` and the Web UI on `http://localhost:8233`; the Standalone Activities nav item is in the top-left of the UI.

## Writing the Activity

An Activity in the Python SDK is a function decorated with `@activity.defn`. It can be sync or `async def`. The way you write a Standalone Activity is identical to how you write an Activity orchestrated by a Workflow — the same Activity can be executed both ways.

```python
# my_activity.py
from dataclasses import dataclass

from temporalio import activity


@dataclass
class ComposeGreetingInput:
    greeting: str
    name: str


@activity.defn
def compose_greeting(input: ComposeGreetingInput) -> str:
    activity.logger.info("Running activity with parameter %s" % input)
    return f"{input.greeting}, {input.name}!"
```

## Running the Worker

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — create a Worker, register the Activity, run the Worker. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

from temporalio.client import Client
from temporalio.envconfig import ClientConfig
from temporalio.worker import Worker

from hello_standalone_activity.my_activity import compose_greeting


async def main():
    connect_config = ClientConfig.load_client_connect_config()
    connect_config.setdefault("target_host", "localhost:7233")
    client = await Client.connect(**connect_config)
    worker = Worker(
        client,
        task_queue="my-standalone-activity-task-queue",
        activities=[compose_greeting],
        activity_executor=ThreadPoolExecutor(5),
    )
    print("worker running...", end="", flush=True)
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
```

`ClientConfig.load_client_connect_config()` reads environment variables and TOML profiles, so the same code runs locally and against Temporal Cloud without changes.

## Execute a Standalone Activity

Use [`client.execute_activity()`](https://python.temporal.io/temporalio.client.Client.html#execute_activity) from application code (not from inside a Workflow Definition) to durably enqueue the Activity, wait for it to be executed on your Worker, and fetch the result.

```python
import asyncio
from datetime import timedelta

from temporalio.client import Client
from temporalio.envconfig import ClientConfig

from hello_standalone_activity.my_activity import ComposeGreetingInput, compose_greeting


async def my_application():
    connect_config = ClientConfig.load_client_connect_config()
    connect_config.setdefault("target_host", "localhost:7233")
    client = await Client.connect(**connect_config)

    activity_result = await client.execute_activity(
        compose_greeting,
        args=[ComposeGreetingInput("Hello", "World")],
        id="my-standalone-activity-id",
        task_queue="my-standalone-activity-task-queue",
        start_to_close_timeout=timedelta(seconds=10),
    )
    print(f"Activity result: {activity_result}")


if __name__ == "__main__":
    asyncio.run(my_application())
```

Or via the CLI:

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

## Start without waiting for the result

Starting a Standalone Activity sends a request to the Temporal Server to durably enqueue your Activity job, without waiting for it to be executed. Use [`client.start_activity()`](https://python.temporal.io/temporalio.client.Client.html#start_activity) to get a handle:

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

CLI equivalent:

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

## Get a handle to an existing Standalone Activity

`client.get_activity_handle()` creates a handle to a previously started Standalone Activity.

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

Use the handle to wait for the result, describe, cancel, or terminate.

## Wait for the result

Under the hood, `client.execute_activity()` is the same as `client.start_activity()` followed by `await activity_handle.result()`:

```python
activity_result = await activity_handle.result()
```

CLI:

```bash
temporal activity result --activity-id my-standalone-activity-id
```

## List Standalone Activities

[`client.list_activities()`](https://python.temporal.io/temporalio.client.Client.html#list_activities) returns an async iterator over `ActivityExecution` entries matching a List Filter. **It returns only Standalone Activity Executions — Activities running inside Workflows are not included.**

```python
import asyncio

from temporalio.client import Client
from temporalio.envconfig import ClientConfig


async def my_application():
    connect_config = ClientConfig.load_client_connect_config()
    connect_config.setdefault("target_host", "localhost:7233")
    client = await Client.connect(**connect_config)

    activities = client.list_activities(
        query="TaskQueue = 'my-standalone-activity-task-queue'",
    )

    async for info in activities:
        print(
            f"ActivityID: {info.activity_id}, Type: {info.activity_type}, Status: {info.status}"
        )


if __name__ == "__main__":
    asyncio.run(my_application())
```

The query parameter accepts the same [List Filter](/list-filter) syntax used for Workflow Visibility. Example: `"ActivityType = 'MyActivity' AND Status = 'Running'"`.

## Count Standalone Activities

[`client.count_activities()`](https://python.temporal.io/temporalio.client.Client.html#count_activities) returns the total count of executions (running, completed, failed, etc.) — **not** the number of queued tasks.

```python
import asyncio

from temporalio.client import Client
from temporalio.envconfig import ClientConfig


async def my_application():
    connect_config = ClientConfig.load_client_connect_config()
    connect_config.setdefault("target_host", "localhost:7233")
    client = await Client.connect(**connect_config)

    resp = await client.count_activities(
        query="TaskQueue = 'my-standalone-activity-task-queue'",
    )

    print("Total activities:", resp.count)

    for group in resp.groups:
        print(f"Group {group.group_values}: {group.count}")


if __name__ == "__main__":
    asyncio.run(my_application())
```

## Run with Temporal Cloud

The samples use `ClientConfig.load_client_connect_config()`, so the same code works against Temporal Cloud — configure the connection via environment variables or a TOML profile, no code changes required.

mTLS env vars:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

API key:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

## Common mistakes

1. **Calling `client.execute_activity()` from inside a Workflow Definition.** This API is for application code (starter programs, web handlers, jobs). From inside a Workflow, use `workflow.execute_activity()` instead — that's a different API.
2. **Omitting required options.** You must pass `id`, `task_queue`, and at least one of `start_to_close_timeout` / `schedule_to_close_timeout` to `execute_activity` / `start_activity`. The Python sample uses `start_to_close_timeout=timedelta(seconds=10)`.
3. **Expecting `list_activities` to include Workflow-driven Activities.** It does not.
4. **Assuming the standalone Activity shares the Workflow ID space.** Standalone Activities have a separate ID space.

