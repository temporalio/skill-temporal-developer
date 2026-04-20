# Python SDK Standalone Activities

## Overview

A **Standalone Activity** is a top-level Activity Execution started directly by a Client, without a Workflow. Standalone Activities are Temporal's **job queue** — they let you use Temporal Activities as durable background jobs (send email, process a webhook, sync data, run one reliable function) in addition to using the same activities as steps inside a Workflow.

If you only need to execute *one* activity with retries and timeouts, a Standalone Activity is cheaper than wrapping it in a Workflow: fewer Billable Actions on Temporal Cloud, lower latency, fewer worker round-trips. If you need to orchestrate multiple activities, use a Workflow.

**Status: Pre-release.** APIs are experimental and subject to backwards-incompatible changes. Requires the [prerelease Temporal CLI](https://github.com/temporalio/cli/releases/tag/v1.6.2-standalone-activity) for `list`/`count` support.

## Key Properties

- Activity Function and Worker registration are **identical** to Workflow activities — same `@activity.defn`, same worker.
- Supports the same retry policies and timeouts as Workflow activities.
- At-least-once execution by default; at-most-once by setting retry max attempts to 1.
- Addressable by Activity ID / Run ID — can get result, cancel, terminate, or describe.
- Deduplication via conflict policy (`USE_EXISTING`, …) and reuse policy (`REJECT_DUPLICATES`, …).
- Priority and fairness scheduling (multi-tenant weighted tiers, starvation protection).
- Separate ID space from Workflows.
- Manual completion by ID / task token — ignore the return value and complete later from an external system.

## Define an Activity

Same as any activity:

```python
# my_activity.py
from dataclasses import dataclass
from temporalio import activity


@dataclass
class ComposeGreetingInput:
    greeting: str
    name: str


@activity.defn
async def compose_greeting(input: ComposeGreetingInput) -> str:
    return f"{input.greeting}, {input.name}!"
```

## Run a Worker

Same as any worker. The Worker registers the activity and polls the task queue. Standalone Activity Executions are dispatched on the same task queue as Workflow activities.

```python
import asyncio
from temporalio.client import Client
from temporalio.worker import Worker

from my_activity import compose_greeting


async def main():
    client = await Client.connect("localhost:7233")
    worker = Worker(
        client,
        task_queue="my-standalone-activity-task-queue",
        activities=[compose_greeting],
    )
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
```

## Execute a Standalone Activity

Call `client.execute_activity(...)` from application code (not from inside a Workflow). It enqueues the activity, waits for it to run on a Worker, and returns the result.

```python
import asyncio
from datetime import timedelta
from temporalio.client import Client

from my_activity import ComposeGreetingInput, compose_greeting


async def main():
    client = await Client.connect("localhost:7233")

    result = await client.execute_activity(
        compose_greeting,
        args=[ComposeGreetingInput("Hello", "World")],
        id="my-standalone-activity-id",
        task_queue="my-standalone-activity-task-queue",
        start_to_close_timeout=timedelta(seconds=10),
    )
    print(f"Activity result: {result}")


if __name__ == "__main__":
    asyncio.run(main())
```

**Required options:**
- `id` — unique Activity ID (enables deduplication and lookup).
- `task_queue`.
- At least one of `start_to_close_timeout` or `schedule_to_close_timeout`.

## Start Without Waiting + Get Handle Later

Use `client.start_activity(...)` to enqueue and return immediately, then wait on the handle (possibly from a different process):

```python
handle = await client.start_activity(
    compose_greeting,
    args=[ComposeGreetingInput("Hello", "World")],
    id="my-standalone-activity-id",
    task_queue="my-standalone-activity-task-queue",
    start_to_close_timeout=timedelta(seconds=10),
)

# Later — possibly elsewhere — reattach by ID:
handle = client.get_activity_handle("my-standalone-activity-id")

result = await handle.result()
# or: await handle.cancel() / handle.terminate() / handle.describe()
```

## List and Count

Requires the prerelease CLI; available programmatically on the client:

```python
async for info in client.list_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
):
    print(info.activity_id, info.status)

count = await client.count_activities(
    query="TaskQueue = 'my-standalone-activity-task-queue'",
)
print(count)
```

## Temporal CLI

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'

temporal activity start ...   # start, don't wait
temporal activity list  --query "TaskQueue = '...'"
temporal activity count --query "TaskQueue = '...'"
```

## When to Use

**Use a Standalone Activity when:**
- You need a single durable background job with retries/timeouts.
- You're replacing a traditional job queue (Celery, Sidekiq, SQS-worker).
- Latency matters and you don't need orchestration.

**Use a Workflow when:**
- You need to coordinate multiple activities.
- You need timers, signals, updates, child workflows, or the saga pattern.
- You need deterministic replay of orchestration state.

The same `@activity.defn` function can be invoked both ways with **zero code changes** in the activity or worker — the choice is made at the call site.

## References

- Docs: [Standalone Activities - Python SDK](https://docs.temporal.io/develop/python/standalone-activities)
- Concept: [What is a Standalone Activity?](https://docs.temporal.io/standalone-activity)
- Sample: [samples-python/hello_standalone_activity](https://github.com/temporalio/samples-python/tree/main/hello_standalone_activity)
