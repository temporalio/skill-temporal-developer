# Python Workflow Streams

## Overview

`temporalio.contrib.workflow_streams` is a Python SDK library that gives a Workflow a durable, offset-addressed event channel built on Signals, Updates, and Queries. <!-- docs/develop/python/workflows/workflow-streams.mdx:22 --> It batches publishes to amortize Signal cost, deduplicates batches for exactly-once delivery to the log, supports topic filtering, and carries state across Continue-As-New. <!-- docs/develop/python/workflows/workflow-streams.mdx:23 -->

The library is in **Public Preview** today; the API may change before GA, and only the **Python** client exists — cross-language client support is on the roadmap. <!-- docs/develop/python/workflows/workflow-streams.mdx:30-37 -->

**Use it for:** outside observers following Workflow/Activity progress — UI updates for an AI agent run, status from a payment or order pipeline, intermediate results from a data job. **Not for:** ultra-low-latency cases like real-time voice, or thousands-of-subscribers fan-out (it targets tens of publishers and subscribers per Workflow). <!-- docs/develop/python/workflows/workflow-streams.mdx:25 -->

**Shape:** the Workflow hosts the event log. Publishers — the Workflow itself, Activities, or external processes via `WorkflowStreamClient` — append events. Subscribers attach to the Workflow ID, optionally filter by topic, and consume events by long-polling from an offset they store themselves. <!-- docs/develop/python/workflows/workflow-streams.mdx:27 -->

## Choose where to host the stream

A `WorkflowStream` lives inside a Workflow, so the first design choice is whether one Workflow hosts both the work and the stream, or whether a dedicated Workflow exists only to host the stream. <!-- docs/develop/python/workflows/workflow-streams.mdx:51 -->

- **Stream on the same Workflow that does the work** when the events come from what that Workflow is already orchestrating (agent run, order pipeline, chat session). The stream's lifecycle aligns with the run; the Workflow ID used to start the work is the same ID subscribers attach to. This is the common shape for AI agents and progress-streaming cases. <!-- docs/develop/python/workflows/workflow-streams.mdx:53 -->
- **Dedicated Workflow for the stream alone** when the stream should outlive any single producer, accept fan-in from unrelated sources, or be subscribable before any work has started. Producers publish from outside (Activities of other Workflows, or external `WorkflowStreamClient` instances). Trade-off: explicit lifecycle management — a dedicated stream Workflow does not terminate on its own, so you need a signal-driven shutdown or a Continue-As-New strategy. <!-- docs/develop/python/workflows/workflow-streams.mdx:55 -->

The Workflow ID is the address. Multiple subscribers can attach to the same ID concurrently. Use distinct Workflow IDs for unrelated streams rather than packing them into one Workflow. <!-- docs/develop/python/workflows/workflow-streams.mdx:57 -->

## Enable streaming on a Workflow

Construct a `WorkflowStream` from the Workflow's `@workflow.init` method. <!-- docs/develop/python/workflows/workflow-streams.mdx:61 --> Construction must happen there because the stream's handlers have to be registered before the first publish Signal arrives; constructing from `@workflow.run` raises `RuntimeError` and would miss publishes that arrived before the run body started executing. <!-- docs/develop/python/workflows/workflow-streams.mdx:61 -->

```python
from dataclasses import dataclass

from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream


@dataclass
class OrderInput:
    order_id: str


@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
```

Constructing `WorkflowStream` creates the in-memory event log and dynamically registers the publish Signal, subscribe Update, and offset Query handlers on the current Workflow. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 --> Constructing **more than one** stream on the same Workflow also raises `RuntimeError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->

If the Workflow uses Continue-As-New, see [Continue-As-New](#continue-as-new) for how to carry stream state across runs. <!-- docs/develop/python/workflows/workflow-streams.mdx:84 -->

## Publish from a Workflow

Bind a topic name to its event type once via `self.stream.topic("name", type=Type)`, then call `publish()` on the returned handle. The handle records the per-stream binding from topic name to value type so call sites don't repeat the type on every publish, and subscribers reading the same handle decode to the matching type. <!-- docs/develop/python/workflows/workflow-streams.mdx:88 -->

```python
from dataclasses import dataclass


@dataclass
class StatusEvent:
    state: str
    progress: int = 0
    detail: str = ""


@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
        self.status = self.stream.topic("status", type=StatusEvent)

    @workflow.run
    async def run(self, input: OrderInput) -> None:
        self.status.publish(StatusEvent(state="validating", detail="checking inventory"))
        await validate_order(input.order_id)

        self.status.publish(StatusEvent(state="charging", progress=33, detail="authorizing payment"))
        await charge_payment(input.order_id)

        self.status.publish(StatusEvent(state="shipping", progress=66, detail="dispatching to warehouse"))
        await dispatch_order(input.order_id)

        self.status.publish(StatusEvent(state="completed", progress=100))
