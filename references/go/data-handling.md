# Go SDK Data Handling

## Overview

The Go SDK uses the `converter.DataConverter` interface to serialize/deserialize workflow inputs, outputs, and activity parameters. The default converter converts values to JSON. Data conversion happens in three layers -- PayloadConverter, PayloadCodec, and ExternalStorage; see `## External Storage` below for offloading large payloads.

## Default Data Converter

The default `CompositeDataConverter` applies converters in order until one returns a non-nil Payload:

1. `converter.NewNilPayloadConverter()` -- nil values
2. `converter.NewByteSlicePayloadConverter()` -- `[]byte`
3. `converter.NewProtoJSONPayloadConverter()` -- Protobuf messages as JSON
4. `converter.NewProtoPayloadConverter()` -- Protobuf messages as binary
5. `converter.NewJSONPayloadConverter()` -- anything JSON-serializable

Structs must have exported fields to be serialized.

## Custom Data Converter

In most cases you don't implement the full `DataConverter` interface directly. Instead, implement a **`PayloadConverter`** for your specific type and insert it into a `CompositeDataConverter`. The `PayloadConverter` interface has four methods:

```go
type PayloadConverter interface {
    ToPayload(value interface{}) (*commonpb.Payload, error) // return nil if this type isn't handled
    FromPayload(payload *commonpb.Payload, valuePtr interface{}) error
    ToString(payload *commonpb.Payload) string
    Encoding() string // e.g. "json/msgpack"
}
```

**Example — custom msgpack PayloadConverter:**

```go
import (
    "encoding/json"
    "fmt"

    commonpb "go.temporal.io/api/common/v1"
    "go.temporal.io/sdk/converter"
    "github.com/vmihailenco/msgpack/v5"
)

const encodingMsgpack = "binary/msgpack"

type MsgpackPayloadConverter struct{}

func (c *MsgpackPayloadConverter) Encoding() string {
    return encodingMsgpack
}

func (c *MsgpackPayloadConverter) ToPayload(value interface{}) (*commonpb.Payload, error) {
    if value == nil {
        return nil, nil
    }
    data, err := msgpack.Marshal(value)
    if err != nil {
        return nil, fmt.Errorf("msgpack marshal: %w", err)
    }
    return &commonpb.Payload{
        Metadata: map[string][]byte{
            converter.MetadataEncoding: []byte(encodingMsgpack),
        },
        Data: data,
    }, nil
}

func (c *MsgpackPayloadConverter) FromPayload(payload *commonpb.Payload, valuePtr interface{}) error {
    if string(payload.GetMetadata()[converter.MetadataEncoding]) != encodingMsgpack {
        return fmt.Errorf("unsupported encoding")
    }
    return msgpack.Unmarshal(payload.Data, valuePtr)
}

func (c *MsgpackPayloadConverter) ToString(payload *commonpb.Payload) string {
    // Decode to a map for human-readable display
    var v interface{}
    if err := msgpack.Unmarshal(payload.Data, &v); err != nil {
        return fmt.Sprintf("<msgpack: %v>", err)
    }
    b, _ := json.Marshal(v)
    return string(b)
}
```

**Register in a CompositeDataConverter and pass to the client:**

```go
dataConverter := converter.NewCompositeDataConverter(
    converter.NewNilPayloadConverter(),
    converter.NewByteSlicePayloadConverter(),
    &MsgpackPayloadConverter{}, // handles your type; falls through to JSON for everything else
    converter.NewJSONPayloadConverter(),
)

c, err := client.Dial(client.Options{
    DataConverter: dataConverter,
})
```

**Per-activity/child-workflow override** — use a different converter for specific calls:

```go
actCtx := workflow.WithDataConverter(ctx, mySpecialConverter)
workflow.ExecuteActivity(actCtx, SensitiveActivity, input)
```

**Note:** If your converter makes remote calls (e.g., to a KMS for encryption), wrap it with `workflow.DataConverterWithoutDeadlockDetection` to avoid deadlock detection timeouts in workflow code.

## Composition of Payload Converters

Use `converter.NewCompositeDataConverter` to chain type-specific converters. The first converter that can handle the type wins.

```go
dataConverter := converter.NewCompositeDataConverter(
    converter.NewNilPayloadConverter(),
    converter.NewByteSlicePayloadConverter(),
    converter.NewProtoJSONPayloadConverter(),
    converter.NewProtoPayloadConverter(),
    YourCustomPayloadConverter(),
    converter.NewJSONPayloadConverter(),
)
```

## Protobuf Support

Binary protobuf:

```go
converter.NewProtoPayloadConverter()
```

JSON protobuf:

```go
converter.NewProtoJSONPayloadConverter()
```

