# External Storage

:::info Pre-Release

"External Storage is in Pre-Release. APIs and configuration may change before the stable release." <!-- docs/encyclopedia/data-conversion/external-storage.mdx:26-27 -->

:::

External Storage offloads large payloads to an external store (such as Amazon S3) and passes a small reference token through Event History in their place <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-33 -->. This is an SDK-level implementation of the [claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern) <!-- docs/encyclopedia/data-conversion/external-storage.mdx:33 -->. The feature is currently available in the Go and Python SDKs <!-- docs/encyclopedia/data-conversion/external-storage.mdx:37-38 -->.

For SDK-specific setup, see `references/go/external-storage.md` and `references/python/external-storage.md`.

## Why External Storage exists

The Temporal Service enforces a maximum per-payload size with a default and recommended limit of 2 MB <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 -->. On Temporal Cloud this 2 MB limit is fixed; self-hosted users can configure it <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 -->. Payloads above the limit fail the operation, and the only workarounds without External Storage are to restructure the code, for example by splitting data across multiple Workflows <!-- docs/encyclopedia/data-conversion/external-storage.mdx:43-45 -->.

Common errors that motivate adopting External Storage include `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` and `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` <!-- docs/troubleshooting/blob-size-limit-error.mdx:35-36 -->. The troubleshooting guide identifies the claim check pattern, built into the SDKs as External Storage, as the most reliable way to avoid hitting payload size limits <!-- docs/troubleshooting/blob-size-limit-error.mdx:65-69 -->.

Even when individual payloads stay under the hard limit, payload data accumulates in Event History; large histories degrade Workflow Task latency <!-- docs/encyclopedia/data-conversion/external-storage.mdx:47-49 -->.

External Storage targets scenarios such as data processing pipelines, AI agent conversations, spiky data sizes, migration from self-hosted (which may have higher configured limits) to Temporal Cloud (fixed at 2 MB), and data governance setups where some organizations prefer to keep payload bytes in infrastructure they control <!-- docs/encyclopedia/data-conversion/external-storage.mdx:51-63 -->. Setting the offload threshold to zero externalizes all payloads regardless of size <!-- docs/encyclopedia/data-conversion/external-storage.mdx:61-63 -->.

## Where it sits in the data conversion pipeline

External Storage sits at the end of the Data Conversion pipeline, after both the Payload Converter and the Payload Codec <!-- docs/encyclopedia/data-conversion/external-storage.mdx:72-73 -->. This ordering matters: because External Storage runs after the Payload Codec, payloads handled by an encryption codec are already encrypted before upload to your store <!-- docs/encyclopedia/data-conversion/external-storage.mdx:98-99 -->.

The store/retrieve lifecycle works as follows:

1. When a Temporal Client sends a payload that exceeds the configured size threshold, the storage driver uploads the payload to your external store and replaces it with a lightweight reference; payloads below the threshold stay inline in Event History <!-- docs/encyclopedia/data-conversion/external-storage.mdx:82-84 -->.
2. When the Temporal Service dispatches Tasks to the Worker, the process reverses: the Worker downloads referenced payloads from external storage in parallel, then passes them back through the Payload Codec and Payload Converter to reconstruct the original data <!-- docs/encyclopedia/data-conversion/external-storage.mdx:86-88 -->.

The SDK parallelizes uploads and downloads to minimize latency. When a single Workflow Task involves multiple payloads that exceed the threshold, the SDK uploads or downloads all of them concurrently rather than one at a time, allowing external storage operations to scale well even when a Task carries many large payloads <!-- docs/encyclopedia/data-conversion/external-storage.mdx:90-92 -->.

When a payload is offloaded, the Temporal UI displays a reference token instead of the actual data; this is expected, and application code receives the fully decoded result because the SDK transparently retrieves the payload before returning it to the Workflow or Client <!-- docs/encyclopedia/data-conversion/external-storage.mdx:94-96 -->.

## Storage drivers

A storage driver connects External Storage to a backing store. Each driver provides two operations <!-- docs/encyclopedia/data-conversion/external-storage.mdx:103 -->:

- **Store.** Upload payloads and return a claim — a set of key-value pairs the driver uses to locate the payload later <!-- docs/encyclopedia/data-conversion/external-storage.mdx:105-106 -->.
- **Retrieve.** Download payloads using the claims that `store` produced <!-- docs/encyclopedia/data-conversion/external-storage.mdx:107-108 -->.

Temporal SDKs include built-in drivers for common storage systems like Amazon S3 <!-- docs/encyclopedia/data-conversion/external-storage.mdx:109 -->. You can configure multiple storage drivers and use a selector function to route payloads to different drivers based on size, type, or other criteria such as hot and cold storage tiers <!-- docs/encyclopedia/data-conversion/external-storage.mdx:109-111 -->.

If the built-in drivers don't support your storage backend, you can implement a custom driver <!-- docs/encyclopedia/data-conversion/external-storage.mdx:115 -->. The Go and Python reference pages link to SDK-specific examples.

## Key configuration settings

Configure External Storage on the Data Converter. The key settings are <!-- docs/encyclopedia/data-conversion/external-storage.mdx:122 -->:

