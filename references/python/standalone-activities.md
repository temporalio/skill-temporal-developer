> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

<!-- docs/develop/python/activities/standalone-activities.mdx:24 -->

# Python Standalone Activities

A Standalone Activity is a top-level Activity Execution started directly by a Temporal Client without using a Workflow <!-- docs/encyclopedia/activities/standalone-activity.mdx:50 -->, suitable for durable single-job tasks such as sending an email, processing a webhook, or syncing data <!-- docs/encyclopedia/activities/standalone-activity.mdx:73 -->. The Activity Function and Worker registration are identical to a Workflow Activity; only the invocation differs <!-- docs/develop/python/activities/standalone-activities.mdx:33 -->. For cross-SDK concepts and limitations, see [/standalone-activity](/standalone-activity) (`docs/encyclopedia/activities/standalone-activity.mdx`).

## Guardrail: do not call from inside a Workflow

Don't call `client.execute_activity` or `client.start_activity` from inside a `@workflow.defn` class — the docs explicitly say "Call this from your application code, not from inside a Workflow Definition." <!-- docs/develop/python/activities/standalone-activities.mdx:216 --> For Workflow-driven activity invocation, use `workflow.execute_activity` instead.

## Prerequisites

- Python 3.9+ <!-- docs/develop/python/activities/standalone-activities.mdx:59 -->
- `temporalio` v1.23.0 or higher <!-- docs/develop/python/activities/standalone-activities.mdx:69 -->
- Temporal CLI v1.7.0 or higher <!-- docs/develop/python/activities/standalone-activities.mdx:75 --> — see [`references/core/install_cli.md`](../core/install_cli.md).
- Temporal Server v1.31.0 or higher is required for Standalone Activities <!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->. The Temporal Dev Server has Standalone Activities enabled by default for local testing <!-- docs/encyclopedia/activities/standalone-activity.mdx:139 -->.

Start a local dev server with `temporal server start-dev` <!-- docs/develop/python/activities/standalone-activities.mdx:94 -->.

## Worker setup

Worker registration is identical to a Workflow-Activity worker — the Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity <!-- docs/develop/python/activities/standalone-activities.mdx:167 -->.

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

<!-- docs/develop/python/activities/standalone-activities.mdx:175 -->

The Activity itself is a normal function with `@activity.defn`; it can optionally be `async def` <!-- docs/develop/python/activities/standalone-activities.mdx:139 -->.

## Execute (await result)

Use `client.execute_activity(...)` to durably enqueue the Activity, wait for it to be executed on a Worker, and fetch the result <!-- docs/develop/python/activities/standalone-activities.mdx:215 -->. Required arguments per the docs: the activity function (first positional), `args=[...]`, `id`, `task_queue`, and a timeout such as `start_to_close_timeout` <!-- docs/develop/python/activities/standalone-activities.mdx:237 -->.

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

<!-- docs/develop/python/activities/standalone-activities.mdx:237 -->

## Start (do not wait)

Use `client.start_activity(...)` to durably enqueue the Activity without waiting for it to be executed, and get a handle back <!-- docs/develop/python/activities/standalone-activities.mdx:278 -->.

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

<!-- docs/develop/python/activities/standalone-activities.mdx:283 -->

## Get an existing handle

Use `client.get_activity_handle(...)` to create a handle to a previously started Standalone Activity <!-- docs/develop/python/activities/standalone-activities.mdx:311 -->.

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

<!-- docs/develop/python/activities/standalone-activities.mdx:314 -->

The handle can be used to wait for the result, describe, cancel, or terminate the Activity <!-- docs/develop/python/activities/standalone-activities.mdx:320 -->.

## Await result later

`client.execute_activity()` is equivalent to `client.start_activity()` followed by `await activity_handle.result()` <!-- docs/develop/python/activities/standalone-activities.mdx:324 -->.

```python
activity_result = await activity_handle.result()
```

<!-- docs/develop/python/activities/standalone-activities.mdx:330 -->

## List Standalone Activities

Use `client.list_activities(query=...)`; the result is an async iterator that yields `ActivityExecution` entries <!-- docs/develop/python/activities/standalone-activities.mdx:342 -->. Only Standalone Activity Executions are returned — Activities running inside Workflows are not included <!-- docs/develop/python/activities/standalone-activities.mdx:346 -->. The `query` parameter accepts [List Filter](/list-filter) syntax (e.g. `"ActivityType = 'MyActivity' AND Status = 'Running'"`) <!-- docs/develop/python/activities/standalone-activities.mdx:388 -->.

```python
activities = client.list_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

async for info in activities:
    print(f"ActivityID: {info.activity_id}, Type: {info.activity_type}, Status: {info.status}")
```

<!-- docs/develop/python/activities/standalone-activities.mdx:362 -->

## Count Standalone Activities

Use `client.count_activities(query=...)` to count Standalone Activity Executions matching a List Filter query <!-- docs/develop/python/activities/standalone-activities.mdx:394 -->. The response exposes `resp.count` and `resp.groups` <!-- docs/develop/python/activities/standalone-activities.mdx:417 -->. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks <!-- docs/develop/python/activities/standalone-activities.mdx:396 -->.

```python
resp = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

print("Total activities:", resp.count)
for group in resp.groups:
    print(f"Group {group.group_values}: {group.count}")
```

<!-- docs/develop/python/activities/standalone-activities.mdx:413 -->

## Temporal CLI mirror

The `temporal activity` subcommand supports Standalone Activities with: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate` <!-- docs/encyclopedia/activities/standalone-activity.mdx:136 -->. Documented invocations:

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

<!-- docs/develop/python/activities/standalone-activities.mdx:264 -->

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

<!-- docs/develop/python/activities/standalone-activities.mdx:301 -->

```bash
temporal activity result --activity-id my-standalone-activity-id
```

<!-- docs/develop/python/activities/standalone-activities.mdx:336 -->

```bash
temporal activity list
```

<!-- docs/develop/python/activities/standalone-activities.mdx:385 -->

```bash
temporal activity count
```

<!-- docs/develop/python/activities/standalone-activities.mdx:436 -->

## Temporal Cloud

The same code works against Temporal Cloud because `ClientConfig.load_client_connect_config()` reads environment variables and TOML profiles, so no code changes are needed <!-- docs/develop/python/activities/standalone-activities.mdx:441 -->. See the "Connect with mTLS" and "Connect with an API key" environment-variable blocks in the Python SDK page for the exact variables <!-- docs/develop/python/activities/standalone-activities.mdx:449 --> <!-- docs/develop/python/activities/standalone-activities.mdx:460 -->. Standalone Activities in Temporal Cloud are available as a Public Preview feature <!-- docs/encyclopedia/activities/standalone-activity.mdx:143 -->.

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->.
- `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are not supported yet <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->.

## Activity context inside a Standalone Activity

<!-- VERIFY: Which `temporalio.activity.Info` fields, and which `temporalio.converter.PayloadConverter` / data-converter serialization-context fields, change nullability when the Activity runs as a Standalone Activity (no parent Workflow)? Docs are silent in `docs/encyclopedia/activities/standalone-activity.mdx` and `docs/develop/python/activities/standalone-activities.mdx` as of this authoring pass. -->