```

`publish()` runs the payload converter to encode each value. The codec chain (encryption, compression, and so on) runs **once** on the Signal or Update envelope that carries the batch, never per item. <!-- docs/develop/python/workflows/workflow-streams.mdx:122 -->

The `type=` argument is optional and defaults to `Any`. Pass it to record the binding (re-binding the same name to an unequal type then raises) or so subscribers can pick up the type from the same handle. <!-- docs/develop/python/workflows/workflow-streams.mdx:124 -->

> Topics are **implicit** — they are created on first publish. There is no `register_topic()` step. <!-- docs/develop/python/workflows/workflow-streams.mdx:27 -->

## Publish from a client

Any process that has a Temporal `Client` and the target Workflow ID can publish to a Workflow's stream by constructing a `WorkflowStreamClient`. This covers HTTP backends, starters, one-off scripts, other Workflows' Activities, and standalone Activities. <!-- docs/develop/python/workflows/workflow-streams.mdx:128 -->

```python
from datetime import timedelta

from temporalio.client import Client
from temporalio.contrib.workflow_streams import WorkflowStreamClient


async def publish_status(workflow_id: str) -> None:
    temporal_client = await Client.connect("localhost:7233")
    stream_client = WorkflowStreamClient.create(
        temporal_client,
        workflow_id=workflow_id,
        batch_interval=timedelta(milliseconds=200),
    )
    async with stream_client:
        status = stream_client.topic("status", type=StatusEvent)
        status.publish(StatusEvent(state="started"))
        ...
        # Buffer is flushed on context manager exit.
```

**From inside an Activity scheduled by a Workflow,** `WorkflowStreamClient.from_within_activity()` infers the Temporal `Client` and the parent Workflow ID from the Activity context, so you don't have to thread them through the Activity's input: <!-- docs/develop/python/workflows/workflow-streams.mdx:153 -->

```python
from temporalio import activity
from temporalio.contrib.workflow_streams import WorkflowStreamClient


@activity.defn
async def stream_deltas(order_id: str) -> None:
    client = WorkflowStreamClient.from_within_activity()
    async with client:
        deltas = client.topic("delta", type=Delta)
        for delta in generate_deltas(order_id):
            deltas.publish(delta)
            activity.heartbeat()
        # Buffer is flushed on context manager exit.
```

**Standalone Activities** (started directly via `Client.start_activity` rather than from a Workflow) have no parent Workflow context, so `from_within_activity()` raises. Fall back to the general pattern with `activity.client()` and thread the target Workflow ID through the Activity's input. <!-- docs/develop/python/workflows/workflow-streams.mdx:171 -->

When events originate in an Activity, **publish from the Activity directly** rather than returning them for the Workflow to forward. The Workflow hosts the stream but does not read its own stream; it processes the Activity's return value and emits its own lifecycle events. Keeping Workflow state independent of streamed output is what lets retried Activity attempts surface to subscribers without polluting the Workflow's durable state. <!-- docs/develop/python/workflows/workflow-streams.mdx:130 -->

### `force_flush=True` vs `await client.flush()`

These two operations look similar and are not interchangeable. <!-- docs/develop/python/workflows/workflow-streams.mdx:173 -->

- **`publish(payload, force_flush=True)`** wakes the background flusher so the current buffer ships without waiting for the next interval. The call returns immediately after appending to the buffer and signaling the flusher; **it does not wait for delivery** to the Workflow or to subscribers. The flusher only runs while the client is entered (`async with client`); outside that, `force_flush=True` queues the wake event but nothing ships until you enter the context or call `await client.flush()`. <!-- docs/develop/python/workflows/workflow-streams.mdx:175 --> Use it for latency-sensitive events: the first delta of a response, or punctuated events like `RETRY` and `STATUS_CHANGE`. <!-- docs/develop/python/workflows/workflow-streams.mdx:181 -->

  ```python
  deltas.publish(delta, force_flush=True)
  ```

- **`await client.flush()`** is a mid-stream **barrier**. Successful completion is proof that the Temporal server has received all prior publications, so subsequent work that depends on those events being durable can proceed. The client stays open for further publishing afterward. Exiting `async with client` already flushes on its way out, so the explicit call is only for barriers in the middle: <!-- docs/develop/python/workflows/workflow-streams.mdx:183 -->

  ```python
  async with client:
      deltas = client.topic("delta", type=Delta)
      for delta in first_phase():
          deltas.publish(delta)

      await client.flush()
      checkpoint_id = await record_phase_one_complete()  # safe only once phase-one events are durable

      for delta in second_phase(checkpoint_id):
          deltas.publish(delta)
  ```

### No backpressure

`publish()` is non-blocking and applies no backpressure. From an Activity or other client, it appends to the client's in-memory buffer and returns; from inside a Workflow, it appends synchronously to the in-memory log (no buffer, nothing to flush). Subscribers pull from the Workflow's log on their own schedule, so a slow subscriber does not slow down publishers. If a publisher emits faster than batches can ship, the buffer grows: memory rises, the stream falls further behind real time, and at the limit Signals cannot keep up. <!-- docs/develop/python/workflows/workflow-streams.mdx:198 -->

If the application needs to bound this, apply the policy (block, drop, error, sample) **upstream** of `publish()`. The library does not pick one for you. <!-- docs/develop/python/workflows/workflow-streams.mdx:200 -->

## Subscribe

Use the same client construction as publishing — `WorkflowStreamClient.create(client, workflow_id)` or `from_within_activity()` — then iterate a topic handle's `subscribe()`. The handle's bound type drives decoding, so each `item.data` arrives as `T` via the client's payload converter. The codec chain is applied once at the Update envelope, not per item. <!-- docs/develop/python/workflows/workflow-streams.mdx:210 -->

```python
from temporalio.client import Client
from temporalio.contrib.workflow_streams import WorkflowStreamClient


