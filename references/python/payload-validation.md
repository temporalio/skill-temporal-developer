# Python SDK Payload Validation

## Overview

The Temporal Service enforces two distinct size limits on data exchanged between Workers and the Service: a per-payload limit and a per-gRPC-message limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:17-22 -->

- **Per-payload limit:** 2 MB on Temporal Cloud, configurable on self-hosted deployments with a default of 2 MB. <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-27 -->
- **Per-gRPC-message limit:** 4 MB per request. This applies to the full request, including all payload data and command metadata. <!-- docs/troubleshooting/blob-size-limit-error.mdx:86-87 -->

A Workflow can hit the gRPC limit even when every individual payload is under 2 MB — scheduling several Activities with moderate inputs, or hundreds of Activities with tiny inputs in the same Workflow Task, can push the combined request past 4 MB. Activity results are also subject to this limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->

A payload is the serialized binary data for the input and output of Workflows and Activities. <!-- docs/troubleshooting/blob-size-limit-error.mdx:27-28 -->

## Python SDK 1.23.0+ behavior

Starting with Python SDK 1.23.0, the SDK fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` when a payload exceeds the size limit. The Workflow is **not** terminated and remains open, so you can deploy a fix and allow the Workflow to continue. <!-- docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->

The same recovery model applies when a gRPC message exceeds 4 MB: the SDK fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, the Workflow remains open, and for Activities the Activity fails with an explicit error instead of timing out silently. <!-- docs/troubleshooting/blob-size-limit-error.mdx:106-108 -->

This is the practical effect:

- **Oversized payload detected.** Workflow Task fails with `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. Workflow stays open. Deploy a fix (smaller payload, External Storage, or codec compression) and the Workflow resumes from the last successful Workflow Task.
- **Oversized Activity result detected.** The Activity fails with an explicit error. No silent `ScheduleToCloseTimeout` after retries. <!-- docs/troubleshooting/blob-size-limit-error.mdx:107-108 -->

Compare this with all other SDK versions, where an oversized payload terminates the Workflow (for inputs) or causes infinite retry loops (for results). <!-- docs/troubleshooting/blob-size-limit-error.mdx:49-55, 110-123 -->

## Error messages you may see

Depending on which operation carried the oversized data and which SDK version is in use, the error surface differs. <!-- docs/troubleshooting/blob-size-limit-error.mdx:32-40 -->

For payload size errors:

- `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 -->
- `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` <!-- docs/troubleshooting/blob-size-limit-error.mdx:36 -->
- `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:37 -->
- `Complete result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:38 -->
- `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:39 -->
- `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:40 -->

For gRPC message size errors:

- `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:99 -->
- `ScheduleToCloseTimeout` (Activities only, when the SDK does not fail the Activity explicitly) <!-- docs/troubleshooting/blob-size-limit-error.mdx:100 -->

## Activity parameter and return-value limits

Each Activity argument is limited to a maximum size of 2 MB, and the total size of the gRPC message — which includes all arguments — is limited to a maximum of 4 MB. <!-- docs/develop/python/activities/basics.mdx:72-73 -->

Activity return values are subject to the same limits: the default payload size limit is 2 MB, and there is a hard limit of 4 MB for any gRPC message size in the Event History transaction. All return values are recorded in the Workflow Execution Event History. <!-- docs/develop/python/activities/basics.mdx:115-118 -->

Because all Payload data is recorded in the Event History, large Event Histories can affect Worker performance — the entire Event History may be transferred to a Worker Process with a Workflow Task. <!-- docs/develop/python/activities/basics.mdx:75-78 -->

## How to keep payloads under the limits

The blob-size-limit-error troubleshooting guide lists two resolution patterns. <!-- docs/troubleshooting/blob-size-limit-error.mdx:57-83 -->

### 1. Offload large payloads to External Storage (claim-check pattern)

External Storage is built into the Python SDK and offloads payloads larger than a configured threshold to an external store like Amazon S3, replacing them with a small reference token in Event History. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-34, 82-85 -->

External Storage is currently in Pre-Release. APIs are experimental and may change. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:26-28 -->

Configuration parameter: `payload_size_threshold`. By default, payloads larger than 256 KiB are offloaded; set to 0 to externalize all payloads regardless of size. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:195-197 -->

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:200-209 -->

