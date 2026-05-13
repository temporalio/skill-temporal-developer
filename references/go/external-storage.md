# External Storage (Go SDK)

> **Status: Pre-Release.** APIs and configuration may change before the stable release. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:14-20 -->

External Storage offloads large payloads to an external store (such as Amazon S3) and passes a small reference token through the Event History instead — the [claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern). <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-33 -->

## When to use

The Temporal Service enforces a per-payload size limit. The default and recommended limit is **2 MB**. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-43 -->

- **Self-hosted**: configurable. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:43 -->
- **Temporal Cloud**: fixed at 2 MB. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:43 -->

Payloads above the limit fail the operation. Without External Storage you must restructure code (for example, split data across multiple Workflows). Even when individual payloads stay under the hard limit, history bloat from accumulated Activity inputs/outputs degrades Workflow Task latency. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:44-49 -->

Scenarios: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:51-63 -->

- **Data processing pipelines** — documents, images, large blobs.
- **AI agent conversations** — long histories grow per turn.
- **Spiky data sizes** — usually small, occasionally large; only the spikes get offloaded.
- **Migration to Temporal Cloud** — self-hosted may use higher configured limits; External Storage lets you migrate without restructuring.
- **Data governance** — store payload data in infrastructure you control; set threshold to externalize all payloads.

## Pipeline placement

External Storage sits at the **end** of the Data Conversion pipeline, **after** the Payload Converter **and** the Payload Codec. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:72-73 -->

```
PayloadConverter -> PayloadCodec -> ExternalStorage
```

- On send: payloads exceeding the threshold are uploaded; a reference token replaces the payload in Event History. Payloads under the threshold stay inline. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:82-84 -->
- On receive: the Worker downloads referenced payloads, then passes them back through the Codec and Converter. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:86-88 -->
- The SDK **parallelizes** uploads and downloads across multiple payloads in a single Task — a Task carrying many large payloads scales without serial latency. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:90-92 -->
- The Temporal UI displays a **reference token** instead of the actual data when a payload is offloaded; application code still receives the fully decoded value because the SDK retrieves it transparently. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:94-96 -->
- Because External Storage runs **after** the Payload Codec, an encryption codec encrypts the payload **before** upload. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:98-99 -->

## Amazon S3 driver

The Go SDK ships an S3 storage driver. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:31 -->

### Prerequisites