async def watch_order(order_id: str) -> None:
    temporal_client = await Client.connect("localhost:7233")
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=order_id)

    status = stream.topic("status", type=StatusEvent)
    async for item in status.subscribe():
        evt = item.data
        print(f"[{evt.progress:3d}%] {evt.state}: {evt.detail}")
        if evt.state == "completed":
            break
```

The iterator handles re-polling, pagination when a poll response hits the ~1 MB cap, and Workflow-side log truncation transparently. Two edge cases: an RPC timeout where Continue-As-New cannot be followed ends the iterator silently (no exception raised), and a validator rejection during a CAN handoff can surface as a `WorkflowUpdateFailedError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:229 -->

**Subscribing from inside the host Workflow is intentionally unsupported.** The Workflow only sees the successful return value of each Activity; the stream may carry partial output from attempts that failed and were retried. Letting the Workflow read its own stream would mix those two views and break the conduit role the Workflow is meant to play. <!-- docs/develop/python/workflows/workflow-streams.mdx:206 -->

Because the Workflow is the single source of truth for stream state, any process bridging events outward (an SSE proxy, a forwarding Activity) can stay **stateless** — store the last delivered `item.offset` and reconnects resume from there without coordinating with anyone but the Workflow. <!-- docs/develop/python/workflows/workflow-streams.mdx:208 -->

### Heterogeneous topics

A topic handle binds one name to one type, so it only fits a single-type subscription. To consume multiple topics with different payload types, call `client.subscribe()` directly with a list of names (or `subscribe([])` for every topic) and pass `result_type=temporalio.common.RawValue`. Each item arrives as the underlying `Payload` wrapped in a `RawValue`; dispatch on `item.topic` and decode with the client's payload converter: <!-- docs/develop/python/workflows/workflow-streams.mdx:233 -->

```python
from temporalio.common import RawValue

converter = temporal_client.data_converter.payload_converter

async for item in stream.subscribe(["status", "progress"], result_type=RawValue):
    if item.topic == "status":
        evt = converter.from_payload(item.data.payload, StatusEvent)
        print(f"[status] {evt.state}: {evt.detail}")
    elif item.topic == "progress":
        evt = converter.from_payload(item.data.payload, ProgressEvent)
        print(f"[progress] {evt.message}")
```

A single iterator over multiple topics also avoids the cancellation race that two concurrent subscribers would create. `RawValue` is also the right shape when you want to forward bytes through to another system without decoding them. <!-- docs/develop/python/workflows/workflow-streams.mdx:249 -->

Omitting `result_type` or passing `result_type=None` decodes each item with the converter's default rules. For the stock JSON converter, that yields a Python primitive, `dict`, or `list`. That works for fully homogeneous streams, but not for the dispatch-by-topic pattern above. <!-- docs/develop/python/workflows/workflow-streams.mdx:251 -->

### Closing the stream

A subscriber's `async for` does not know when the publisher is done. End-of-stream is an **application-level** concern; Workflow Streams does not impose a marker. Without coordination, a subscriber will keep polling until the Workflow reaches a terminal state, and a Workflow that returns immediately after its last publish can lose that publish's poll round-trip in the gap. <!-- docs/develop/python/workflows/workflow-streams.mdx:255 -->

