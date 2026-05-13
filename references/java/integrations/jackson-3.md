# Jackson 3 Payload Conversion (Java SDK)

The Java SDK ships its `JacksonJsonPayloadConverter` against Jackson 2 by default and offers an **opt-in delegate** that swaps in a Jackson 3 implementation at startup. The two converters use the same `"json/plain"` encoding on the wire, so a Jackson-3-enabled client can interoperate with workers and clients still on Jackson 2 without rewriting history.

This page is the reference for the opt-in. For the Jackson 2 baseline (default converter chain, `withPayloadConverterOverrides`, codec composition), see `references/java/data-handling.md`.

## When to opt in

- Your application classpath has moved to Jackson 3 (`tools.jackson.core:jackson-databind:3.x`) — e.g. you are on Spring Framework 7 / Spring Boot 4, which target Jackson 3.
- You want Jackson 3's native handling of `java.time` types and `Optional` without registering modules manually.
- You need to remove Jackson 2 from your classpath entirely.

If none of the above apply, stay on the Jackson 2 default. The opt-in API is marked `@Experimental`, so its signature may change before it stabilizes.

## Requirements

- Java SDK `io.temporal:temporal-sdk` v1.34.0 or later.
- Java 17 or newer at runtime. The Jackson 3 converter is delivered through the SDK jar's multi-release `java17/` entry; on older Java versions the class stub throws `UnsupportedOperationException` with the message "Jackson 3 PayloadConverter requires Java 17+ and Jackson 3.x (tools.jackson.core:jackson-databind) on the classpath".
- `tools.jackson.core:jackson-databind:3.x` on the classpath. Note the new Maven groupId — Jackson 3 lives under `tools.jackson.*`, not `com.fasterxml.jackson.*`.

If either prerequisite is missing, `JacksonJsonPayloadConverter.setDefaultAsJackson3(true, ...)` throws `IllegalStateException`.

## The opt-in API

There is one entry point:

```java
// io.temporal.common.converter.JacksonJsonPayloadConverter

@Experimental
public static void setDefaultAsJackson3(boolean defaultAsJackson3, boolean jackson2Compat)
```

Parameters:

- `defaultAsJackson3` — `true` makes instances built via the default `JacksonJsonPayloadConverter()` constructor delegate all serialization/deserialization to a `Jackson3JsonPayloadConverter`. `false` reverts to Jackson 2.
- `jackson2Compat` — only meaningful when `defaultAsJackson3` is `true`. When `true`, the Jackson 3 converter is configured with Jackson 2.x default behaviors for maximum wire compatibility. When `false`, native Jackson 3 defaults are used.

The setting is global: it affects the converter present in `DefaultDataConverter.STANDARD_PAYLOAD_CONVERTERS`, which means it applies to anything that goes through the default data converter.

**Call site requirement.** The JavaDoc directs callers to "call this method early in your application, before creating any Temporal clients". Treat that as a hard requirement: clients capture their data converter at build time, so toggling the flag afterward has no effect on already-built clients.

### Minimal opt-in at startup

```java
import io.temporal.common.converter.JacksonJsonPayloadConverter;

public static void main(String[] args) {
    // Switch the default payload converter to Jackson 3 with Jackson-2-compatible defaults.
    JacksonJsonPayloadConverter.setDefaultAsJackson3(true, /* jackson2Compat */ true);

    // Now build clients / workers as usual.
    WorkflowServiceStubs service = WorkflowServiceStubs.newLocalServiceStubs();
    WorkflowClient client = WorkflowClient.newInstance(service);
    // ...
}
```

`WorkflowServiceStubs`, `WorkflowClient`, and the default `Jackson` converter are the same APIs documented for Jackson 2 — see `docs/develop/java/best-practices/converters-and-encryption.mdx`.

## Wire compatibility vs behavior compatibility

The two converters return the same encoding type so payloads are interchangeable on the wire:

- `JacksonJsonPayloadConverter.getEncodingType()` → `"json/plain"`.
- `Jackson3JsonPayloadConverter.getEncodingType()` → `"json/plain"` (returned from `EncodingKeys.METADATA_ENCODING_JSON_NAME`).

That means:

- A worker running Jackson 2 can deserialize a payload serialized by a Jackson-3 client (and vice versa), assuming the JSON shape itself is compatible.
- Existing workflow histories continue to deserialize after a Jackson-3 opt-in.

Wire compatibility is **not** the same as behavior compatibility. Jackson 3 changes several serialization defaults relative to Jackson 2 (`java.time` handling, `Optional`, etc.). If you opt in with `jackson2Compat=false`, JSON output and parsing semantics may differ from what was on the wire before the switch. If you need bit-for-bit identical JSON, use `jackson2Compat=true`.

