# Python SDK: Workflow Streams

`temporalio.contrib.workflow_streams` gives a Workflow a durable, offset-addressed event channel built on Signals, Updates, and Queries. <!-- docs/develop/python/workflows/workflow-streams.mdx:22 --> Publishers append events, subscribers attach to a Workflow Id and consume from an offset they store. The library batches publishes, deduplicates batches for exactly-once delivery to the log, supports topic filtering, and carries state across Continue-As-New. <!-- docs/develop/python/workflows/workflow-streams.mdx:22-23 -->

**Status: Public Preview.** Only the Python client exists today; cross-language client support is on the roadmap. The API may change before GA. <!-- docs/develop/python/workflows/workflow-streams.mdx:31-37 -->

## When to use it

Reach for Workflow Streams when external observers need to follow the progress of a Workflow and its Activities: updating a UI as an AI agent works, surfacing status from a payment or order pipeline, reporting intermediate results from a data job. It is **not** suited to ultra-low-latency cases like real-time voice, and it targets modest fan-out — tens of publishers and subscribers per Workflow, not thousands. <!-- docs/develop/python/workflows/workflow-streams.mdx:25 -->

## Choose where to host the stream

The stream lives inside a Workflow, so the first design choice is whose lifecycle it shares: <!-- docs/develop/python/workflows/workflow-streams.mdx:51 -->

- **Host on the Workflow that does the work** when events come from what that Workflow is already orchestrating (agent run, order pipeline, chat session). The stream starts when the run starts and ends when it returns; subscribers attach to the same Workflow Id used to start the work. Common shape for AI agents and most progress-streaming cases. <!-- docs/develop/python/workflows/workflow-streams.mdx:53 -->
- **Dedicated stream Workflow** when the stream should outlive any single producer, accept fan-in from multiple unrelated sources, or be subscribable before any work has started. Producers publish from outside (Activities of other Workflows, or external `WorkflowStreamClient` instances). The trade-off is explicit lifecycle management — a dedicated stream Workflow does not terminate on its own, so it needs a signal-driven shutdown or Continue-As-New strategy. <!-- docs/develop/python/workflows/workflow-streams.mdx:55 -->

Either way, the Workflow Id is the subscription address. Multiple subscribers can attach concurrently (e.g., multiple browser tabs). Use distinct Workflow Ids for unrelated streams. <!-- docs/develop/python/workflows/workflow-streams.mdx:57 -->

## Enable streaming on a Workflow

Import from `temporalio.contrib.workflow_streams` and construct `WorkflowStream` inside `@workflow.init`. <!-- docs/develop/python/workflows/workflow-streams.mdx:61, 67 --> Construction must happen there because the stream's handlers have to be registered before the first publish Signal arrives; constructing from `@workflow.run` raises `RuntimeError` and would miss publishes that arrived before the run body started. <!-- docs/develop/python/workflows/workflow-streams.mdx:61 --> Constructing more than one stream on the same Workflow also raises `RuntimeError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->

```python
from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream

@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
```

Constructing `WorkflowStream` creates the in-memory event log and dynamically registers the publish Signal, the subscribe Update, and the offset Query on the current Workflow. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->

## Publish from a Workflow

Bind a topic name to its event type once via `self.stream.topic("name", type=Type)`, then call `publish()` on the returned handle. The handle records the per-stream binding so call sites do not have to repeat the type on every publish, and subscribers reading the same handle decode to the matching type. <!-- docs/develop/python/workflows/workflow-streams.mdx:88 -->

```python
@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
        self.status = self.stream.topic("status", type=StatusEvent)

    @workflow.run
    async def run(self, input: OrderInput) -> None:
        self.status.publish(StatusEvent(state="validating"))
        ...
```

Topics are **implicit** — they are created on first publish; there is no `create_topic` step. <!-- docs/develop/python/workflows/workflow-streams.mdx:27 --> The `type=` argument is optional and defaults to `Any`; pass it to make re-binding the same name to an unequal type raise, and so subscribers can pick up the type from the same handle. <!-- docs/develop/python/workflows/workflow-streams.mdx:124 -->