A common pattern combines two pieces: <!-- docs/develop/python/workflows/workflow-streams.mdx:257 -->

1. **In-band terminator.** The Workflow (or its Activity) publishes a sentinel event the subscriber recognizes and breaks on. `StatusEvent(state="completed")` is the minimal form. <!-- docs/develop/python/workflows/workflow-streams.mdx:259 -->
2. **Brief overlap before the Workflow returns.** A poll Update still in flight when the Workflow returns surfaces as `AcceptedUpdateCompletedWorkflow`, and no new polls can complete after that. If the Workflow returns immediately after publishing the terminator, subscribers may miss it. <!-- docs/develop/python/workflows/workflow-streams.mdx:260 -->

**Fixed sleep (simplest).** Sleep between the terminator and the return: <!-- docs/develop/python/workflows/workflow-streams.mdx:264 -->

```python
# at the end of @workflow.run
self.status.publish(StatusEvent(state="completed", progress=100))
await workflow.sleep(timedelta(seconds=30))
return result
```

A few hundred milliseconds is tight under realistic conditions; thirty seconds is a generous default. The cost is small — the Workflow Run stays open for that duration but does no other work. <!-- docs/develop/python/workflows/workflow-streams.mdx:273 -->

**Acknowledgment handshake.** The subscriber sends a Signal once it has the terminator; the Workflow waits up to a timeout and returns as soon as the ack arrives: <!-- docs/develop/python/workflows/workflow-streams.mdx:275 -->

```python
@workflow.signal
async def subscriber_acknowledged_terminator(self) -> None:
    self.subscriber_done = True

@workflow.run
async def run(self, input: ChatInput) -> str:
    ...
    try:
        await workflow.wait_condition(
            lambda: self.subscriber_done,
            timeout=timedelta(seconds=30),
        )
    except TimeoutError:
        pass  # No subscriber attached; the run still completes cleanly.
    return result
```

The timeout is still required because the subscriber may not be attached, or may have gone away. With the ack on top, the typical case exits as soon as the subscriber confirms receipt. <!-- docs/develop/python/workflows/workflow-streams.mdx:293 -->

**Inspecting terminal status.** `subscribe()` exits cleanly when the Workflow reaches `COMPLETED`, `FAILED`, `CANCELED`, `TERMINATED`, or `TIMED_OUT`, but does **not** distinguish among them. Call `await temporal_client.get_workflow_handle(workflow_id).describe()` after the loop to inspect status. <!-- docs/develop/python/workflows/workflow-streams.mdx:297 -->

## Continue-As-New {#continue-as-new}

If a Workflow runs for minutes and finishes (a single chat completion, an order pipeline, a one-shot agent), you can skip this section. CAN becomes relevant for streams that run for hours or accumulate thousands of events, where you need to roll the run over to keep history bounded. <!-- docs/develop/python/workflows/workflow-streams.mdx:301 -->

Subscribers automatically follow Continue-As-New chains. Workflow IDs are stable across CAN, so the iterator fetches a fresh handle for the same Workflow ID and continues polling from the carried offset. CAN-following requires the client retained from `WorkflowStreamClient.create()` or `from_within_activity()`; clients constructed directly with a single handle cannot re-target the new run. <!-- docs/develop/python/workflows/workflow-streams.mdx:303 -->

To roll over without subscribers seeing a gap, carry both your application state **and** the stream state. Add a `WorkflowStreamState | None` field to the Workflow input, pass it to the constructor, and call `WorkflowStream.continue_as_new(build_args)` to invoke the rollover. The helper drains waiting subscribers, waits for in-flight handlers to finish, then calls `workflow.continue_as_new` with the args produced by `build_args(post_drain_state)`: <!-- docs/develop/python/workflows/workflow-streams.mdx:305 -->

```python
from dataclasses import dataclass, field

from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream, WorkflowStreamState


@dataclass
class AppState:
    items_processed: int = 0


@dataclass
class WorkflowInput:
    app_state: AppState = field(default_factory=AppState)
    stream_state: WorkflowStreamState | None = None


@workflow.defn
class LongRunningWorkflow:
    @workflow.init
    def __init__(self, input: WorkflowInput) -> None:
        self.app_state = input.app_state
        self.stream = WorkflowStream(prior_state=input.stream_state)

    @workflow.run
    async def run(self, input: WorkflowInput) -> None:
        while True:
            await do_one_iteration(self)
            if workflow.info().is_continue_as_new_suggested():
                await self.stream.continue_as_new(
                    lambda stream_state: [
                        WorkflowInput(
                            app_state=self.app_state,
                            stream_state=stream_state,
                        )
                    ]
                )
```