- An S3 bucket you have read and write access to. Configure a lifecycle policy so payloads survive the full Workflow lifetime — see [Lifecycle](#lifecycle). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:35-36 -->
- Install the driver module and its dependencies: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:37 -->

```bash
go get go.temporal.io/sdk/contrib/aws/s3driver go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 github.com/aws/aws-sdk-go-v2/config github.com/aws/aws-sdk-go-v2/service/s3
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:37 -->

### Construct the driver

The driver picks up [AWS credentials](https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/configure-gosdk.html) from the environment (env vars, IAM role, AWS config file). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:41 -->

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
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:46-60 -->

The bucket is wrapped via `s3driver.StaticBucket(...)` inside `s3driver.Options` — it is not a bare string. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:53-56 -->

### Wire it to the Client

`ExternalStorage` is configured on `client.Options` — not on `worker.Options`, not on a `DataConverter`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:68-73 -->

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
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:68-79 -->

All Workflows and Activities running on the Worker use the storage driver automatically — no business-logic changes required. The driver uploads and downloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:87-88 -->

## `PayloadSizeThreshold`

Default offload threshold is **256 KiB**. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:83 --> <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-232 -->

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:238-243 -->

**Trap:** `PayloadSizeThreshold: 0` is interpreted as the **default (256 KiB)** — not "externalize everything". To externalize **all** payloads regardless of size, set `PayloadSizeThreshold: 1`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-233 -->

## Custom storage driver

Implement the `converter.StorageDriver` interface when no built-in driver fits. Use a durable backing store that survives process crashes and remains accessible to all Workers and to debugging tooling after the Workflow completes. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:92-97 -->

### The four interface methods

The `converter.StorageDriver` interface requires four methods: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:185 -->

- **`Name() string`** — unique identifier for **this driver instance**. The SDK records the name in the claim check reference and uses it to route retrievals to the right driver. **Changing the `Name()` after payloads have been stored breaks retrieval.** Example: `"s3-primary"` vs. `"s3-archive"`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-189 -->
- **`Type() string`** — identifier for the **driver implementation**. Same value across all instances of the same driver type regardless of configuration. Two S3 drivers named `"s3-primary"` and `"s3-archive"` both return `"aws.s3driver"`; a local-disk driver returns `"local-disk"`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:190-192 -->
- **`Store(ctx, payloads) ([]StorageDriverClaim, error)`** — uploads a slice of payloads, returns one `StorageDriverClaim` per payload. A claim is a set of string key-value pairs the driver uses to locate the payload later. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:193-194 -->
- **`Retrieve(ctx, claims) ([]*commonpb.Payload, error)`** — given the claims that `Store()` produced, returns the original payloads. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:195 -->

### Interface shape

```go
type LocalDiskStorageDriver struct {
    storeDir string
}

func NewLocalDiskStorageDriver(storeDir string) converter.StorageDriver {
    return &LocalDiskStorageDriver{storeDir: storeDir}
}

func (d *LocalDiskStorageDriver) Name() string { return "my-local-disk" }
func (d *LocalDiskStorageDriver) Type() string { return "local-disk" }

func (d *LocalDiskStorageDriver) Store(
    ctx converter.StorageDriverStoreContext,
    payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) { /* ... */ }

func (d *LocalDiskStorageDriver) Retrieve(
    ctx converter.StorageDriverRetrieveContext,
    claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) { /* ... */ }
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:102-177 -->

### `Store()` — type-switch on `ctx.Target`

`ctx.Target` carries identity for the operation; use a type switch to inspect it. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:204-207 -->

- `converter.StorageDriverWorkflowInfo` — Workflow-bound operations. Fields include `Namespace`, `WorkflowID`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:124-127 -->
- `converter.StorageDriverActivityInfo` — **only** used for **standalone (non-workflow-bound) activities**. Activities started **by a Workflow** use `StorageDriverWorkflowInfo`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:128-133 -->

```go
func (d *LocalDiskStorageDriver) Store(
    ctx converter.StorageDriverStoreContext,
    payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) {
    dir := d.storeDir
    switch info := ctx.Target.(type) {
    case converter.StorageDriverWorkflowInfo:
        if info.WorkflowID != "" {
            dir = filepath.Join(d.storeDir, info.Namespace, info.WorkflowID)
        }
    case converter.StorageDriverActivityInfo:
        // StorageDriverActivityInfo is only used for standalone (non-workflow-bound)
        // activities. Activities started by a workflow use StorageDriverWorkflowInfo.
        if info.ActivityID != "" {
            dir = filepath.Join(d.storeDir, info.Namespace, info.ActivityID)
        }
    }
    if err := os.MkdirAll(dir, 0o755); err != nil {
        return nil, fmt.Errorf("create store directory: %w", err)
    }

    claims := make([]converter.StorageDriverClaim, len(payloads))
    for i, payload := range payloads {
        key := uuid.NewString() + ".bin"
        filePath := filepath.Join(dir, key)

        data, err := proto.Marshal(payload)
        if err != nil {
            return nil, fmt.Errorf("marshal payload: %w", err)
        }
        if err := os.WriteFile(filePath, data, 0o644); err != nil {
            return nil, fmt.Errorf("write payload: %w", err)
        }

        claims[i] = converter.StorageDriverClaim{
            ClaimData: map[string]string{"path": filePath},
        }
    }
    return claims, nil
}
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:118-157 -->

Marshal the Payload protobuf to bytes with `proto.Marshal(payload)` and write to your store. The application data has already been serialized by the Payload Converter and Payload Codec before it reaches the driver. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:199-202 -->

Return a `StorageDriverClaim` per payload with enough information to retrieve it later. Consider structuring keys to include namespace / Workflow ID so you can identify which Workflow owns each payload. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:204-207 -->

### `Retrieve()` — reverse the Store

```go
func (d *LocalDiskStorageDriver) Retrieve(
    ctx converter.StorageDriverRetrieveContext,
    claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) {
    payloads := make([]*commonpb.Payload, len(claims))
    for i, claim := range claims {
        filePath := claim.ClaimData["path"]
        data, err := os.ReadFile(filePath)
        if err != nil {
            return nil, fmt.Errorf("read payload: %w", err)
        }
        payload := &commonpb.Payload{}
        if err := proto.Unmarshal(data, payload); err != nil {
            return nil, fmt.Errorf("unmarshal payload: %w", err)
        }
        payloads[i] = payload
    }
    return payloads, nil
}
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:159-177 -->

Download bytes using `claim.ClaimData`, then reconstruct with `proto.Unmarshal(data, payload)`. The Payload Converter handles deserializing application data after the driver returns. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:211-213 -->

### Wire the custom driver

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{NewLocalDiskStorageDriver("/tmp/temporal-payload-store")},
    },
})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:219-225 -->

Notes on driver behavior: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:90-92 -->

- The SDK parallelizes uploads/downloads across the payload slice. Your `Store()` / `Retrieve()` receives a slice and may process it however it likes — the parallelism is the SDK's concern, not an interface requirement. The built-in S3 driver does parallel I/O internally.
- The local-disk driver is for local development and testing only. Production stores must be durable and accessible to all Workers. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:96-97 -->