- **Size threshold.** The driver offloads payloads larger than this value, which defaults to 256 KiB <!-- docs/encyclopedia/data-conversion/external-storage.mdx:124 -->.
- **Drivers.** One or more storage driver implementations <!-- docs/encyclopedia/data-conversion/external-storage.mdx:125 -->.
- **Driver selector.** When using multiple drivers, you must provide a function that chooses which driver handles each payload <!-- docs/encyclopedia/data-conversion/external-storage.mdx:126-127 -->.

The exact API names live in `references/go/external-storage.md` and `references/python/external-storage.md`.

## Lifecycle management and TTL

Temporal does not automatically delete payloads from your external store, and payloads can also be orphaned if a request fails after upload completes <!-- docs/encyclopedia/data-conversion/external-storage.mdx:131-132 -->. Configure a lifecycle policy that both ensures these payloads are eventually cleaned up and provides a grace period for debugging and recovery <!-- docs/encyclopedia/data-conversion/external-storage.mdx:132-133 -->.

The TTL must be long enough that payloads remain available for the entire lifetime of the Workflow plus its retention window <!-- docs/encyclopedia/data-conversion/external-storage.mdx:135-136 -->:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

<!-- docs/encyclopedia/data-conversion/external-storage.mdx:139 -->

For example, if your longest-running Workflow has a Run Timeout of 14 days and your Namespace retention period is 30 days, configure your lifecycle rule to expire objects after at least 44 days <!-- docs/encyclopedia/data-conversion/external-storage.mdx:142-143 -->.

If your Workflows run indefinitely (no Run Timeout), there is no finite TTL that guarantees safety — set a generous TTL based on operational needs and use Continue-as-New for Workflows that need to run longer; the new run uploads fresh payloads, and the old run's payloads only need to survive its retention period <!-- docs/encyclopedia/data-conversion/external-storage.mdx:145-148 -->.

## Codec Server integration

When Workers and Clients use External Storage, storage drivers replace some payloads in Event History with small references that point to data in an external store; the Temporal Service and the Web UI only see those references <!-- docs/encyclopedia/data-conversion/codec-server.mdx:84-86 -->. The Codec Server must be able to handle downloading and decoding in the correct order so users can view Workflow data in the UI or CLI <!-- docs/encyclopedia/data-conversion/codec-server.mdx:87-88 -->.

To support External Storage, create a handler using `NewPayloadHTTPHandler` with `PayloadHTTPHandlerOptions` <!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-91 -->. The options accept your storage drivers, your pre-storage codecs (the Payload Codecs configured in your Worker's Data Converter), and any post-storage codecs (codecs applied by a proxy after external storage); the handler applies them in the correct order across all endpoints automatically <!-- docs/encyclopedia/data-conversion/codec-server.mdx:91-93 -->.

When the handler is configured with storage drivers, the existing endpoints become storage-aware and a new `/download` endpoint becomes available <!-- docs/encyclopedia/data-conversion/codec-server.mdx:93-94 -->:

- **`/download`** retrieves the actual payload data from external storage and decodes it through the Payload Codec; this endpoint is used internally by `/decode` when it encounters storage references, but you can also call it directly from the Web UI to retrieve the decoded payload <!-- docs/encyclopedia/data-conversion/codec-server.mdx:105-108 -->.
- **`/decode`** still decodes encoded payloads, but also handles storage references. By default `/decode` uses the download logic internally to retrieve and decode any storage references alongside regular payloads. With the `?preserveStorageRefs=true` query parameter, `/decode` skips retrieval and returns storage references as-is <!-- docs/encyclopedia/data-conversion/codec-server.mdx:109-111 -->.
- **`/encode`** applies the Payload Codec, then uploads payloads that exceed the size threshold to external storage and replaces them with reference tokens <!-- docs/encyclopedia/data-conversion/codec-server.mdx:112-113 -->.

:::caution Do not use `NewPayloadHTTPHandler` as a remote codec target

`NewPayloadHTTPHandler` runs the full encode-store-encode and decode-retrieve-decode pipeline. Do not use it as a target for a remote Data Converter or remote codec on your Workers. For remote codecs, use `NewPayloadCodecHTTPHandler` separately. If you need both, set up `NewPayloadHTTPHandler` for the Web UI and CLI alongside `NewPayloadCodecHTTPHandler` for your Workers, and configure both with the same codecs. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:98-101 -->

:::

## Driver migration

To migrate between storage drivers (for example, from one S3 bucket or account to another), register both the old and the new driver on the Data Converter so the unselected driver remains available for retrieval. The driver selector routes new uploads to the new driver while existing references continue to resolve through the old driver. This applies the same multi-driver mechanism described under [Storage drivers](#storage-drivers) — multiple drivers plus a selector — to a migration scenario <!-- docs/encyclopedia/data-conversion/external-storage.mdx:109-111 -->.

Keep the old driver registered at least as long as your TTL formula (`TTL > Maximum Workflow Run Timeout + Namespace Retention Period`) implies any old references can still be referenced by an in-flight or retained Workflow <!-- docs/encyclopedia/data-conversion/external-storage.mdx:135-143 -->.

<!-- VERIFY: The docs do not describe an on-history reference-token format migration distinct from driver migration. This section frames the user-brief "prerelease reference format migration" as driver migration only. -->

## SDK pointers

This topic affects the Go and Python SDKs only <!-- docs/encyclopedia/data-conversion/external-storage.mdx:37-38 -->. For SDK-specific Data Converter setup, drivers, selectors, and custom driver implementations, see:

- `references/go/external-storage.md`
- `references/python/external-storage.md`
