# Go SDK External Storage

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## What this is

External Storage uses the **claim check pattern**: it offloads each Payload to an external store (e.g. Amazon S3 or Google Cloud Storage), records a small reference token (the "claim check") in Event History, and uses that token to retrieve the Payload when needed. The SDK handles storage and retrieval transparently.

## When to use it

- A Workflow input, Activity input, Activity result, or Workflow result will exceed the **2 MB** per-payload limit (the limit is fixed at 2 MB on Temporal Cloud; configurable on self-hosted only).
- Long Event Histories degrade Workflow Task latency (e.g. AI agent conversations that grow per turn).
- The user wants payload data to live in storage **they** control. Set `PayloadSizeThreshold: 1` to externalize all payloads (`0` selects the default 256 KiB threshold in Go).
- The user is migrating from self-hosted (with a larger configured limit) to Temporal Cloud.

## Where it sits in the pipeline

Order: **Payload Converter → Payload Codec → External Storage**. Storage runs last on outbound; it reverses on inbound.

Consequences:

- If a Payload Codec encrypts data, the bytes are already encrypted **before** upload to your store.
- The Temporal UI shows the reference token, not the data; the SDK transparently retrieves the payload before handing it to your Workflow or Client.
- Every Client and Worker that might read an offloaded payload needs the same External Storage configuration.

## Setup with a built-in driver

The Go SDK ships drivers for Amazon S3 and Google Cloud Storage. Only the driver setup differs between the two; everything after that is identical.

Amazon S3:

```bash
go get go.temporal.io/sdk/contrib/aws/s3driver \
       go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 \
       go.temporal.io/sdk/contrib/envconfig \
       github.com/aws/aws-sdk-go-v2/config \
       github.com/aws/aws-sdk-go-v2/service/s3
```

Google Cloud Storage:

```bash
go get go.temporal.io/sdk/contrib/gcp/gcsdriver \
       go.temporal.io/sdk/contrib/gcp/gcsdriver/gcssdk \
       go.temporal.io/sdk/contrib/envconfig \
       cloud.google.com/go/storage
```

### Amazon S3 driver

```go
import (
    "context"
    "log"

    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "go.temporal.io/sdk/contrib/aws/s3driver"
    "go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2"
)

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

The AWS SDK reads standard credentials from the environment (env vars, IAM role, or AWS config file).

### Google Cloud Storage driver

```go
import (
    "context"
    "log"

    "cloud.google.com/go/storage"
    "go.temporal.io/sdk/contrib/gcp/gcsdriver"
    "go.temporal.io/sdk/contrib/gcp/gcsdriver/gcssdk"
)

gcsClient, err := storage.NewClient(context.Background())
if err != nil {
    log.Fatalf("create GCS client: %v", err)
}

driver, err := gcsdriver.NewDriver(gcsdriver.Options{
    Client: gcssdk.NewClient(gcsClient),
    Bucket: gcsdriver.StaticBucket("my-temporal-payloads"),
})
if err != nil {
    log.Fatalf("create GCS driver: %v", err)
}
```

The Google Cloud SDK reads Application Default Credentials.

For either driver, pass a `BucketFunc` as `Bucket` instead of `StaticBucket` to route payloads at runtime. The function receives the store context and the payload and returns a bucket name.

### Configure the Client and Worker

```go
import (
    "log"

    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/contrib/envconfig"
    "go.temporal.io/sdk/converter"
    "go.temporal.io/sdk/worker"
)

opts := envconfig.MustLoadDefaultClientOptions()
opts.ExternalStorage = converter.ExternalStorage{
    Drivers: []converter.StorageDriver{driver},
}

c, err := client.Dial(opts)
if err != nil {
    log.Fatalf("connect to Temporal: %v", err)
}
defer c.Close()

