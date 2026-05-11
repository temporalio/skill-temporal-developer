# Go SDK — Payload Size Validation

## Overview

This file covers Go-specific behavior for payload size limits. For shared concepts — the 2 MB per-payload limit, the 4 MB gRPC message limit, error message strings, and `WORKFLOW_TASK_FAILED_CAUSE_*` causes — see `references/core/payload-validation.md`.

Important up front: **eager Worker-side size validation is NOT documented for the Go SDK.** The Go SDK does not pre-validate payload sizes against server limits before sending; the documented eager-fail behavior applies only to Python SDK 1.23.0+ <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46 -->. The closest documented worker-side size-aware mechanism available in Go is External Storage's `PayloadSizeThreshold` <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:84 -->, which proactively offloads large payloads to an external store rather than failing the task.

## Documented Go behavior on size-limit violations

Go falls into the "All other SDK versions" category in the troubleshooting docs <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:49 -->. The behavior depends on which operation carried the oversized data.

### Payload size limit (2 MB per payload)

For Go, when a payload exceeds the per-payload size limit:

- **Inputs (Workflow input, Activity input):** "The Temporal Service rejects the command and terminates the Workflow. You'll need to resolve the issue and restart the Workflow." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:51-52 -->
- **Activity result:** "The Temporal Service rejects the Activity completion and the Activity fails with an error." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:53 -->
- **Workflow result:** "The Workflow gets stuck in a retry loop. The server rejects the `CompleteWorkflowExecution` command, and replay produces the same oversized result." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:54-55 -->

### gRPC message size limit (4 MB per request)

For Go, when the gRPC message exceeds the limit:

- **Workflow Tasks:** "The Workflow gets stuck in a retry loop that isn't visible in the Event History... If the combined size exceeds 4 MB, the SDK catches the gRPC error and sends a failed Workflow Task response with cause `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`. Replay produces the same oversized request every time, so the Workflow never makes progress." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:112-116 -->
- **Activity Tasks:** "The Activity gets stuck in a retry loop or exits with a `ScheduleToCloseTimeout`... Each retry completes successfully but fails to deliver the result. The Activity retries until the `ScheduleToCloseTimeout` expires. If no `ScheduleToCloseTimeout` is set, the Activity retries indefinitely until the Workflow is manually terminated. The `ResourceExhausted` gRPC error only appears in Worker logs." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:118-123 -->

Note: across all of these cases, the Go SDK reacts to the server's rejection or to the gRPC error — it does not pre-check sizes against the server limit before attempting to send.

## `PayloadSizeThreshold` — the proactive-offload worker knob

The Go SDK exposes a single documented size-aware configuration knob through External Storage. It does not fail tasks on oversized payloads; instead, it offloads them to an external store using the claim check pattern.

- Option name: `PayloadSizeThreshold` <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:84 -->
- Default: payloads larger than 256 KiB are offloaded <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:83 -->
- `PayloadSizeThreshold: 1` externalizes all payloads regardless of size <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 -->
- A value of `0` is interpreted as the default (256 KiB) <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:233 -->

Note: this is the OPPOSITE convention from the Python SDK — in Go, `0` means "use the default," not "offload everything."

Canonical snippet from the Go docs <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:237-244 -->:

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```

External Storage is in Pre-release; APIs and configuration may change before stable release <!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:14-20 -->.

## Custom Payload Codec compression

A custom Payload Codec can reduce per-payload size by compressing encoded bytes inside `Encode` (and decompressing in `Decode`) before payloads reach the Temporal Service. The Go docs show a snappy-compression Codec as an example <!-- documentation/docs/develop/go/best-practices/data-handling/data-encryption.mdx:54-101 -->. The Codec is wired in via `converter.NewCodecDataConverter` and passed through `client.Options.DataConverter` <!-- documentation/docs/develop/go/best-practices/data-handling/data-encryption.mdx:39-50 -->. The troubleshooting guide also explicitly lists "Use compression with a custom Payload Codec for large payloads" as a mitigation, while noting "if payload sizes continue to grow, the problem can arise again." <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->

## What's NOT documented for Go

Across the files consulted, the following do **not** exist for the Go SDK:

- No documented `MaxPayloadSize` (or equivalent) Worker option that fails tasks when a payload would exceed a size threshold.
- No documented eager-fail equivalent to Python SDK 1.23.0+'s `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` handling (which keeps the Workflow open instead of terminating) <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->.
- No documented metric counter for blob-size violations.

Documented mitigations to use instead:

- **External Storage / claim check pattern** — built into the SDK; offloads payloads above `PayloadSizeThreshold` <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:59-66 --><!-- documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx:22-27 -->.
- **Compression via custom Payload Codec** <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->.
- **Batching** at the Workflow or Workflow-Task level for gRPC-message-size issues <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:127-133 -->.

## Sources consulted

- `documentation/docs/troubleshooting/blob-size-limit-error.mdx`
- `documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx`
- `documentation/docs/develop/go/best-practices/data-handling/index.mdx`
- `documentation/docs/develop/go/best-practices/data-handling/data-encryption.mdx`
