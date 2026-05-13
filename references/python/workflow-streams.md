# Workflow Streams (Python SDK)

> **Public Preview.** The `temporalio.contrib.workflow_streams` module is in Public Preview. The API may change before general availability. Python is the only language with a client today; cross-language client support is on the roadmap.

Workflow Streams gives a Workflow a **durable, offset-addressed event channel** built on Temporal's basic message primitives — Signals (publish), Updates (subscribe long-poll), and Queries (offset). It batch-publishes to amortize per-Signal cost, deduplicates batches for exactly-once delivery to the log, supports topic filtering, and carries state across Continue-As-New.

**Use it when:** outside observers need to follow Workflow progress — UI for an AI agent run, payment/order pipeline status, intermediate results from a data job. **Don't use it for:** ultra-low-latency cases like real-time voice, or fan-out beyond tens of publishers/subscribers per Workflow.

## Where to host the stream

A `WorkflowStream` lives inside a Workflow. Two shapes:

1. **Host the stream on the Workflow that does the work.** Events come from what that Workflow is orchestrating; lifecycle aligns with the run. The Workflow ID used to start the work is the same one subscribers attach to. This is the common shape for AI agents and progress streaming.
2. **Use a dedicated Workflow for the stream alone.** Choose this when the stream must outlive any single producer, accept fan-in from unrelated sources, or be subscribable before any work has started. Producers publish from outside. Trade-off: you own lifecycle — signal-driven shutdown or a Continue-As-New strategy.

Workflow ID is the subscriber address. Multiple subscribers can attach to the same ID concurrently. Use distinct Workflow IDs for unrelated streams; do not pack them into one.

## Enable streaming on a Workflow

Construct the stream **in `@workflow.init`** (the constructor — runs once before any Signal/Update can be delivered). Constructing from `@workflow.run` raises `RuntimeError`. Constructing more than one stream on the same Workflow also raises `RuntimeError`.

```python
from temporalio import workflow
from temporalio.contrib.workflow_streams import WorkflowStream


@workflow.defn
class OrderWorkflow:
    @workflow.init
    def __init__(self, input: OrderInput) -> None:
        self.stream = WorkflowStream()
```

Constructing `WorkflowStream` registers three handlers on the Workflow dynamically: the publish Signal, the subscribe Update, and the offset Query.

## Publish from a Workflow

Bind a topic name to its event type once via `self.stream.topic("name", type=Type)`, then call `publish()` on the returned handle. The handle records the name→type binding so call sites don't repeat the type and subscribers reading the same handle decode to the matching type. The `type=` argument is optional and defaults to `Any`.

Topics are **implicit and created on first publish** — there is no separate registration step.

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

`publish()` runs the payload converter to encode each value. The codec chain (encryption, compression) runs **once** on the Signal/Update envelope that carries the batch, not per item.

## Publish from a client (HTTP backend, starter, Activity)

Any process with a Temporal `Client` and the target Workflow ID can publish by constructing a `WorkflowStreamClient`. Use the async context manager so the buffer flushes on exit.

```python
from temporalio.client import Client
from temporalio.contrib.workflow_streams import WorkflowStreamClient

stream_client = WorkflowStreamClient.create(
    temporal_client,
    workflow_id=workflow_id,
    batch_interval=timedelta(milliseconds=200),
)
async with stream_client:
    status = stream_client.topic("status", type=StatusEvent)
    status.publish(StatusEvent(state="started"))
    # Buffer flushes on context-manager exit.
```

### Inside an Activity scheduled by a Workflow

`WorkflowStreamClient.from_within_activity()` infers the Temporal `Client` and the parent Workflow ID from the Activity context:

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

For a [standalone Activity](/develop/python/activities/standalone-activities) (started directly via `Client.start_activity`), there is no parent Workflow context, so `from_within_activity()` raises. Use `WorkflowStreamClient.create(client, workflow_id)` with the target Workflow ID threaded through the Activity's input.

