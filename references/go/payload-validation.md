# Go SDK Payload Validation

## Why eager validation

The Temporal Service enforces a 2 MB per-payload limit and gRPC enforces a 4 MB
per-message limit on every request a Worker sends back to the server.
The Go SDK is not part of the "Python SDK 1.23.0+" graceful-failure cohort, so
when a Worker tries to upload an oversized payload the consequences are harsh:
oversized Workflow input terminates the Workflow, an oversized Activity result
fails the Activity, an oversized Workflow result puts the Workflow in a stuck
retry loop, and oversized gRPC messages also produce stuck retries that are
not visible in the Event History.
Catching size problems on the Worker before the bytes go on the wire lets you
fail fast with a controlled error rather than rely on server-side rejection.

## What the server enforces

| Limit | Value | Source / failure cue |
| --- | --- | --- |
| Per-payload (Workflow context, each Workflow/Activity argument, each result) | 2 MB error, 256 KB warn | `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.`  |
| Per gRPC message (entire request, all commands + metadata) | 4 MB | gRPC limit per message received   |
| Event History transaction (`DefaultTransactionSizeLimit`) | 4 MB | Largest transaction size allowed for persistence of Event Histories  |

The 2 MB per-payload limit is "configurable on self-hosted deployments with a
default of 2 MB"  but
"non-configurable for Temporal Cloud".
The 4 MB Event-History transaction limit is also "non-configurable for Temporal
Cloud".

A single Workflow Task can blow through the 4 MB gRPC limit even when every
individual payload is under 2 MB: "Scheduling several Activities with
moderate-sized inputs, or hundreds of Activities with tiny inputs in the same
Workflow Task can push the combined request past 4 MB."
Treat the 2 MB and 4 MB limits as two independent ceilings; eager validation
that only checks individual payloads will not catch the gRPC case.

### Server-side error strings to recognize

The troubleshooting doc lists the messages the server can emit when payloads
exceed the limit:

- `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`
- `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.`
- `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit`
- `Complete result exceeds size limit`
- `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`
- `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE`

For the gRPC case the cues are `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`
and Activity-only `ScheduleToCloseTimeout`.

## Failure modes in the Go SDK (no graceful path)

The troubleshooting doc carves the SDK ecosystem into "Python SDK 1.23.0+" and
"All other SDK versions" ; the
Go SDK is in the "all other" bucket. Concretely:

- **Workflow or Activity input over 2 MB:** "The Temporal Service rejects the
  command and terminates the Workflow. You'll need to resolve the issue and
  restart the Workflow."
- **Activity result over 2 MB:** "The Temporal Service rejects the Activity
  completion and the Activity fails with an error."
- **Workflow result over 2 MB:** "The Workflow gets stuck in a retry loop. The
  server rejects the `CompleteWorkflowExecution` command, and replay produces
  the same oversized result."
- **gRPC message over 4 MB from a Workflow Task:** "The Workflow gets stuck in
  a retry loop that isn't visible in the Event History."
- **gRPC message over 4 MB from an Activity:** "The Activity gets stuck in a
  retry loop or exits with a `ScheduleToCloseTimeout`. ... The `ResourceExhausted`
  gRPC error only appears in Worker logs."

None of these failure modes are friendly to debug after the fact. Worker-side
size checks turn them into a single explicit error you control.

## Validation seams the Go SDK exposes

The allowed docs do not publish a named `PayloadValidator` API for the Go SDK.
What the docs do publish are three documented seams where Worker-side code can
observe payloads before they leave the process:

- **Custom `PayloadCodec`.** "Implement your own claim check pattern by using a
  custom Payload Codec."
  In the Go data-handling pipeline the Payload Codec sits between the Payload
  Converter and External Storage: "the application data has already been
  serialized by the Payload Converter and Payload Codec before it reaches the
  driver."
  This is the seam closest to the wire, so a custom codec is the most reliable
  place to enforce a size ceiling on serialized bytes.