`publish()` runs the payload converter to encode each value. The codec chain (encryption, compression, etc.) runs once on the Signal envelope that carries the batch, never per item. <!-- docs/develop/python/workflows/workflow-streams.mdx:122 -->

## Publish from a client (Activities, HTTP backends, external scripts)

Any process holding a Temporal `Client` and the target Workflow Id can publish via `WorkflowStreamClient`. Construct it with `WorkflowStreamClient.create(client, workflow_id)` and use it as an async context manager — the buffer flushes on exit. <!-- docs/develop/python/workflows/workflow-streams.mdx:128 -->

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
        # Buffer flushed on context manager exit.
```

Inside an Activity scheduled by a Workflow, use `WorkflowStreamClient.from_within_activity()` — it infers the `Client` and the parent Workflow Id from the Activity context, so you do not have to thread them through the Activity's input. <!-- docs/develop/python/workflows/workflow-streams.mdx:153 -->

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
```

For a [standalone Activity](/develop/python/activities/standalone-activities) (started directly via `Client.start_activity` rather than from a Workflow), there is no parent Workflow context to infer, so `from_within_activity()` raises. Fall back to the general pattern with `activity.client()` and thread the Workflow Id through the Activity input. <!-- docs/develop/python/workflows/workflow-streams.mdx:171 -->