### When events originate in an Activity, publish from the Activity directly

Don't return events for the Workflow to forward. The Workflow hosts the stream but **does not read its own stream**; keeping Workflow state independent of streamed output is what lets retried Activity attempts surface to subscribers without polluting durable state. See [Delivery semantics](#delivery-semantics).

### `force_flush=True` and `client.flush()`

Two operations give the application explicit control over when batches ship:

- **`publish(..., force_flush=True)`** wakes the background flusher so the current buffer ships without waiting for `batch_interval`. The call returns immediately after appending; it does **not** wait for delivery. Use it for latency-sensitive events: the first delta of a response, or punctuated events like `RETRY` / `STATUS_CHANGE`. The flusher only runs while the client is entered (`async with client`); outside that, `force_flush=True` queues the wake event but nothing ships until you enter the context or call `await client.flush()`.
- **`await client.flush()`** is a mid-stream barrier. Successful completion is proof that the Temporal server has received all prior publications. The client stays open afterward. Exiting `async with client` already flushes on its way out, so explicit `flush()` is only for mid-stream barriers.

`publish()` applies **no backpressure**. If a publisher emits faster than batches can ship, the in-memory buffer grows. If your app needs to bound this (cap memory, keep the stream close to real time), apply the policy (block, drop, error, sample) upstream of `publish()`. Workflow Streams does not pick one for you.

## Subscribe

Same client construction as publishing: `WorkflowStreamClient.create(client, workflow_id)`, or `from_within_activity()` inside an Activity. Iterate `subscribe()` on a topic handle — bound type drives decoding so each `item.data` arrives as `T`.

```python
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

The iterator handles re-polling, pagination when a poll response hits the ~1 MB cap, and Workflow-side log truncation transparently. Two edge cases: an RPC timeout where Continue-As-New cannot be followed ends the iterator silently (no exception raised); a validator rejection during a CAN handoff can surface as `WorkflowUpdateFailedError`.

**Subscribing from inside the host Workflow is intentionally unsupported.** The Workflow only sees the successful return value of each Activity; the stream may carry partial output from failed-and-retried attempts. Letting the Workflow read its own stream would mix the two views and break the conduit role.

### Heterogeneous topics

A topic handle binds one name to one type, so it only fits single-type subscription. To consume multiple topics with different payload types, call `client.subscribe()` directly with a list of names (or `subscribe([])` for every topic) and pass `result_type=temporalio.common.RawValue`. Dispatch on `item.topic` and decode with the client's payload converter:

```python
from temporalio.common import RawValue

converter = temporal_client.data_converter.payload_converter

async for item in stream.subscribe(["status", "progress"], result_type=RawValue):
    if item.topic == "status":
        evt = converter.from_payload(item.data.payload, StatusEvent)
    elif item.topic == "progress":
        evt = converter.from_payload(item.data.payload, ProgressEvent)
