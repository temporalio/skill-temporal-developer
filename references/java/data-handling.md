# Java SDK Data Handling

## Overview

The Java SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters. The `DataConverter` interface controls how values are converted to and from Temporal `Payload` protobufs.

## Default Data Converter

`DefaultDataConverter` applies converters in order, using the first that accepts the value:

1. `NullPayloadConverter` — `null` values
2. `ByteArrayPayloadConverter` — `byte[]` as raw binary
3. `ProtobufJsonPayloadConverter` — Protobuf `Message` instances as JSON
4. `ProtobufPayloadConverter` — Protobuf `Message` instances as binary
5. `JacksonJsonPayloadConverter` — Everything else via Jackson `ObjectMapper`

## Jackson Integration

Use `JacksonJsonPayloadConverter` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:227 --> with a custom `ObjectMapper` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:232 --> for advanced serialization (e.g., Java 8 time module, custom serializers):

```java
ObjectMapper mapper = new ObjectMapper()
    .registerModule(new JavaTimeModule())
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

DefaultDataConverter converter = DefaultDataConverter.newDefaultInstance()
    .withPayloadConverterOverrides(
        new JacksonJsonPayloadConverter(mapper)
    );

WorkflowServiceStubs service = WorkflowServiceStubs.newLocalServiceStubs();
WorkflowClient client = WorkflowClient.newInstance(
    service,
    WorkflowClientOptions.newBuilder()
        .setDataConverter(converter)
        .build()
);
```

The default JSON path uses Jackson — workflow inputs <!-- docs/develop/java/workflows/basics.mdx:150 --> and activity inputs <!-- docs/develop/java/activities/basics.mdx:75 --> must be serializable by the default Jackson JSON Payload Converter.

## Jackson 3 Opt-In

The Java SDK lets you opt into **Jackson 3** payload conversion at startup while remaining **wire-compatible** with the Jackson 2 converters described above. <!-- pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3 -->

What this means in practice:

- **Default stays Jackson 2.** The `JacksonJsonPayloadConverter` shown in the section above is the documented default. <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:227-235 --> Opting into Jackson 3 is a deliberate startup-time choice, not an automatic upgrade. <!-- VERIFY: confirm the default-vs-opt-in framing once Jackson 3 docs ship -->
- **Wire compatibility.** Payloads produced by a Jackson 3 conversion path can be decoded by Jackson 2 converters, and vice versa. This is the design guarantee that lets a fleet upgrade incrementally — a worker running Jackson 3 can still read history events that were written by a Jackson 2 client, and a Jackson 2 client can still read results written by a Jackson 3 worker. <!-- pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3 -->
- **Scope: Java SDK only.** This opt-in exists only in the Java SDK; the Python, TypeScript, Go, and .NET SDKs are unaffected. <!-- pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:4-6 -->

<!-- VERIFY: The exact opt-in API surface — class name (e.g. analogous to `JacksonJsonPayloadConverter`), builder method on `WorkflowClientOptions` / `WorkerFactoryOptions`, or standalone configuration entry point — is not yet present in `docs/develop/java/best-practices/converters-and-encryption.mdx`. Do not invent the symbol; consult the Java SDK 1.35.0+ release notes / `io.temporal.common.converter` javadoc for the verbatim token before writing a code example here. -->

<!-- VERIFY: The Maven / Gradle artifact coordinates required to pull in the Jackson 3 conversion path (e.g. a separate `temporal-*` module or an additional `tools.jackson.*` dependency) are not documented in the docs clone. Do not invent coordinates. -->

<!-- VERIFY: Whether the Jackson 3 opt-in changes the `encoding` metadata value on emitted payloads, or reuses the Jackson 2 `json/plain` encoding to preserve wire compatibility, is not stated in docs. The info.json wire-compatibility claim is consistent with reusing the existing encoding, but this should be confirmed against the SDK source before documenting. -->