Both are included in the default data converter. SDK v1.26.0 (March 2024) migrated from gogo/protobuf to google/protobuf. If you need backward compatibility with older payloads encoded with gogo, use the `LegacyTemporalProtoCompat` option.

## Payload Encryption

Implement the `converter.PayloadCodec` interface (`Encode` and `Decode`) and wrap the default data converter:

```go
// Codec implements converter.PayloadCodec for encryption.
type Codec struct{}

func (Codec) Encode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    result := make([]*commonpb.Payload, len(payloads))
    for i, p := range payloads {
        origBytes, err := p.Marshal()
        if err != nil {
            return payloads, err
        }
        encrypted := encrypt(origBytes) // your encryption logic
        result[i] = &commonpb.Payload{
            Metadata: map[string][]byte{converter.MetadataEncoding: []byte("binary/encrypted")},
            Data:     encrypted,
        }
    }
    return result, nil
}

func (Codec) Decode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    result := make([]*commonpb.Payload, len(payloads))
    for i, p := range payloads {
        if string(p.Metadata[converter.MetadataEncoding]) != "binary/encrypted" {
            result[i] = p
            continue
        }
        decrypted := decrypt(p.Data) // your decryption logic
        result[i] = &commonpb.Payload{}
        err := result[i].Unmarshal(decrypted)
        if err != nil {
            return payloads, err
        }
    }
    return result, nil
}
```

Wrap with `CodecDataConverter` and pass to client:

```go
var DataConverter = converter.NewCodecDataConverter(
    converter.GetDefaultDataConverter(),
    &Codec{},
)

c, err := client.Dial(client.Options{
    DataConverter: DataConverter,
})
```

## External Storage

> **Pre-Release.** External Storage is in Pre-Release; APIs and configuration may change before the stable release.

External Storage implements the [claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern): payloads that exceed a size threshold are uploaded to an external store (such as Amazon S3) and replaced in the Event History with a small reference token. The Temporal Service enforces a 2 MB per-payload limit by default, so offloading lets Workflows and Activities exchange data larger than that limit.

External Storage sits at the end of the Data Conversion pipeline, after both the PayloadConverter and the PayloadCodec. The SDK uploads and downloads payloads concurrently to minimize latency when a Task carries multiple offloaded payloads.

### Configure the built-in S3 storage driver

Install the S3 driver module and its dependencies:

```go
// go get go.temporal.io/sdk/contrib/aws/s3driver go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 github.com/aws/aws-sdk-go-v2/config github.com/aws/aws-sdk-go-v2/service/s3
```

Load your AWS configuration and create the driver:

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

Wire the driver into `client.Options.ExternalStorage`:

```go
c, err := client.Dial(client.Options{
    HostPort: "localhost:7233",
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{driver},
    },
})
```

All Workflows and Activities running on the Worker use the driver automatically; the SDK validates payload integrity on retrieve.

### Configure the payload size threshold

`PayloadSizeThreshold` defaults to 256 KiB. A value of `0` is interpreted as the default; set it to `1` to externalize all payloads regardless of size.

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers:              []converter.StorageDriver{driver},
        PayloadSizeThreshold: 1,
    },
})
```

### Implement a custom storage driver

A custom driver implements `converter.StorageDriver` with exactly four methods:

- `Name()` -- per-instance identifier stored in the claim (e.g. `"s3-primary"`); changing it after payloads are stored breaks retrieval.
- `Type()` -- implementation identifier shared across all instances of the same driver (e.g. `"aws.s3driver"`).
- `Store()` -- accepts a slice of `*commonpb.Payload`, writes them to your backing store, and returns one `StorageDriverClaim` per payload.
- `Retrieve()` -- accepts the claims `Store()` produced and returns the original payloads.

`Store()` receives a `StorageDriverStoreContext`; type-switch on `ctx.Target` against `converter.StorageDriverWorkflowInfo` and `converter.StorageDriverActivityInfo` to access identity information for the payload owner. `StorageDriverActivityInfo` only applies to standalone (non-workflow-bound) Activities -- Activities started by a Workflow use `StorageDriverWorkflowInfo`.

```go
type LocalDiskStorageDriver struct{ storeDir string }

func (d *LocalDiskStorageDriver) Name() string { return "my-local-disk" }
func (d *LocalDiskStorageDriver) Type() string { return "local-disk" }

func (d *LocalDiskStorageDriver) Store(
    ctx converter.StorageDriverStoreContext,
    payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) {
    dir := d.storeDir
    switch info := ctx.Target.(type) {
    case converter.StorageDriverWorkflowInfo:
        dir = filepath.Join(dir, info.Namespace, info.WorkflowID)
    case converter.StorageDriverActivityInfo:
        dir = filepath.Join(dir, info.Namespace, info.ActivityID)
    }
    // ... marshal each payload with proto.Marshal, write to dir,
    //     return a StorageDriverClaim{ClaimData: map[string]string{"path": ...}}
    return claims, nil
}