The `| None` on `stream_state` is **required**: `prior_state` is `None` on a fresh start and a `WorkflowStreamState` instance after a rollover. Always use the concrete type, not `Any`. With `Any`, the data converter rebuilds the field as a plain `dict` and `WorkflowStream(prior_state=...)` raises `AttributeError` accessing `.log` / `.base_offset` / `.publishers` on the dict. <!-- docs/develop/python/workflows/workflow-streams.mdx:347 -->

For other CAN parameters (`task_queue`, `retry_policy`, `run_timeout`, …), use the explicit recipe: <!-- docs/develop/python/workflows/workflow-streams.mdx:349 -->

```python
self.stream.detach_pollers()
await workflow.wait_condition(workflow.all_handlers_finished)
workflow.continue_as_new(
    args=[WorkflowInput(app_state=self.app_state, stream_state=self.stream.get_state())],
    task_queue="other-tq",
)
```

The carried `WorkflowStreamState` includes the entire in-memory log of the previous run, so streams that carry large items can hit Temporal's per-payload size limit at the rollover. Offload bytes via External Storage so each item is a small reference, and combine with `truncate()` to keep the carried log small. <!-- docs/develop/python/workflows/workflow-streams.mdx:360 -->

## Tuning

The most important question when tuning is: how often do you want to update your UI? That drives the trade-off between user-perceived latency and the number of history events accumulated. The library defaults assume a slow-moving UI; LLM token streaming and other interactive cases need lower latency, which means tuning. <!-- docs/develop/python/workflows/workflow-streams.mdx:364 -->

Each batched publish is one Signal, and each subscriber poll is one Update. Both accumulate against Workflow history; on metered deployments, both drive billing. For long-running streams, plan a Continue-As-New policy from the start. <!-- docs/develop/python/workflows/workflow-streams.mdx:366 -->

### Settings that matter most

- **`batch_interval`** — default **2 seconds**. <!-- docs/develop/python/workflows/workflow-streams.mdx:370 --> Maximum time between automatic flushes from the client. Lower to make the stream feel live; raise to amortize Signal cost. For an LLM token stream feeding a chat UI, **200 ms** is a good starting point (a 30-second response generates roughly 150 publish Signals rather than several hundred). Below 100 ms the per-Signal RPC overhead starts to dominate. <!-- docs/develop/python/workflows/workflow-streams.mdx:370 -->

  For per-publish overrides where a specific event needs lower latency, pass `force_flush=True` on that publish (first delta of a response, or punctuated events like `RETRY`, `STATUS_CHANGE`). **Do not make this the default mode:** per-token `force_flush=True` on a 500-token completion produces 500 publish Signals — tractable but meaningful; per-character `force_flush=True` is not. <!-- docs/develop/python/workflows/workflow-streams.mdx:372 -->

### Other settings

You usually do not need to touch these. <!-- docs/develop/python/workflows/workflow-streams.mdx:376 -->

- **`max_batch_size`** — default **unbounded**. <!-- docs/develop/python/workflows/workflow-streams.mdx:378 --> Caps items per batch. With the default only `batch_interval` bounds batch size, so a hot publisher can accumulate enough between intervals that the resulting Signal exceeds Temporal's per-message gRPC payload limit. Set `max_batch_size` to bound by item count, or call `force_flush=True` after each logical chunk to bound by application boundaries. For large items, offload via External Storage so each item is a small reference.
- **`poll_cooldown`** — subscriber-side, default **100 ms**. <!-- docs/develop/python/workflows/workflow-streams.mdx:379 --> Sleep between polls. Skipped only when a poll response was capped at the ~1 MB gRPC limit and more items remain (`more_ready` flag), so the next poll can drain immediately. That path is an optimization for bursty producers; in the steady state, every poll waits the cooldown before the next. Hold a single iterator and consume from it rather than opening and closing subscriptions in a loop.
- **`max_retry_duration`** — default **10 minutes**. <!-- docs/develop/python/workflows/workflow-streams.mdx:380 --> How long the client retries a failed publish batch before giving up and raising `TimeoutError`. Tune higher if the application can tolerate longer outages; lower if you want failures to surface quickly.
- **`publisher_ttl`** — default **15 minutes**. <!-- docs/develop/python/workflows/workflow-streams.mdx:381 --> How long the Workflow retains per-publisher deduplicate state. At each Continue-As-New, entries older than this are dropped. Tune higher if publishers can be silent for extended windows.

**Keep `max_retry_duration < publisher_ttl`.** <!-- docs/develop/python/workflows/workflow-streams.mdx:383 --> A retry that outlasts its dedup record can land as a duplicate when it finally succeeds. The defaults satisfy this; if you tune one, tune the other.

## Delivery semantics