`payload_size_threshold` is **not** an eager-validation knob. It controls when External Storage offloads a payload; it does not change the server-side 2 MB / 4 MB enforcement, and it does not configure when the SDK fails a Workflow Task. See [Python SDK: External Storage](https://github.com/temporalio/skill-temporal-developer/blob/main/references/python/data-handling.md) for setup details.

### 2. Compression via a custom Payload Codec

Compression with a custom Payload Codec may address the immediate issue, but if payload sizes continue to grow, the problem can arise again. <!-- docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->

### 3. Batching for gRPC message limits

If the gRPC 4 MB limit is the issue rather than per-payload size, break larger batches of commands into smaller ones — process Activities or Child Workflows in smaller batches within a Workflow, or execute Activities in smaller batches within a single Workflow Task with brief sleeps between batches. <!-- docs/troubleshooting/blob-size-limit-error.mdx:127-133 -->

## Failure modes for older Python SDK versions and other SDKs

For "all other SDK versions" — i.e. Python before 1.23.0, and the Go/Java/TypeScript/.NET SDKs as documented — payload-size failures are loud and expensive: <!-- docs/troubleshooting/blob-size-limit-error.mdx:49-55 -->

- **Workflow input or Activity input over 2 MB:** The Temporal Service rejects the command and **terminates the Workflow**. You must resolve the issue and restart the Workflow. <!-- docs/troubleshooting/blob-size-limit-error.mdx:51-52 -->
- **Activity result over 2 MB:** The Temporal Service rejects the Activity completion and the Activity fails with an error. <!-- docs/troubleshooting/blob-size-limit-error.mdx:53 -->
- **Workflow result over 2 MB:** The Workflow gets stuck in a retry loop. The server rejects the `CompleteWorkflowExecution` command, and replay produces the same oversized result. <!-- docs/troubleshooting/blob-size-limit-error.mdx:54-55 -->

For gRPC message limits on older versions: <!-- docs/troubleshooting/blob-size-limit-error.mdx:110-123 -->

- **Workflow Tasks over 4 MB:** Stuck retry loop not visible in Event History. The SDK catches the gRPC error and sends `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`. Replay produces the same oversized request every time. <!-- docs/troubleshooting/blob-size-limit-error.mdx:112-116 -->
- **Activity Tasks over 4 MB:** The Activity executes successfully but the result can't be delivered. Each retry succeeds locally but fails to deliver. The Activity retries until `ScheduleToCloseTimeout` expires, or indefinitely if no such timeout is set. Only `ResourceExhausted` shows up — in Worker logs, not in Event History. <!-- docs/troubleshooting/blob-size-limit-error.mdx:118-123 -->

The takeaway: upgrading to Python SDK 1.23.0+ is the cheapest defense against silently-stuck Workflows caused by oversized payloads.

## Server-side enforcement (background)

The 2 MB per-payload limit corresponds to the server's `limit.blobSize.error` dynamic configuration key (default 2 MB = 2 × 1024 × 1024). A separate `limit.blobSize.warn` key (default 512 KB) emits a warning to server logs before the hard error threshold is reached. <!-- docs/references/dynamic-configuration.mdx:209-210 -->

On Temporal Cloud the per-payload limit is **non-configurable** at 2 MB and the per-Event-History-transaction limit is non-configurable at 4 MB. <!-- docs/evaluate/temporal-cloud/limits.mdx:227-236 -->

On self-hosted deployments, the per-payload limit is configurable; the default is 2 MB. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 -->

## Quick checklist

- Run the Python SDK at version 1.23.0 or newer so payload-size errors fail Workflow Tasks rather than terminate Workflows or trigger silent retry loops.
- Treat 2 MB per payload and 4 MB per gRPC message as hard limits in design. On Cloud they are non-configurable; on self-hosted, plan as if they were.
- For Workflows that may handle data near the limit, configure External Storage on the `DataConverter` and pick a `payload_size_threshold` well under 2 MB.
- For Workflows that schedule many Activities or Child Workflows in a single Workflow Task, batch them and pause between batches to stay under 4 MB.
- Always set `ScheduleToCloseTimeout` on Activities — otherwise an oversized Activity result on an older SDK retries indefinitely.

## See also

- `references/python/data-handling.md` — Python data converters, External Storage setup details, custom storage drivers.
- `references/core/gotchas.md` — short summary of payload size limits as an anti-pattern.
- `references/core/error-reference.md` — `TMPRL1103` entry and other Workflow Task error codes.
- `docs/troubleshooting/blob-size-limit-error.mdx` — canonical troubleshooting reference.
