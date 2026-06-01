> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

# Python Standalone Activities

A Standalone Activity is a top-level Activity Execution started directly by a Temporal Client without using a Workflow , suitable for durable single-job tasks such as sending an email, processing a webhook, or syncing data . The Activity Function and Worker registration are identical to a Workflow Activity; only the invocation differs . For cross-SDK concepts and limitations, see [/standalone-activity](/standalone-activity) (`docs/encyclopedia/activities/standalone-activity.mdx`).

## Guardrail: do not call from inside a Workflow

Don't call `client.execute_activity` or `client.start_activity` from inside a `@workflow.defn` class — the docs explicitly say "Call this from your application code, not from inside a Workflow Definition."  For Workflow-driven activity invocation, use `workflow.execute_activity` instead.

## Prerequisites

- Python 3.9+
- `temporalio` v1.23.0 or higher
- Temporal CLI v1.7.0 or higher  — see [`references/core/install_cli.md`](../core/install_cli.md).
- Temporal Server v1.31.0 or higher is required for Standalone Activities . The Temporal Dev Server has Standalone Activities enabled by default for local testing .

Start a local dev server with `temporal server start-dev` .

## Worker setup

Worker registration is identical to a Workflow-Activity worker — the Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity .

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

from temporalio.client import Client
from temporalio.envconfig import ClientConfig
from temporalio.worker import Worker

from my_activity import compose_greeting


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
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
```

The Activity itself is a normal function with `@activity.defn`; it can optionally be `async def` .

## Execute (await result)

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

## Start (do not wait)

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

## Get an existing handle

Use `client.get_activity_handle(...)` to create a handle to a previously started Standalone Activity .

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

The handle can be used to wait for the result, describe, cancel, or terminate the Activity .

## Await result later

`client.execute_activity()` is equivalent to `client.start_activity()` followed by `await activity_handle.result()` .

```python
activity_result = await activity_handle.result()
```

## List Standalone Activities

Use `client.list_activities(query=...)`; the result is an async iterator that yields `ActivityExecution` entries . Only Standalone Activity Executions are returned — Activities running inside Workflows are not included . The `query` parameter accepts [List Filter](/list-filter) syntax (e.g. `"ActivityType = 'MyActivity' AND Status = 'Running'"`) .

```python
activities = client.list_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

async for info in activities:
    print(f"ActivityID: {info.activity_id}, Type: {info.activity_type}, Status: {info.status}")
```

## Count Standalone Activities

Use `client.count_activities(query=...)` to count Standalone Activity Executions matching a List Filter query . The response exposes `resp.count` and `resp.groups` . This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks .

```python
resp = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

print("Total activities:", resp.count)
for group in resp.groups:
    print(f"Group {group.group_values}: {group.count}")
```

## Temporal CLI mirror

The `temporal activity` subcommand supports Standalone Activities with: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate` . Documented invocations:

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

```bash
temporal activity result --activity-id my-standalone-activity-id
```

```bash
temporal activity list
```

```bash
temporal activity count
```

## Temporal Cloud

The same code works against Temporal Cloud because `ClientConfig.load_client_connect_config()` reads environment variables and TOML profiles, so no code changes are needed . See the "Connect with mTLS" and "Connect with an API key" environment-variable blocks in the Python SDK page for the exact variables  . Standalone Activities in Temporal Cloud are available as a Public Preview feature .

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview .
- `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are not supported yet .

