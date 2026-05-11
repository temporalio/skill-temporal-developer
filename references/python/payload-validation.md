# Python SDK — Payload Size Validation

## Overview

This file covers Python-specific behavior for payload size and gRPC message size limits. For limit values (2 MB payload, 4 MB gRPC), error message catalogs, and shared cause codes, see `references/core/payload-validation.md`. The Python SDK 1.23.0+ is the only documented SDK with eager-fail behavior that keeps oversized-payload Workflows open instead of terminating them <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46 -->, and External Storage's `payload_size_threshold` is the Python-specific worker-side knob for proactively offloading payloads before they hit the limit <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:79 -->.

## Python SDK 1.23.0+ eager-fail behavior

The documentation describes the behavior with these statements:

> **Python SDK 1.23.0+:** The SDK fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is not terminated and remains open, so you can deploy a fix and allow the Workflow to continue.
<!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->

Key points:

- The cause surfaced is `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46 -->.
- The Workflow "is not terminated and remains open," allowing a code fix to be deployed and the Workflow to continue <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->.
- This applies to **both** the payload-size case and the gRPC-message-size case. The gRPC case uses the same cause string:

> **Python SDK 1.23.0+:** The SDK fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is not terminated and remains open, so you can deploy a fix and allow the Workflow to continue. For Activities, the Activity fails with an explicit error instead of timing out silently.
<!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:106-108 -->

Note that the gRPC case shares the same `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` cause (not a distinct gRPC-specific cause) <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:106 -->. For Activities, instead of retrying silently until `ScheduleToCloseTimeout` expires, the Activity "fails with an explicit error" <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:108 -->.

The doc describes the gRPC behavior on other SDKs as the SDK "catches the gRPC error" <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:114-115 -->, which implies the send was attempted rather than pre-validated by byte count. The same wording applies conceptually for the Python 1.23.0+ flow — the failure is surfaced as a failed Workflow Task response, not as a pre-flight size check the docs document.

## Proactive offload via External Storage (`payload_size_threshold`)

External Storage is the Python-specific, worker-side, size-aware mitigation. Rather than reacting to oversized payloads after the fact, the Data Converter offloads payloads above a configurable threshold to a storage backend (such as S3) and passes a small reference token through Event History <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:22-25 -->.

> By default, payloads larger than 256 KiB are offloaded to external storage. You can adjust this with the `payload_size_threshold` parameter, or set it to 0 to externalize all payloads regardless of size.
<!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:195-197 -->

- Parameter: `payload_size_threshold` <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:80 -->
- Default: 256 KiB <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:79 -->
- `payload_size_threshold=0` externalizes all payloads regardless of size <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:80 -->

Configure it on the `DataConverter`:

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```
<!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:201-209 -->

Pass the converter to both Client and Worker so Workflows and Activities offload automatically without business-logic changes <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:83-84 -->.

External Storage is currently in Pre-release; APIs and configuration may change before the stable release <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:14-20 -->.

## Custom Payload Codec compression

A `PayloadCodec` transforms `Payload` bytes after serialization and before they are sent to the Temporal Service, and can be used to compress payloads to reduce their size <!-- documentation/docs/develop/python/best-practices/data-handling/data-encryption.mdx:16 -->. The documented example uses `cramjam` for snappy compression in the `encode()` method, with `decode()` reversing it <!-- documentation/docs/develop/python/best-practices/data-handling/data-encryption.mdx:26-54 -->.

The general guidance on resolving payload-size errors lists compression as an option:

> Use compression with a custom Payload Codec for large payloads. This may address the immediate issue, but if payload sizes continue to grow, the problem can arise again.
<!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:81-82 -->

For the `PayloadCodec` interface (`encode`/`decode`) and how to attach it to the `DataConverter`, see `data-encryption.mdx` <!-- documentation/docs/develop/python/best-practices/data-handling/data-encryption.mdx:22-69 -->.

## When to choose which

| Approach | What it does | When to use |
| --- | --- | --- |
| Upgrade to Python SDK 1.23.0+ | Fails the Workflow Task with `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` and keeps the Workflow open <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:46-47 --> | You want visible failures rather than terminated Workflows or silent Activity timeouts, so you can deploy a fix and continue <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:47 --> |
| External Storage (`payload_size_threshold`) | Offloads payloads above the threshold to durable storage; Event History carries a reference token <!-- documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx:22-25 --> | You want to prevent oversized payloads from ever reaching the limit. Described as "the most reliable way to avoid hitting payload size limits" <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:68-70 --> |
| Custom Payload Codec compression | Compresses encoded payload bytes before they are sent <!-- documentation/docs/develop/python/best-practices/data-handling/data-encryption.mdx:16 --> | Stopgap — "may address the immediate issue, but if payload sizes continue to grow, the problem can arise again" <!-- documentation/docs/troubleshooting/blob-size-limit-error.mdx:81-82 --> |

Note: the Python 1.23.0+ behavior and External Storage offload are complementary — the SDK upgrade improves how oversized payloads are reported, while External Storage reduces the chance that any payload is oversized in the first place.

## Sources consulted

- `documentation/docs/troubleshooting/blob-size-limit-error.mdx`
- `documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx`
- `documentation/docs/develop/python/best-practices/data-handling/index.mdx`
- `documentation/docs/develop/python/best-practices/data-handling/data-encryption.mdx`