**Exactly-once at the execution layer.** Each `(publisher_id, sequence)` batch lands in the Workflow's event log at most once, even if the publisher's underlying Signal is retried by the SDK or the network. Once in the log, every subscriber that polls past its offset will see it. Deduplicate state is carried across Continue-As-New, so a retried publish that arrives after a rollover still lands at most once. <!-- docs/develop/python/workflows/workflow-streams.mdx:387 -->

> "Exactly-once at the execution layer" is **not** the same as "exactly-once to subscribers." Subscribers that handle an item and crash before persisting their next offset will reprocess that item on resume. A subscriber whose offset falls below the new base after `truncate()` is silently advanced and may re-receive items. <!-- docs/develop/python/workflows/workflow-streams.mdx:397, 419 -->

**Ordering.** The log imposes a single total order on all events, fixed once written: an event at offset N stays at offset N on every read. Within one publisher (one `WorkflowStreamClient` instance, or the Workflow itself), events appear in publish order. Across concurrent publishers, the interleaving is whatever the Workflow saw when serializing inbound Signals — stable once recorded, but **not under application control**. If event A must precede event B, publish them from the **same publisher**. <!-- docs/develop/python/workflows/workflow-streams.mdx:389 -->

**Activity retries surface to subscribers.** When an Activity that publishes events fails partway through and Temporal retries it, **both attempts' events appear in the stream**. An Activity that publishes three `TEXT_DELTA` events and then errors, then retries and publishes its full output, will deliver three partial events followed by the complete sequence. The Workflow itself sees only the successful attempt's return value, but a UI subscribed to the stream will see the partial output unless it dedupes. <!-- docs/develop/python/workflows/workflow-streams.mdx:391 -->

The conventional pattern is for an Activity that detects it's on a retry attempt to publish a `RETRY` event with `force_flush=True`, and for the consumer to clear or annotate prior-attempt output when it sees one. Treat the stream as an append-only log of attempts and let an idempotent consumer reducer reconcile them: overwrite on terminal events like `STATUS_CHANGE` or `TEXT_COMPLETE`, or reset an accumulator on a sentinel like `AGENT_START` before deltas resume. <!-- docs/develop/python/workflows/workflow-streams.mdx:393 -->

> `RETRY`, `TEXT_DELTA`, `TEXT_COMPLETE`, `STATUS_CHANGE`, and `AGENT_START` are **application-defined** event names from the doc's examples. They are not library constants. Choose names that suit your application.

**Other failure modes.** Events still in a publisher's in-memory client buffer are **lost** if the process crashes before they ship. Subscribers that handle an item and crash before persisting their next offset will reprocess that item on resume. Build consumer state with both in mind. <!-- docs/develop/python/workflows/workflow-streams.mdx:397 -->

### The dedup window

- **`publisher_ttl`** (default 15 minutes). Retention for per-publisher deduplicate state. At each Continue-As-New, entries whose `last_seen` is older than this are dropped. `last_seen` is updated on each **successful** publish (not on each retry attempt), so a publisher that retries through a long partition without success can still age out. Tune upward via `WorkflowStream.continue_as_new(publisher_ttl=...)` if publishers can be silent for extended windows. <!-- docs/develop/python/workflows/workflow-streams.mdx:401 -->
- **`max_retry_duration`** (default 10 minutes). A `WorkflowStreamClient` retries a failed batch for up to this long. If it elapses with the batch still pending, the client gives up, the pending batch is dropped, and `TimeoutError` is raised. On timeout, the dropped batch is **at-most-once**: it may or may not have reached the Workflow. Subsequent publishes resume with the next sequence. <!-- docs/develop/python/workflows/workflow-streams.mdx:402 -->

  **Caveat:** the `TimeoutError` raises from inside the background flusher task and terminates it. Until you call `await client.flush()` or exit `async with`, subsequent publishes accumulate in the buffer with no flusher to ship them. <!-- docs/develop/python/workflows/workflow-streams.mdx:404 -->

**Invariant: `max_retry_duration < publisher_ttl`.** If a publisher's retry window exceeds dedup retention, the dedup state for that publisher can age out (at the next Continue-As-New) before the retry lands. A retry that arrives after its dedup record has been pruned is treated as a fresh publish, and if the original delivery had also succeeded, the same logical batch lands twice. The defaults satisfy this; if you tune one, tune the other. <!-- docs/develop/python/workflows/workflow-streams.mdx:406 -->

## Architecture

Three pieces of machinery hide behind the user-facing API. <!-- docs/develop/python/workflows/workflow-streams.mdx:410 -->

