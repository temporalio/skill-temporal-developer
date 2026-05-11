# Payload Size Validation — Core Concepts

## Overview

In Temporal, "payload validation" refers to the size constraints the Temporal Service enforces on the serialized binary data — [Payloads](/dataconversion#payload) — that pass between the Client, Workers, and the Service, and on the gRPC envelopes that carry them. There are two distinct, independent limits: a per-payload blob size limit and a per-gRPC-message limit. Both can produce Workflow Task failures, but they have different causes, different error messages, and require different mitigations. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:17 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:21 -->

The behavior when a limit is exceeded is not uniform across SDKs — only Python SDK 1.23.0+ has documented eager-fail behavior; for all other SDK versions the Temporal Service rejects the command, and what happens next depends on which part of the Workflow carried the oversized data. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:44 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:49 --> For SDK-specific guidance see the sibling files `references/python/payload-validation.md` and `references/go/payload-validation.md`.

## The two distinct size limits

| Limit | Value | What it covers | Source |
| --- | --- | --- | --- |
| Per-payload blob size | 2 MB (Temporal Cloud); 2 MB default on self-hosted | A single serialized payload — Workflow context, Workflow/Activity input, Workflow/Activity result, Signal/Update input, memo, etc. | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:26 --> <!-- documentation/docs/evaluate/temporal-cloud/limits.mdx:233 --> |
| Per-gRPC-message size | 4 MB | The full gRPC request, including all payload data and command metadata combined. A Workflow Task that schedules many Activities or returns a large result can hit this even when no individual payload exceeds 2 MB. | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:86 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:91 --> <!-- documentation/docs/evaluate/temporal-cloud/limits.mdx:218 --> |

Temporal Cloud declares both the 2 MB per-payload limit and the 4 MB Event History transaction limit non-configurable. <!-- documentation/docs/evaluate/temporal-cloud/limits.mdx:228 --> <!-- documentation/docs/evaluate/temporal-cloud/limits.mdx:236 -->

## Server defaults and configurability

Self-hosted Temporal documents the following defaults relevant to payload validation:

- gRPC: 4 MB limit on each message received. <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:36 -->
- Event batch size: `DefaultTransactionSizeLimit` is 4 MB — the largest transaction size allowed for the persistence of Event Histories. <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:37 -->
- Blob size warn threshold: documented as 256 KB, emitting `Blob size exceeds limit.` in server logs. <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:40 -->
- Blob size error threshold: 2 MB, producing `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.` <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:41 -->

The blob size thresholds are exposed as dynamic configuration:

- `limit.blobSize.warn` — limit, in bytes, for BLOBs size in an Event when a warning is thrown in the server logs. <!-- documentation/docs/references/dynamic-configuration.mdx:209 -->
- `limit.blobSize.error` — limit, in bytes, for BLOBs size in an Event when an error occurs in the transaction. Default 2 MB. <!-- documentation/docs/references/dynamic-configuration.mdx:210 -->

<!-- VERIFY: The self-hosted defaults page says Temporal "warns at 256 KB" (defaults.mdx:40), but the dynamic configuration reference lists the default for `limit.blobSize.warn` as "512 KB (512 × 1024)" (dynamic-configuration.mdx:209). Which is authoritative — has one source drifted from the code, or is the page documenting a historical default? -->

## Error causes and messages

The documented `WorkflowTaskFailedCause` enum values and human-readable messages tied to payload validation:

| Condition | Documented cause / error string | Source |
| --- | --- | --- |
| Payload exceeds per-blob limit | `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:35 --> |
| Payload upload exceeded error limit | `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:36 --> |
| Activity scheduling input too large | `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:37 --> |
| Workflow / Activity result too large | `Complete result exceeds size limit` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:38 --> |
| Workflow completion result too large | `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:39 --> |
| Update workflow execution message too large | `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:40 --> |
| gRPC message exceeds 4 MB | `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:99 --> |
| Activity result undeliverable over gRPC | `ScheduleToCloseTimeout` (Activities only) | <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:100 --> |

Related entries in the Workflow Task error catalog also surface payload size as a resolution step:

- `Bad Schedule Activity Attributes` — "Adjust the size of the received payload to stay within the given size limit." <!-- documentation/docs/references/errors.mdx:99 -->
- `Bad Modify Workflow Properties Attributes` — applies to Upsert Memo or payload attributes that "are either unset or exceeding size limits." <!-- documentation/docs/references/errors.mdx:62 --> <!-- documentation/docs/references/errors.mdx:63 -->
- `Bad Continue as New Attributes` — "If the payload or memo exceeded size limits, adjust the input size." <!-- documentation/docs/references/errors.mdx:49 -->
- `Bad Signal Input Size` — "the Payload has exceeded the Signal's available input size." <!-- documentation/docs/references/errors.mdx:117 -->
- `gRPC Message Too Large` — "Workflow Task response exceeds the gRPC message size limit of 4 MB. The Workflow Execution is automatically terminated because this is a non-recoverable error." <!-- documentation/docs/references/errors.mdx:197 --> <!-- documentation/docs/references/errors.mdx:198 -->

The documented server log strings for blob size violations are `Blob size exceeds limit.` (warn) and `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.` (error). <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:40 --> <!-- documentation/docs/production-deployment/self-hosted-guide/defaults.mdx:41 -->

## Where memo fits

Memos travel as Payloads and are subject to the same per-blob constraints as any other payload — the docs do not specify a separate memo size limit. The documented error path that names memos is `Bad Modify Workflow Properties Attributes`, which covers the Upsert Memo command and instructs the user to "Adjust the size of the Memo or payload to fit within the system's limits." <!-- documentation/docs/references/errors.mdx:60 --> <!-- documentation/docs/references/errors.mdx:62 --> <!-- documentation/docs/references/errors.mdx:66 --> `Bad Continue as New Attributes` likewise treats memo size and payload size with the same instruction. <!-- documentation/docs/references/errors.mdx:49 -->

## SDK behavior overview

**Python SDK 1.23.0+** — the SDK fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is not terminated and remains open, so a fix can be deployed and the Workflow allowed to continue. The same eager-fail behavior is documented for the gRPC-message-too-large case, where the Activity also fails with an explicit error instead of timing out silently. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:47 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:106 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:108 -->

**All other SDK versions (including Go)** — the Temporal Service rejects the offending command, and the consequence depends on where the oversized data sits. For per-payload violations: Workflow input and Activity input cause the Service to reject the command and terminate the Workflow; an oversized Activity result causes the Activity to fail with an error; an oversized Workflow result puts the Workflow in a retry loop because replay produces the same oversized `CompleteWorkflowExecution` command each time. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:49 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:51 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:53 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:54 --> For per-gRPC-message violations: Workflow Tasks get stuck in a non-progressing retry loop — the SDK catches the gRPC error and sends a failed Workflow Task response with cause `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`; Activity Tasks retry until `ScheduleToCloseTimeout` expires (or indefinitely if no timeout is set), with `ResourceExhausted` visible only in Worker logs. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:112 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:114 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:118 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:122 --> Note: even where the SDK "catches the gRPC error," the upload was attempted and failed at the gRPC layer — this is not pre-send validation. For SDK-specific options and patterns see the language reference files.

## Mitigation summary

- Offload large payloads via the claim check pattern using built-in [External Storage](/external-storage) (Pre-release) or a custom [Payload Codec](/payload-codec); pass references in Workflow code rather than the data itself. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:59 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:64 -->
- Compress large payloads using a custom Payload Codec — addresses the immediate symptom but does not bound long-term growth. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:81 -->
- Break large command batches into smaller batches at the Workflow level (process Activities or Child Workflows in waves) or at the Workflow Task level (smaller batches per Task, brief sleeps between them) to stay under the 4 MB gRPC message limit. <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:127 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:128 --> <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:131 -->
- For the `gRPC Message Too Large` cause specifically, the error catalog also suggests Continue-As-New for long-running Workflows and reducing Workflow return size. <!-- documentation/docs/references/errors.mdx:203 -->

## Sources consulted

- `documentation/docs/troubleshooting/blob-size-limit-error.mdx`
- `documentation/docs/references/errors.mdx`
- `documentation/docs/production-deployment/self-hosted-guide/defaults.mdx`
- `documentation/docs/references/dynamic-configuration.mdx`
- `documentation/docs/evaluate/temporal-cloud/limits.mdx`