| Mode | `defaultAsJackson3` | `jackson2Compat` | Behavior |
|---|---|---|---|
| Jackson 2 (default) | `false` | n/a | Existing behavior; classpath needs `com.fasterxml.jackson.*` |
| Jackson 3, compat mode | `true` | `true` | Uses Jackson 3 but applies `JsonMapper.builderWithJackson2Defaults()`-style defaults for wire/output compatibility |
| Jackson 3, native | `true` | `false` | Native Jackson 3 defaults; output may differ from Jackson 2 |

## The Jackson 3 converter class

If you need a `PayloadConverter` instance directly (e.g. to inject it into a custom converter chain), the class is:

```java
// io.temporal.common.converter.Jackson3JsonPayloadConverter

public Jackson3JsonPayloadConverter()                            // native Jackson 3 defaults
public Jackson3JsonPayloadConverter(boolean jackson2Compat)      // toggle compatibility mode
public Jackson3JsonPayloadConverter(JsonMapper mapper)           // custom JsonMapper
```

`JsonMapper` here is `tools.jackson.databind.json.JsonMapper` (the Jackson 3 replacement for `com.fasterxml.jackson.databind.ObjectMapper`).

You can wire an instance into the default converter chain the same way as any other `PayloadConverter`:

```java
DefaultDataConverter ddc =
    DefaultDataConverter.newDefaultInstance()
        .withPayloadConverterOverrides(new Jackson3JsonPayloadConverter(/* jackson2Compat */ true));

WorkflowClientOptions options =
    WorkflowClientOptions.newBuilder().setDataConverter(ddc).build();
```

The `withPayloadConverterOverrides` + `setDataConverter` pattern is the same as for the Jackson 2 converter — see `docs/develop/java/best-practices/converters-and-encryption.mdx`.

## Important limitations

- **Explicit `ObjectMapper` bypasses delegation.** A `JacksonJsonPayloadConverter` built with `new JacksonJsonPayloadConverter(objectMapper)` keeps using the supplied Jackson 2 `ObjectMapper` even after `setDefaultAsJackson3(true, ...)` has been called. The global flag only affects converters built via the default constructor.
- **Global, not per-client.** There is no `WorkflowClientOptions` setter, system property, environment variable, or `application.properties` key that performs this opt-in. The opt-in is the static Java method call only.
- **Marked `@Experimental`.** Do not assume the signature, parameter names, or behavior of `setDefaultAsJackson3` will be stable across minor SDK releases.
- **No `is`/`get`/`reset` companion.** The SDK source exposes only `setDefaultAsJackson3`; there is no documented getter for current state or reset helper.

## Common mistakes

- Importing Jackson 3 types from `com.fasterxml.jackson.*`. The Jackson 3 package root is `tools.jackson.*`.
- Calling `setDefaultAsJackson3` after constructing a `WorkflowClient`. The client has already captured the default data converter; the change does not propagate.
- Assuming `jackson2Compat=true` reproduces every Jackson 2 quirk. It applies the documented compatibility defaults; configuration applied to a custom Jackson 2 `ObjectMapper` (custom modules, naming strategies, etc.) is not automatically carried over.
- Treating "wire-compatible" as "drop-in." Confirm `java.time`, `Optional`, and enum-naming behavior in your domain payloads before flipping the flag in production.

## Driver: Spring Boot 4 / Spring Framework 7

A common reason to flip the opt-in is moving an application to Spring Boot 4 or Spring Framework 7, which target Jackson 3. If you use the `temporal-spring-boot-starter`, the starter still constructs its `WorkflowClient` from the default data converter — calling `setDefaultAsJackson3(true, true)` in your `main` method (before Spring's `SpringApplication.run`) lets the starter's clients pick up the Jackson 3 delegate. See `references/java/integrations/spring-boot.md` for starter wiring details.

## Version availability

| SDK version | Jackson 3 status |
|---|---|
| < 1.34.0 | Not available |
| 1.34.0 (2026-04-01) | Introduced, `@Experimental` |

<!-- Sources:
docs/develop/java/workflows/basics.mdx
docs/develop/java/activities/basics.mdx
docs/develop/java/best-practices/converters-and-encryption.mdx
sdk-java: temporal-sdk/src/main/java/io/temporal/common/converter/JacksonJsonPayloadConverter.java
sdk-java: temporal-sdk/src/main/java17/io/temporal/common/converter/Jackson3JsonPayloadConverter.java
sdk-java: release notes v1.34.0 (2026-04-01)
-->
