# Standalone Activities — Python SDK

## Overview

Standalone Activities are Activities that run independently, without being orchestrated by a Workflow. <!-- docs/develop/python/activities/standalone-activities.mdx:29-31 --> Instead of starting an Activity from within a Workflow Definition, you start a Standalone Activity directly from a Temporal Client. <!-- docs/develop/python/activities/standalone-activities.mdx:29-31 --> The way you write the Activity and register it with a Worker is identical to Workflow Activities; the only difference is that you execute a Standalone Activity directly from your Temporal Client. <!-- docs/develop/python/activities/standalone-activities.mdx:33-35 -->

## Support stage and minimum versions

- Support: **Public Preview**. <!-- docs/develop/python/activities/standalone-activities.mdx:22-27 -->
- Temporal Python SDK: **v1.23.0 or higher**. <!-- docs/develop/python/activities/standalone-activities.mdx:69 -->
- Python: **3.9+**. <!-- docs/develop/python/activities/standalone-activities.mdx:59 -->
- Temporal CLI (for the equivalent commands shown below): **v1.7.0 or higher**. <!-- docs/develop/python/activities/standalone-activities.mdx:75 -->

## Write the Activity

An Activity in the Python SDK is a normal function decorated with `@activity.defn`. <!-- docs/develop/python/activities/standalone-activities.mdx:139-140 --> It can optionally be an `async def`. <!-- docs/develop/python/activities/standalone-activities.mdx:140 --> An Activity can be executed both as a Standalone Activity and as a Workflow Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:141-142 -->

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

## Worker

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — you create a Worker, register the Activity, and run the Worker. <!-- docs/develop/python/activities/standalone-activities.mdx:167-169 --> The Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:169 -->

For sync (non-`async`) Activities, supply an `activity_executor=ThreadPoolExecutor(...)` to the Worker. <!-- docs/develop/python/activities/standalone-activities.mdx:194 -->

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
<!-- docs/develop/python/activities/standalone-activities.mdx:175-202 -->

## Execute a Standalone Activity

Use `client.execute_activity()` to execute a Standalone Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:214-215 --> Call this from your application code, not from inside a Workflow Definition. <!-- docs/develop/python/activities/standalone-activities.mdx:216 --> It durably enqueues the Standalone Activity in the Temporal Server, waits for it to be executed on your Worker, and then fetches the result. <!-- docs/develop/python/activities/standalone-activities.mdx:217-218 -->

```python
activity_result = await client.execute_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:237-243 -->

## Start without waiting for the result

Starting a Standalone Activity sends a request to the Temporal Server to durably enqueue your Activity job, without waiting for it to be executed by your Worker. <!-- docs/develop/python/activities/standalone-activities.mdx:275-276 --> Use `client.start_activity()` to start your Standalone Activity and get a handle. <!-- docs/develop/python/activities/standalone-activities.mdx:278-280 -->

```python
activity_handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:283-290 -->

## Get a handle to an existing Standalone Activity

Use `client.get_activity_handle()` to create a handle to a previously started Standalone Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:311 -->

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:314-317 -->

You can use the handle to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:320 -->

## Wait for the result

Under the hood, calling `client.execute_activity()` is the same as calling `client.start_activity()` to durably enqueue the Standalone Activity, and then calling `await activity_handle.result()` to wait for the activity to be executed and fetch the result. <!-- docs/develop/python/activities/standalone-activities.mdx:324-327 -->

```python
activity_result = await activity_handle.result()
```
<!-- docs/develop/python/activities/standalone-activities.mdx:330 -->

## List Standalone Activities

Use `client.list_activities()` to list Standalone Activity Executions that match a List Filter query. <!-- docs/develop/python/activities/standalone-activities.mdx:341-343 --> The result is an async iterator that yields `ActivityExecution` entries. <!-- docs/develop/python/activities/standalone-activities.mdx:343-344 -->

These APIs return only Standalone Activity Executions; Activities running inside Workflows are not included. <!-- docs/develop/python/activities/standalone-activities.mdx:346 -->