func (d *LocalDiskStorageDriver) Retrieve(
    ctx converter.StorageDriverRetrieveContext,
    claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) { /* read + proto.Unmarshal */ }
```

### Use multiple storage drivers (driver migration)

Register multiple drivers to migrate between storage backends or to route payloads across clouds. Any driver in the list that is not selected for storing is still available for retrieval, which is how driver migration works -- keep the legacy driver registered so its existing claims can be read while new payloads go to the preferred driver.

When more than one driver is registered, you must provide a `DriverSelector` that implements `StorageDriverSelector`. Returning `nil` from `SelectDriver` keeps the payload inline in Event History.

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

external := converter.ExternalStorage{
    Drivers:        []converter.StorageDriver{preferredDriver, legacyDriver},
    DriverSelector: &PreferredSelector{preferred: preferredDriver},
}
```

### Codec Server with External Storage

External Storage runs after the PayloadCodec, so if your codec encrypts, payloads are already encrypted before upload to your store.

A Codec Server that handles external storage exposes three endpoints. `/encode` applies the Payload Codec, then uploads payloads exceeding the threshold and replaces them with reference tokens. `/decode` decodes encoded payloads and, by default, transparently retrieves any storage references; pass `?preserveStorageRefs=true` to skip retrieval and return references as-is. `/download` retrieves and decodes a single storage reference and is called by the Web UI when a user clicks through to view the full payload.

Construct the Web UI / CLI handler with `NewPayloadHTTPHandler` and `PayloadHTTPHandlerOptions`, passing your storage drivers and codecs. Do **not** point a remote Worker codec at `NewPayloadHTTPHandler`: it runs the full encode-store-encode and decode-retrieve-decode pipeline. For remote Worker codecs, use `NewPayloadCodecHTTPHandler` separately, configured with the same codecs.

See `docs/encyclopedia/data-conversion/codec-server.mdx#external-storage` for the full walkthrough and the Go codec server sample at `https://github.com/temporalio/samples-go/tree/main/codec-server`.

### Lifecycle management

Temporal does not delete payloads from your external store. Configure a lifecycle policy on the bucket so orphaned payloads are eventually cleaned up while remaining available for debugging and recovery. The TTL must cover the entire lifetime of the Workflow plus its retention window:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

For example, a 14-day Maximum Workflow Run Timeout with a 30-day Namespace Retention Period requires a lifecycle rule that expires objects after at least 44 days.

For Workflows that run indefinitely (no Run Timeout), there is no finite TTL that guarantees safety. Use [Continue-as-New](/workflow-execution/continue-as-new); the new run uploads fresh payloads, and the old run's payloads only need to survive its retention period.

## Search Attributes

Set at workflow start:

```go
handle, err := c.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
    SearchAttributes: map[string]interface{}{
        "OrderStatus": "pending",
        "CustomerId":  "cust-456",
    },
}, OrderWorkflow, input)
```

Upsert from within a workflow:

```go
err := workflow.UpsertSearchAttributes(ctx, map[string]interface{}{
    "OrderStatus": "completed",
})
```

Typed search attributes (v1.26.0+, preferred):

```go
var OrderStatusKey = temporal.NewSearchAttributeKeyKeyword("OrderStatus")

err := workflow.UpsertTypedSearchAttributes(ctx, OrderStatusKey.ValueSet("completed"))
```

Query workflows by search attributes:

```go
resp, err := c.ListWorkflow(ctx, &workflowservice.ListWorkflowExecutionsRequest{
    Query: `OrderStatus = "pending" AND CustomerId = "cust-456"`,
})
```

## Workflow Memo

Set in start options:

```go
handle, err := c.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
    Memo: map[string]interface{}{
        "customerName": "Alice",
        "notes":        "Priority customer",
    },
}, OrderWorkflow, input)
```

Read memo from workflow info. Upsert memo (Go SDK only):

```go
err := workflow.UpsertMemo(ctx, map[string]interface{}{
    "notes": "Updated notes",
})
```

## Best Practices

1. Use structs with exported fields for inputs and outputs
2. Prefer JSON for readability during development, protobuf for performance in production
3. Keep payloads small -- see `references/core/gotchas.md` for limits
4. Use `PayloadCodec` for encryption; never store sensitive data unencrypted
5. Configure the same data converter on both client and worker
6. When payloads risk approaching the 2 MB per-payload limit, enable External Storage (see `## External Storage` above) to offload them via the claim check pattern instead of restructuring the Workflow
7. Configure a lifecycle policy on your external store with `TTL > Maximum Workflow Run Timeout + Namespace Retention Period` so payloads outlive the Workflows that reference them