```

A single iterator over multiple topics also avoids the cancellation race two concurrent subscribers would create. `RawValue` is also the right shape when forwarding bytes through to another system without decoding.

Omitting `result_type` (or passing `None`) decodes each item with the converter's default rules. For the stock JSON converter, that means a Python primitive, `dict`, or `list` — fine for fully homogeneous streams, not for dispatch-by-topic with concrete dataclasses.

## Closing the stream

`subscribe()` has no built-in end-of-stream marker — end-of-stream is application-level. Without coordination, a subscriber polls until the Workflow reaches a terminal state. A Workflow that returns immediately after its last publish can lose that publish's poll round-trip in the gap: a poll Update in flight when the Workflow returns surfaces as `AcceptedUpdateCompletedWorkflow`, and no new polls complete after that.

Two ways to provide an overlap before the Workflow returns:

**Fixed sleep (simplest).** Sleep between the terminator and the return:

```python
# at the end of @workflow.run
self.status.publish(StatusEvent(state="completed", progress=100))
await workflow.sleep(timedelta(seconds=30))
return result
```

A few hundred ms is tight under realistic conditions; thirty seconds is a generous default. The Workflow Run stays open for that duration but does no other work.

**Acknowledgment handshake.** The subscriber signals the Workflow once it has the terminator; the Workflow waits up to a timeout, returning as soon as the ack arrives:

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

The fallback timeout is required because the subscriber may not be attached or may have gone away. With the ack, the typical online case exits as soon as the subscriber confirms.

**Inspecting terminal status.** `subscribe()` exits cleanly when the Workflow reaches `COMPLETED`, `FAILED`, `CANCELED`, `TERMINATED`, or `TIMED_OUT`, but does not distinguish among them. If you need to know which, call `await temporal_client.get_workflow_handle(workflow_id).describe()` after the loop returns.

## Continue-As-New

Skip this section if your Workflow runs for minutes and finishes (single chat completion, order pipeline, one-shot agent). Continue-As-New becomes relevant for streams that run for hours or accumulate thousands of events.

Subscribers automatically follow Continue-As-New chains. Workflow IDs are stable across CAN, so the iterator fetches a fresh handle for the same ID and continues from the carried offset. CAN-following requires the client retained from `WorkflowStreamClient.create()` or `from_within_activity()`; clients constructed directly with a single handle cannot re-target the new run.

To roll over without a gap, carry both your application state and the stream state across the boundary. Add a `WorkflowStreamState | None` field to your Workflow input, pass it to the constructor via `prior_state=`, and call `WorkflowStream.continue_as_new(build_args)`. The helper drains waiting subscribers, waits for in-flight handlers to finish, then calls `workflow.continue_as_new` with the args produced by `build_args(post_drain_state)`:

```python
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

**The `| None` on `stream_state` is required.** `prior_state` is `None` on a fresh start and a `WorkflowStreamState` instance after a rollover. **Always use the concrete type, not `Any`.** With `Any`, the data converter rebuilds the field as a plain `dict` and `WorkflowStream(prior_state=...)` raises `AttributeError` accessing `.log` / `.base_offset` / `.publishers` on the dict.

To pass other Continue-As-New parameters (`task_queue`, `retry_policy`, `run_timeout`), use the explicit recipe instead:

```python
self.stream.detach_pollers()
await workflow.wait_condition(workflow.all_handlers_finished)
workflow.continue_as_new(
    args=[WorkflowInput(app_state=self.app_state, stream_state=self.stream.get_state())],
    task_queue="other-tq",
)
```

The carried `WorkflowStreamState` includes the entire in-memory log of the previous run, so streams that carry large items can hit Temporal's per-payload size limit at the rollover. Offload bytes via [External Storage](/external-storage) so each item is a small reference, and combine with `truncate()` to keep the carried log small.

## Tuning

The most important question: how often do you want to update your UI? That drives the trade-off between user-perceived latency and the number of history events the Workflow accumulates. Each batched publish is one Signal; each subscriber poll is one Update. Both accumulate against the Workflow's history. For long-running streams, plan a Continue-As-New policy from the start.

### Settings that matter most

- **`batch_interval`** — default **2 seconds**. Maximum time between automatic flushes from the client. Lower it to make the stream feel live; raise it to amortize Signal cost. For an LLM token stream feeding a chat UI, 200 ms is a good starting point. Below 100 ms the per-Signal RPC overhead starts to dominate.

For per-publish overrides where one specific event needs lower latency than the batch interval (first delta, `RETRY`, `STATUS_CHANGE`), pass `force_flush=True` on that publish. Don't make it the default mode — per-token `force_flush=True` produces one Signal per token.

### Other settings

You usually do not need to touch these.