```python
activities = client.list_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

async for info in activities:
    print(
        f"ActivityID: {info.activity_id}, Type: {info.activity_type}, Status: {info.status}"
    )
```
<!-- docs/develop/python/activities/standalone-activities.mdx:362-369 -->

The `query` parameter accepts the same List Filter syntax used for Workflow Visibility, for example, `"ActivityType = 'MyActivity' AND Status = 'Running'"`. <!-- docs/develop/python/activities/standalone-activities.mdx:388-389 -->

## Count Standalone Activities

Use `client.count_activities()` to count Standalone Activity Executions that match a List Filter query. <!-- docs/develop/python/activities/standalone-activities.mdx:394-395 --> This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. <!-- docs/develop/python/activities/standalone-activities.mdx:395-396 -->

```python
resp = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

print("Total activities:", resp.count)

for group in resp.groups:
    print(f"Group {group.group_values}: {group.count}")
```
<!-- docs/develop/python/activities/standalone-activities.mdx:413-420 -->

The response exposes a total `resp.count` and a `resp.groups` collection, where each group has `group_values` and `count` attributes. <!-- docs/develop/python/activities/standalone-activities.mdx:417-420 -->

## CLI parity

Each major SDK action has an equivalent `temporal activity` command. Examples below use the same task queue and Activity ID as the SDK snippets above.

Execute and wait for the result: <!-- docs/develop/python/activities/standalone-activities.mdx:261-270 --> <!-- docs/cli/activity.mdx -->

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:264-270 -->

Start without waiting: <!-- docs/develop/python/activities/standalone-activities.mdx:298-307 --> <!-- docs/cli/activity.mdx -->

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:301-307 -->

Wait for a result by Activity ID: <!-- docs/develop/python/activities/standalone-activities.mdx:333-337 --> <!-- docs/cli/activity.mdx -->

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/python/activities/standalone-activities.mdx:336 -->

List Standalone Activities: <!-- docs/develop/python/activities/standalone-activities.mdx:382-386 --> <!-- docs/cli/activity.mdx -->

```bash
temporal activity list
```
<!-- docs/develop/python/activities/standalone-activities.mdx:385 -->

Count Standalone Activities: <!-- docs/develop/python/activities/standalone-activities.mdx:433-437 --> <!-- docs/cli/activity.mdx -->

```bash
temporal activity count
```
<!-- docs/develop/python/activities/standalone-activities.mdx:436 -->

## Connect via environment / TOML config

All code samples use `ClientConfig.load_client_connect_config()` to configure the Temporal Client connection. <!-- docs/develop/python/activities/standalone-activities.mdx:102-104 --> It responds to environment variables and TOML configuration files, so the same code works against a local dev server and Temporal Cloud without changes. <!-- docs/develop/python/activities/standalone-activities.mdx:104-108 -->

```python
connect_config = ClientConfig.load_client_connect_config()
connect_config.setdefault("target_host", "localhost:7233")
client = await Client.connect(**connect_config)
```
<!-- docs/develop/python/activities/standalone-activities.mdx:187-189 -->

For Temporal Cloud, set environment variables with values from your Cloud Namespace settings — either mTLS or API key — then run the same Worker and starter code shown above. <!-- docs/develop/python/activities/standalone-activities.mdx:441-470 -->

mTLS environment variables: <!-- docs/develop/python/activities/standalone-activities.mdx:449-458 -->

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/python/activities/standalone-activities.mdx:454-458 -->

API key environment variables: <!-- docs/develop/python/activities/standalone-activities.mdx:460-468 -->

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/python/activities/standalone-activities.mdx:465-468 -->

## Notes

- A handle obtained from `client.get_activity_handle()` can be used to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:320 --> The docs page covers only those handle operations.
- Because Standalone Activities run without a Workflow, no parent Workflow exists; workflow-related fields are absent in the Activity context. <!-- VERIFY --> Open question: the docs page does not state explicit field-level nullability behavior for Activity Info / serialization context — confirm against SDK reference before relying on specific field names.
