# Payload Validation and Size Limits

Temporal enforces size limits on data flowing between Clients, Workers, and the
Temporal Service. There are **two distinct limits** with different scopes,
different error codes, and different mitigations. Confusing them leads to wrong
fixes. <!-- docs/troubleshooting/blob-size-limit-error.mdx:17-22 -->

This reference is language-agnostic. For SDK-specific configuration (custom
validators, External Storage setup) see:

- `references/go/payload-validation.md`
- `references/python/payload-validation.md`

## The two limits at a glance

| Limit                  | Default | Scope                          | Configurable?                                           | Canonical error                                            |
| ---------------------- | ------- | ------------------------------ | ------------------------------------------------------- | ---------------------------------------------------------- |
| Per-payload size       | 2 MB    | One individual Payload         | Self-hosted: yes <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-28 --> / Cloud: no <!-- docs/evaluate/temporal-cloud/limits.mdx:230-236 --> | `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 --> |
| Per gRPC message size  | 4 MB    | Entire gRPC request (all commands + metadata in one Workflow Task response) | Not configurable; Cloud documents it as fixed <!-- docs/evaluate/temporal-cloud/limits.mdx:217-219 --> | `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:99 --> |

These are independent failure modes. A Workflow can stay under 2 MB on every
individual payload and still blow the 4 MB gRPC limit by scheduling many
Activities (or one Activity with many moderate-sized inputs) in a single
Workflow Task. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->

## Limit 1 — Per-payload (2 MB)

### What it is

