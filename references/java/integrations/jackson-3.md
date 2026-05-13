# Jackson 3 opt-in (Java SDK)

The Temporal Java SDK is adding an opt-in path to use Jackson 3 for the default JSON `PayloadConverter` <!-- VERIFY: which class/method exposes the Jackson 3 opt-in? sdk-java is not vendored here -->. Today, the default JSON converter is the Jackson 2-based `JacksonJsonPayloadConverter` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:227 -->, and Workflow and Activity inputs are expected to be serializable by the "default Jackson JSON Payload Converter" <!-- docs/develop/java/workflows/basics.mdx:150 --> <!-- docs/develop/java/activities/basics.mdx:75 -->. The Jackson 3 opt-in is designed to be wire-compatible so that a mixed fleet (some workers on Jackson 2, some on Jackson 3) can poll the same Workflow Execution without breaking replay or new tasks.

## Why this exists

Jackson 3 ships with a different package namespace and several breaking-API changes vs. Jackson 2. Without an explicit opt-in, every Temporal Java SDK user would inherit Jackson 2's behavior indefinitely, and applications would be unable to upgrade their own Jackson dependency past 2.x without conflicting with the SDK's default converter. An opt-in lets an application migrate to Jackson 3 on its own schedule while preserving the replayability of Workflow Histories that were originally encoded by a Jackson 2 worker.

## Wire-compatibility contract

The opt-in is safe to roll out incrementally because of how Temporal's Composite Data Converter selects a `PayloadConverter`:

- A `PayloadConverter` advertises an encoding via `getEncodingType()` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:207 -->, and the Jackson-based JSON converter uses `"json/plain"` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:208 -->.
- The Composite Data Converter "tries the Payload Converters in that specific order until a Payload Converter returns a non-nil Payload" <!-- docs/encyclopedia/data-conversion/payload-converter.mdx:49 -->, with the default order being nil, byte slice, proto JSON, proto binary, JSON <!-- docs/encyclopedia/data-conversion/payload-converter.mdx:38 -->.
- On the receive side, `fromData` is selected based on the Payload's encoding metadata, using the `PayloadConverter` interface methods `toData` and `fromData` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:212 --> <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:217 -->.

As long as both the Jackson 2 and Jackson 3 implementations:

1. claim the same encoding type (`"json/plain"`), and
2. produce and accept the same JSON bytes for a given POJO,

a Jackson 2 worker and a Jackson 3 worker can interoperate on the same Workflow Execution. A Workflow input written by a Jackson 2 client can be read by a Jackson 3 worker, and vice versa, because each side picks its installed `"json/plain"` converter and parses the bytes <!-- VERIFY: confirm Jackson 3 converter advertises "json/plain" and that its JSON byte output for standard POJOs is byte-identical (or at least value-equivalent on parse) to Jackson 2's -->.

## The opt-in mechanism

Opt-in is performed at startup time when constructing the `DataConverter` <!-- VERIFY: exact class/method name for the Jackson 3 opt-in --> and installing it on `WorkflowClientOptions.setDataConverter(...)` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:154 -->. The shape mirrors the existing custom-`PayloadConverter` pattern: build a `DefaultDataConverter`, override the JSON entry with the Jackson 3 converter via `withPayloadConverterOverrides` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:247 -->, then pass the result to `WorkflowClientOptions`.

Skeleton (do not copy verbatim — the Jackson 3 symbols are placeholders pending verification):

```java
// import io.temporal.common.converter.DefaultDataConverter;
// import io.temporal.client.WorkflowClient;
// import io.temporal.client.WorkflowClientOptions;
// import io.temporal.serviceclient.WorkflowServiceStubs;

// VERIFY: Jackson 3 converter class name and its ObjectMapper-equivalent type
// (Jackson 3 moved away from com.fasterxml.jackson; the exact import/coordinate
// for both the SDK's Jackson 3 converter and the underlying mapper need confirmation)
PayloadConverter jackson3Json = /* VERIFY: new <Jackson3JsonPayloadConverter>(<mapper>) */;

DefaultDataConverter ddc =
    DefaultDataConverter.newDefaultInstance() // docs/develop/java/best-practices/converters-and-encryption.mdx:246
        .withPayloadConverterOverrides(jackson3Json); // docs/develop/java/best-practices/converters-and-encryption.mdx:247

WorkflowServiceStubs service = WorkflowServiceStubs.newLocalServiceStubs();
WorkflowClient client =
    WorkflowClient.newInstance(
        service,
        WorkflowClientOptions.newBuilder()
            .setDataConverter(ddc) // docs/develop/java/best-practices/converters-and-encryption.mdx:154
            .build());
```

