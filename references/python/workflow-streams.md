# Workflow Streams (Python)

`temporalio.contrib.workflow_streams` is a public-preview Python SDK library that gives a Workflow a durable, offset-addressed event channel built on Signals, Updates, and Queries. <!-- docs/develop/python/workflows/workflow-streams.mdx:22 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:31-33 --> It batch-publishes events, deduplicates batches for exactly-once delivery to the log, supports topic filtering, and carries state across Continue-As-New. <!-- docs/develop/python/workflows/workflow-streams.mdx:23 -->

The API may change before general availability. Only the Python client is available today; cross-language client support is on the roadmap. <!-- docs/develop/python/workflows/workflow-streams.mdx:35-37 -->

## When to use it

Use Workflow Streams when outside observers need to follow Workflow/Activity progress: updating a UI as an AI agent works, surfacing status from a payment or order pipeline, or reporting intermediate results from a data job. It is **not suited to ultra-low-latency cases like real-time voice**, and it targets modest fan-out — tens of publishers and subscribers per Workflow, not thousands. <!-- docs/develop/python/workflows/workflow-streams.mdx:25 -->

If you only need Signals/Queries/Updates as primitives, use them directly — see `references/python/patterns.md`. If you need LLM/Pydantic plumbing around the streaming Activity, see `references/python/ai-patterns.md`.

## Mental model

- **The Workflow hosts the event log.** It is an in-memory append-only list of `(topic, data)` entries inside Workflow state, each with a monotonically increasing global offset. <!-- docs/develop/python/workflows/workflow-streams.mdx:412 -->
- **Publishers append** — the Workflow itself, Activities, or any external process holding a Temporal `Client` (via `WorkflowStreamClient`). <!-- docs/develop/python/workflows/workflow-streams.mdx:27 -->
- **Subscribers long-poll** from an offset they store, optionally filtered by topic. <!-- docs/develop/python/workflows/workflow-streams.mdx:27 -->
- **Topics are implicit** — a topic is created on first publish; there is no `register_topic` or `create_topic`. <!-- docs/develop/python/workflows/workflow-streams.mdx:27 -->
- The Workflow ID is the address subscribers use. Multiple subscribers can attach concurrently — the normal case for a UI with several browser tabs. Use distinct Workflow IDs for unrelated streams. <!-- docs/develop/python/workflows/workflow-streams.mdx:57 -->

## Choose where to host the stream

Two shapes, mostly differing in lifecycle: <!-- docs/develop/python/workflows/workflow-streams.mdx:51 -->

| Shape | Use when | Lifecycle |
|---|---|---|
| Stream on the working Workflow | Events come from the same orchestration (agent run, order pipeline, chat session). | Aligned with the run; ends when `run()` returns. |
| Dedicated stream Workflow | Stream must outlive any one producer, accept fan-in from unrelated sources, or be subscribable before work starts. | Explicit shutdown required — Signal-driven termination or a Continue-As-New strategy. |

<!-- docs/develop/python/workflows/workflow-streams.mdx:53 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:55 -->

## Enable streaming on a Workflow

Construct `WorkflowStream` from `@workflow.init`. **Construction from `@workflow.run` raises `RuntimeError`** because the stream's handlers must be registered before the first publish Signal arrives. <!-- docs/develop/python/workflows/workflow-streams.mdx:61 --> Constructing more than one `WorkflowStream` on the same Workflow also raises `RuntimeError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->

```python
from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream

@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
```

Constructing `WorkflowStream` dynamically registers three handlers on the Workflow: the publish Signal, the subscribe Update, and an offset Query. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->

