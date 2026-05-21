# Standalone Activities — Python SDK

Standalone Activities are Activities that run independently, without being orchestrated by a Workflow. Instead of starting an Activity from within a Workflow Definition, you start one directly from a Temporal Client.
<!-- docs/develop/python/activities/standalone-activities.mdx:29 -->

Temporal Python SDK support for Standalone Activities is at **Public Preview**.
<!-- docs/develop/python/activities/standalone-activities.mdx:22 -->

**Dual-use:** The way you write the Activity and register it with a Worker is identical to Workflow Activities. The only difference is that you execute a Standalone Activity directly from your Temporal Client. An Activity Function can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.
<!-- docs/develop/python/activities/standalone-activities.mdx:33-35 -->
<!-- docs/develop/python/activities/standalone-activities.mdx:140-142 -->

## Prerequisites

- **Python 3.9+**
- **Temporal Python SDK** v1.23.0 or higher (`uv add temporalio`)
- **Temporal CLI** v1.7.0 or higher
<!-- docs/develop/python/activities/standalone-activities.mdx:59-89 -->

Server requirement: Temporal Server v1.31.0 or higher (Public Preview).
<!-- VERIFY: server version not stated in the Python doc; encyclopedia page lists v1.31.0+ -->

Start a local dev server:

```bash
temporal server start-dev
```
<!-- docs/develop/python/activities/standalone-activities.mdx:93-95 -->

The Web UI is available at `http://localhost:8233`, with a Standalone Activities item in the nav bar.
<!-- docs/develop/python/activities/standalone-activities.mdx:113-114 -->

## Write an Activity Function

An Activity in the Temporal Python SDK is just a normal function with the `@activity.defn` decorator. It can optionally be an `async def`. The way you write a Standalone Activity is identical to how you write an Activity orchestrated by a Workflow.
<!-- docs/develop/python/activities/standalone-activities.mdx:139-142 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:146-163 -->

## Run a Worker with the Activity registered

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — you create a Worker, register the Activity, and run the Worker. The Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.
<!-- docs/develop/python/activities/standalone-activities.mdx:167-171 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:175-201 -->

Run the Worker:

```bash
uv run hello_standalone_activity/worker.py
```
<!-- docs/develop/python/activities/standalone-activities.mdx:206-208 -->

## Execute a Standalone Activity

Use `client.execute_activity()` to execute a Standalone Activity. Call this from your application code, not from inside a Workflow Definition. This durably enqueues your Standalone Activity in the Temporal Server, waits for it to be executed on your Worker, and then fetches the result.
<!-- docs/develop/python/activities/standalone-activities.mdx:214-218 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:222-248 -->

The kwargs shown by the doc are: `args`, `id`, `task_queue`, `start_to_close_timeout`.
<!-- docs/develop/python/activities/standalone-activities.mdx:237-243 -->

You can also execute a Standalone Activity with the Temporal CLI:

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:264-270 -->

## Start a Standalone Activity without waiting for the result

Starting a Standalone Activity means sending a request to the Temporal Server to durably enqueue your Activity job, without waiting for it to be executed by your Worker. Use `client.start_activity()` to start your Standalone Activity and get a handle.
<!-- docs/develop/python/activities/standalone-activities.mdx:275-280 -->

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:283-289 -->

CLI equivalent:

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:301-307 -->

<!-- VERIFY: the Python doc does not show ID conflict-policy / reuse-policy kwargs (e.g. USE_EXISTING, REJECT_DUPLICATES) for start_activity. Omitting policy options here; see the core Standalone Activity reference for policy semantics. -->

## Get a handle to an existing Standalone Activity

Use `client.get_activity_handle()` to create a handle to a previously started Standalone Activity:
<!-- docs/develop/python/activities/standalone-activities.mdx:311 -->

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:314-317 -->

You can use the handle to wait for the result, describe, cancel, or terminate the Activity.
<!-- docs/develop/python/activities/standalone-activities.mdx:320 -->

## Wait for the result of a Standalone Activity

Calling `client.execute_activity()` is equivalent to calling `client.start_activity()` to durably enqueue the Standalone Activity, and then calling `await activity_handle.result()` to wait for the activity to be executed and fetch the result.
<!-- docs/develop/python/activities/standalone-activities.mdx:324-327 -->

```python
activity_result = await activity_handle.result()
```
<!-- docs/develop/python/activities/standalone-activities.mdx:330 -->

CLI equivalent (wait for a result by Activity ID):

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/python/activities/standalone-activities.mdx:336 -->

## List Standalone Activities

Use `client.list_activities()` to list Standalone Activity Executions that match a List Filter query. The result is an async iterator that yields `ActivityExecution` entries. These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included.
<!-- docs/develop/python/activities/standalone-activities.mdx:341-346 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:350-373 -->

The `query` parameter accepts the same List Filter syntax used for Workflow Visibility (e.g., `"ActivityType = 'MyActivity' AND Status = 'Running'"`).
<!-- docs/develop/python/activities/standalone-activities.mdx:388-389 -->

CLI equivalent:

```bash
temporal activity list
```
<!-- docs/develop/python/activities/standalone-activities.mdx:385 -->

## Count Standalone Activities

Use `client.count_activities()` to count Standalone Activity Executions that match a List Filter query. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. It works the same way as counting Workflow Executions.
<!-- docs/develop/python/activities/standalone-activities.mdx:394-397 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:401-424 -->

CLI equivalent:

```bash
temporal activity count
```
<!-- docs/develop/python/activities/standalone-activities.mdx:436 -->

## Run Standalone Activities with Temporal Cloud

The code samples on this page use `ClientConfig.load_client_connect_config()`, so the same code works against Temporal Cloud — just configure the connection via environment variables or a TOML profile. No code changes are needed.
<!-- docs/develop/python/activities/standalone-activities.mdx:441-443 -->

### Connect with mTLS

Set these environment variables with values from your Temporal Cloud Namespace settings:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:449-458 -->

### Connect with an API key

Set these environment variables with values from your Temporal Cloud API key settings:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/python/activities/standalone-activities.mdx:460-468 -->

Then run the Worker and starter code as shown in the earlier sections.
<!-- docs/develop/python/activities/standalone-activities.mdx:470 -->