w := worker.New(c, "my-task-queue", worker.Options{})
```

A Worker inherits External Storage from the Client it is created with. When your Workers run in their own process, repeat this setup there — a Client or Worker without the matching driver cannot resolve a reference.

Workflows and Activities running on the Worker use the driver automatically — no changes to business logic.

## Built-in driver behavior

Both the S3 and GCS drivers:

- Upload and download payloads **concurrently**. Multiple offloaded payloads in a single Workflow Task are stored or retrieved in parallel, not sequentially.
- Address objects by a SHA-256 hash of the contents, scoped by Namespace, Workflow ID, and Run ID, and verify that hash on retrieval. One Run passing the same payload to several Activities uploads it once; a different Run, Workflow, or Namespace stores its own copy, so storage scales with the number of Runs rather than with how often a Run passes a payload around.
- Reject any single payload larger than `MaxPayloadSize`, which defaults to **50 MiB**. `PayloadSizeThreshold` does not raise this ceiling — set `MaxPayloadSize` for the largest payload the application must support, and size the backing store to match.
- Include diagnostic metadata, such as the AWS region, in storage errors.

## Payload size threshold

- Default: **256 KiB**.
- Set `PayloadSizeThreshold: 1` to externalize **all** payloads regardless of size.
- `PayloadSizeThreshold: 0` is **interpreted as the default (256 KiB)** — it does **not** mean "externalize everything".
- The size compared against the threshold is that of the serialized Payload, including its metadata, not just your data.

```go
opts := envconfig.MustLoadDefaultClientOptions()
opts.ExternalStorage = converter.ExternalStorage{
    Drivers:              []converter.StorageDriver{driver},
    PayloadSizeThreshold: 1,
}

c, err := client.Dial(opts)
```

## Multiple drivers and migration

When you register more than one driver, you **must** supply a `DriverSelector` implementing `StorageDriverSelector`. The selector chooses which driver stores each payload. Unselected drivers remain available for **retrieval** — this is how you migrate between storage backends without losing access to existing claims.

- Return `nil` from the selector to keep a specific payload inline in Event History.
- Every registered driver must have a distinct `Name()`; duplicates are rejected when the Client or Worker is constructed. `s3driver` defaults its name to `"aws.s3driver"` and `gcsdriver` to `"gcp.gcsdriver"`, so registering two drivers of the same kind requires setting `DriverName` on at least one.

```go
import (
    commonpb "go.temporal.io/api/common/v1"

    "go.temporal.io/sdk/converter"
)

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

Useful routing patterns include driver migration, hot/cold storage tiers, per-tenant storage, and selecting S3 or GCS based on the runtime environment.

## Custom storage driver

Implement `converter.StorageDriver` with **four** methods:

- `Name() string` — unique identifier for **this driver instance**, stored in the claim reference so the SDK can route retrieval. Renaming after payloads are stored **breaks retrieval**.
- `Type() string` — identifier for the driver **implementation**, same across all instances regardless of configuration (e.g. `"aws.s3driver"`, `"local-disk"`). It is reported in Worker heartbeats.
- `Store(ctx, payloads) ([]StorageDriverClaim, error)` — upload each Payload protobuf and return one claim per payload, in the same order. A claim is a `map[string]string` the driver uses to locate the payload later.
- `Retrieve(ctx, claims) ([]*commonpb.Payload, error)` — download bytes using claim data and reconstruct each Payload, one per claim, in the same order.

Inside `Store()`, marshal each payload with `proto.Marshal(payload)`; in `Retrieve()`, reconstruct with `proto.Unmarshal(data, payload)`. The application data has already been serialized by the Payload Converter and Payload Codec before it reaches the driver.

`ctx.Context` carries the context of the operation that triggered the driver call — pass it to your storage calls so cancellation and deadlines propagate, and so sibling operations stop after the first failure.

`ctx.Target` provides identity information. Type-switch over `StorageDriverWorkflowInfo` and `StorageDriverActivityInfo` to access the namespace / Workflow ID / Activity ID, and use it to scope storage keys. Hash or encode identifiers before using them as path segments because identifiers can contain path separators or traversal sequences. `StorageDriverActivityInfo` is only used for standalone (non-workflow-bound) Activities; Activities started by a Workflow get `StorageDriverWorkflowInfo`.