If your Workflow uses Continue-As-New, see [Continue-As-New](#continue-as-new) below.

## Publish from a Workflow

Bind a topic with `stream.topic(name, type=Type)` once, then call `publish()` on the returned handle. The handle records the per-stream binding from topic name to value type so callers don't repeat the type on every publish, and so subscribers reading the same handle decode to the matching type. The `type=` argument is optional and defaults to `Any`. <!-- docs/develop/python/workflows/workflow-streams.mdx:88 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:124 -->

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

Inside a Workflow, `publish()` appends synchronously to the in-memory log — there is no buffer and nothing to flush. <!-- docs/develop/python/workflows/workflow-streams.mdx:198 --> The payload converter encodes each value; the codec chain (encryption, compression, …) runs once per Signal envelope, never per item. <!-- docs/develop/python/workflows/workflow-streams.mdx:122 -->

## Publish from a client

Any process with a Temporal `Client` and the target Workflow ID can publish via `WorkflowStreamClient`. This is the general pattern — HTTP backends, starters, other Workflows' Activities, standalone Activities. <!-- docs/develop/python/workflows/workflow-streams.mdx:128 -->

```python
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
        # Buffer is flushed on context manager exit.
```

### `from_within_activity()` — Workflow-scheduled Activities only

Inside an Activity scheduled by a Workflow, `WorkflowStreamClient.from_within_activity()` infers the Temporal `Client` and the parent Workflow ID from the Activity context, so you don't have to thread them through the Activity's input: <!-- docs/develop/python/workflows/workflow-streams.mdx:153 -->

```python
@activity.defn
async def stream_deltas(order_id: str) -> None:
    client = WorkflowStreamClient.from_within_activity()
    async with client:
        deltas = client.topic("delta", type=Delta)
        for delta in generate_deltas(order_id):
            deltas.publish(delta)
            activity.heartbeat()
```

**Standalone Activities (`Client.start_activity`) have no parent Workflow context — `from_within_activity()` raises there.** Fall back to `WorkflowStreamClient.create(activity.client(), workflow_id=...)` with the target Workflow Id threaded through the Activity's input. <!-- docs/develop/python/workflows/workflow-streams.mdx:171 --> For background on standalone Activities, see `references/python/advanced-features.md` and the doc at `docs/develop/python/activities/standalone-activities.mdx`.

### When events come from an Activity, publish from the Activity

Don't return events for the Workflow to forward. The Workflow hosts the stream but does not read its own stream; it processes the Activity's return value and emits its own lifecycle events. Keeping Workflow state independent of streamed output is what lets retried Activity attempts surface to subscribers without polluting the Workflow's durable state — see [Delivery semantics](#delivery-semantics). <!-- docs/develop/python/workflows/workflow-streams.mdx:130 -->

### `force_flush=True` vs `await client.flush()`

These are two different operations: <!-- docs/develop/python/workflows/workflow-streams.mdx:173 -->

- **`publish(..., force_flush=True)`** wakes the background flusher so the current buffer ships without waiting for the next `batch_interval`. The call returns immediately after appending to the buffer and signaling the flusher — **it does not wait for delivery to the Workflow or to subscribers**. The flusher only runs while the client is entered (`async with client`); outside that, `force_flush=True` queues the wake event but nothing ships until you enter the context or call `await client.flush()`. <!-- docs/develop/python/workflows/workflow-streams.mdx:175 --> Use it for latency-sensitive events: the first delta of a response, or punctuated events like `RETRY` and `STATUS_CHANGE`. <!-- docs/develop/python/workflows/workflow-streams.mdx:181 -->
- **`await client.flush()`** is a mid-stream barrier. Successful return is proof the Temporal server has received all prior publications, so subsequent work that depends on those events being durable can proceed. The client stays open for further publishing afterward. Exiting `async with client` flushes on its way out, so the explicit call is only for barriers in the middle. <!-- docs/develop/python/workflows/workflow-streams.mdx:183 -->

```python
async with client:
    for delta in first_phase():
        deltas.publish(delta)
    await client.flush()
    checkpoint_id = await record_phase_one_complete()  # safe: phase-one events durable
    for delta in second_phase(checkpoint_id):
        deltas.publish(delta)
```

### No backpressure

`publish()` is non-blocking and applies no backpressure. From an Activity or other client, it appends to the in-memory buffer and returns; from inside a Workflow, it appends synchronously to the in-memory log. Subscribers pull from the Workflow's log on their own schedule, so a slow subscriber does not slow down publishers. If a publisher emits faster than batches can ship to the server, the buffer grows: more memory, more lag, and at the limit Signals cannot keep up. Apply any bound (block, drop, error, sample) upstream of `publish()` — the library does not choose for you. <!-- docs/develop/python/workflows/workflow-streams.mdx:198 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:200 -->

## Subscribe

Use the same `WorkflowStreamClient` you'd use to publish — `WorkflowStreamClient.create(client, workflow_id)` from any process with a Temporal `Client`, or `from_within_activity()` inside an Activity. Iterate a topic handle's `subscribe()`. The handle's bound type drives decoding, so each `item.data` arrives as `T` via the client's payload converter. <!-- docs/develop/python/workflows/workflow-streams.mdx:204 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:210 -->

```python
async def watch_order(order_id: str) -> None:
    temporal_client = await Client.connect("localhost:7233")
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=order_id)

    status = stream.topic("status", type=StatusEvent)
    async for item in status.subscribe():
        evt = item.data
        if evt.state == "completed":
            break
```

The iterator handles re-polling, pagination when a poll response hits the ~1 MB cap, and Workflow-side log truncation transparently. Two edge cases: an RPC timeout where Continue-As-New cannot be followed ends the iterator silently, and a validator rejection during a CAN handoff can surface as `WorkflowUpdateFailedError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:229 -->

Subscribers don't need an `async with` — the flusher only runs for publishers. <!-- docs/develop/python/workflows/workflow-streams.mdx:526 -->

### Subscribing from inside the host Workflow is unsupported

The Workflow only sees the successful return value of each Activity; the stream may carry partial output from attempts that failed and were retried. Letting the Workflow read its own stream would mix those two views and break the conduit role the Workflow plays. <!-- docs/develop/python/workflows/workflow-streams.mdx:206 -->

### Heterogeneous topics

A topic handle binds one name to one type, so it only fits a single-type subscription. To consume multiple topics whose payload types differ, call `client.subscribe()` directly with a list of names (or `subscribe([])` for every topic) and pass `result_type=temporalio.common.RawValue` so each item arrives as the underlying `Payload` wrapped in a `RawValue`. Dispatch on `item.topic` and decode `item.data.payload` with the client's payload converter: <!-- docs/develop/python/workflows/workflow-streams.mdx:233 -->

```python
from temporalio.common import RawValue

converter = temporal_client.data_converter.payload_converter

async for item in stream.subscribe(["status", "progress"], result_type=RawValue):
    if item.topic == "status":
        evt = converter.from_payload(item.data.payload, StatusEvent)
    elif item.topic == "progress":
        evt = converter.from_payload(item.data.payload, ProgressEvent)
```

A single iterator over multiple topics also avoids the cancellation race that two concurrent subscribers would create. `RawValue` is also the right shape when you want to forward the bytes through to another system without decoding them. <!-- docs/develop/python/workflows/workflow-streams.mdx:249 -->

Omitting `result_type` (or passing `result_type=None`) decodes each item with the converter's default rules. For the stock JSON converter that means a Python primitive, `dict`, or `list` — fine for fully homogeneous streams, not for the dispatch-by-topic pattern. <!-- docs/develop/python/workflows/workflow-streams.mdx:251 -->

## Closing the stream

End-of-stream is application-level. The library imposes no sentinel. Without coordination a subscriber will keep polling until the Workflow reaches a terminal state, and a Workflow that returns immediately after its last publish can lose that publish's poll round-trip in the gap. <!-- docs/develop/python/workflows/workflow-streams.mdx:255 -->

The conventional pattern is two pieces: <!-- docs/develop/python/workflows/workflow-streams.mdx:257 -->

1. **An in-band terminator** the subscriber recognizes and breaks on (e.g. `StatusEvent(state="completed")`).
2. **A brief overlap before the Workflow returns** — without it, a poll Update still in flight when the Workflow returns surfaces as `AcceptedUpdateCompletedWorkflow` and no new polls can complete after that. <!-- docs/develop/python/workflows/workflow-streams.mdx:260 -->

Two ways to provide the overlap: <!-- docs/develop/python/workflows/workflow-streams.mdx:262 -->

### Fixed sleep (simplest)

```python
self.status.publish(StatusEvent(state="completed", progress=100))
await workflow.sleep(timedelta(seconds=30))
return result
```

A few hundred milliseconds is tight under realistic conditions; thirty seconds is a generous default. The Workflow Run stays open for that duration but does no other work. <!-- docs/develop/python/workflows/workflow-streams.mdx:273 -->

### Acknowledgment handshake

The subscriber sends a Signal once it has the terminator; the Workflow waits up to a timeout, returning as soon as the ack arrives. <!-- docs/develop/python/workflows/workflow-streams.mdx:275 -->

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

The timeout is still required — the subscriber may not be attached or may have gone away. With the ack on top, the typical case (subscriber online) exits as soon as the subscriber confirms receipt, regardless of how long the fallback timeout is. <!-- docs/develop/python/workflows/workflow-streams.mdx:295 -->

### Inspecting terminal status

`subscribe()` exits cleanly when the Workflow reaches `COMPLETED`, `FAILED`, `CANCELED`, `TERMINATED`, or `TIMED_OUT`, but does not distinguish among them. If you need to know which (display success/failure, log the outcome, decide whether to retry), call `await temporal_client.get_workflow_handle(workflow_id).describe()` after the loop returns. <!-- docs/develop/python/workflows/workflow-streams.mdx:297 -->

## Continue-As-New {#continue-as-new}

For Workflows that finish in minutes (single chat completion, order pipeline, one-shot agent), you can skip this section. Continue-As-New becomes relevant for streams running for hours or accumulating thousands of events. <!-- docs/develop/python/workflows/workflow-streams.mdx:301 -->

Subscribers automatically follow CAN chains: Workflow IDs are stable across CAN, so the iterator fetches a fresh handle and continues polling from the carried offset. **CAN-following requires the client retained from `WorkflowStreamClient.create()` or `from_within_activity()`; clients constructed directly with a single handle cannot re-target the new run.** <!-- docs/develop/python/workflows/workflow-streams.mdx:303 -->

### Helper recipe

Add a `WorkflowStreamState | None` field to your Workflow input, pass it to the constructor, and call `WorkflowStream.continue_as_new(build_args)` to roll over. The helper drains waiting subscribers, waits for in-flight handlers to finish, then calls `workflow.continue_as_new` with the args produced by `build_args(post_drain_state)`. <!-- docs/develop/python/workflows/workflow-streams.mdx:305 -->

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

**The `| None` on `stream_state` is required, and the type must be the concrete `WorkflowStreamState`, not `Any`.** `prior_state` is `None` on a fresh start and a `WorkflowStreamState` after a rollover. With `Any`, the data converter rebuilds the field as a plain `dict` and `WorkflowStream(prior_state=...)` raises `AttributeError` accessing `.log` / `.base_offset` / `.publishers` on the dict. <!-- docs/develop/python/workflows/workflow-streams.mdx:347 -->

### Explicit recipe (for `task_queue`, `retry_policy`, `run_timeout`, …)

```python
self.stream.detach_pollers()
await workflow.wait_condition(workflow.all_handlers_finished)
workflow.continue_as_new(
    args=[WorkflowInput(app_state=self.app_state, stream_state=self.stream.get_state())],
    task_queue="other-tq",
)
```

<!-- docs/develop/python/workflows/workflow-streams.mdx:349-358 -->

### Payload size at rollover

The carried `WorkflowStreamState` includes the entire in-memory log of the previous run, so streams that carry large items can hit Temporal's per-payload size limit at the rollover. (Individual publish Signals and subscribe Update responses can also exceed the limit, but the carried state is the most acute case because it accumulates the full log window.) Offload bytes via External Storage so each item is a small reference, and combine that with `truncate()` to keep the carried log itself small. <!-- docs/develop/python/workflows/workflow-streams.mdx:360 -->

## Tuning

The driving question: how often do you want to update the UI? Each batched publish is one Signal; each subscriber poll is one Update. Both accumulate against the Workflow's history. <!-- docs/develop/python/workflows/workflow-streams.mdx:366 -->

For long-running streams, plan a [Continue-As-New](#continue-as-new) policy from the start.

### Settings

| Setting | Default | What it does |
|---|---|---|
| `batch_interval` | 2 seconds | Maximum time between automatic flushes from the client. Lower it (e.g. 200 ms for LLM token streaming) to make the stream feel live; raise it to amortize Signal cost. Below 100 ms per-Signal RPC overhead starts to dominate. <!-- docs/develop/python/workflows/workflow-streams.mdx:370 --> |
| `max_batch_size` | unbounded | Caps items per batch. Without it, only `batch_interval` bounds batch size, so a hot publisher can accumulate enough items between intervals to exceed Temporal's per-message gRPC payload limit. Alternative: `force_flush=True` after each logical chunk to bound by application boundaries. <!-- docs/develop/python/workflows/workflow-streams.mdx:378 --> |
| `poll_cooldown` | 100 ms | Subscriber sleep between polls. Skipped only when a poll response was capped at the ~1 MB gRPC limit and more items remain (a `more_ready` flag in the response). In the steady state every poll waits the cooldown. Hold a single iterator rather than opening/closing in a loop. <!-- docs/develop/python/workflows/workflow-streams.mdx:379 --> |
| `max_retry_duration` | 10 minutes | How long the client retries a failed publish batch before giving up and raising `TimeoutError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:380 --> |
| `publisher_ttl` | 15 minutes | How long the Workflow retains per-publisher deduplicate state. At each CAN, entries older than this are dropped. <!-- docs/develop/python/workflows/workflow-streams.mdx:381 --> |

**Invariant: `max_retry_duration < publisher_ttl`.** If you tune one, tune the other — a long-running retry that outlasts its dedup record can produce a duplicate when it finally succeeds. The defaults (10 min < 15 min) satisfy this. <!-- docs/develop/python/workflows/workflow-streams.mdx:383 --> <!-- docs/develop/python/workflows/workflow-streams.mdx:406 -->

For per-publish overrides where one specific event needs lower latency than the batch interval (the first delta of a response, or punctuated events like `RETRY` and `STATUS_CHANGE`), pass `force_flush=True` on that publish. Per-token `force_flush=True` on a 500-token completion produces 500 publish Signals — meaningful but tractable; per-character `force_flush=True` is not. <!-- docs/develop/python/workflows/workflow-streams.mdx:372 -->

## Delivery semantics

**Exactly-once at the execution layer.** Each `(publisher_id, sequence)` batch lands in the Workflow's event log at most once, even if the publisher's underlying Signal is retried by the SDK or the network. Deduplicate state is carried across Continue-As-New so a retried publish that arrives after a rollover still lands at most once. <!-- docs/develop/python/workflows/workflow-streams.mdx:387 -->

**Ordering.** The log imposes a single total order on all events, fixed once written. Within one publisher (one `WorkflowStreamClient` instance, or the Workflow itself), events appear in publish order. Across concurrent publishers the interleaving is whatever the Workflow saw when serializing inbound Signals; the order is stable once recorded but not under application control. If event A must precede event B, publish them from the same publisher. <!-- docs/develop/python/workflows/workflow-streams.mdx:389 -->

**Activity retries surface to subscribers.** When an Activity that publishes events fails partway and Temporal retries it, *both* attempts' events appear in the stream. An Activity that publishes three `TEXT_DELTA` events and then errors, then retries and publishes its full output, will deliver three partial events followed by the complete sequence. The Workflow itself sees only the successful attempt's return value, but a UI subscribed to the stream will see the partial output unless it dedupes. **Consumers must reset or annotate on retry events; the library does not do this automatically.** <!-- docs/develop/python/workflows/workflow-streams.mdx:391 -->

The conventional pattern: an Activity that detects it's on a retry attempt publishes a `RETRY` event with `force_flush=True`, and the consumer clears or annotates prior-attempt output when it sees one. Treat the stream as an append-only log of attempts and let an idempotent reducer reconcile them (overwrite on terminal events like `STATUS_CHANGE` or `TEXT_COMPLETE`, reset an accumulator on a sentinel like `AGENT_START` before deltas resume). <!-- docs/develop/python/workflows/workflow-streams.mdx:393 -->

**Other failure modes.** <!-- docs/develop/python/workflows/workflow-streams.mdx:397 -->

- Events still in a publisher's in-memory client buffer are **lost** if the process crashes before they ship.
- Subscribers that handle an item and crash before persisting their next offset will **reprocess** that item on resume. Persist offset *after* successful handling.

**Dedup window details.** <!-- docs/develop/python/workflows/workflow-streams.mdx:401 -->

- `publisher_ttl` retention is updated on each *successful* publish (not on retry attempts), so a publisher that retries through a long partition without success can still age out. A publisher that returns after a longer pause may produce a duplicate. Tune upward via `WorkflowStream.continue_as_new(publisher_ttl=...)` if your publishers can be silent for extended windows.
- On `max_retry_duration` timeout, the dropped batch is at-most-once: it may or may not have reached the Workflow. Subsequent publishes resume cleanly with the next sequence. One operational caveat: the `TimeoutError` raises from inside the background flusher task and terminates it. Until you call `await client.flush()` or exit the `async with` block, subsequent publishes accumulate in the buffer with no flusher to ship them. <!-- docs/develop/python/workflows/workflow-streams.mdx:404 -->

## Architecture

Three pieces of machinery hide behind the user-facing API: <!-- docs/develop/python/workflows/workflow-streams.mdx:410 -->

### Append-only log inside the Workflow

`WorkflowStream` keeps an in-memory list of `(topic, data)` entries with monotonically increasing global offsets. Subscribers maintain their own cursor and on each long-poll receive the next range past it. Because the log lives in Workflow state, it is replay-safe and is carried across Continue-As-New via `WorkflowStreamState`. <!-- docs/develop/python/workflows/workflow-streams.mdx:412 -->

Two mechanisms bound log growth, and they do different jobs: <!-- docs/develop/python/workflows/workflow-streams.mdx:414 -->

- **`truncate(up_to_offset)`** drops entries from the in-memory log (and therefore from the carried CAN payload). **It does not remove publish Signals already recorded in history.** <!-- docs/develop/python/workflows/workflow-streams.mdx:416 -->
- **Continue-As-New** starts a fresh history. **This is the only way to shrink history; `truncate()` alone cannot.** <!-- docs/develop/python/workflows/workflow-streams.mdx:417 -->

A subscriber whose offset falls below the new base after a `truncate()` is silently advanced. Internally, the poll raises `ApplicationError("TruncatedOffset")`; the Python client catches it and resets to offset 0, which the Workflow reads as "from the current base." The iterator does not raise, but the subscriber may re-receive items already in the log past the new base. Applications that depend on seeing every event exactly once must keep subscribers ahead of truncation or implement their own gap and re-delivery handling using `item.offset`. <!-- docs/develop/python/workflows/workflow-streams.mdx:419 -->

### Wire-level handlers (private, dynamically registered)

The three handlers registered when you construct a `WorkflowStream`: <!-- docs/develop/python/workflows/workflow-streams.mdx:421 -->

| Handler | Type | Purpose |
|---|---|---|
| `__temporal_workflow_stream_publish` | Signal | Receives batched publishes |
| `__temporal_workflow_stream_poll` | Update | Long-poll used by subscribers |
| `__temporal_workflow_stream_offset` | Query | Reports the current head offset |

Poll responses are capped at roughly 1 MB by accumulating items until the next would exceed the budget; high-throughput producers see a steady stream of small batches. A single item that exceeds 1 MB on its own is admitted unconditionally — offload large items via External Storage so each item is a small reference. <!-- docs/develop/python/workflows/workflow-streams.mdx:421 -->

### Batching and deduplicating

Every batch carries a unique identifier (the client's id paired with a monotonic batch sequence number), so a Signal retried by the SDK or the network deduplicates to a single landing in the Workflow's event log. Deduplicate state is part of the Workflow's carried state, so the guarantee survives Continue-As-New (subject to `publisher_ttl`). <!-- docs/develop/python/workflows/workflow-streams.mdx:423 -->

**This dedup applies at the Signal layer, not the Activity layer.** An *Activity retry* is a different concept from a *publish retry*: when Temporal retries the Activity, the retried execution constructs a new `WorkflowStreamClient` with its own client id, so from the stream's perspective every attempt is a fresh publisher whose batches will not deduplicate against the prior attempt's. That is why retried-attempt events appear alongside the successful attempt's output. <!-- docs/develop/python/workflows/workflow-streams.mdx:425 -->

## Gotchas

- **`WorkflowStreamClient` is asyncio-only.** The client buffer is mutated on the publish path and read from the flusher inside a single event loop. **Don't call `publish()` from a worker thread.** <!-- docs/develop/python/workflows/workflow-streams.mdx:431 -->
- **First-activation handler race.** `WorkflowStream` registers its publish-Signal handler dynamically from `__init__`, so on the very first activation a publish Signal can be queued before class-level `@workflow.signal` or `@workflow.update` handlers have run. A handler that observes state set by stream initialization in that same activation can see pre-publish state. Fix: make the handler `async def` and `await asyncio.sleep(0)` once before reading state — a no-op yield that adds no history events. **Don't substitute `workflow.sleep(0)`, which records a timer event.** Once the first activation completes, the handler is permanent and the race does not recur. <!-- docs/develop/python/workflows/workflow-streams.mdx:432 -->
- **Type bindings aren't shared across publishers.** Each `WorkflowStream` and each `WorkflowStreamClient` records topic types only for its own instance. If two publishers bind the same topic name to different types, the mismatch is not caught at publish, and the subscriber gets a decode error when it processes events from the mismatched publisher. <!-- docs/develop/python/workflows/workflow-streams.mdx:433 -->
- **`publish()` is non-blocking.** No backpressure — see [No backpressure](#no-backpressure).
- **One `WorkflowStream` per Workflow.** Constructing a second one raises `RuntimeError`. <!-- docs/develop/python/workflows/workflow-streams.mdx:82 -->
- **Workflow doesn't read its own stream.** Subscribing from inside the host Workflow is intentionally unsupported. <!-- docs/develop/python/workflows/workflow-streams.mdx:206 -->

## Application: Stream LLM output

The headline use case fits the publish/subscribe shapes above. An Activity calls the model and publishes deltas; the Workflow kicks off the Activity and waits for the consumer to acknowledge end-of-stream; the consumer subscribes, accumulates deltas, and clears accumulated state on `RETRY` before continuing. The shape works for a terminal client, a desktop UI, or an SSE endpoint forwarding to a browser. <!-- docs/develop/python/workflows/workflow-streams.mdx:435-439 -->

For the broader LLM/Pydantic plumbing around the Activity (Pydantic data converter, `AsyncOpenAI(max_retries=0)` discipline, generic LLM Activity shape), see `references/python/ai-patterns.md`. For conceptual AI patterns, see `references/core/ai-patterns.md`.

### Activity — publish deltas, surface retries

```python
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
            # force_flush only on first delta; subsequent deltas batch at 200 ms.
            deltas.publish(TextDelta(text=text), force_flush=first)
            first = False
            full.append(text)
        close.publish({})
    return "".join(full)
```

<!-- docs/develop/python/workflows/workflow-streams.mdx:441-488 -->

### Workflow — ack-handshake termination

```python
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

<!-- docs/develop/python/workflows/workflow-streams.mdx:490-521 -->

### Consumer — accumulate deltas, reset on retry, ack on close

```python
async def stream_chat(chat_id: str) -> str:
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=chat_id)
    converter = temporal_client.data_converter.payload_converter
    output: list[str] = []

    def render() -> None:
        ...  # display the accumulated output

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
            await temporal_client.get_workflow_handle(chat_id).signal(
                ChatWorkflow.subscriber_acknowledged_terminator
            )
            break

    return "".join(output)
```

<!-- docs/develop/python/workflows/workflow-streams.mdx:523-553 -->

Why this shape: <!-- docs/develop/python/workflows/workflow-streams.mdx:555-560 -->

- The Activity is the publisher because it owns the non-deterministic LLM call. The Workflow processes only the Activity's return value, never reading its own stream.
- The Activity publishes a `RETRY` event when `activity.info().attempt > 1` so the UI can clear stale accumulated deltas before the next attempt's deltas arrive.
- Termination uses an ack handshake: the consumer signals once it has the `close` event, so the Workflow exits as soon as the subscriber confirms; the `wait_condition` timeout is the fallback when no subscriber is attached.
- `force_flush=True` is used only on the first delta and on the `RETRY` sentinel, where latency matters; per-delta `force_flush=True` would generate one Signal per token.

## See also

- `references/python/patterns.md` — Signals, Updates, Queries, and Continue-As-New primitives that Workflow Streams is built on.
- `references/python/ai-patterns.md` — Pydantic data converter, OpenAI/LiteLLM client config, generic LLM Activity shape.
- `references/core/ai-patterns.md` — conceptual AI/LLM patterns.
- `docs/develop/python/workflows/message-passing.mdx` — message-passing primitives.
- Workflow Streams runnable samples: `https://github.com/temporalio/samples-python/tree/main/workflow_streams` — basic publish/subscribe, reconnecting subscriber, external publisher, bounded log. <!-- docs/develop/python/workflows/workflow-streams.mdx:43 -->
- API reference: `https://python.temporal.io/temporalio.contrib.workflow_streams.html`. <!-- docs/develop/python/workflows/workflow-streams.mdx:565 -->
