# Go SDK Data Handling

## Overview

The Go SDK uses the `converter.DataConverter` interface to serialize/deserialize workflow inputs, outputs, and activity parameters. The default converter converts values to JSON.

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

**Memo values:** by default the Go SDK does **not** route Workflow Memo serialization through this custom `DataConverter`; a separate `client.Options` flag opts Memo encoding into the user-configured converter. See [Routing Memo serialization through your DataConverter](#routing-memo-serialization-through-your-dataconverter-go-sdk-flag) under the Workflow Memo section below.

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

A Memo is a non-indexed set of Workflow Execution metadata supplied at start time or from Workflow code and returned when describing or listing Workflow Executions. <!-- docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx:169 --> Memos lack type safety and are eventually consistent — don't use them for execution-critical data. <!-- docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx:179-180 -->

`StartWorkflowOptions.Memo` is `map[string]interface{}`, default empty. <!-- docs/develop/go/client/temporal-client.mdx:700,888 -->

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
<!-- shape matches docs/develop/go/client/temporal-client.mdx:891-902 -->

Read memo from workflow info. Upsert memo (Go SDK only):

```go
err := workflow.UpsertMemo(ctx, map[string]interface{}{
    "notes": "Updated notes",
})
```

### Routing Memo serialization through your DataConverter (Go SDK flag)

By default the Go SDK serializes Memo values with its own JSON converter rather than the user-configured `DataConverter` passed to `client.Dial`. <!-- VERIFY: confirm default behavior against go.temporal.io/sdk/client godoc; documentation clone is silent on the default --> The Go SDK has added a `client.Options` flag that, when enabled, routes Memo serialization through the user-configured `DataConverter` so the same Payload Converters (and any wrapping `CodecDataConverter`) used for Workflow inputs/outputs also apply to Memos. <!-- VERIFY: exact field name on client.Options and its default; not present in ../documentation/docs/ as of this authoring pass — check pkg.go.dev/go.temporal.io/sdk/client.Options -->

Practical consequences when the flag is enabled:

- Custom `PayloadConverter`s registered in your `CompositeDataConverter` are used to encode Memo values, instead of the SDK's built-in JSON encoding for Memos. <!-- VERIFY -->
- If your `DataConverter` is wrapped in a `CodecDataConverter` (for example to apply a `PayloadCodec` for encryption or compression), that codec also runs over Memo Payloads. <!-- VERIFY: confirm whether the flag covers the Codec stage as well as the Converter stage -->
- The same converter configured on the client (`client.Options{DataConverter: ...}`) is what gets used. <!-- docs/develop/go/best-practices/data-handling/data-encryption.mdx:110-118 -->

Scope notes:

- This flag is Go SDK-only. Other SDKs may expose equivalent behavior under different names; see their language references.
- Search Attributes are unaffected — they are stored indexed and follow their own typing rules; see [Search Attributes](#search-attributes) above. <!-- docs/develop/go/client/temporal-client.mdx:904-933 -->
- Existing Memos written before enabling the flag remain encoded with the SDK's previous default; switching the flag does not retroactively re-encode them. <!-- VERIFY -->

> **Source caveat:** as of this authoring pass, the local `temporalio/documentation` clone does not document this flag. Confirm the exact field name on `client.Options`, its default value, and whether it covers the `PayloadCodec` stage by reading the Go SDK godoc at `pkg.go.dev/go.temporal.io/sdk/client` before relying on this section.

## Best Practices

1. Use structs with exported fields for inputs and outputs
2. Prefer JSON for readability during development, protobuf for performance in production
3. Keep payloads small -- see `references/core/gotchas.md` for limits
4. Use `PayloadCodec` for encryption; never store sensitive data unencrypted
5. Configure the same data converter on both client and worker