A custom driver can be packaged as a [plugin](/develop/plugins-guide) for reuse across services. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:227 -->

## Multiple drivers & driver migration

Registering more than one driver **requires** a `DriverSelector` implementing the `StorageDriverSelector` interface. The selector chooses which driver stores each payload. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:249-250 -->

- Any registered driver **not selected for storing** remains available for **retrieval**. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:250-251 -->
- Return **`nil`** from the selector to keep a specific payload **inline** in Event History. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252 -->
- Driver migration ≠ automatic format conversion: register both old and new drivers; the selector picks the preferred for **writes**; the unselected driver remains available for reads of existing claims. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:256-258 -->

Common uses: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:254-261 -->

- **Driver migration.** Worker still needs to retrieve payloads created with an older driver; register both, prefer the new one for writes.
- **Multi-cloud routing.** E.g. S3 for AWS Workers, GCS for GCP Workers — the selector picks based on the runtime environment.

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
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:269-286 -->

## Codec Server interplay

When Workers and Clients use External Storage, the Event History contains references — not payload data. The Temporal Service and Web UI only see the references. A Codec Server that supports External Storage must download **and** decode in the correct order. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:84-88 -->

Build the handler with `NewPayloadHTTPHandler` + `PayloadHTTPHandlerOptions`. The options accept your storage drivers, pre-storage codecs (the Payload Codecs configured in your Worker's Data Converter), and post-storage codecs (proxies that encode after External Storage). The handler runs them in the correct order across all endpoints automatically. With storage drivers configured, the existing endpoints become storage-aware and a new `/download` endpoint appears. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-94 -->

Endpoints: <!-- docs/encyclopedia/data-conversion/codec-server.mdx:55-58 --> <!-- docs/encyclopedia/data-conversion/codec-server.mdx:105-113 -->

- **`/encode`** — applies the Payload Codec, then uploads payloads above the threshold to external storage and replaces them with reference tokens. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:112-113 -->
- **`/decode`** — decodes encoded payloads and **also** handles storage references. By default `/decode` calls the download path internally for any references in the request and returns fully decoded data alongside regular payloads. With **`?preserveStorageRefs=true`**, `/decode` **skips retrieval** and returns storage references as-is — it does **not** skip decoding of non-reference payloads. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:109-111 -->
- **`/download`** — retrieves payload bytes from external storage and decodes them through the Payload Codec. Used internally by `/decode` when it encounters storage references; the Web UI calls it directly when a user clicks to view a storage reference. Only available when the handler is configured with storage drivers. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:105-108 -->

**Caution — do not conflate the two HTTP handler constructors:** <!-- docs/encyclopedia/data-conversion/codec-server.mdx:96-103 -->

- `NewPayloadHTTPHandler` runs the **full** encode-store-encode and decode-retrieve-decode pipeline. **Do not** point a Worker's remote Data Converter or remote codec at it.
- `NewPayloadCodecHTTPHandler` is the constructor for **remote codecs on Workers**.
- If you need both, run `NewPayloadHTTPHandler` for the Web UI / CLI **alongside** `NewPayloadCodecHTTPHandler` for Workers, configured with the same codecs.

Example flow (CLI start → UI view): <!-- docs/encyclopedia/data-conversion/codec-server.mdx:122-135 -->

1. CLI sends plaintext input to `/encode`.
2. Codec Server encodes; if the result exceeds the threshold, it uploads to external storage and returns a reference token.
3. CLI sends the reference to the Temporal Service; it is stored in Event History.
4. Web UI later fetches the Event History and calls `/decode?preserveStorageRefs=true`.
5. Codec Server decodes non-reference payloads and returns storage references untouched. UI shows reference metadata.
6. User clicks a reference; UI calls `/download`.
7. Codec Server retrieves bytes from external storage, decodes them, and returns plaintext.

## Lifecycle {#lifecycle}

Temporal does **not** automatically delete payloads from your external store. Configure a lifecycle policy on the store. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:131-133 -->

TTL must be long enough that payloads survive the entire Workflow lifetime **plus** its retention window: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:135-140 -->

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```
<!-- docs/encyclopedia/data-conversion/external-storage.mdx:139 -->

Example: longest Workflow Run Timeout 14 days + Namespace retention 30 days → at least 44 days. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:142-143 -->

**Indefinite Workflows.** With no Run Timeout there is no finite TTL that guarantees safety. Set a generous TTL based on operational needs; use Continue-as-New for Workflows that need to run longer. The new run uploads fresh payloads, so the old run's payloads only need to survive **its** retention period. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:145-148 -->

See the [External Storage encyclopedia page](/external-storage) for the full lifecycle prose.