Because `withPayloadConverterOverrides` replaces an entry in the default chain by matching on `getEncodingType()` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:207 -->, supplying a Jackson 3 converter that returns `"json/plain"` cleanly replaces the Jackson 2 default for that slot without disturbing the nil, byte slice, proto JSON, or proto binary converters <!-- docs/encyclopedia/data-conversion/payload-converter.mdx:38 -->.

## Setup checklist

1. Decide your Jackson 3 dependency strategy. Jackson 3 uses a new package namespace and module coordinates distinct from Jackson 2 <!-- VERIFY: confirm the groupId/artifactId your application should declare alongside the Temporal SDK's Jackson 3 module, and whether the SDK module is a separate artifact (e.g., a temporal-sdk-jackson3 add-on) or part of the core SDK -->.
2. Add the Temporal SDK module that ships the Jackson 3 converter to your build <!-- VERIFY: artifactId and version range for the Jackson 3 converter module -->.
3. Construct your Jackson 3 mapper, applying any project-specific configuration (modules, serialization features, naming strategy). Carry over any Jackson 2 configuration deliberately — see "Common mistakes" below.
4. Build the `DataConverter` using `DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(...)` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:246 --> with the Jackson 3 `PayloadConverter` instance.
5. Install it on `WorkflowClientOptions.setDataConverter(...)` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:154 --> on every `WorkflowClient` your process constructs (worker side and starter side both).
6. If you also use a `PayloadCodec` (for example, for encryption), wrap the Jackson 3 `DefaultDataConverter` in `CodecDataConverter` exactly as you did with the Jackson 2 default <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:155 -->.

## Mixed-fleet rollout

Because the wire format remains `"json/plain"` JSON bytes <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:208 -->, a phased rollout is safe:

- Canary one worker on Jackson 3 against a non-critical Task Queue, then expand.
- Workers running Jackson 2 and workers running Jackson 3 can both poll the same Workflow Execution: each side picks its installed `"json/plain"` converter for `toData`/`fromData` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:212 --> <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:217 -->.
- A Workflow that started on Jackson 2 can complete on Jackson 3 because the History's JSON payloads are decoded against whatever `"json/plain"` converter the current worker has installed, and the converter selection follows the Composite Data Converter's encoding-based dispatch <!-- docs/encyclopedia/data-conversion/payload-converter.mdx:49 -->.

Verify your specific POJO set first: any Jackson 2 customization that has no direct Jackson 3 equivalent could cause a serialization drift even when the encoding type matches <!-- VERIFY: enumerate Jackson 2 ObjectMapper features without a Jackson 3 equivalent that are relevant to Temporal payloads -->.

## Common mistakes and gotchas

- **Wrong override slot.** `withPayloadConverterOverrides` replaces an entry by matching on `getEncodingType()` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:207 -->. The Jackson 3 override must return `"json/plain"` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:208 --> to replace the Jackson 2 default rather than appending a new converter that is never selected.
- **Confusing converter with codec.** Jackson 2 vs. Jackson 3 is a `PayloadConverter` concern — serialization shape <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:199 -->. Encryption and compression are a `PayloadCodec` concern — byte-to-byte transformation <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:39 -->. The two are independent and are wired together via `CodecDataConverter` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:37 -->; opting into Jackson 3 does not change your codec, and vice versa.
- **Pinned Jackson 2 mapper configuration.** Custom `ObjectMapper` builds (modules, feature flags, naming strategies) used with `JacksonJsonPayloadConverter` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:231 --> may not have one-to-one equivalents on the Jackson 3 mapper. Audit each feature on the Jackson 2 mapper before switching <!-- VERIFY: which Jackson 2 ObjectMapper features lack Jackson 3 equivalents or have renamed equivalents in the new namespace -->.
- **Setting the converter on only one client.** The example in the docs deliberately uses a single `WorkflowClient` "in your Worker process and to start your Workflow Executions" <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:148 -->. If your application constructs separate clients for starting Workflows vs. running Workers, both must be built with the same `DataConverter`, or Workflow input/output will fail to round-trip.
- **Forgetting non-JSON converters.** The default chain also includes nil, byte slice, and proto converters <!-- docs/encyclopedia/data-conversion/payload-converter.mdx:38 -->. Use `DefaultDataConverter.newDefaultInstance()` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:246 --> as the base and override only the JSON slot — do not hand-roll a one-converter chain.

## Related references

- `references/java/data-handling.md` — broader context on Jackson and `PayloadConverter` usage in the Java SDK.
- `docs/develop/java/best-practices/converters-and-encryption.mdx` — canonical source for custom `PayloadConverter`, `JacksonJsonPayloadConverter`, `DefaultDataConverter`, `withPayloadConverterOverrides`, and `WorkflowClientOptions.setDataConverter`.
