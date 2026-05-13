# Go SDK Payload Validation

## Overview

The Temporal Service enforces two distinct size limits on data exchanged between Workers and the Service: a per-payload limit and a per-gRPC-message limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:17-22 -->

- **Per-payload limit:** 2 MB on Temporal Cloud, configurable on self-hosted deployments with a default of 2 MB. <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-27 -->
- **Per-gRPC-message limit:** 4 MB per request. This applies to the full request, including all payload data and command metadata. <!-- docs/troubleshooting/blob-size-limit-error.mdx:86-87 -->

A Workflow can hit the gRPC limit even when every individual payload is under 2 MB — scheduling several Activities with moderate inputs, or hundreds of Activities with tiny inputs in the same Workflow Task, can push the combined request past 4 MB. Activity results are also subject to this limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->

A payload is the serialized binary data for the input and output of Workflows and Activities. <!-- docs/troubleshooting/blob-size-limit-error.mdx:27-28 -->

## Go SDK behavior

The Temporal documentation describes one SDK with eager Workflow-Task-failure semantics for oversized payloads: Python SDK 1.23.0+. <!-- docs/troubleshooting/blob-size-limit-error.mdx:46-47 --> The Go SDK is **not** documented as exposing equivalent eager validation — there is no documented Go option such as `MaxPayloadSize` or a Worker flag that fails Tasks before upload.

What is documented for the Go SDK is the **"All other SDK versions"** failure path. The behavior depends on where the oversized data originates. <!-- docs/troubleshooting/blob-size-limit-error.mdx:49-55, 110-123 -->

### Per-payload size errors (over 2 MB)

- **Workflow input or Activity input over 2 MB.** The Temporal Service rejects the command and **terminates the Workflow**. You must resolve the issue and restart the Workflow. <!-- docs/troubleshooting/blob-size-limit-error.mdx:51-52 -->
- **Activity result over 2 MB.** The Temporal Service rejects the Activity completion and the Activity fails with an error. <!-- docs/troubleshooting/blob-size-limit-error.mdx:53 -->
- **Workflow result over 2 MB.** The Workflow gets stuck in a retry loop. The server rejects the `CompleteWorkflowExecution` command, and replay produces the same oversized result. <!-- docs/troubleshooting/blob-size-limit-error.mdx:54-55 -->

### gRPC message size errors (over 4 MB)

- **Workflow Tasks over 4 MB.** The Workflow gets stuck in a retry loop that **isn't visible in the Event History**. The Worker completes the Workflow Task and sends all the commands the Workflow produced back to the Temporal Service. If the combined size exceeds 4 MB, the SDK catches the gRPC error and sends a failed Workflow Task response with cause `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`. Replay produces the same oversized request every time, so the Workflow never makes progress. <!-- docs/troubleshooting/blob-size-limit-error.mdx:112-116 -->
- **Activity Tasks over 4 MB.** The Activity gets stuck in a retry loop or exits with a `ScheduleToCloseTimeout`. The Activity executes successfully, but the Worker can't deliver the oversized result over gRPC. The server never receives the completion, so it retries the Activity. Each retry completes successfully but fails to deliver the result. The Activity retries until `ScheduleToCloseTimeout` expires. If no `ScheduleToCloseTimeout` is set, the Activity retries indefinitely until the Workflow is manually terminated. The `ResourceExhausted` gRPC error only appears in **Worker logs**, not in Event History. <!-- docs/troubleshooting/blob-size-limit-error.mdx:118-123 -->

The practical consequence: **oversized payloads are diagnosed only after upload fails**, and on the Workflow result / gRPC paths the symptom is a silently stuck Workflow rather than an explicit error. Always set `ScheduleToCloseTimeout` on Activities so an oversized result eventually fails the Activity rather than retrying forever.

## Error messages you may see

Depending on which operation carried the oversized data, the error surface differs. <!-- docs/troubleshooting/blob-size-limit-error.mdx:32-40 -->

For payload size errors:

- `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` <!-- docs/troubleshooting/blob-size-limit-error.mdx:36 -->
- `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:37 -->
- `Complete result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:38 -->
- `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:39 -->
- `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:40 -->
- `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` (cause string surfaced in the Workflow Task failed event) <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 -->

For gRPC message size errors:

