# Python SDK Payload Validation

This page covers eager, Worker-side (and Client-side) validation of payload
and Memo sizes before they reach the Temporal Service. The Python SDK does
**not** publish a single API named `PayloadValidator`; instead, validation is
a pattern you assemble out of the SDK's documented data-conversion and
interceptor seams.

## Why eager validation

The Temporal Service rejects any single payload larger than 2 MB
 and rejects any
gRPC request larger than 4 MB .
A Workflow Task can hit the 4 MB gRPC ceiling even when every individual
payload is under 2 MB
. Even with the
graceful failure mode introduced in Python SDK 1.23.0+ (where the Workflow
Task fails with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` and the
Workflow stays open) ,
catching oversized payloads before submission saves a Workflow Task round
trip and avoids surfacing a task failure to operators. For SDK versions
older than 1.23.0 (and for all non-Python SDKs in this respect), the
consequences are harsher: an oversized Workflow or Activity input terminates
the Workflow, and an oversized Workflow result loops in retry forever
.

## What the server enforces

| Limit | Value | Notes |
| --- | --- | --- |
| Per-payload size | 2 MB  | Default on self-hosted, fixed on Temporal Cloud  |
| Per-payload warn | 256 KB  | `Blob size exceeds limit.` server log  |
| gRPC message | 4 MB  | Each request, including all commands and metadata  |
| Event History transaction | 4 MB  | `DefaultTransactionSizeLimit`  |

Notes on each limit:

- **2 MB per payload.** Enforced by the Temporal Service. The error string
  is `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.`
   and,
  through the SDK, `[TMPRL1103] Attempted to upload payloads with size that
  exceeded the error limit.`
  . On self-hosted
  deployments the limit is configurable
  . On Temporal
  Cloud the limit is fixed and **non-configurable**
  .
- **256 KB warn threshold.** On self-hosted deployments only, the Temporal
  Service logs `Blob size exceeds limit.` at 256 KB
  . This
  is a server-side warning, not a client-side rejection. Do not confuse it
  with the External Storage default of **256 KiB**, which is the threshold
  the SDK uses to decide whether to offload a payload to S3 (see below)
  .
- **4 MB gRPC.** Enforced by gRPC itself
  . A
  single Workflow Task that schedules many Activities sends one request
  containing every command and every input
  .
- **4 MB Event History transaction.** The largest transaction size allowed
  when persisting Event History
  .
  Non-configurable on Temporal Cloud
  .

## Failure modes in Python

The Python SDK and the Temporal Service have different behaviors depending
on SDK version, on which message exceeded which limit, and on whether the
payload was an input or a result.

### Python SDK 1.23.0+

Both oversized-payload (2 MB) and oversized-gRPC (4 MB) failures surface as
a Workflow Task failure with cause
`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`

. The Workflow
is not terminated; it stays open. You can deploy a fix and the Workflow
continues from where it failed
. For Activities,
the Activity fails with an explicit error rather than timing out silently
.

This is the graceful mode. It is still better to validate eagerly so that
the Workflow Task does not need to fail at all.

### All other SDK versions (and pre-1.23.0 Python)

The behavior depends on which direction the oversized data was traveling
:

- **Workflow input / Activity input over 2 MB.** The Temporal Service
  rejects the command and **terminates** the Workflow. You have to restart
  it . Possible
  command-attribute error strings include
  `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input
  exceeds size limit`
  .
- **Activity result over 2 MB.** The Temporal Service rejects the Activity
  completion and the Activity fails
  .
- **Workflow result over 2 MB.** The Workflow gets **stuck in a retry
  loop**. The server rejects `CompleteWorkflowExecution`, and replay
  produces the same oversized result on every retry
  . The error
  strings are `Complete result exceeds size limit` and
  `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`
  .
- **Workflow Task over 4 MB gRPC.** The Workflow gets stuck in a retry loop
  that is not visible in Event History. The SDK catches the gRPC error and
  sends a failed Workflow Task response with cause
  `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`. Replay produces the
  same oversized request every time, so the Workflow never makes progress
  .
- **Activity Task over 4 MB gRPC.** The Activity executes successfully but
  the Worker cannot deliver the oversized result over gRPC. The Activity
  retries until `ScheduleToCloseTimeout` expires; without that timeout, the
  Activity retries indefinitely
  .

### Update messages

If an Update payload causes the failure, the cause is
`WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE`
.

## Validation seams the Python SDK exposes

The allowed docs do not publish a Python class named `PayloadValidator`.
Instead, three documented seams let you intercept payloads and inspect them
before they leave the process:

1. **Custom Payload Codec.** A Payload Codec sits between the Payload
   Converter and the wire
   . It
   sees serialized bytes. A custom codec can inspect `len(payload.data)` for
   each payload and refuse to encode if it exceeds your ceiling. The
   troubleshooting guide explicitly suggests a custom Payload Codec for
   compression of large payloads
   ; the same seam
   is available for size enforcement. The Python data-encryption guide is
   where Payload Codecs are documented in the SDK
   .
2. **Custom `EncodingPayloadConverter` inside a `CompositePayloadConverter`.**
   The default Payload Converter is a `CompositePayloadConverter` that tries
   each `EncodingPayloadConverter` in order until one handles the value
   .
   To handle custom data types, create a new `EncodingPayloadConverter`
   .
   You can wrap an existing converter and inspect the size of the produced
   `Payload` before returning it. This runs **before** the Payload Codec, so
   it sees the bytes the converter produced for one value at a time.
3. **Interceptors.** The Python interceptors guide lists five categories of
   inbound and outbound calls you can wrap
   . The
   encyclopedia entry explicitly lists `Input/output validation` as a common
   use case for interceptors
   . The relevant interceptor
   classes for the validation pattern are:
   - `OutboundInterceptor` (Client) — wraps Client calls such as
     `start_workflow()` and `signal_workflow()` before they hit the network
     .
   - `WorkflowOutboundInterceptor` — wraps calls a Workflow makes to the
     SDK, such as `start_activity()` and `start_child_workflow()`
     .
   - `WorkflowInboundInterceptor` — wraps calls arriving into a Workflow
     Execution, including handling Messages
     .
   - `ActivityInboundInterceptor` — wraps Activity execution
     .

Each seam runs at a different point in the pipeline. A Payload Codec sees
every payload that crosses the wire; an interceptor only sees the calls it
wraps. Pick the seam that fits the layer at which you want to fail.

## Pattern: size-check inside a custom Payload Codec

The Payload Codec sees serialized bytes for every payload that flows in or
out, so it is the most uniform place to enforce a size ceiling. The Payload
Codec interface is not shown verbatim in the allowed docs, but the docs
confirm that:

- The Payload Codec sits between the Payload Converter and External Storage
  in the data-conversion pipeline
  .
- The troubleshooting guide tells you to use a custom Payload Codec to
  modify the bytes of large payloads
  .
- The Python external-storage guide describes the codec as the layer that
  has already run by the time storage drivers receive a `Payload`
  .

The general shape:

```python
# Subclass the SDK's PayloadCodec abstract class. Override encode() to
# inspect serialized bytes and raise if any single payload's data exceeds
# your ceiling. decode() should pass through unchanged.
#
# Wire the codec onto a DataConverter and pass that DataConverter to both
# the Client and the Worker. Workflows and Activities running on that
# Worker will then route all serialized payloads through your codec.

# Example skeleton (token names per the docs; do not copy verbatim):
#
#   class SizeLimitCodec(PayloadCodec):
#       def __init__(self, max_bytes: int = 1_500_000) -> None:
#           self._max_bytes = max_bytes
#
#       async def encode(self, payloads):
#           for p in payloads:
#               if len(p.data) > self._max_bytes:
#                   raise ValueError(
#                       f"payload size {len(p.data)} exceeds "
#                       f"limit {self._max_bytes}"
#                   )
#           return list(payloads)
#
#       async def decode(self, payloads):
#           return list(payloads)
```

Notes on the example:

- `len(p.data)` works because the `Payload` is a protobuf message whose
  `data` field is the serialized bytes; the custom storage driver doc
  confirms this protobuf shape by serializing with
  `payload.SerializeToString()` and reconstructing with
  `payload.ParseFromString(raw)`
  .
- Pick your ceiling well below 2 MB so payloads that come close to the
  limit do not eat your entire gRPC budget. A Workflow Task that schedules
  several Activities sends one combined request
  .
- Codec `decode()` should be a no-op for the validator. Raising on decode
  would block payloads that are already in Event History.
- Wire the codec onto the `DataConverter` and pass that converter to both
  the Client and the Worker, the same way External Storage is wired
  .

## Pattern: validate inputs via an interceptor

The encyclopedia interceptors entry lists `Input/output validation` as a
canonical use case for interceptors
. Use a Client outbound
interceptor (or a Workflow outbound interceptor) to inspect arguments
**before** they are submitted.

The Python interceptors guide shows the shape of a Client outbound
interceptor: subclass `temporalio.client.Interceptor` and return an
`OutboundInterceptor` from `intercept_client()` that overrides the methods
you care about
.
For example, an outbound `start_workflow()` interceptor receives a
`StartWorkflowInput`
, which you
can inspect before passing it to `super().start_workflow(input)`.

Worker-side, define a class inheriting from `worker.Interceptor`, implement
`intercept_activity()` to return an `ActivityInboundInterceptor`, and use
`workflow_interceptor_class` to return a `WorkflowInboundInterceptor` for
Workflow-side interception

. Register
Worker-only interceptors in the `interceptors` argument of `Worker()`
; register Client
interceptors in the `interceptors` argument of `Client.connect()`
.

Caveats:

- Workflow inbound and outbound interceptor methods run during replay; use
  replay-safe APIs in them
  . A size check
  on an `input` object that does not call any non-deterministic API is
  replay-safe.
- An interceptor that lives in user code sees Python objects, not
  serialized bytes. To estimate the on-wire size, you either serialize
  through the configured Payload Converter or fall back to checking source
  data (for example, `len(b)` on a `bytes` argument). For bytes-accurate
  validation, the Payload Codec is a better seam.
- If your interceptor class inherits from both `client.Interceptor` and
  `worker.Interceptor`, pass it to `Client.connect()` rather than to
  `Worker()`
  .

## Pattern: offload via External Storage (complementary)

External Storage is **not** validation; it is offload. But it can keep
payloads that would otherwise trip the 2 MB limit off the wire entirely, by
uploading them to S3 (or another backend) and replacing them with a small
reference token in the Event History
.

Configure External Storage on the `DataConverter` using `ExternalStorage`
and pass the converter to your Client and Worker
.
By default, payloads larger than 256 KiB are offloaded
.
Adjust the threshold with the `payload_size_threshold` parameter; set it to
0 to externalize all payloads regardless of size

.

```python
# Example threshold configuration (verbatim from the docs):
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```

External Storage sits at the end of the data-conversion pipeline, after
both the Payload Converter and the Payload Codec
. That
ordering matters: if you use both a size-checking codec and External
Storage, the codec runs **first**, so the codec sees the full payload
bytes. If your validator's purpose is "fail rather than offload past a
ceiling", configure the codec to reject above that ceiling; if your
validator's purpose is "stay under 2 MB at all costs", lower
`payload_size_threshold` so offload happens before the codec ever sees an
oversized payload.

External Storage is currently in **Pre-Release**
;
APIs may change.

## Memo size considerations

Memo data is a payload. The allowed docs do not publish a separate numeric
limit for Memo payloads. What the docs do say:

- The `Bad Modify Workflow Properties Attributes` error indicates that
  attributes on `Upsert Memo` or on a payload are exceeding size limits;
  the resolution is to "adjust the size of the Memo or payload to fit
  within the system's limits"
  .
- The `Bad Continue as New Attributes` error explicitly calls out that "if
  the payload or memo exceeded size limits, adjust the input size"
  .
- The configurable-defaults page describes the 2 MB blob-size limit as
  applying to "Payloads (including Workflow context and each Workflow and
  Activity argument and return value)"
  .

In other words, Memo payloads are subject to the same per-payload 2 MB
ceiling and contribute to the same 4 MB gRPC and 4 MB Event-History
transaction ceilings as Workflow and Activity payloads. Do **not** assert
a separate numeric Memo-only limit in your code or documentation.

If you want to validate Memo size, the Client outbound interceptor for
`start_workflow()` is the place: `StartWorkflowInput` is available there
, and you can
inspect the memo before submission.

## What to check before shipping

- **Which data path is this?** Workflow input, Activity input, Workflow
  result, Activity result, Signal payload, Update payload, or Memo. Each
  has a different failure mode if it goes over 2 MB
  .
- **What is your SDK version?** Python SDK 1.23.0+ fails Workflow Tasks
  gracefully; older versions terminate Workflows on oversized inputs and
  loop forever on oversized results
  .
- **Are you on Temporal Cloud?** The 2 MB limit is non-configurable on
  Cloud ; the 4 MB
  Event-History transaction limit is non-configurable on Cloud
  .
- **Is your validation ceiling well below 2 MB?** A Workflow Task that
  schedules multiple Activities is one combined gRPC request
  ; a per-payload
  ceiling of, say, 1.5 MB leaves headroom for several payloads plus
  metadata in the same request.
- **Are you also using External Storage?** Offload removes bytes from the
  wire entirely
  . A
  size-checking codec plus a low `payload_size_threshold` is a robust
  combination: the threshold catches most large payloads before they hit
  the codec; the codec catches anything that slipped through.
- **Are you handling Memo size?** Memo data is a payload, subject to the
  same limits . Validate it on the
  Client side via an outbound interceptor on `start_workflow()`.

## See also

- `references/core/gotchas.md` &sect; Payload Size Limits — cross-SDK
  framing of the 2 MB and 4 MB ceilings.
- `references/python/data-handling.md` — Payload Converters, Payload
  Codecs, and Data Converter wiring for the Python SDK.
