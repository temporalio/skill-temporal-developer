> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are Activities run independently of any Workflow, started directly from a Temporal Client — useful when you need a single durable, retryable task (job-queue style) and not multi-step orchestration. The same Activity method can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.

Standalone Activities are conceptually the same across all SDKs. Read the [cross-SDK concept file](references/core/standalone-activities.md) if you have not already, and then see below for the Python SDK specific APIs for calling Standalone Activities.

## Prerequisites

- Temporal Python SDK v1.23.0 or higher.
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](references/core/install_cli.md) if needed. Dev server includes Standalone Activities support.
- For production, Temporal Server v1.31.0 or higher (or Temporal Cloud).

## Hosting Activities on a Worker

The Activity is defined just as activities normally are in Temporal. Worker registration is also the same.

```python
import asyncio
import concurrent.futures

from temporalio.client import Client
from temporalio.envconfig import ClientConfig
from temporalio.worker import Worker

from my_activity import compose_greeting


async def main():
    connect_config = ClientConfig.load_client_connect_config()
    connect_config.setdefault("target_host", "localhost:7233")
    client = await Client.connect(**connect_config)
    with concurrent.futures.ThreadPoolExecutor(max_workers=100) as activity_executor:
        worker = Worker(
            client,
            task_queue="my-standalone-activity-task-queue",
            activities=[compose_greeting], # register whatever your activity(ies) is/are
            activity_executor=activity_executor,
        )
        await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
```

## Calling and managing Standalone Activities

Start and manage Standalone Activities from your application code using the Temporal Client.

### Do not call from inside a Workflow

Don't call `client.execute_activity` or `client.start_activity` or any other Standalone Activity APIs from inside a `@workflow.defn` class — for Workflow-driven activity invocation, use `workflow.execute_activity` instead.

### Connect a Client

The Standalone Activity operations are methods on a connected `Client`. The examples below assume this `client`.

```python
from temporalio.client import Client
from temporalio.envconfig import ClientConfig

connect_config = ClientConfig.load_client_connect_config()
connect_config.setdefault("target_host", "localhost:7233")
client = await Client.connect(**connect_config)
```

### Execute (await result)

Use `client.execute_activity(...)` to durably enqueue the Activity, wait for it to be executed on a Worker, and fetch the result . Required arguments per the docs: the activity function (first positional), `args=[...]`, `id`, `task_queue`, and a timeout such as `start_to_close_timeout` .

```python
from datetime import timedelta

activity_result = await client.execute_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

### Start (do not wait)

Use `client.start_activity(...)` to durably enqueue the Activity without waiting for it to be executed, and get a handle back .

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

### Get an existing handle

Use `client.get_activity_handle(...)` to create a handle to a previously started Standalone Activity .

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

The handle can be used to wait for the result, describe, cancel, or terminate the Activity .

### Await result later

`client.execute_activity()` is equivalent to `client.start_activity()` followed by `await activity_handle.result()` .

```python
activity_result = await activity_handle.result()
```

### List Standalone Activities

Use `client.list_activities(query=...)`; the result is an async iterator that yields `ActivityExecution` entries . Only Standalone Activity Executions are returned — Activities running inside Workflows are not included . The `query` parameter accepts [List Filter](/list-filter) syntax (e.g. `"ActivityType = 'MyActivity' AND Status = 'Running'"`) .

```python
activities = client.list_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

async for info in activities:
    print(f"ActivityID: {info.activity_id}, Type: {info.activity_type}, Status: {info.status}")
```

### Count Standalone Activities

Use `client.count_activities(query=...)` to count Standalone Activity Executions matching a List Filter query . The response exposes `resp.count` and `resp.groups` . This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks .

```python
resp = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

print("Total activities:", resp.count)
for group in resp.groups:
    print(f"Group {group.group_values}: {group.count}")
```
