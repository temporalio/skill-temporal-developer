# External Storage - Go SDK

External Storage offloads large Payloads (typically over the Temporal Service's 2 MB per-Payload limit) to a backing store such as Amazon S3, passing a small claim-check reference through Event History instead. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:22-25 -->

> **Pre-Release.** External Storage is in Pre-Release. APIs and configuration may change before the stable release. Join the `#large-payloads` Slack channel for feedback or help. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:14-20 -->

## Install

The S3 driver lives in a contrib module; install it together with the AWS SDK v2 dependencies:

```sh
go get go.temporal.io/sdk/contrib/aws/s3driver \
       go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 \
       github.com/aws/aws-sdk-go-v2/config \
       github.com/aws/aws-sdk-go-v2/service/s3
```

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:37 -->

You also need an S3 bucket with read/write access. Plan for [lifecycle management](/external-storage#lifecycle) so payloads stay around for the entire lifetime of the Workflow. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:35-36 -->

## Built-in S3 driver setup

The driver picks up the standard AWS credentials chain (environment variables, IAM role, or AWS config file). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:41-42 -->

### 1. Create the driver

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

### 2. Wire into `client.Options`

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

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:68-80 -->

All Workflows and Activities on Workers built from this Client use the driver automatically; no business-logic changes are required. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:87-88 -->

## Configure payload size threshold

Set `PayloadSizeThreshold` on `converter.ExternalStorage` to control which payloads are offloaded:

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:238-243 -->

**Read the semantics carefully — this is the most common SDK mistake:**

- Default (when the field is unset) is 256 KiB. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-232 -->
- Set it to **1** to externalize every payload regardless of size. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 -->
- A value of **0 is interpreted as the default (256 KiB)** — it does **not** mean "externalize all". <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:233 -->

If you want to force every payload to external storage, use `PayloadSizeThreshold: 1`, not `0`.

## Implement a custom storage driver

If the built-in drivers do not cover your backing store, implement `converter.StorageDriver`. Store payloads durably so they survive process crashes and remain available for debugging and auditing after the Workflow completes. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:92-94 -->

### The interface (four methods)

A custom driver implements `converter.StorageDriver` with four methods: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:185 -->

- **`Name()`** returns a unique string that identifies the *driver instance*. The SDK stores this name in the claim-check reference so it can route retrieval back to the right driver. **Renaming a driver after payloads have been stored breaks retrieval.** Example: two S3 drivers might be named `"s3-primary"` and `"s3-archive"`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-189 -->
- **`Type()`** returns a string that identifies the *driver implementation*. Unlike `Name()`, `Type()` must be identical across every instance of the same implementation regardless of configuration. Both `"s3-primary"` and `"s3-archive"` instances return `"aws.s3driver"` as their type; the sample local-disk driver returns `"local-disk"`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:190-192 -->
- **`Store()`** receives a slice of payloads and returns one `StorageDriverClaim` per payload. A claim is a set of string key-value pairs the driver uses to locate the payload later. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:193-194 -->
- **`Retrieve()`** receives the claims that `Store()` produced and returns the original payloads. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:195 -->

### `Store()` and the target type-switch

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
    // ... marshal each payload with proto.Marshal and write it ...
    claims[i] = converter.StorageDriverClaim{
        ClaimData: map[string]string{"path": filePath},
    }
}
```

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:118-155 -->

Key points:

- Signature: `(ctx converter.StorageDriverStoreContext, payloads []*commonpb.Payload) ([]converter.StorageDriverClaim, error)`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:118-121 -->
- `ctx.Target` is a type-switch over `StorageDriverWorkflowInfo` (`Namespace`, `WorkflowID`) and `StorageDriverActivityInfo` (`Namespace`, `ActivityID`). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:123-133 -->
- `StorageDriverActivityInfo` is only used for standalone (non-workflow-bound) activities. Activities started by a workflow use `StorageDriverWorkflowInfo`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:129-130 -->
- Marshal the Payload protobuf with `proto.Marshal(payload)`. The application data has already been run through the Payload Converter and Payload Codec before reaching the driver. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:199-202 -->
- Return one `StorageDriverClaim{ ClaimData: map[string]string{...} }` per payload, encoding whatever you need to find the bytes later. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:152-155 -->

### `Retrieve()`

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

Signature: `(ctx converter.StorageDriverRetrieveContext, claims []converter.StorageDriverClaim) ([]*commonpb.Payload, error)`. Reconstruct each Payload with `proto.Unmarshal`; the Payload Converter handles deserializing the application data afterward. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:159-162,211-213 -->

### Configure the Client with your driver

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{NewLocalDiskStorageDriver("/tmp/temporal-payload-store")},
    },
})
```

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:219-225 -->

The local-disk example is for development and testing only — in production, use a durable, shared store accessible to all Workers. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:96-97 -->

## Use multiple drivers (and migrations)

If you register more than one driver, you must also set `DriverSelector` on `converter.ExternalStorage`. The selector implements `StorageDriverSelector` with: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:249-250 -->

```go
SelectDriver(ctx converter.StorageDriverStoreContext, payload *commonpb.Payload) (converter.StorageDriver, error)
```

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:273-278 -->

Important behaviors:

- The selector picks which driver *stores* each payload. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:249-250 -->
- **Any driver in the list that is not selected for storing is still available for retrieval** — register legacy drivers here when migrating between backends. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:250-251 -->
- Return `nil` from the selector to keep that specific payload inline in Event History. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252 -->

### Driver-migration example

Register both drivers; the selector always returns the preferred one, so new writes go there while old claims still resolve through the legacy driver: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:254-265 -->

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

<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:269-285 -->

Multi-cloud routing is the other common case: select based on the runtime environment (S3 on AWS Workers, GCS on GCP Workers, etc.). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:259-261 -->

## Concurrency and integrity

The driver uploads and downloads payloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:88 -->

## Common pitfalls

- **`PayloadSizeThreshold: 0` is *not* "externalize all".** A value of 0 falls back to the default 256 KiB. Use `1` to externalize every payload. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 -->
- **Do not rename a driver after deploy.** `Name()` is baked into the claim reference; changing it breaks retrieval of any payload stored under the old name. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:188-189 -->
- **`Type()` vs `Name()` are not the same.** `Name()` varies per instance; `Type()` is fixed per implementation regardless of configuration. Both methods are required. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-192 -->
- **Selector returns `nil`, not a sentinel value**, to keep a payload inline. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252 -->
- **Standalone Activities vs Workflow-bound Activities.** Activities started from a Workflow surface as `StorageDriverWorkflowInfo`. `StorageDriverActivityInfo` only appears for standalone activities. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:129-130 -->

## See also

- [External Storage (concept)](../core/external-storage.md) — claim-check pattern, data pipeline, lifecycle management.