- **`max_batch_size`** — default **unbounded**. Caps the number of items per batch. With the default, only `batch_interval` bounds batch size; a hot publisher can accumulate enough items that the resulting Signal exceeds Temporal's per-message gRPC payload limit. Set `max_batch_size` to bound by item count, or `force_flush=True` after each logical chunk. For large items, offload via External Storage.
- **`poll_cooldown`** (subscriber-side) — default **100 ms**. The subscriber sleeps for this interval between polls. The cooldown is skipped only when a poll response was capped at the ~1 MB gRPC limit and more items remain (`more_ready` flag). Hold a single iterator and consume from it rather than opening and closing subscriptions in a loop.
- **`max_retry_duration`** — default **10 minutes**. How long the client retries a failed publish batch before giving up and raising `TimeoutError`.
- **`publisher_ttl`** — default **15 minutes**. How long the Workflow retains per-publisher deduplicate state. At each Continue-As-New, entries older than this are dropped.

**Invariant: `max_retry_duration < publisher_ttl`.** If you tune one, tune the other. A retry that arrives after its dedup record has been pruned is treated as a fresh publish and the same logical batch can land twice. The defaults (10 min < 15 min) satisfy this.

## Delivery semantics

**Exactly-once at the execution layer.** Each `(publisher_id, sequence)` batch lands in the Workflow's event log at most once, even if the publisher's underlying Signal is retried by the SDK or the network. Dedup state is carried across Continue-As-New, so a retried publish that arrives after a rollover still lands at most once.

**Ordering.** The log imposes a single total order, fixed once written: an event at offset N stays at offset N on every read. Within one publisher (one `WorkflowStreamClient` instance, or the Workflow itself), events appear in publish order. Across concurrent publishers, the interleaving is whatever the Workflow saw when serializing inbound Signals — stable once recorded but not under application control. **If event A must precede event B, publish them from the same publisher.**

**Activity retries surface to subscribers.** When an Activity that publishes events fails partway through and Temporal retries it, **both** attempts' events appear in the stream. The Workflow itself sees only the successful attempt's return value (durable execution hides retries), but a UI subscribed to the stream sees the partial output unless it dedupes. The conventional pattern: an Activity that detects it's on a retry attempt publishes a `RETRY` event with `force_flush=True`; the consumer clears or annotates prior-attempt output when it sees one. **Consumers must reset or annotate on retry events; the library does not do this automatically.**

> **Publish retry vs. Activity retry.** Signal-layer publish retries dedupe to a single landing (same `publisher_id`, same `sequence`). An *Activity retry* constructs a new `WorkflowStreamClient` with a new client id, so from the stream's perspective every attempt is a fresh publisher whose batches will not dedupe against the prior attempt's. This is why retried-attempt events show up alongside the successful attempt's output.

**Other failure modes.**

- Events still in a publisher's in-memory client buffer are lost if the process crashes before they ship.
- Subscribers that handle an item and crash before persisting their next offset will reprocess that item on resume.

**`TimeoutError` operational caveat.** When `max_retry_duration` is exhausted, the dropped batch is at-most-once: it may or may not have reached the Workflow. The `TimeoutError` raises from inside the background flusher task and **terminates it**. Until you call `await client.flush()` or exit the `async with` block, subsequent publishes accumulate in the buffer with no flusher to ship them.

## Architecture

The user-facing API hides three pieces of machinery worth understanding when you tune throughput, debug delivery, or reason about history size.