A [Payload](/dataconversion#payload) is the serialized binary form of one
Workflow or Activity input or return value. The Temporal Service enforces a
per-payload limit of 2 MB. On Temporal Cloud this limit is fixed at 2 MB; on
self-hosted deployments the default is 2 MB but can be tuned via dynamic
configuration. <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-28 -->

### Server-side warn vs. error thresholds (self-hosted)

The self-hosted server has two thresholds for blob (payload) size:

- **Warn** (soft) — logs a warning `Blob size exceeds limit.` on the server.
- **Error** (hard) — rejects the operation with
  `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.` <!-- docs/production-deployment/self-hosted-guide/defaults.mdx:39-42 -->

The dynamic-config keys and their documented defaults:

| Key                   | Purpose                       | Default                                                                                        |
| --------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------- |
| `limit.blobSize.warn` | Soft warn threshold (bytes)   | 512 KB per dynamic-config reference <!-- docs/references/dynamic-configuration.mdx:209 -->; the self-hosted defaults page lists 256 KB <!-- docs/production-deployment/self-hosted-guide/defaults.mdx:40 --> |
| `limit.blobSize.error`| Hard error threshold (bytes)  | 2 MB <!-- docs/references/dynamic-configuration.mdx:210 --> <!-- docs/production-deployment/self-hosted-guide/defaults.mdx:41 --> |

<!-- VERIFY: The dynamic-configuration table says limit.blobSize.warn default is 512 KB, but the self-hosted defaults page says 256 KB. Which is the current source of truth? -->

**Temporal Cloud:** the 2 MB per-payload limit is **non-configurable**. <!-- docs/evaluate/temporal-cloud/limits.mdx:230-236 -->

### Error codes you will see

Depending on which command carried the oversized payload and which SDK is in
use, the failure surfaces as one of these strings: <!-- docs/troubleshooting/blob-size-limit-error.mdx:32-40 -->

- `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 -->
- `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` <!-- docs/troubleshooting/blob-size-limit-error.mdx:36 -->
- `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:37 -->
- `Complete result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:38 -->
- `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:39 -->
- `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:40 -->

These map onto specific Workflow Task failure causes documented in the error
reference, including
[Bad Schedule Activity Attributes](/references/errors#bad-schedule-activity-attributes), <!-- docs/references/errors.mdx:94-99 -->
[Bad Continue as New Attributes](/references/errors#bad-continue-as-new-attributes), <!-- docs/references/errors.mdx:43-49 -->
[Bad Modify Workflow Properties Attributes](/references/errors#bad-modify-workflow-properties-attributes), <!-- docs/references/errors.mdx:60-66 -->
and [Bad Signal Input Size](/references/errors#bad-signal-input-size). <!-- docs/references/errors.mdx:115-119 -->

### Failure behavior depends on SDK version

This is the most important distinction in this whole document, because the
behavior in older SDKs is dramatically worse than in newer Python.

#### Python SDK 1.23.0+

The SDK fails the Workflow Task **locally** before sending it to the server,
with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is
**not terminated** and remains open, so you can deploy a fix and let the
Workflow continue. <!-- docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->

#### All other SDK versions

There is no documented client-side eager validation. The behavior is whatever
the server does when it receives the oversized request, and it depends on which
command carried the oversized payload: <!-- docs/troubleshooting/blob-size-limit-error.mdx:49-55 -->

| Where the oversized payload appears                  | What happens                                                                                                                                                                                                          |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Workflow input** or **Activity input**             | Temporal Service rejects the command and **terminates the Workflow**. Resolve and start a new Workflow. <!-- docs/troubleshooting/blob-size-limit-error.mdx:51-52 -->                                                  |
| **Activity result**                                  | Temporal Service rejects the Activity completion; the Activity **fails with an error**. <!-- docs/troubleshooting/blob-size-limit-error.mdx:53 -->                                                                     |
| **Workflow result** (`CompleteWorkflowExecution`)    | Workflow gets stuck in a **retry loop** — replay produces the same oversized result. <!-- docs/troubleshooting/blob-size-limit-error.mdx:54-55 -->                                                                     |

> Practical implication for non-Python (and pre-1.23.0 Python) SDKs: an
> oversized input silently destroys a Workflow Execution. An oversized return
> value silently hangs the Workflow. These failures are difficult to detect
> from inside the Workflow code.

## Limit 2 — Per gRPC message (4 MB)

### What it is

All Client/Worker/Service communication is gRPC, and gRPC enforces 4 MB per
request. This limit applies to the **full request**, including all payload data
and command metadata in a single Workflow Task response. <!-- docs/troubleshooting/blob-size-limit-error.mdx:86-89 -->

The platform also documents a related transaction limit:
`DefaultTransactionSizeLimit` is 4 MB and bounds the largest transaction
permitted for persistence of Event Histories. <!-- docs/production-deployment/self-hosted-guide/defaults.mdx:37-38 -->
Temporal Cloud documents the same 4 MB Event History transaction limit as
non-configurable. <!-- docs/evaluate/temporal-cloud/limits.mdx:222-228 -->

### How it gets hit

A Worker can hit 4 MB even when every individual payload is well under 2 MB:

- Scheduling **several Activities with moderate-sized inputs** in one Workflow
  Task. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->
- Scheduling **hundreds of Activities with tiny inputs** in one Workflow Task. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->
- A Workflow that schedules too many Activities, Child Workflows, or commands
  in a single Workflow Task, or returns a large result. <!-- docs/references/errors.mdx:198-200 -->

Activity results are also subject to this limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:93 -->

### Error codes

- `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:99 -->
- `ScheduleToCloseTimeout` (Activities only — see below) <!-- docs/troubleshooting/blob-size-limit-error.mdx:100 -->

The error-reference page for [`gRPC Message Too Large`](/references/errors#grpc-message-too-large)
states the Workflow Execution is **automatically terminated** because the
condition is non-recoverable. <!-- docs/references/errors.mdx:195-205 -->

### Failure behavior depends on SDK version

#### Python SDK 1.23.0+

The SDK fails the Workflow Task locally with cause
`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`; the Workflow remains open. For
Activities, the Activity fails with an explicit error instead of timing out
silently. <!-- docs/troubleshooting/blob-size-limit-error.mdx:106-108 -->

#### All other SDK versions

| Where the oversized gRPC message originates | What happens                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Workflow Task response**                  | The Workflow gets stuck in a **retry loop that is not visible in Event History**. The SDK catches the gRPC error and sends a failed Workflow Task response with cause `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`. Replay produces the same oversized request every time, so the Workflow never makes progress. <!-- docs/troubleshooting/blob-size-limit-error.mdx:112-116 -->                                                                       |
| **Activity Task completion**                | The Activity gets stuck in a retry loop or exits with `ScheduleToCloseTimeout`. The Activity executes successfully but its result cannot be delivered. Each retry succeeds and fails to deliver. If `ScheduleToCloseTimeout` is unset, the Activity retries indefinitely until the Workflow is manually terminated. The `ResourceExhausted` gRPC error only appears in Worker logs. <!-- docs/troubleshooting/blob-size-limit-error.mdx:118-123 --> |

## Memos

A Memo is a non-indexed set of Workflow Execution metadata supplied at start
time or in Workflow code. <!-- docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx:167-169 -->

Memos are subject to the same payload size limits as any other payload. The
error reference notes that
[Bad Modify Workflow Properties Attributes](/references/errors#bad-modify-workflow-properties-attributes)
fails when properties in the Upsert Memo or in a payload are unset or exceed
size limits, and instructs you to "adjust the size of the Memo or payload to
fit within the system's limits". <!-- docs/references/errors.mdx:60-66 -->
[Bad Continue as New Attributes](/references/errors#bad-continue-as-new-attributes)
similarly fires "if the payload or memo exceeded size limits". <!-- docs/references/errors.mdx:43-49 -->

<!-- VERIFY: Is there a documented SDK-side eager memo-size validator distinct from the generic payload validator? The docs I consulted only describe Memos as subject to the same payload limits, not as having a separate configurable validator. -->

## How to make Workers fail fast on oversized data

### Mitigation 1 — External Storage (claim check pattern)

The documented mitigation for the **per-payload (2 MB)** limit is the
[claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern),
built into the SDKs as **External Storage**. The Data Converter offloads
payloads larger than a configured size threshold to an external store (such as
Amazon S3) and passes a small reference token through the Event History. <!-- docs/troubleshooting/blob-size-limit-error.mdx:64-66 --> <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-33 -->

**Release stage:** External Storage is in **Pre-Release**. APIs and configuration
may change before stable release. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:24-30 --> <!-- docs/troubleshooting/blob-size-limit-error.mdx:74-77 -->

**Default offload threshold:** 256 KiB (not to be confused with the 256 KB
server-side blob-warn threshold above — different unit, different layer). <!-- docs/encyclopedia/data-conversion/external-storage.mdx:124 -->

**Important scope note:** External Storage addresses the **per-payload** limit
by replacing large payloads with small reference tokens. It does **not** fix
the 4 MB gRPC limit when that limit is caused by **too many commands** in a
single Workflow Task — the request is large because of command count and
metadata, not because any individual payload is large. For that, batch commands
across multiple Workflow Tasks. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 --> <!-- docs/troubleshooting/blob-size-limit-error.mdx:127-133 -->

For SDK setup of External Storage (drivers, selectors, thresholds), see the
language-specific files at `references/go/payload-validation.md` and
`references/python/payload-validation.md`.

### Mitigation 2 — Batching commands per Workflow Task

To resolve the 4 MB gRPC limit when caused by too many commands per Workflow
Task: <!-- docs/troubleshooting/blob-size-limit-error.mdx:127-133 -->

- **Workflow-level batching.** Process Activities or Child Workflows in smaller
  batches; await each batch before moving to the next.
- **Workflow-Task-level batching.** Execute Activities in smaller batches
  within a single Workflow Task; introduce brief pauses or sleeps between
  batches.

If the request is large because of **payload sizes** rather than command count,
use External Storage (or a custom Payload Codec with compression) instead. <!-- docs/troubleshooting/blob-size-limit-error.mdx:134-135 -->

### Mitigation 3 — Compression via a custom Payload Codec

A custom [Payload Codec](/payload-codec) can compress large payloads. This may
address the immediate issue, but if payload sizes continue to grow, the
problem can recur. <!-- docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->

## Quick lookup — symptom to limit

| Symptom                                                                 | Which limit                | First thing to check                                          |
| ----------------------------------------------------------------------- | -------------------------- | ------------------------------------------------------------- |
| Workflow Task failed with cause `PAYLOADS_TOO_LARGE`                    | Per-payload 2 MB           | Single oversized argument or return value                     |
| Workflow Task failed with cause `GRPC_MESSAGE_TOO_LARGE`                | Per gRPC message 4 MB      | Too many commands in one Workflow Task, or a huge result      |
| Workflow terminated immediately after start with no useful events       | Per-payload 2 MB on input (non-Python or pre-1.23.0 SDK) | Workflow / Activity input size                                |
| Activity executes successfully but Workflow appears stuck retrying it   | Per gRPC message 4 MB on Activity completion | Activity result size or `ScheduleToCloseTimeout` set?         |
| `ResourceExhausted` in Worker logs but no error in Event History        | Per gRPC message 4 MB on Activity completion | Worker logs are the only signal — see [Activity Tasks behavior](#all-other-sdk-versions-1) |
| Workflow looping on `CompleteWorkflowExecution` with no progress        | Per-payload 2 MB on Workflow result | Workflow return value                                         |

## See also

- [`references/core/error-reference.md`](error-reference.md) — Workflow Task failure causes overview.
- [`references/core/gotchas.md`](gotchas.md) — anti-patterns that lead to oversized payloads.
- `references/go/payload-validation.md` — Go SDK configuration.
- `references/python/payload-validation.md` — Python SDK configuration (including the 1.23.0+ eager-validation behavior).