**Append-only log inside the Workflow.** `WorkflowStream` keeps an in-memory list of `(topic, data)` entries inside Workflow state, each with a monotonically increasing global offset. Subscribers maintain their own cursor and on each long-poll receive the next range past it. Because the log lives in Workflow state, it is replay-safe and carries across Continue-As-New via `WorkflowStreamState`. <!-- docs/develop/python/workflows/workflow-streams.mdx:412 -->

Two mechanisms bound log growth, and they do different jobs: <!-- docs/develop/python/workflows/workflow-streams.mdx:414 -->

- **`truncate(up_to_offset)`** drops entries from the in-memory log (and therefore from the carried Continue-As-New payload). It does **not** remove publish Signals already recorded in history. <!-- docs/develop/python/workflows/workflow-streams.mdx:416 -->
- **Continue-As-New** starts a fresh history. This is the **only** way to shrink history; truncate alone cannot. <!-- docs/develop/python/workflows/workflow-streams.mdx:417 -->

A subscriber whose offset falls below the new base after `truncate()` is silently advanced. Internally, the poll raises `ApplicationError("TruncatedOffset")`; the Python client catches it and resets to offset 0, which the Workflow reads as "from the current base." The iterator does not raise, but the subscriber may re-receive items already in the log past the new base. Applications that depend on seeing every event exactly once must keep subscribers ahead of truncation or implement their own gap/re-delivery handling using `item.offset`. <!-- docs/develop/python/workflows/workflow-streams.mdx:419 -->

**Wire-level handlers.** The three handlers registered when you construct a `WorkflowStream` are: <!-- docs/develop/python/workflows/workflow-streams.mdx:421 -->

- `__temporal_workflow_stream_publish` — the Signal that receives batched publishes.
- `__temporal_workflow_stream_poll` — the long-poll Update that subscribers use.
- `__temporal_workflow_stream_offset` — the Query that reports the current head offset.

Poll responses are capped at roughly **1 MB** by accumulating items until the next would exceed the budget. A single item that exceeds 1 MB on its own is admitted unconditionally; offload large items via External Storage so each item is a small reference. <!-- docs/develop/python/workflows/workflow-streams.mdx:421 -->

