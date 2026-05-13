# External Storage — Go SDK

:::info Pre-Release feature

External Storage is in [Pre-Release](https://docs.temporal.io/evaluate/development-production-features/release-stages#pre-release). APIs and configuration may change before the stable release.

:::

## When to reach for it

The Temporal Service enforces a 2 MB per-payload limit by default. The limit is configurable on self-hosted deployments and fixed at 2 MB on Temporal Cloud. External Storage offloads payloads that exceed a configured threshold to an external store (such as Amazon S3) and threads a small reference token through the Event History instead — the [claim-check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern).

Common drivers:

- Data processing pipelines that push documents, images, or large blobs through Workflows.
- AI agent conversations whose cumulative history grows with each turn.
- Spiky payload sizes where only occasional payloads exceed the threshold.
- Migrations to Temporal Cloud from a self-hosted deployment with a higher configured limit.
- Data governance: keep payload bytes in infrastructure you control by setting the threshold to externalize all payloads.

If you are already hitting size errors (`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.`, `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`), External Storage is the recommended fix.

## Where it sits in the data pipeline

External Storage runs at the end of the Data Conversion pipeline, after the [Payload Converter](https://docs.temporal.io/develop/go/data-handling/data-conversion) and the [Payload Codec](https://docs.temporal.io/develop/go/data-handling/data-encryption). The implication: by the time a `StorageDriver` receives a `*commonpb.Payload`, the application data has already been serialized and (if you use an encryption codec) encrypted.

The SDK parallelizes uploads and downloads when a single Workflow Task involves multiple offloaded payloads, and it validates payload integrity on retrieve.

## Built-in S3 driver

The Go SDK ships an S3 driver in a separate contrib module.

### Prerequisites

- An Amazon S3 bucket you have read/write access to.
- Install the driver and its AWS SDK v2 dependencies — transcribe the dependency list verbatim:

  ```text
  go get go.temporal.io/sdk/contrib/aws/s3driver \
         go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 \
         github.com/aws/aws-sdk-go-v2/config \
         github.com/aws/aws-sdk-go-v2/service/s3
  ```


The S3 driver uses standard AWS credentials from the environment (environment variables, IAM role, or AWS config file).

### Create the driver

```go
cfg, err := config.LoadDefaultConfig(context.Background(),
    config.WithRegion("us-east-2"),
)
if err != nil {
    log.Fatalf("load AWS config: %v", err)
}

driver, err := s3driver.NewDriver(s3driver.Options{
    Client: awssdkv2.NewClient(s3.NewFromConfig(cfg)),
    Bucket: s3driver.StaticBucket("my-temporal-payloads"),
})
if err != nil {
    log.Fatalf("create S3 driver: %v", err)
}
```


Key tokens — `s3driver.NewDriver`, `s3driver.Options`, `awssdkv2.NewClient`, `s3.NewFromConfig`, `s3driver.StaticBucket` — appear verbatim in the docs snippet. Do not paraphrase them.

### Wire the driver into the Client

```go
c, err := client.Dial(client.Options{
    HostPort: "localhost:7233",
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{driver},
    },
})
if err != nil {
    log.Fatalf("connect to Temporal: %v", err)
}
defer c.Close()

w := worker.New(c, "my-task-queue", worker.Options{})
```


Configuration shape: the field on `client.Options` is `ExternalStorage`, typed `converter.ExternalStorage`, whose `Drivers` field is a `[]converter.StorageDriver`. All Workflows and Activities running on the Worker use the driver automatically — no changes to business logic.

## Payload size threshold

By default, payloads larger than **256 KiB** are offloaded. Tune with `PayloadSizeThreshold` on `converter.ExternalStorage`:

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```


Documented sentinel values:

- `PayloadSizeThreshold: 1` — externalize **all** payloads regardless of size.
- `PayloadSizeThreshold: 0` — interpreted as the **default** (256 KiB).

> **Trap:** these sentinels differ between Go and Python. Python uses `payload_size_threshold=0` to externalize all payloads; Go uses `1`. Do not transpose them.

## Custom `StorageDriver`

Implement `converter.StorageDriver` if the built-in drivers don't cover your backend. Store payloads durably — they must survive process crashes and remain available for debugging and auditing after the Workflow completes.

The interface has **four** methods.

| Method | Returns | Constraint |
|---|---|---|
| `Name()` | `string` — unique driver-instance identifier | Stored in the claim-check reference. Changing it after payloads have been stored breaks retrieval. Two S3 drivers may be `"s3-primary"` and `"s3-archive"`. |
| `Type()` | `string` — driver-implementation identifier | **Constant** across all instances of the same implementation regardless of configuration. Both `"s3-primary"` and `"s3-archive"` return `"aws.s3driver"`; the local-disk sample returns `"local-disk"`. |
| `Store(ctx, payloads) ([]StorageDriverClaim, error)` | one `StorageDriverClaim` per payload | A claim is a set of string key-value pairs the driver uses to locate the payload later. |
| `Retrieve(ctx, claims) ([]*commonpb.Payload, error)` | the original payloads | Receives the claims that `Store()` produced. |


### Local-disk sample (development only)

The docs ship a `LocalDiskStorageDriver` sample. It is documented as **"for local development and testing only"** — use a durable, Worker-accessible store in production.

Key shapes from the sample:

- `Store()` receives `converter.StorageDriverStoreContext`. Its `Target` field is one of `converter.StorageDriverWorkflowInfo` or `converter.StorageDriverActivityInfo` — use a type switch to read it. Worker-bound Activity stores use `StorageDriverWorkflowInfo`; `StorageDriverActivityInfo` is only used for **standalone (non-workflow-bound) Activities**.
- Serialize each `*commonpb.Payload` with `proto.Marshal(payload)`.
- A `StorageDriverClaim` carries a `ClaimData map[string]string`.
- `Retrieve()` reverses the process: read the bytes by `claim.ClaimData[...]`, then `proto.Unmarshal(data, payload)` into a fresh `&commonpb.Payload{}`.

Consider structuring your storage keys to embed identity (namespace, Workflow ID) from `ctx.Target` so that you can later attribute a payload to its owning Workflow.

### Plug the custom driver in

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{NewLocalDiskStorageDriver("/tmp/temporal-payload-store")},
    },
})
```


You can also package a driver as a [plugin](https://docs.temporal.io/develop/plugins-guide) for reuse across services.

## Multiple drivers and migration

Register multiple drivers when you need to read from one backend while writing to another (storage-backend migration, or multi-cloud routing). You **must** provide a `DriverSelector` that implements `converter.StorageDriverSelector` — without it, multi-driver setups are not valid.

The selector chooses which driver stores each payload. Drivers in the list that the selector never picks are still consulted for **retrieval**, which is what makes migration work. Return `nil` from the selector to keep a specific payload **inline** in Event History.

Documented use cases:

- **Driver migration.** Register the legacy driver alongside the preferred one. Selector always returns the preferred driver; the legacy driver stays in the list so existing claims still resolve.
- **Multi-cloud storage.** Route payloads to different backends based on runtime (e.g., S3 on AWS Workers, GCS on GCP Workers).

```go
type PreferredSelector struct {
    preferred converter.StorageDriver
}

func (s *PreferredSelector) SelectDriver(
    ctx converter.StorageDriverStoreContext,
    payload *commonpb.Payload,
) (converter.StorageDriver, error) {
    return s.preferred, nil
}

func MultipleDriversSetup(preferredDriver, legacyDriver converter.StorageDriver) converter.ExternalStorage {
    return converter.ExternalStorage{
        Drivers:        []converter.StorageDriver{preferredDriver, legacyDriver},
        DriverSelector: &PreferredSelector{preferred: preferredDriver},
    }
}
```



## Codec Server interaction

When your Workers and Clients use External Storage, the Temporal Service and Web UI only see small references — not the actual payload data. A Codec Server that the Web UI and CLI use to decode payloads must therefore become **storage-aware** to display real data.

### Build a storage-aware handler

Use `NewPayloadHTTPHandler` with `PayloadHTTPHandlerOptions`. The options accept:

- your **storage drivers** (the same drivers configured on your Workers' `converter.ExternalStorage`),
- your **pre-storage codecs** (the Payload Codecs configured in your Worker's Data Converter),
- and any **post-storage codecs** (codecs applied by a proxy after external storage).

The handler applies these in the correct order across all endpoints automatically.

> **Caution.** `NewPayloadHTTPHandler` runs the full encode-store-encode and decode-retrieve-decode pipeline. **Do not use it as a target for a remote Data Converter or remote codec on your Workers** — for remote codecs, use `NewPayloadCodecHTTPHandler` separately. If you need both, set up `NewPayloadHTTPHandler` for the Web UI and CLI alongside `NewPayloadCodecHTTPHandler` for your Workers, and configure both with the same codecs.

### The three endpoints

When you configure the handler with storage drivers, the existing endpoints become storage-aware and a new `/download` endpoint becomes available:

- **`/encode`** — applies the Payload Codec, then uploads payloads that exceed the size threshold to external storage and replaces them with reference tokens.
- **`/decode`** — decodes encoded payloads and also handles storage references. By default, `/decode` retrieves and decodes any storage references alongside regular payloads. With the `?preserveStorageRefs=true` query parameter, `/decode` skips retrieval and returns storage references as-is.
- **`/download`** — retrieves the actual payload data from external storage and decodes it through the Payload Codec. Used internally by `/decode` when it encounters storage references, and called directly by the Web UI when a user clicks to view the full payload for a storage reference.

The end-to-end flow the docs walk through: CLI sends plaintext input to `/encode` → server encodes, exceeds threshold, uploads, returns a reference token → CLI sends the reference to the Temporal Service → later, the Web UI calls `/decode?preserveStorageRefs=true` to render the event history with reference metadata → user clicks a reference → Web UI calls `/download` to fetch the decoded payload.

## Lifecycle management

Temporal does **not** automatically delete payloads from your external store. Payloads can also be orphaned if a request fails after upload completes. Configure a lifecycle policy on your store with a TTL that satisfies:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```


Worked example from the docs: a 14-day Run Timeout plus a 30-day retention period → expire objects after **at least 44 days**.

For Workflows with no Run Timeout, there is no finite TTL that guarantees safety. Set a generous TTL and use [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) for indefinitely-running Workflows — the new run uploads fresh payloads, and the old run's payloads only need to outlive its retention period.

## Common mistakes (anti-patterns)

| Wrong | Right |
|---|---|
| `client.Dial(client.Options{ExternalStorage: driver})` (passing the driver directly) | `client.Dial(client.Options{ExternalStorage: converter.ExternalStorage{Drivers: []converter.StorageDriver{driver}}})` |
| `PayloadSizeThreshold: 0` to externalize all payloads | `PayloadSizeThreshold: 1` externalizes all. `0` means "use default (256 KiB)". |
| Treating `Type()` as a per-instance identifier | `Name()` is unique per instance; `Type()` is constant across instances of the same implementation. |
| Renaming a driver after payloads have been stored | The SDK stores `Name()` in the claim-check reference; changing it breaks retrieval. |
| Registering multiple drivers without a `DriverSelector` | When you register multiple drivers, you **must** provide a `DriverSelector` that implements `StorageDriverSelector`. |
| Pointing Workers' remote codec at `NewPayloadHTTPHandler` | `NewPayloadHTTPHandler` is for Web UI / CLI. Use `NewPayloadCodecHTTPHandler` for remote codecs on Workers. |
| Promoting the `LocalDiskStorageDriver` sample as a production driver | Documented as "for local development and testing only". Use a durable, Worker-accessible store in production. |
| Assuming Temporal cleans up the external store | Temporal does not delete payloads — set a lifecycle policy with TTL > Run Timeout + Namespace Retention. |
| Treating the External Storage API as stable | Pre-Release; APIs and configuration may change. |

## Cross-references

- Concept overview: [External Storage](https://docs.temporal.io/external-storage) (`docs/encyclopedia/data-conversion/external-storage.mdx`).
- Codec Server with External Storage: [Codec Server](https://docs.temporal.io/codec-server#external-storage) (`docs/encyclopedia/data-conversion/codec-server.mdx`).
- Why this matters: [Troubleshoot payload and gRPC message size limit errors](https://docs.temporal.io/troubleshooting/blob-size-limit-error) (`docs/troubleshooting/blob-size-limit-error.mdx`).
- Data Conversion pipeline framing: `references/go/data-handling.md` (this skill).