Validate claim data in `Retrieve()` as untrusted input. A driver that resolves a filesystem path, object key, or URL straight out of the claim will follow whatever a hand-crafted reference payload puts there, so re-check that the resolved location stays inside the store the driver owns.

Worked example — local-disk driver (development/testing only):

```go
import (
    "crypto/sha256"
    "encoding/hex"
    "fmt"
    "os"
    "path/filepath"
    "strings"

    commonpb "go.temporal.io/api/common/v1"
    "google.golang.org/protobuf/proto"

    "go.temporal.io/sdk/converter"
)

type LocalDiskStorageDriver struct {
    storeDir string
}

func safePathSegment(value string) string {
    sum := sha256.Sum256([]byte(value))
    return hex.EncodeToString(sum[:])
}

func NewLocalDiskStorageDriver(storeDir string) converter.StorageDriver {
    return &LocalDiskStorageDriver{storeDir: storeDir}
}

// resolvePath rejects claim data that points outside the store directory.
func (d *LocalDiskStorageDriver) resolvePath(claimPath string) (string, error) {
    root, err := filepath.Abs(d.storeDir)
    if err != nil {
        return "", fmt.Errorf("resolve store directory: %w", err)
    }
    resolved, err := filepath.Abs(claimPath)
    if err != nil {
        return "", fmt.Errorf("resolve claim path: %w", err)
    }
    if resolved != root && !strings.HasPrefix(resolved, root+string(os.PathSeparator)) {
        return "", fmt.Errorf("claim path %q escapes the store directory", claimPath)
    }
    return resolved, nil
}

func (d *LocalDiskStorageDriver) Name() string { return "my-local-disk" }
func (d *LocalDiskStorageDriver) Type() string { return "local-disk" }

func (d *LocalDiskStorageDriver) Store(
    ctx converter.StorageDriverStoreContext,
    payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) {
    dir := d.storeDir
    switch info := ctx.Target.(type) {
    case converter.StorageDriverWorkflowInfo:
        if info.WorkflowID != "" {
            dir = filepath.Join(
                d.storeDir,
                safePathSegment(info.Namespace),
                safePathSegment(info.WorkflowID),
            )
        }
    case converter.StorageDriverActivityInfo:
        if info.ActivityID != "" {
            dir = filepath.Join(
                d.storeDir,
                safePathSegment(info.Namespace),
                safePathSegment(info.ActivityID),
            )
        }
    }
    if err := os.MkdirAll(dir, 0o755); err != nil {
        return nil, fmt.Errorf("create store directory: %w", err)
    }

    claims := make([]converter.StorageDriverClaim, len(payloads))
    for i, payload := range payloads {
        data, err := proto.Marshal(payload)
        if err != nil {
            return nil, fmt.Errorf("marshal payload: %w", err)
        }
        sum := sha256.Sum256(data)
        key := hex.EncodeToString(sum[:]) + ".bin"
        filePath := filepath.Join(dir, key)
        if err := os.WriteFile(filePath, data, 0o644); err != nil {
            return nil, fmt.Errorf("write payload: %w", err)
        }
        claims[i] = converter.StorageDriverClaim{
            ClaimData: map[string]string{"path": filePath},
        }
    }
    return claims, nil
}

func (d *LocalDiskStorageDriver) Retrieve(
    ctx converter.StorageDriverRetrieveContext,
    claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) {
    payloads := make([]*commonpb.Payload, len(claims))
    for i, claim := range claims {
        filePath, err := d.resolvePath(claim.ClaimData["path"])
        if err != nil {
            return nil, err
        }
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

You can package a custom driver as a [plugin](https://docs.temporal.io/develop/plugins-guide) for reuse across services.

## Multi-region durability with Amazon S3

For regional-failure tolerance, configure S3 Cross-Region Replication (CRR) and an S3 Multi-Region Access Point (MRAP), then pass the MRAP ARN as the bucket:

```go
driver, err := s3driver.NewDriver(s3driver.Options{
    Client: awssdkv2.NewClient(s3.NewFromConfig(cfg)),
    Bucket: s3driver.StaticBucket("arn:aws:s3::123456789012:accesspoint/mfzwi23gnjvgw.mrap"),
})
```

The AWS SDK for Go v2 uses SigV4A signing automatically when the bucket value is an MRAP ARN, so no additional client configuration is required.

Cross-region replication is eventually consistent. Activities reading newly written Payloads from another region need an appropriate Retry Policy. Replication, versioning, and Replication Time Control can add significant cost.

## Codec Server with External Storage

When Workers and Clients use External Storage, Event History contains reference tokens — not payload data. For the Web UI and CLI to display decoded payloads, the Codec Server must download from external storage **and** decode through the Payload Codec in the correct order.

Build the Codec Server with `NewPayloadHTTPHandler` and `PayloadHTTPHandlerOptions`. Pass it your storage drivers, your pre-storage codecs (the Payload Codecs your Workers use), and any post-storage codecs (applied by a proxy after external storage).

When configured with storage drivers, the handler exposes:

- **`/download`** — retrieves payload data from external storage and decodes it through the Payload Codec. The Web UI calls this when a user clicks to view the full payload behind a reference.
- **`/decode`** — decodes encoded payloads and, by default, retrieves storage references inline. Pass `?preserveStorageRefs=true` to return storage references as-is without retrieval.
- **`/encode`** — applies the Payload Codec, then uploads payloads exceeding the threshold and replaces them with reference tokens.

**Don't use `NewPayloadHTTPHandler` as a remote Data Converter or remote codec target for your Workers** — it runs the full encode-store-encode and decode-retrieve-decode pipeline. For remote codecs use `NewPayloadCodecHTTPHandler` separately. If you need both, run both handlers, configured with the same codecs.

The [Go External Storage sample](https://github.com/temporalio/samples-go/tree/main/external-storage) is a working end-to-end setup to copy from: a Worker with an S3 driver behind a zlib Payload Codec, a Codec Server built on `NewPayloadHTTPHandler` (`codec-server/main.go`), and a mock S3 service so it runs locally without an AWS account.

## Lifecycle and failure handling

Temporal does **not** auto-delete payloads from your store. Configure a TTL on your bucket:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

Example: Run Timeout 14 days + Namespace retention 30 days → set TTL to at least 44 days.

For Workflows with no finite Run Timeout, there is no safe finite TTL. Use Continue-as-New so the new run uploads fresh payloads and the old run's payloads only need to survive its retention period.

The SDK does not retry a failed `Store` or `Retrieve` call within the same Task attempt. The failure fails the current Workflow Task or Activity Task attempt; Temporal then retries the Task as a whole, and the new attempt retries the storage operation along with it. For Activities, the Retry Policy controls the timing. Storage operations should therefore be idempotent — content-addressable keys are one way to get that.

## Anti-patterns

- **Don't change `Name()` after payloads have been stored.** The name is embedded in the claim reference; renaming breaks retrieval of existing claims.
- **Don't use `PayloadSizeThreshold: 0` to mean "externalize all".** `0` is interpreted as the default (256 KiB). Use `PayloadSizeThreshold: 1`.
- **Don't register multiple drivers without a `DriverSelector`.** The selector is required when there are multiple drivers.
- **Don't register duplicate driver names.** Two same-kind drivers share a default name; set `DriverName` on at least one.
- **Don't omit External Storage configuration from a Client or Worker that may retrieve offloaded data.** It cannot resolve the reference without the matching driver.
- **Don't assume the 2 MB Temporal limit is the driver's maximum.** The S3 and GCS drivers reject payloads above `MaxPayloadSize`, which defaults to 50 MiB.
- **Don't point a Worker's remote codec at `NewPayloadHTTPHandler`.** Use `NewPayloadCodecHTTPHandler` for remote codec endpoints.
- **Don't omit a TTL on the bucket.** Payloads are orphaned otherwise; orphaned objects can also remain if a request fails after upload.