**Until the docs catch up:** keep using the documented Jackson 2 `JacksonJsonPayloadConverter` path shown in the section above. If you need Jackson 3 features today (e.g., the new `tools.jackson` API surface in your own code), wrap your serialization inside a custom `PayloadConverter` implementation (see "Custom Data Converter" below) rather than guessing at an unreleased Temporal-side API.

## Custom Data Converter

Implement `PayloadConverter` for custom serialization:

```java
public class MyCustomPayloadConverter implements PayloadConverter {
    @Override
    public String getEncodingType() {
        return "json/my-custom";
    }

    @Override
    public Optional<Payload> toData(Object value) throws DataConverterException {
        // Return Optional.empty() if this converter doesn't handle the type
        if (!(value instanceof MyCustomType)) {
            return Optional.empty();
        }
        // Serialize to Payload
        byte[] data = serialize(value);
        return Optional.of(
            Payload.newBuilder()
                .putMetadata("encoding", ByteString.copyFromUtf8(getEncodingType()))
                .setData(ByteString.copyFrom(data))
                .build()
        );
    }

    @Override
    public <T> T fromData(Payload content, Class<T> valueClass, Type valueType)
        throws DataConverterException {
        // Deserialize from Payload
        return deserialize(content.getData().toByteArray(), valueClass);
    }
}
```

Override specific converters in the default chain:

```java
DefaultDataConverter converter = DefaultDataConverter.newDefaultInstance()
    .withPayloadConverterOverrides(new MyCustomPayloadConverter());
```

## Composition of Payload Converters

`DefaultDataConverter` holds a list of `PayloadConverter` instances tried in order. The first converter whose `toData()` returns a non-empty `Optional` wins. When using `withPayloadConverterOverrides()`, converters with matching encoding types replace existing ones.

```java
DefaultDataConverter converter = DefaultDataConverter.newDefaultInstance()
    .withPayloadConverterOverrides(
        new MyCustomPayloadConverter(),       // encoding: "json/my-custom"
        new JacksonJsonPayloadConverter(mapper) // replaces default Jackson converter
    );
```

## Protobuf Support

Protobuf messages are handled by `ProtobufJsonPayloadConverter` (enabled by default). It serializes `com.google.protobuf.Message` instances as JSON for human readability in the Temporal UI.

```java
// Protobuf messages work out of the box as workflow/activity params
@WorkflowInterface
public interface MyWorkflow {
    @WorkflowMethod
    MyProtoResult run(MyProtoInput input);
}
```

For binary protobuf encoding instead of JSON, use `ProtobufPayloadConverter`:

```java
DefaultDataConverter converter = DefaultDataConverter.newDefaultInstance()
    .withPayloadConverterOverrides(new ProtobufPayloadConverter());
```

## Payload Encryption

Use `PayloadCodec` with `CodecDataConverter` to encrypt/compress payloads:

```java
public class EncryptionCodec implements PayloadCodec {
    private final SecretKey key;

    public EncryptionCodec(SecretKey key) {
        this.key = key;
    }

    @Override
    public List<Payload> encode(List<Payload> payloads) {
        return payloads.stream().map(payload -> {
            // Encrypt payload.toByteArray() using your chosen algorithm (e.g., AES/GCM)
            byte[] encrypted = encryptBytes(payload.toByteArray(), key);
            return Payload.newBuilder()
                .putMetadata("encoding", ByteString.copyFromUtf8("binary/encrypted"))
                .setData(ByteString.copyFrom(encrypted))
                .build();
        }).collect(Collectors.toList());
    }

    @Override
    public List<Payload> decode(List<Payload> payloads) {
        return payloads.stream().map(payload -> {
            String encoding = payload.getMetadataOrDefault(
                "encoding", ByteString.EMPTY).toStringUtf8();
            if (!"binary/encrypted".equals(encoding)) return payload;
            // Decrypt and reconstruct the original Payload
            byte[] decrypted = decryptBytes(payload.getData().toByteArray(), key);
            return Payload.parseFrom(decrypted);
        }).collect(Collectors.toList());
    }
}
```

Apply the codec to the client:

```java
CodecDataConverter codecDataConverter = new CodecDataConverter(
    DefaultDataConverter.newDefaultInstance(),
    Collections.singletonList(new EncryptionCodec(secretKey))
);

WorkflowClient client = WorkflowClient.newInstance(
    service,
    WorkflowClientOptions.newBuilder()
        .setDataConverter(codecDataConverter)
        .build()
);
```

## Search Attributes

Custom searchable fields for workflow visibility.

```java
import io.temporal.common.SearchAttributeKey;
import io.temporal.common.SearchAttributes;

// Define typed search attribute keys
static final SearchAttributeKey<String> ORDER_ID =
    SearchAttributeKey.forKeyword("OrderId");
static final SearchAttributeKey<String> ORDER_STATUS =
    SearchAttributeKey.forKeyword("OrderStatus");
static final SearchAttributeKey<Double> ORDER_TOTAL =
    SearchAttributeKey.forDouble("OrderTotal");
static final SearchAttributeKey<OffsetDateTime> CREATED_AT =
    SearchAttributeKey.forOffsetDateTime("CreatedAt");

// Set at workflow start
WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("order-" + orderId)
    .setTaskQueue("orders")
    .setTypedSearchAttributes(
        SearchAttributes.newBuilder()
            .set(ORDER_ID, orderId)
            .set(ORDER_STATUS, "pending")
            .set(ORDER_TOTAL, 99.99)
            .set(CREATED_AT, OffsetDateTime.now())
            .build()
    )
    .build();
```

Upsert during workflow execution:

```java
@WorkflowInterface
public interface OrderWorkflow {
    @WorkflowMethod
    String run(Order order);
}

public class OrderWorkflowImpl implements OrderWorkflow {
    static final SearchAttributeKey<String> ORDER_STATUS =
        SearchAttributeKey.forKeyword("OrderStatus");

    @Override
    public String run(Order order) {
        // ... process order ...

        Workflow.upsertTypedSearchAttributes(
            ORDER_STATUS.valueSet("completed")
        );
        return "done";
    }
}
```

### Querying Workflows by Search Attributes

```java
ListWorkflowExecutionsRequest request = ListWorkflowExecutionsRequest.newBuilder()
    .setNamespace("default")
    .setQuery("OrderStatus = 'processing' OR OrderStatus = 'pending'")
    .build();
```

## Workflow Memo

Store arbitrary metadata with workflows (not searchable).

```java
// Set memo at workflow start
WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("order-" + orderId)
    .setTaskQueue("orders")
    .setMemo(Map.of(
        "customer_name", order.getCustomerName(),
        "notes", "Priority customer"
    ))
    .build();
```

```java
// Read memo from workflow
@Override
public String run(Order order) {
    String notes = Workflow.getMemo("notes", String.class);
    // ...
}
```

## Deterministic APIs for Values

Use these APIs within workflows for deterministic values:

```java
@Override
public String run() {
    // Deterministic UUID (same on replay)
    String uniqueId = Workflow.randomUUID().toString();

    // Deterministic random (same on replay)
    Random rng = Workflow.newRandom();
    int value = rng.nextInt(100);

    // Deterministic current time (same on replay)
    long now = Workflow.currentTimeMillis();

    return uniqueId;
}
```

## Best Practices

1. Use Jackson `ObjectMapper` customization for complex serialization needs
2. Keep payloads small — see `references/core/gotchas.md` for limits
3. Encrypt sensitive data with `PayloadCodec` and `CodecDataConverter`
4. Use POJOs or Protobuf messages for workflow/activity parameters
5. Use `Workflow.randomUUID()`, `Workflow.newRandom()`, and `Workflow.currentTimeMillis()` for deterministic values
6. Prefer the documented Jackson 2 default (`JacksonJsonPayloadConverter`) until you have a specific reason to opt into Jackson 3; the two are wire-compatible, but the Jackson 3 opt-in API is not yet covered in the Temporal docs — verify the exact symbol in the Java SDK 1.35.0+ release notes and roll out through a staging environment first