- **Custom `PayloadConverter`.** "Use a Composite Data Converter to apply
  custom, type-specific Payload Converters in a specified order."
  "`NewCompositeDataConverter` creates a new instance of `CompositeDataConverter`
  from an ordered list of type-specific Payload Converters."
  A custom converter sees the marshaled output for the types it handles and can
  reject values it would convert into oversized payloads. Note this is per-type;
  data routed to another converter in the composite never reaches yours.
- **Interceptors.** The encyclopedia entry on Interceptors lists "Input/output
  validation" as one of the common use cases.
  Interceptors "work like middleware: each interceptor wraps the next, forming
  a chain that executes around the underlying operation."
  The Go-specific interceptor mechanics are not covered in the docs allowed for
  this reference, so consult the Go SDK API docs for the concrete interfaces.

The right seam depends on what you want to validate. Bytes on the wire belong
in a Codec; type-shaped business validation belongs in a Converter; cross-
cutting "every Activity input must be smaller than X" belongs in an Interceptor.

## Pattern: size-check inside a custom PayloadCodec

A Payload Codec "converts bytes to bytes": the `Encode` step runs on outbound
data, after the Payload Converter has produced `*commonpb.Payload` values, and
the `Decode` step reverses it on inbound data. The data flow is documented as
"the application data has already been serialized by the Payload Converter and
Payload Codec before it reaches the driver" for External Storage.

A size-check codec inspects each outbound `*commonpb.Payload`'s `Data` field
length and returns an error if it exceeds a ceiling that is set well below the
2 MB server limit. Leaving headroom matters because:

1. The gRPC message wrapping the payload includes commands and other metadata,
   so any payload that approaches 2 MB risks pushing the request near 4 MB.
2. The 2 MB per-payload limit is non-configurable on Temporal Cloud.

```go
// Sketch only. Refer to the converter.PayloadCodec interface in the Go SDK
// for the canonical method signatures.
//
// The codec implements Encode(out) and Decode(in), each of which sees a
// []*commonpb.Payload. Encode is the right place to enforce a ceiling
// before bytes are handed to the next layer.

type SizeLimitCodec struct {
    Max int // bytes; set well below 2 MB to leave gRPC headroom
}

func (c *SizeLimitCodec) Encode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    for _, p := range payloads {
        if c.Max > 0 && len(p.GetData()) > c.Max {
            return nil, fmt.Errorf(
                "payload size %d exceeds configured ceiling %d (server limit is 2 MB)",
                len(p.GetData()), c.Max,
            )
        }
    }
    return payloads, nil
}

func (c *SizeLimitCodec) Decode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    return payloads, nil
}
```

Compose this codec with your existing Data Converter when you build the Client.
The Go data-handling docs show that the default pipeline already chains the
Payload Converter and Payload Codec layers, with the Codec running closer to
the wire.
The codec wrapping mechanics (the converter type that pairs a `PayloadCodec`
with a `DataConverter`) are not described in the docs allowed here; consult the
Go SDK API reference for the exact wrapper type.

A few rules of thumb when building this pattern:

- **Set the ceiling below 2 MB, not at 2 MB.** The 2 MB limit applies to the
  raw payload, but a Workflow Task can carry multiple payloads plus command
  metadata in the same 4 MB gRPC envelope.
- **Apply it to both directions if it matters.** `Encode` covers outbound
  payloads from the Client and Worker; `Decode` covers payloads coming back in.
- **Order matters relative to compression and External Storage.** External
  Storage "runs after the Payload Codec, [so] if you use an encryption codec,
  payloads are already encrypted before upload to your store."
  A size-check codec that runs before External Storage will see the
  pre-offload bytes; running External Storage after the size check is what
  lets the offload mechanism rescue payloads that would otherwise be rejected.

## Pattern: offload via External Storage (complementary)

External Storage is not validation; it is a claim-check mechanism that
offloads oversized payloads to an external store and replaces them with a
small reference in the Event History.
"When a Temporal Client sends a payload that exceeds the configured size
threshold, the storage driver uploads the payload to your external store and
replaces it with a lightweight reference. Payloads below the threshold stay
inline in the Event History."

