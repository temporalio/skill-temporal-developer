# Python SDK Streaming

## Overview

**Temporal does not have a first-class streaming primitive.** Workflows are durable and every input/output becomes an Event in history, so streaming data *through* a workflow is expensive and bloats history. There are well-established patterns for streaming *from* and *to* activities, and for observing workflow progress incrementally.

Common sources of this question:
- Streaming LLM / agent responses back to a client
- Server-Sent Events (SSE) or WebSocket endpoints backed by a workflow
- Processing a paginated API or a video/audio stream

## Pattern 1: Stream Directly from Activity to External Consumer (Recommended)

Activities are regular Python code — they can write to any external transport. Pass the destination address (queue/stream/channel) into the activity, and let the activity push incrementally.

```python
from temporalio import activity

@activity.defn
async def stream_llm_response(prompt: str, channel_id: str) -> str:
    full_text = []
    async for chunk in llm_client.stream(prompt):
        # Push each chunk to Redis pub/sub, Pusher, Kafka, Ably, a websocket, etc.
        await pubsub.publish(channel_id, chunk)
        full_text.append(chunk)
        activity.heartbeat(len(full_text))  # checkpoint progress
    return "".join(full_text)
```

The workflow starts the activity with a channel ID; a separate HTTP/SSE endpoint in your API tier reads from the same channel and forwards bytes to the client.

**Retries:** emit a "reset" sentinel before retrying so the consumer can discard the partial prefix, or design the consumer to dedupe by sequence number.

## Pattern 2: Progress via Workflow Queries / Updates / Signals

For low-frequency progress updates where the consumer polls (not true streaming):

```python
@workflow.defn
class GenerateWorkflow:
    def __init__(self) -> None:
        self._chunks: list[str] = []
        self._done = False

    @workflow.run
    async def run(self, prompt: str) -> str:
        self._chunks = await workflow.execute_activity(
            generate_chunks, prompt, start_to_close_timeout=timedelta(minutes=5),
        )
        self._done = True
        return "".join(self._chunks)

    @workflow.query
    def progress(self) -> dict:
        return {"chunks": self._chunks, "done": self._done}
```

Caller polls `handle.query(GenerateWorkflow.progress)`. Use Workflow **Updates** when you need request/response semantics with a response tied to a specific caller.

Every chunk you push into workflow state via signal becomes a history event. Keep the rate low (seconds, not milliseconds).

## Pattern 3: Iterate Workflow History Events

Poll the workflow's event history to observe activity starts/completions as they happen:

```python
handle = await client.start_workflow(
    FireMessageWorkflow.run, payload,
    id="...", task_queue="...",
)

async for event in handle.fetch_history_events(wait_new_event=True):
    if event.HasField("activity_task_completed_event_attributes"):
        yield_progress_to_client(event)
```

Good for showing a UI of which steps have run. Not a substitute for data-streaming.

## Pattern 4: Long-Running Heartbeating Activity for Infinite Streams

For ingesting a paginated API, video frames, or another live source:

- One long activity reads the stream and periodically heartbeats its cursor / batch offset.
- Per batch, the activity either processes inline or starts a child workflow per batch (`client.start_workflow`) to fan out processing.
- On activity retry, read `activity.heartbeat_details()` and resume from the last checkpoint.
- Subscribe to cancellation so the activity exits cleanly when the workflow is cancelled or times out.

See `references/python/patterns.md` for heartbeating details and the [samples-python polling/frequent sample](https://github.com/temporalio/samples-python/tree/main/polling/frequent).

## What Not to Do

- **Don't use a signal per chunk at high frequency.** Signals land in history, and in a sustained stream the workflow may fail to continue-as-new because signals arrive faster than they can be drained.
- **Don't store large intermediate buffers in workflow state.** Accumulated chunks grow history. Either flush to external storage (see `references/python/large-payloads.md`) or keep in activity-local memory.
- **Don't use `run_streamed`** from the OpenAI Agents SDK inside a Temporal-hosted agent — streaming isn't supported yet by the `OpenAIAgentsPlugin`. Tracked in [sdk-python#1009](https://github.com/temporalio/sdk-python/issues/1009). Use the non-streamed `Runner.run` path until first-class streaming lands.

## Summary

| Use case | Recommended pattern |
| --- | --- |
| Stream LLM tokens to a browser | Activity → Redis/Pusher/SSE server, client subscribes separately |
| Show workflow step progress in a UI | Query, Update, or history event iteration |
| Process a paginated source with millions of items | Long heartbeating activity that starts child workflows per batch |
| Stream results between activities | Blob storage + reference passing (see large-payloads.md) |
