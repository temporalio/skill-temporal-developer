# External Storage (Concept)

External Storage offloads large payloads to an external store (such as Amazon S3) and passes a small reference token through Event History instead — the [claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern). <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32 -->

This page is SDK-agnostic. For setup and APIs, see the per-SDK pages:

- `references/go/external-storage.md`
- `references/python/external-storage.md`

For interaction with the Codec Server (Web UI / `tctl` decoding), see `references/core/external-storage-codec-server.md`.

## Stability: Pre-Release

External Storage is in **Pre-Release**. APIs and configuration may change before the stable release. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:24-28 --> Feedback and questions go to the `#large-payloads` Slack channel. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:27-28 -->

## Why use External Storage

The Temporal Service enforces a per-payload size limit. The default and recommended limit is **2 MB**; this limit is fixed at 2 MB on Temporal Cloud and configurable on self-hosted deployments. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 --> <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-27 --> Payloads that exceed this limit fail the operation. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:44 -->

Even when individual payloads stay under the hard limit, payload data accumulates in Event History; large histories degrade Workflow Task latency. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:47-49 -->

The docs call out these scenarios where External Storage helps: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:51-63 -->

- **Data processing pipelines** that handle documents, images, or other large blobs.
- **AI agent conversations** whose history grows with each turn.
- **Spiky data sizes** — Workflows usually small but occasionally large; only over-threshold payloads are offloaded.
- **Migration to Temporal Cloud** from self-hosted deployments that had higher configured limits, without restructuring Workflows that exceed 2 MB.
- **Data governance** — store payload data in infrastructure you control. The docs note you can "set the offload size threshold to zero to externalize all payloads regardless of size" as a way to achieve this. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:61-63 -->

## Where External Storage sits in the data conversion pipeline

A Data Converter has three layers, of which only the Payload Converter is required; the Payload Codec and External Storage layers are optional. <!-- docs/develop/go/best-practices/data-handling/index.mdx:28-30 --> <!-- docs/develop/python/best-practices/data-handling/index.mdx:28-30 --> External Storage sits **at the end of the pipeline, after both the Payload Converter and the Payload Codec**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:72-73 -->

Send path (Client/Worker outbound):

1. Payload Converter serializes application data to bytes.
2. Payload Codec transforms encoded payloads (e.g. encrypt, compress). <!-- docs/develop/go/best-practices/data-handling/index.mdx:34 -->
3. If the encoded payload exceeds the configured size threshold, the storage driver uploads it to your external store and replaces it with a lightweight reference. Payloads below the threshold stay inline in Event History. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:82-84 -->

Receive path (Worker inbound) reverses the order: the Worker downloads referenced payloads from external storage in parallel, then passes them back through the Payload Codec and Payload Converter to reconstruct the original data. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:86-88 -->

Because External Storage runs after the Payload Codec, if you use an encryption codec, **payloads are already encrypted before upload to your store**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:98-99 -->

When a payload is offloaded, the Temporal Web UI displays the reference token instead of the actual data. This is expected behaviour; application code still receives the fully decoded result because the SDK transparently retrieves the payload from external storage before returning it to the Workflow or Client. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:94-96 -->

## Storage drivers

A storage driver connects External Storage to a backing store. Each driver provides two operations: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:103 -->

- **Store** — upload payloads and return a **claim**, a set of key-value pairs the driver uses to locate the payload later. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:105-106 -->
- **Retrieve** — download payloads using the claims that `store` produced. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:107 -->

Temporal SDKs include built-in drivers for common storage systems like Amazon S3. You can configure multiple storage drivers and use a selector function to route payloads to different drivers based on size, type, or other criteria such as hot/cold storage tiers. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:109-111 -->

If a built-in driver does not support your storage backend, you can implement a custom driver; see the per-SDK pages for the exact interface. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:115-118 -->

## Key configuration settings

External Storage is configured on the Data Converter. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:122 --> The key conceptual knobs are: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:124-127 -->

- **Size threshold** — the driver offloads payloads larger than this value. The default is **256 KiB**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:124 --> Note: this is the SDK-side offload threshold, which is distinct from the 2 MB Temporal Service per-payload limit above.
- **Drivers** — one or more storage driver implementations.
- **Driver selector** — when using multiple drivers, you must provide a function that chooses which driver handles each payload. "Driver selector" is the documented term. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:126-127 -->

Per-SDK type and parameter names appear in the per-SDK files.

## Concurrent upload and download

The SDK parallelizes uploads and downloads to minimize latency. When a single Workflow Task involves multiple payloads that exceed the threshold, **the SDK uploads or downloads all of them concurrently rather than one at a time**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:90-92 --> This lets external storage operations scale well even when a Task carries many large payloads. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:92 -->

## Lifecycle and TTL management

Temporal does **not** automatically delete payloads from your external store, and payloads can be orphaned if a request fails after the upload completes. Configure a lifecycle policy on the store that cleans these up while leaving a grace period for debugging and recovery. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:131-133 -->

Your TTL must be long enough that payloads remain available for the entire lifetime of the Workflow plus its retention window: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:135-136 -->

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```
<!-- docs/encyclopedia/data-conversion/external-storage.mdx:139 -->

Worked example from the docs: if your longest-running Workflow has a Run Timeout of 14 days and your Namespace retention period is 30 days, configure your lifecycle rule to expire objects after **at least 44 days**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:142-143 -->

If your Workflows run indefinitely (no Run Timeout), **"there is no finite TTL that guarantees safety"**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:145 --> Set a generous TTL based on operational needs and use [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) for Workflows that need to run longer; the new run uploads fresh payloads, and the old run's payloads only need to survive its retention period. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:145-148 -->

## Pre-Release: moving between drivers

External Storage is Pre-Release; APIs and configuration may change before the stable release. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:26-27 --> The docs do not document a reference-token format-version field or an explicit migration tool between versions of the feature itself.

For moving payload data between storage backends (for example, migrating from one bucket to another), the documented pattern is to configure **multiple storage drivers** and use a **driver selector** to route writes to the new backend while reads still resolve via the old backend. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:109-111 --> See the per-SDK pages for the registration API.

## See also

- `references/go/external-storage.md` — Go SDK setup and APIs.
- `references/python/external-storage.md` — Python SDK setup and APIs.
- `references/core/external-storage-codec-server.md` — decoding offloaded payloads in the Web UI and `tctl` via a Codec Server.
- [Payload size limit troubleshooting](https://docs.temporal.io/troubleshooting/blob-size-limit-error) — error messages, behaviour by SDK version, and workarounds when payloads exceed 2 MB. <!-- docs/troubleshooting/blob-size-limit-error.mdx:24-83 -->