- `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:99 -->
- `ScheduleToCloseTimeout` (Activities only — the Activity retries until this timeout expires; only `ResourceExhausted` is visible in Worker logs) <!-- docs/troubleshooting/blob-size-limit-error.mdx:100, 118-123 -->

## Activity parameter and return-value limits

There is no explicit limit to the total number of parameters that an Activity Definition may support, but there is a limit to the total size of the data that ends up encoded into a gRPC message Payload. A single argument is limited to a maximum size of 2 MB, and the total size of a gRPC message, which includes all the arguments, is limited to a maximum of 4 MB. <!-- docs/develop/go/activities/basics.mdx:74-78 -->

Activity return values are subject to the same limits: the default payload size limit is 2MB, and there is a hard limit of 4MB for any gRPC message size in the Event History transaction. All return values are recorded in a Workflow Execution Event History. <!-- docs/develop/go/activities/basics.mdx:119 -->

Because all Payload data is recorded in the Event History, large Event Histories can affect Worker performance — the entire Event History could be transferred to a Worker Process with a Workflow Task. <!-- docs/develop/go/activities/basics.mdx:80-81 -->

## How to keep payloads under the limits

The blob-size-limit-error troubleshooting guide lists two resolution patterns. <!-- docs/troubleshooting/blob-size-limit-error.mdx:57-83 -->

### 1. Offload large payloads to External Storage (claim-check pattern)

External Storage is built into the Go SDK and offloads payloads larger than a configured threshold to an external store like Amazon S3, replacing them with a small reference token in Event History. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-34, 82-85 -->

External Storage is currently in Pre-Release. APIs are experimental and may change. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:26-28 -->

Configuration option: `PayloadSizeThreshold`. By default, payloads larger than 256 KiB are offloaded; set to 1 to externalize all payloads regardless of size. A value of 0 is interpreted as the default (256 KiB). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-233 -->

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:237-244 -->

`PayloadSizeThreshold` is **not** an eager-validation knob. It controls when External Storage offloads a payload; it does not change the server-side 2 MB / 4 MB enforcement, and it does not configure a Worker to fail Tasks before upload. See `references/go/data-handling.md` for setup details.

### 2. Compression via a custom Payload Codec

Compression with a custom Payload Codec may address the immediate issue, but if payload sizes continue to grow, the problem can arise again. <!-- docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->

### 3. Batching for gRPC message limits

If the gRPC 4 MB limit is the issue rather than per-payload size, break larger batches of commands into smaller ones — process Activities or Child Workflows in smaller batches within a Workflow, or execute Activities in smaller batches within a single Workflow Task with brief sleeps between batches. <!-- docs/troubleshooting/blob-size-limit-error.mdx:127-133 -->

## Server-side enforcement (background)

The 2 MB per-payload limit corresponds to the server's `limit.blobSize.error` dynamic configuration key (default 2 MB = 2 × 1024 × 1024). A separate `limit.blobSize.warn` key (default 512 KB) emits a warning to server logs before the hard error threshold is reached. <!-- docs/references/dynamic-configuration.mdx:209-210 -->

On Temporal Cloud the per-payload limit is **non-configurable** at 2 MB and the per-Event-History-transaction limit is non-configurable at 4 MB. <!-- docs/evaluate/temporal-cloud/limits.mdx:227-236 -->

On self-hosted deployments, the per-payload limit is configurable; the default is 2 MB. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 -->

## Quick checklist

- Treat 2 MB per payload and 4 MB per gRPC message as hard limits in design. On Cloud they are non-configurable; on self-hosted, plan as if they were.
- Always set `ScheduleToCloseTimeout` on Activities — otherwise an oversized Activity result retries indefinitely with only a `ResourceExhausted` log line on the Worker.
- For Workflows that may handle data near the limit, configure External Storage on the Client `Options` and pick a `PayloadSizeThreshold` well under 2 MB. Note the Pre-Release status.
- For Workflows that schedule many Activities or Child Workflows in a single Workflow Task, batch them and pause between batches to stay under 4 MB.
- When a Workflow appears stuck without visible Event History progress, check Worker logs for `ResourceExhausted` or for cause strings like `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`.

## See also

- `references/go/data-handling.md` — Go data converters, External Storage setup details, custom storage drivers.
- `references/core/gotchas.md` — short summary of payload size limits as an anti-pattern.
- `references/core/error-reference.md` — `TMPRL1103` entry and other Workflow Task error codes.
- `docs/troubleshooting/blob-size-limit-error.mdx` — canonical troubleshooting reference.