**Batching and deduplicating.** Every batch carries a unique identifier (the client's id paired with a monotonic batch sequence number), so a Signal retried by the SDK or the network deduplicates to a single landing in the Workflow's event log. Deduplicate state is part of the Workflow's carried state, so the guarantee survives Continue-As-New (subject to `publisher_ttl`). <!-- docs/develop/python/workflows/workflow-streams.mdx:423 -->

This dedup applies at the **Signal layer**, not the Activity layer. An *Activity retry* is a different concept from a *publish retry*: when Temporal retries the Activity, the retried execution constructs a new `WorkflowStreamClient` with its own client id, so from the stream's perspective every attempt is a fresh publisher whose batches will not deduplicate against the prior attempt's. That is why retried-attempt events appear in the stream alongside the successful attempt's output. <!-- docs/develop/python/workflows/workflow-streams.mdx:425 -->

## Gotchas

- **`WorkflowStreamClient` is asyncio-only.** The buffer is mutated on the publish path and read from the flusher inside a single event loop. Don't call `publish()` from a worker thread. <!-- docs/develop/python/workflows/workflow-streams.mdx:431 -->
- **Custom handlers on the first activation.** `WorkflowStream` registers its publish-Signal handler dynamically from `__init__`, so on the very first activation a publish Signal can be queued before class-level `@workflow.signal` or `@workflow.update` handlers have run. A handler that observes state set by stream initialization in that same activation can see pre-publish state. The fix is to make the handler `async def` and `await` once before reading state. **`asyncio.sleep(0)`** is a no-op yield that suffices and adds no history events. Don't substitute `workflow.sleep(0)` — that records a timer event. Once the first activation completes, the handler is permanent and the race does not recur. <!-- docs/develop/python/workflows/workflow-streams.mdx:432 -->
- **Type bindings are not shared across publishers.** Each `WorkflowStream` and each `WorkflowStreamClient` records topic types only for its own instance. If two publishers bind the same topic name to different types, the mismatch is not caught at publish; the subscriber gets a decode error when it processes events from the mismatched publisher. <!-- docs/develop/python/workflows/workflow-streams.mdx:433 -->

## Application: Stream LLM output

An Activity calls the model and publishes deltas as they arrive; the Workflow kicks off the Activity and waits for the consumer to acknowledge end-of-stream; the consumer subscribes, accumulates the deltas, and **clears its accumulated state on `RETRY`** before continuing. The shape works for a terminal client, a desktop UI, or an SSE endpoint forwarding to a browser; whatever holds the displayed state calls `render()` to display it. <!-- docs/develop/python/workflows/workflow-streams.mdx:437 -->

If the Activity can retry, the consumer side has to account for it: a retried attempt is a fresh publisher, so its output appears in the stream alongside the previous attempt's. <!-- docs/develop/python/workflows/workflow-streams.mdx:439 -->

```python
# activity.py
from openai import AsyncOpenAI


@dataclass
class TextDelta:
    text: str


@activity.defn
async def stream_completion(prompt: str) -> str:
    stream_client = WorkflowStreamClient.from_within_activity(
        batch_interval=timedelta(milliseconds=200),
    )
    # Disable provider-side retries; let Temporal own retry policy at the Activity layer.
    openai_client = AsyncOpenAI(max_retries=0)

    async with stream_client:
        deltas = stream_client.topic("delta", type=TextDelta)
        retry = stream_client.topic("retry", type=dict)
        close = stream_client.topic("close")

        # Tell consumers an earlier attempt's deltas are stale.
        if activity.info().attempt > 1:
            retry.publish({"attempt": activity.info().attempt}, force_flush=True)

        full: list[str] = []
        first = True
        oai_stream = await openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            stream=True,
        )
        async for chunk in oai_stream:
            if not chunk.choices:
                continue
            text = chunk.choices[0].delta.content
            if not text:
                continue
            # force_flush only on the first delta so the user sees something
            # immediately; subsequent deltas batch at the 200 ms interval.
            deltas.publish(TextDelta(text=text), force_flush=first)
            first = False
            full.append(text)
        close.publish({})
    return "".join(full)
```

```python
# workflow.py
@workflow.defn
class ChatWorkflow:
    @workflow.init
    def __init__(self, input: ChatInput) -> None:
        self.stream = WorkflowStream()
        self.subscriber_done: bool = False

    @workflow.signal
    async def subscriber_acknowledged_terminator(self) -> None:
        self.subscriber_done = True

    @workflow.run
    async def run(self, input: ChatInput) -> str:
        result = await workflow.execute_activity(
            stream_completion,
            input.prompt,
            start_to_close_timeout=timedelta(minutes=5),
        )
        # With the ack on top, the typical case exits as soon as the subscriber confirms.
        try:
            await workflow.wait_condition(
                lambda: self.subscriber_done,
                timeout=timedelta(seconds=30),
            )
        except TimeoutError:
            pass  # No subscriber; the run still completes cleanly.
        return result
```

```python
# consumer.py: accumulates the model's output and resets on retry
async def stream_chat(chat_id: str) -> str:
    # Subscribe-only; no `async with` needed because the flusher only runs for publishers.
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=chat_id)
    converter = temporal_client.data_converter.payload_converter
    output: list[str] = []

    def render() -> None:
        ...  # display the accumulated output (terminal redraw, UI update, etc.)

    async for item in stream.subscribe(
        ["delta", "retry", "close"], result_type=RawValue
    ):
        if item.topic == "retry":
            # Earlier attempt's deltas are stale; drop what we've shown.
            output.clear()
            render()
        elif item.topic == "delta":
            delta = converter.from_payload(item.data.payload, TextDelta)
            output.append(delta.text)
            render()
        elif item.topic == "close":
            # Acknowledge so the Workflow can return without a sleep.
            await temporal_client.get_workflow_handle(chat_id).signal(
                ChatWorkflow.subscriber_acknowledged_terminator
            )
            break

    return "".join(output)
```

Why this shape: <!-- docs/develop/python/workflows/workflow-streams.mdx:555 -->

- The **Activity** is the publisher because it owns the non-deterministic LLM call. The Workflow processes only the Activity's return value, never reading its own stream.
- The Activity publishes a `RETRY` event when `activity.info().attempt > 1`, so the UI can clear accumulated deltas before the next attempt's deltas arrive.
- Termination uses an **ack handshake**: the consumer signals the Workflow once it has received the `close` event. The `wait_condition` timeout is the fallback when no subscriber is attached.
- `force_flush=True` is used only on the first delta and on the `RETRY` sentinel, where latency matters. Subsequent deltas batch at the 200 ms `batch_interval`.

## See also

- [`temporalio.contrib.workflow_streams` API reference](https://python.temporal.io/temporalio.contrib.workflow_streams.html) — full signatures and edge-case details.
- [Workflow Streams samples (samples-python)](https://github.com/temporalio/samples-python/tree/main/workflow_streams) — runnable scenarios covering basic publish/subscribe, reconnecting subscribers, external publishers, and bounded logs.
- `references/python/patterns.md` — Signals, Updates, Queries, and the broader message-passing primitives Workflow Streams is built on.
- `references/python/ai-patterns.md` — Pydantic data converter, OpenAI configuration, and LLM workflow patterns that pair with this library.