In Go you configure this on the Client by passing `converter.ExternalStorage`
with one or more `converter.StorageDriver` instances:

```go
c, err := client.Dial(client.Options{
    HostPort: "localhost:7233",
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{driver},
    },
})
```

The threshold above which payloads are offloaded is controlled by
`PayloadSizeThreshold`: "By default, payloads larger than 256 KiB are offloaded
to external storage. You can adjust this with the `PayloadSizeThreshold` option,
even setting it to 1 to externalize all payloads regardless of size."
"A value of 0 is interpreted as the default (256 KiB)."

The encyclopedia entry summarizes the same point: "**Size threshold.** The
driver offloads payloads larger than this value, which defaults to 256 KiB."

Why this is complementary to validation, not a substitute:

- External Storage **is the recommended primary mitigation**. The
  troubleshooting doc lists "Offload large payloads to an object store" as
  step 1, naming the claim-check pattern and pointing to External Storage and
  custom Payload Codecs as ways to implement it.
- It is still a `Pre-Release` feature; "APIs and configuration may change
  before the stable release."
  An explicit size guard catches mistakes even before this layer kicks in.
- External Storage does not protect against the 4 MB gRPC limit driven by
  command count: "A Workflow can hit this limit even when every individual
  payload is under 2 MB."
  Reduce that case by batching commands, not by raising offload limits.

## Memo size considerations

Memo data is itself a payload and is subject to the same per-payload and
aggregate limits as other payloads in the Workflow Task. The errors reference
describes "Bad Modify Workflow Properties Attributes" as failing "to validate
attributes on a property in the Upsert Memo or in a payload. These attributes
are either unset or exceeding size limits" and prescribes adjusting "the size
of the Memo or payload to fit within the system's limits".

The self-hosted defaults page documents a single "Blob size limit for Payloads
(including Workflow context and each Workflow and Activity argument and return
value)" with a 256 KB warn and 2 MB error threshold; there is no separate
numeric memo limit published.
The Event-History 4 MB transaction limit applies to Memo updates the same way
it applies to other commands.

If you size-check inside a custom `PayloadCodec`, the codec sees memo payloads
on the same path it sees Workflow and Activity payloads, so a single ceiling
covers all of them. If you need a tighter ceiling for memo than for Workflow
inputs, do that in an Interceptor where you have the operation context.

## What to check before shipping

- **Which path is the data on?** Workflow input, Activity input, Activity
  result, Workflow result, Memo, and Signal/Update inputs each have distinct
  failure modes in the Go SDK. Map your large fields to the failure mode you
  would get and decide whether that is acceptable.
- **Is your codec ceiling well below 2 MB?** The 2 MB per-payload limit is
  one of two ceilings. The gRPC envelope is 4 MB total.
  Pick a per-payload ceiling that leaves room for command metadata and other
  payloads in the same Workflow Task.
- **Are you also using External Storage?** A size-check codec without a
  fallback rejects oversized payloads; pairing it with External Storage means
  the offload happens first and the codec only fires for truly aberrant
  cases.
- **Are you running on Temporal Cloud?** "This limit is non-configurable for
  Temporal Cloud."
  On Cloud you cannot raise the 2 MB ceiling; the answer is always to shrink
  the payload or offload it.
- **Are large Workflow Tasks driven by many small commands?** If yes, the
  fix is "Break larger batches of commands into smaller batch sizes" via
  Workflow-level or Workflow-Task-level batching.
  No codec-level size check can prevent the cumulative 4 MB gRPC failure.
- **Does your codec preserve error context?** A clean error from `Encode`
  shows up at the call site that produced the value; an oversized payload
  that reaches the server can produce a stuck retry loop with no visible
  history.

## See also

- `references/core/gotchas.md` Payload Size Limits: the cross-language summary
  of the 2 MB / 4 MB limits and their failure modes.
- `references/go/data-handling.md`: Payload Converter, Payload Codec, and
  Data Converter composition in the Go SDK.