**Publish from the producer, not via Workflow forwarding.** When events originate in an Activity, publish from the Activity directly rather than returning them for the Workflow to forward. The Workflow hosts the stream but does not read it; it processes the Activity's return value and emits its own lifecycle events. Keeping Workflow state independent of streamed output is what lets retried Activity attempts surface to subscribers without polluting the Workflow's durable state. See [Delivery semantics](#delivery-semantics). <!-- docs/develop/python/workflows/workflow-streams.mdx:130 -->

### `force_flush=True` vs `await client.flush()`

Two operations give explicit control over when batches ship: <!-- docs/develop/python/workflows/workflow-streams.mdx:173 -->

- **`publish(..., force_flush=True)`** wakes the background flusher so the current buffer ships without waiting for the next interval. The flusher only runs while the client is entered (`async with client`); outside that, `force_flush=True` queues the wake event but nothing ships until you enter the context or call `await client.flush()`. The call **returns immediately after appending to the buffer and signaling the flusher** — it does not wait for delivery to the Workflow or to subscribers. <!-- docs/develop/python/workflows/workflow-streams.mdx:175 --> Use it for latency-sensitive events: the first delta of a response, punctuated events like `RETRY` or `STATUS_CHANGE`. <!-- docs/develop/python/workflows/workflow-streams.mdx:181 -->
- **`await client.flush()`** is a mid-stream barrier. Successful completion proves the Temporal server has received all prior publications, so subsequent work that depends on those events being durable can proceed. The client stays open for further publishing afterward. Exiting `async with client` already flushes on its way out, so the explicit call is only for barriers in the middle. <!-- docs/develop/python/workflows/workflow-streams.mdx:183 -->

```python
async with client:
    for delta in first_phase():
        deltas.publish(delta)
    await client.flush()
    checkpoint_id = await record_phase_one_complete()
    for delta in second_phase(checkpoint_id):
        deltas.publish(delta)
```

### Backpressure: `publish()` does not apply any

`publish()` is non-blocking. From an Activity or other client, it appends to the in-memory buffer and returns; from inside a Workflow, it appends synchronously to the in-memory log. Subscribers pull on their own schedule, so a slow subscriber does not slow down publishers. If a publisher emits faster than batches can ship to the server, the buffer grows: memory rises, the stream falls behind real time, and at the limit Signals cannot keep up at all. If you need to bound this, apply the policy (block, drop, error, sample) **upstream** of `publish()`; the library does not pick one for you. <!-- docs/develop/python/workflows/workflow-streams.mdx:198-200 -->

## Subscribe

Subscribing uses the same client construction as publishing: `WorkflowStreamClient.create(client, workflow_id)` from any process, or `from_within_activity()` inside an Activity. <!-- docs/develop/python/workflows/workflow-streams.mdx:204 -->

**Subscribing from inside the host Workflow is intentionally unsupported.** <!-- docs/develop/python/workflows/workflow-streams.mdx:206 --> The Workflow only sees the successful return value of each Activity; the stream may carry partial output from attempts that failed and were retried. Letting the Workflow read its own stream would mix those two views and break the conduit role.

The Workflow is the single source of truth for stream state, so any process bridging events to the outside world (an SSE proxy, a forwarding Activity) can stay stateless — store the last delivered `item.offset`, and reconnects resume from that offset without coordinating with anyone but the Workflow. <!-- docs/develop/python/workflows/workflow-streams.mdx:208 -->

Iterate a topic handle's `subscribe()`. The bound type drives decoding, so each `item.data` arrives as `T` via the client's payload converter. The codec chain is applied once at the Update envelope, not per item. <!-- docs/develop/python/workflows/workflow-streams.mdx:210 -->

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

The iterator handles re-polling, pagination when a poll response hits the ~1 MB cap, and Workflow-side log truncation transparently. <!-- docs/develop/python/workflows/workflow-streams.mdx:229 --> Two edge cases:

- An RPC timeout where Continue-As-New cannot be followed ends the iterator silently (no exception raised). <!-- docs/develop/python/workflows/workflow-streams.mdx:229 -->
- A validator rejection during a CAN handoff can surface as `WorkflowUpdateFailedError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:229 -->

### Heterogeneous topics

A topic handle binds one name to one type, so it only fits a single-type subscription. To consume multiple topics with different payload types, call `client.subscribe()` directly with a list of names (or `subscribe([])` for every topic) and pass `result_type=temporalio.common.RawValue` so each item arrives as the underlying `Payload` wrapped in a `RawValue`. Dispatch on `item.topic` and decode the wrapped payload with the client's payload converter: <!-- docs/develop/python/workflows/workflow-streams.mdx:233 -->

```python
from temporalio.common import RawValue

converter = temporal_client.data_converter.payload_converter

async for item in stream.subscribe(["status", "progress"], result_type=RawValue):
    if item.topic == "status":
        evt = converter.from_payload(item.data.payload, StatusEvent)
    elif item.topic == "progress":
        evt = converter.from_payload(item.data.payload, ProgressEvent)
```

A single iterator over multiple topics also avoids the cancellation race two concurrent subscribers would create. `RawValue` is the right shape when you want to forward bytes without decoding. <!-- docs/develop/python/workflows/workflow-streams.mdx:249 --> Omitting `result_type` or passing `result_type=None` decodes each item with the converter's default rules (for the stock JSON converter: a primitive, `dict`, or `list`) — works for fully homogeneous streams, not for dispatch-by-topic where each topic has its own concrete dataclass. <!-- docs/develop/python/workflows/workflow-streams.mdx:251 -->

## Closing the stream

A subscriber's `async for` does not know when the publisher is done. End-of-stream is an application-level concern; Workflow Streams does not impose a marker. Without coordination, a subscriber will keep polling until the Workflow reaches a terminal state, and a Workflow that returns immediately after its last publish can lose that publish's poll round-trip in the gap. <!-- docs/develop/python/workflows/workflow-streams.mdx:255 -->

A common pattern combines two pieces:

1. **An in-band terminator.** The Workflow (or its Activity) publishes a sentinel event the subscriber recognizes and breaks on. <!-- docs/develop/python/workflows/workflow-streams.mdx:259 -->
2. **A brief overlap before the Workflow returns.** A poll Update that is still in flight when the Workflow returns surfaces to the client as `AcceptedUpdateCompletedWorkflow`, and no new polls can complete after that. If the Workflow returns immediately after publishing the terminator, subscribers may miss it. <!-- docs/develop/python/workflows/workflow-streams.mdx:260 -->

Two ways to provide that overlap: <!-- docs/develop/python/workflows/workflow-streams.mdx:262 -->

**Fixed sleep (simplest).** Sleep between the terminator and the return:

```python
# at the end of @workflow.run
self.status.publish(StatusEvent(state="completed", progress=100))
await workflow.sleep(timedelta(seconds=30))
return result
```

A few hundred milliseconds is tight under realistic conditions; thirty seconds is a generous default. The Workflow Run stays open for that duration but does no other work. <!-- docs/develop/python/workflows/workflow-streams.mdx:273 -->

**Acknowledgment handshake.** The subscriber sends a Signal once it has the terminator; the Workflow waits up to a timeout, returning as soon as the ack arrives. The timeout is the fallback for when no subscriber is attached:

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

With the ack on top, the typical case exits as soon as the subscriber confirms receipt, regardless of fallback timeout. <!-- docs/develop/python/workflows/workflow-streams.mdx:295 -->

**Inspecting terminal status.** `subscribe()` exits cleanly when the Workflow reaches `COMPLETED`, `FAILED`, `CANCELED`, `TERMINATED`, or `TIMED_OUT`, but does not distinguish among them. To know which, call `await temporal_client.get_workflow_handle(workflow_id).describe()` after the loop returns. <!-- docs/develop/python/workflows/workflow-streams.mdx:297 -->

## Continue-As-New

Skip this section if your Workflow runs for minutes and finishes (a single chat completion, an order pipeline, a one-shot agent). Continue-As-New matters for streams that run for hours or accumulate thousands of events, where you need to roll the run over to keep history bounded. <!-- docs/develop/python/workflows/workflow-streams.mdx:301 -->

**Subscribers automatically follow Continue-As-New chains**, so a long-running Workflow can roll over without disrupting active consumers. Workflow Ids are stable across Continue-As-New; the iterator fetches a fresh handle for the same Workflow Id and continues polling from the carried offset. CAN-following requires the client retained from `WorkflowStreamClient.create()` or `from_within_activity()`; clients constructed directly with a single handle cannot re-target the new run. <!-- docs/develop/python/workflows/workflow-streams.mdx:303 -->

To roll over without subscribers seeing a gap, carry both application state and stream state across the boundary. Add a `WorkflowStreamState | None` field to the Workflow input, pass it to the constructor, and call `WorkflowStream.continue_as_new(build_args)`. The helper drains waiting subscribers, waits for in-flight handlers to finish, then calls `workflow.continue_as_new` with the args produced by `build_args(post_drain_state)`. <!-- docs/develop/python/workflows/workflow-streams.mdx:305 -->

```python
from dataclasses import dataclass, field
from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream, WorkflowStreamState

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

**The `| None` on `stream_state` is required, and the type must be `WorkflowStreamState`, not `Any`.** With `Any`, the data converter rebuilds the field as a plain `dict` and `WorkflowStream(prior_state=...)` raises `AttributeError` accessing `.log` / `.base_offset` / `.publishers`. <!-- docs/develop/python/workflows/workflow-streams.mdx:347 -->

To pass other CAN parameters (`task_queue`, `retry_policy`, `run_timeout`, ...), use the explicit recipe — the order is load-bearing: <!-- docs/develop/python/workflows/workflow-streams.mdx:349 -->

```python
self.stream.detach_pollers()
await workflow.wait_condition(workflow.all_handlers_finished)
workflow.continue_as_new(
    args=[WorkflowInput(app_state=self.app_state, stream_state=self.stream.get_state())],
    task_queue="other-tq",
)
```

**Payload-size caveat at rollover.** The carried `WorkflowStreamState` includes the entire in-memory log of the previous run, so streams that carry large items can hit Temporal's per-payload size limit at the rollover. Offload bytes via [External Storage](/external-storage) so each item is a small reference, and combine with `truncate()` to keep the carried log small. <!-- docs/develop/python/workflows/workflow-streams.mdx:360 -->

## Tuning

Each batched publish is one Signal; each subscriber poll is one Update. Both accumulate against the Workflow's history. A more responsive UI means more messages and more history per second; messages drive workload (and on metered deployments, billing), while history accumulates against Temporal's per-run limits. For long-running streams, plan a Continue-As-New policy from the start. <!-- docs/develop/python/workflows/workflow-streams.mdx:366 -->

**Settings that matter most:**

- **`batch_interval`** — default **2 seconds**. Maximum time between automatic flushes from the client. For LLM token streams feeding a chat UI, 200 ms is a good starting point. Below 100 ms the per-Signal RPC overhead starts to dominate. <!-- docs/develop/python/workflows/workflow-streams.mdx:370 -->
- **Per-publish override:** `publish(..., force_flush=True)` for one specific event that needs lower latency than the batch interval. Do not make this the default mode: per-character `force_flush=True` is not tractable. <!-- docs/develop/python/workflows/workflow-streams.mdx:372 -->

**Other settings (rarely needed):**

- **`max_batch_size`** — default **unbounded**. Caps items per batch. With the default, only `batch_interval` bounds batch size, so a hot publisher can accumulate enough items between intervals that the resulting Signal exceeds Temporal's per-message gRPC payload limit. Set `max_batch_size` to bound by item count, or call `force_flush=True` after each logical chunk to bound by application boundaries. For large items, offload via External Storage. <!-- docs/develop/python/workflows/workflow-streams.mdx:378 -->
- **`poll_cooldown`** — subscriber-side, default **100 ms**. The subscriber sleeps for this interval between polls. The cooldown is skipped only when a poll response was capped at the ~1 MB gRPC limit and more items remain. Hold a single iterator and consume from it rather than opening and closing subscriptions in a loop. <!-- docs/develop/python/workflows/workflow-streams.mdx:379 -->
- **`max_retry_duration`** — default **10 minutes**. How long the client retries a failed publish batch before giving up and raising `TimeoutError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:380 -->
- **`publisher_ttl`** — default **15 minutes**. How long the Workflow retains per-publisher deduplicate state. At each Continue-As-New, entries older than this are dropped. <!-- docs/develop/python/workflows/workflow-streams.mdx:381 -->

**Invariant: `max_retry_duration < publisher_ttl`.** A long-running retry must not outlast its dedup record — otherwise a retry that finally succeeds after the record was pruned will land twice. The defaults (10 min < 15 min) satisfy this; if you tune one, tune the other. <!-- docs/develop/python/workflows/workflow-streams.mdx:383, 406 -->

## Delivery semantics

**Exactly-once at the execution layer.** Each `(publisher_id, sequence)` batch lands in the Workflow's event log at most once, even if the publisher's underlying Signal is retried by the SDK or the network. Once an event is in the log, every subscriber that polls past its offset will see it, and deduplicate state is carried across Continue-As-New so a retried publish that arrives after a rollover still lands at most once. <!-- docs/develop/python/workflows/workflow-streams.mdx:387 --> The qualifier "at the execution layer" matters — see "Other failure modes" below for what is not covered.

**Ordering.** The log imposes a single total order on all events, fixed once written: an event at offset N stays at offset N on every read. Within one publisher (one `WorkflowStreamClient` instance, or the Workflow itself), events appear in publish order. Across concurrent publishers, the interleaving is whatever the Workflow saw when serializing inbound Signals; the order is stable once recorded but not under application control. If event A must precede event B, publish them from the same publisher. <!-- docs/develop/python/workflows/workflow-streams.mdx:389 -->

**Activity retries surface to subscribers — *both* attempts' events appear.** When an Activity that publishes events fails partway through and Temporal retries it, the partial events from the failed attempt **and** the full events from the retried attempt both appear in the stream. The Workflow itself sees only the successful attempt's return value (durable execution hides retries from the Workflow), but a UI subscribed to the stream will see the partial output unless it dedupes. **The library does not do this automatically.** <!-- docs/develop/python/workflows/workflow-streams.mdx:391 -->

The conventional pattern: an Activity that detects it is on a retry attempt publishes a `RETRY` event with `force_flush=True`, and the consumer clears or annotates prior-attempt output when it sees one. Treat the stream as an append-only log of attempts; let an idempotent consumer reducer reconcile them — overwrite on terminal events like `STATUS_CHANGE` or `TEXT_COMPLETE`, or reset an accumulator on a sentinel like `AGENT_START` before deltas resume. Because the Workflow processes only Activity return values rather than reading the stream itself, its own state stays independent of these retried events. <!-- docs/develop/python/workflows/workflow-streams.mdx:393 -->

**Other failure modes.** <!-- docs/develop/python/workflows/workflow-streams.mdx:397 -->

- Events still in a publisher's in-memory client buffer are **lost** if the process crashes before they ship.
- Subscribers that handle an item and crash before persisting their next offset will **reprocess** that item on resume. Build consumer state with both in mind.

**Two limits on the deduplication window:** <!-- docs/develop/python/workflows/workflow-streams.mdx:399 -->

- **`publisher_ttl`** (default 15 minutes). Retention for the per-publisher deduplicate state. At each Continue-As-New, entries whose `last_seen` is older than this are dropped. `last_seen` updates on each *successful* publish (not on each retry attempt), so a publisher that retries through a long partition without success can still age out. A publisher that returns after a longer pause may produce a duplicate. <!-- docs/develop/python/workflows/workflow-streams.mdx:401 -->
- **`max_retry_duration`** (default 10 minutes). A `WorkflowStreamClient` retries a failed batch for up to this long. If the duration elapses with the batch still pending (sustained network partition, for example), the client gives up, the pending batch is dropped, and a `TimeoutError` is raised. On timeout, the dropped batch is **at-most-once**: it may or may not have reached the Workflow. Subsequent publishes resume cleanly with the next sequence. <!-- docs/develop/python/workflows/workflow-streams.mdx:402 -->

**Operational caveat on `TimeoutError`.** The exception raises from inside the background flusher task and terminates it. Until you call `await client.flush()` or exit the `async with` block, subsequent publishes accumulate in the buffer with no flusher to ship them. <!-- docs/develop/python/workflows/workflow-streams.mdx:404 -->

## Architecture

Three pieces of machinery worth understanding when tuning throughput, debugging delivery, or reasoning about history size: <!-- docs/develop/python/workflows/workflow-streams.mdx:410 -->

**Append-only log inside the Workflow.** `WorkflowStream` keeps an in-memory list of `(topic, data)` entries inside the Workflow's state, each with a monotonically increasing global offset. Subscribers maintain their own cursor and on each long-poll receive the next range past it. Because the log lives in Workflow state, it is replay-safe and is carried across Continue-As-New via `WorkflowStreamState`. <!-- docs/develop/python/workflows/workflow-streams.mdx:412 -->

Two mechanisms bound log growth — and they do different jobs:

- **`truncate(up_to_offset)`** drops entries from the in-memory log (and from the carried CAN payload). It **does not** remove publish Signals already recorded in history. <!-- docs/develop/python/workflows/workflow-streams.mdx:416 -->
- **Continue-As-New** starts a fresh history. **Only Continue-As-New shrinks history**; `truncate()` alone cannot. <!-- docs/develop/python/workflows/workflow-streams.mdx:417 -->

A subscriber whose offset falls below the new base after a `truncate()` is silently advanced. Internally, the poll raises `ApplicationError("TruncatedOffset")`; the Python client catches it and resets to offset 0, which the Workflow reads as "from the current base." The iterator does not raise, but the subscriber may re-receive items already in the log past the new base. Applications that depend on seeing every event exactly once must keep subscribers ahead of truncation or implement their own gap and re-delivery handling using `item.offset`. <!-- docs/develop/python/workflows/workflow-streams.mdx:419 -->

**Wire-level handlers.** Three reserved names are registered when you construct a `WorkflowStream`: `__temporal_workflow_stream_publish` (the Signal that receives batched publishes), `__temporal_workflow_stream_poll` (the long-poll Update that subscribers use), and `__temporal_workflow_stream_offset` (the Query that reports the current head offset). Poll responses are capped at roughly **1 MB** by accumulating items until the next would exceed the budget. A single item that exceeds 1 MB on its own is admitted unconditionally; offload large items via External Storage. <!-- docs/develop/python/workflows/workflow-streams.mdx:421 -->

**Batching and deduplicating.** Every batch carries a unique identifier (the client's id paired with a monotonic batch sequence number), so a Signal retried by the SDK or the network deduplicates to a single landing in the Workflow's event log. Deduplicate state is carried across Continue-As-New (subject to `publisher_ttl`). <!-- docs/develop/python/workflows/workflow-streams.mdx:423 -->

This dedup applies at the **Signal layer**, not the **Activity layer**. An *Activity retry* is a different concept from a *publish retry*: when Temporal retries the Activity, the retried execution constructs a new `WorkflowStreamClient` with its own client id, so from the stream's perspective every attempt is a fresh publisher whose batches will not deduplicate against the prior attempt's. That is why retried-attempt events appear in the stream alongside the successful attempt's output. <!-- docs/develop/python/workflows/workflow-streams.mdx:425 -->

## Gotchas

- **`WorkflowStreamClient` is asyncio-only.** The client buffer is mutated on the publish path and read from the flusher inside a single event loop. Do not call `publish()` from a worker thread. <!-- docs/develop/python/workflows/workflow-streams.mdx:431 -->
- **Custom handlers reading stream state on the first activation.** `WorkflowStream` registers its publish-Signal handler dynamically from `__init__`, so on the very first activation a publish Signal can be queued before class-level `@workflow.signal` or `@workflow.update` handlers have run. A handler that observes state set by stream initialization in that same activation can see pre-publish state. Make the handler `async def` and `await` once before reading state — `asyncio.sleep(0)` is a no-op yield that suffices and adds no history events. Do **not** substitute `workflow.sleep(0)`, which records a timer event. The race does not recur after the first activation completes. <!-- docs/develop/python/workflows/workflow-streams.mdx:432 -->
- **Type bindings aren't shared across publishers.** Each `WorkflowStream` and each `WorkflowStreamClient` records topic types only for its own instance. If two publishers bind the same topic name to different types, the mismatch is not caught at publish; the subscriber gets a decode error when it processes events from the mismatched publisher. <!-- docs/develop/python/workflows/workflow-streams.mdx:433 -->

## Application: Stream LLM output

A worked end-to-end pattern from the docs page. <!-- docs/develop/python/workflows/workflow-streams.mdx:435 --> The Activity publishes deltas as they arrive; the Workflow kicks off the Activity and waits for the consumer to acknowledge end-of-stream; the consumer subscribes, accumulates the deltas, and clears its accumulated state on `RETRY` before continuing.

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
# consumer.py
async def stream_chat(chat_id: str) -> str:
    # Subscribe-only; no `async with` needed because the flusher only runs for publishers.
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=chat_id)
    converter = temporal_client.data_converter.payload_converter
    output: list[str] = []

    async for item in stream.subscribe(
        ["delta", "retry", "close"], result_type=RawValue
    ):
        if item.topic == "retry":
            output.clear()  # Earlier attempt's deltas are stale.
        elif item.topic == "delta":
            delta = converter.from_payload(item.data.payload, TextDelta)
            output.append(delta.text)
        elif item.topic == "close":
            await temporal_client.get_workflow_handle(chat_id).signal(
                ChatWorkflow.subscriber_acknowledged_terminator
            )
            break

    return "".join(output)
```

Deliberate choices in this shape: <!-- docs/develop/python/workflows/workflow-streams.mdx:555 -->

- The Activity is the publisher because it owns the non-deterministic LLM call; the Workflow processes only the Activity's return value.
- The Activity publishes a `RETRY` event when `activity.info().attempt > 1` so the UI can clear accumulated deltas before the next attempt arrives.
- Termination uses an *ack handshake*: the consumer signals once it has `close`; the `wait_condition` timeout is the fallback when no subscriber is attached.
- `force_flush=True` only on the first delta and on `RETRY`; per-delta would generate one Signal per token.

## See also

- [`temporalio.contrib.workflow_streams` API reference](https://python.temporal.io/temporalio.contrib.workflow_streams.html) <!-- docs/develop/python/workflows/workflow-streams.mdx:565 -->
- [Workflow Streams samples (samples-python)](https://github.com/temporalio/samples-python/tree/main/workflow_streams) — basic publish/subscribe, reconnecting subscriber, external publisher, bounded log. <!-- docs/develop/python/workflows/workflow-streams.mdx:564 -->
- `references/python/patterns.md` — Signals, Updates, and Queries (the primitives Workflow Streams is built on).
- `references/python/ai-patterns.md` — broader LLM-on-Temporal patterns.