- **Append-only log inside the Workflow.** `WorkflowStream` keeps an in-memory list of `(topic, data)` entries inside the Workflow's state, each with a monotonically increasing global offset. Subscribers maintain their own cursor and on each long-poll receive the next range past it. The log is replay-safe and is carried across Continue-As-New via `WorkflowStreamState`.
- **`truncate(up_to_offset)`** drops entries from the in-memory log (and the carried CAN payload). It does **not** remove publish Signals already recorded in history. **Continue-As-New** is the only way to shrink history; `truncate` alone cannot.
- A subscriber whose offset falls below the new base after `truncate()` is silently advanced. Internally the poll raises `ApplicationError("TruncatedOffset")`; the Python client catches it and resets to offset 0. The iterator does **not** raise, but the subscriber may re-receive items past the new base. Applications that depend on seeing every event exactly once must keep subscribers ahead of truncation or implement their own gap handling using `item.offset`.
- **Wire-level handlers** (informational — useful for debugging history): `__temporal_workflow_stream_publish` (publish Signal), `__temporal_workflow_stream_poll` (subscribe Update), `__temporal_workflow_stream_offset` (head-offset Query). Poll responses are capped at ~1 MB by accumulating items until the next would exceed the budget; a single item that exceeds 1 MB on its own is admitted unconditionally. Offload large items via External Storage.
- **Batching and deduplicating.** Every batch carries a unique identifier (client id paired with monotonic batch sequence). A Signal retried by the SDK or the network deduplicates to a single landing. Dedup state survives Continue-As-New, subject to `publisher_ttl`.

### Gotchas

- **`WorkflowStreamClient` is asyncio-only.** The client buffer is mutated on the publish path and read from the flusher inside a single event loop. Don't call `publish()` from a worker thread.
- **Custom handlers reading stream state on the first activation.** `WorkflowStream` registers its publish-Signal handler dynamically from `__init__`, so on the very first activation a publish Signal can be queued before class-level `@workflow.signal` or `@workflow.update` handlers have run. A handler that observes state set by stream initialization in that same activation can see pre-publish state. Fix: make the handler `async def` and `await asyncio.sleep(0)` once before reading state. Do **not** substitute `workflow.sleep(0)`, which records a timer event.
- **Type bindings aren't shared across publishers.** Each `WorkflowStream` and each `WorkflowStreamClient` records topic types only for its own instance. If two publishers bind the same topic name to different types, the mismatch is not caught at publish; the subscriber gets a decode error when it processes events from the mismatched publisher.

## Worked example: streaming LLM output

The headline use case. An Activity calls the model and publishes deltas as they arrive; the Workflow kicks off the Activity and waits for the consumer to acknowledge end-of-stream; the consumer subscribes, accumulates the deltas, and clears accumulated state on `RETRY` before continuing.

```python
# activity.py
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
# consumer.py — accumulates the model's output and resets on retry
async def stream_chat(chat_id: str) -> str:
    stream = WorkflowStreamClient.create(temporal_client, workflow_id=chat_id)
    converter = temporal_client.data_converter.payload_converter
    output: list[str] = []

    async for item in stream.subscribe(
        ["delta", "retry", "close"], result_type=RawValue
    ):
        if item.topic == "retry":
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

Key choices in this shape:

- The **Activity** is the publisher because it owns the non-deterministic LLM call. The Workflow processes only the Activity's return value, never reading its own stream.
- The Activity publishes a `RETRY` event when `activity.info().attempt > 1`, letting the UI clear accumulated deltas before the next attempt's deltas arrive.
- Termination uses an **ack handshake**: the consumer signals the Workflow once it has the `close` event so the Workflow can return as soon as the subscriber confirms. The `wait_condition` timeout is the fallback when no subscriber is attached.
- `force_flush=True` is used only on the first delta and on the `RETRY` sentinel — per-delta `force_flush=True` would generate one Signal per token.

## See also

- [Workflow Streams samples (samples-python)](https://github.com/temporalio/samples-python/tree/main/workflow_streams) — runnable scenarios covering basic publish/subscribe, reconnecting subscribers, external publishers, and bounded logs.
- [`temporalio.contrib.workflow_streams` API reference](https://python.temporal.io/temporalio.contrib.workflow_streams.html).
- `references/python/patterns.md` — Signals, Updates, and Queries that Workflow Streams is built on.
- `references/python/data-handling.md` — payload converters and codecs.
- `references/python/ai-patterns.md` — AI/LLM workflow patterns where streaming output is the headline use case.
