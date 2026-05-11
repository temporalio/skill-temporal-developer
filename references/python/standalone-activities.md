# Python: Standalone Activities

Standalone Activities run independently of any Workflow. Instead of starting an Activity from inside a Workflow Definition, you start it directly from a Temporal Client. The way you author the Activity function and register it with a Worker is identical to Workflow Activities — the only difference is how it is executed.

<!-- Sources: docs/develop/python/activities/standalone-activities.mdx:29-35 -->

## Prerequisites

- **Python 3.9+** <!-- docs/develop/python/activities/standalone-activities.mdx:59 -->
- **Temporal Python SDK** (`temporalio`) v1.23.0 or higher <!-- docs/develop/python/activities/standalone-activities.mdx:69 -->
- **Temporal CLI** v1.7.0 or higher <!-- docs/develop/python/activities/standalone-activities.mdx:75 -->
- Release stage: Public Preview <!-- docs/develop/python/activities/standalone-activities.mdx:24-25 -->

## Define an Activity

An Activity is a normal Python function annotated with `@activity.defn`; it may be `async def` or a regular function. The same Activity can be executed as either a Standalone Activity or a Workflow Activity.

<!-- Sources: docs/develop/python/activities/standalone-activities.mdx:139-142 -->

```python
from temporalio import activity

@activity.defn
def compose_greeting(input: ComposeGreetingInput) -> str:
    activity.logger.info("Running activity with parameter %s" % input)
    return f"{input.greeting}, {input.name}!"
```

<!-- docs/develop/python/activities/standalone-activities.mdx:159-163 -->

## Run a Worker

A Worker that serves Standalone Activities is set up the same way as a Worker for Workflow Activities: create a `Worker`, register the Activity, and run it. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

<!-- Sources: docs/develop/python/activities/standalone-activities.mdx:167-171 -->

```python
from temporalio.client import Client
from temporalio.worker import Worker

client = await Client.connect("localhost:7233")
worker = Worker(
    client,
    task_queue="my-standalone-activity-task-queue",
    activities=[compose_greeting],
)
await worker.run()
```

<!-- docs/develop/python/activities/standalone-activities.mdx:190-197 -->

## Execute a Standalone Activity

Use `client.execute_activity()` <!-- docs/develop/python/activities/standalone-activities.mdx:215 --> to durably enqueue the Activity, wait for it to run on a Worker, and fetch the result. Call this from application code, not from a Workflow Definition.

```python
activity_result = await client.execute_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)
```

Parameters shown:

- The Activity function (or its registered name) <!-- docs/develop/python/activities/standalone-activities.mdx:238 -->
- `args=` <!-- docs/develop/python/activities/standalone-activities.mdx:239 -->
- `id=` <!-- docs/develop/python/activities/standalone-activities.mdx:240 -->
- `task_queue=` <!-- docs/develop/python/activities/standalone-activities.mdx:241 -->
- `start_to_close_timeout=` <!-- docs/develop/python/activities/standalone-activities.mdx:242 -->

## Start without waiting for the result

Use `client.start_activity()` <!-- docs/develop/python/activities/standalone-activities.mdx:279 --> to durably enqueue the Activity and return a handle without waiting for execution.

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

## Get a handle to an existing Standalone Activity

Use `client.get_activity_handle()` <!-- docs/develop/python/activities/standalone-activities.mdx:311 --> to construct a handle to a previously started Standalone Activity by `activity_id` and `run_id`.

```python
activity_handle = client.get_activity_handle(
    activity_id="my-standalone-activity-id",
    run_id="the-run-id",
)
```

<!-- docs/develop/python/activities/standalone-activities.mdx:314-317 -->

With a handle you can wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/python/activities/standalone-activities.mdx:320 -->

## Wait for the result

Await `activity_handle.result()` to fetch the result of an Activity started via `start_activity()` or `get_activity_handle()`. Under the hood, `client.execute_activity()` is equivalent to `start_activity()` followed by `await activity_handle.result()`.

<!-- Sources: docs/develop/python/activities/standalone-activities.mdx:324-330 -->

```python
activity_result = await activity_handle.result()
```

<!-- docs/develop/python/activities/standalone-activities.mdx:330 -->

## List Standalone Activities

Use `client.list_activities(query=...)` <!-- docs/develop/python/activities/standalone-activities.mdx:342 --> to list Standalone Activity Executions matching a List Filter query. The return value is an async iterator that yields ActivityExecution entries. <!-- docs/develop/python/activities/standalone-activities.mdx:343-344 -->

These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included. <!-- docs/develop/python/activities/standalone-activities.mdx:346 -->

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

The `query` parameter accepts the same List Filter syntax used for Workflow Visibility, for example `"ActivityType = 'MyActivity' AND Status = 'Running'"`. <!-- docs/develop/python/activities/standalone-activities.mdx:388-389 -->

## Count Standalone Activities

Use `client.count_activities(query=...)` <!-- docs/develop/python/activities/standalone-activities.mdx:394 --> to count Standalone Activity Executions matching a List Filter query. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. <!-- docs/develop/python/activities/standalone-activities.mdx:395-397 -->

```python
resp = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)

print("Total activities:", resp.count)

for group in resp.groups:
    print(f"Group {group.group_values}: {group.count}")
```

<!-- docs/develop/python/activities/standalone-activities.mdx:413-420 -->

## CLI equivalents

The Temporal CLI mirrors the Standalone Activity Client APIs.

Execute and wait for a result: <!-- docs/develop/python/activities/standalone-activities.mdx:264-270 -->

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

Start without waiting: <!-- docs/develop/python/activities/standalone-activities.mdx:301-307 -->

```bash
temporal activity start \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

Fetch a result by Activity ID: <!-- docs/develop/python/activities/standalone-activities.mdx:336 -->

```bash
temporal activity result --activity-id my-standalone-activity-id
```

List and count: <!-- docs/develop/python/activities/standalone-activities.mdx:385,436 -->

```bash
temporal activity list
temporal activity count
```

## Temporal Cloud

All Python examples on the source page use `ClientConfig.load_client_connect_config()` <!-- docs/develop/python/activities/standalone-activities.mdx:103 -->, which responds to environment variables and TOML configuration files, so the same code runs against a local dev server and Temporal Cloud without changes. <!-- docs/develop/python/activities/standalone-activities.mdx:104-108 -->

Connect with mTLS — set: <!-- docs/develop/python/activities/standalone-activities.mdx:449-458 -->

```
TEMPORAL_ADDRESS
TEMPORAL_NAMESPACE
TEMPORAL_TLS_CLIENT_CERT_PATH
TEMPORAL_TLS_CLIENT_KEY_PATH
```

Connect with an API key — set: <!-- docs/develop/python/activities/standalone-activities.mdx:461-468 -->

```
TEMPORAL_ADDRESS
TEMPORAL_NAMESPACE
TEMPORAL_API_KEY
```

## See also

For conceptual background, version compatibility matrix, the full CLI subcommand inventory, and known limitations of Standalone Activities (including which operations such as Pause/Unpause/Reset/Update-Options are supported), see `references/core/standalone-activities.md`.
