# Temporal Java SDK — Jackson 3 Payload Conversion (opt-in)

## Status

This page is forward-looking. The local Temporal documentation clone consulted for this skill (`../documentation/`) currently documents only the **Jackson 2** `JacksonJsonPayloadConverter` path. Jackson-3-specific names — the new startup opt-in API, the converter class name, and any separate artifact coordinates — are flagged with `` below and must be confirmed against the Java SDK 1.35.0 docs once they land.

Until then, treat this page as: **what we know about the converter architecture (from Jackson 2) plus the unverified questions that need answering for Jackson 3.**

## Why this exists

The Temporal Java SDK's default JSON payload converter is `JacksonJsonPayloadConverter`, which wraps a Jackson 2 `ObjectMapper`.  Workflow inputs  and activity inputs  must be serializable by this converter.

Jackson 3 is the upstream FasterXML rewrite that, among other changes, renamed the package root from `com.fasterxml.jackson.*` to `tools.jackson.*` and made `ObjectMapper`/`JsonMapper` construction immutable-builder-based.  Existing Temporal Java applications already on Jackson 2 do not need to migrate; the topic info.json describing this skill states that the Jackson 3 conversion path will be **opt-in** and **wire-compatible** with payloads produced by the existing Jackson 2 converter.

## What is documented today (Jackson 2)

These facts come straight from `../documentation/` and frame the surface the Jackson 3 opt-in is layered on top of.

### Default converter chain

`DefaultDataConverter` is the entry point. Tokens that need conversion pass through each registered `PayloadConverter` in order; the first one whose encoding type matches handles the conversion.  The default chain's final fallback is `JacksonJsonPayloadConverter`, which serializes "everything else" via Jackson `ObjectMapper`. See `references/java/data-handling.md` for the full default ordering.

### Overriding a default converter

Override the JSON converter by constructing a custom `JacksonJsonPayloadConverter(ObjectMapper)` and passing it to `DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(...)`. The encoding type returned by `getEncodingType()` (e.g. `"json/plain"`) determines which default converter is replaced.

```java
// Jackson 2 (current, documented)
ObjectMapper objectMapper = new ObjectMapper();
// Add your custom logic here.
JacksonJsonPayloadConverter jackson2Converter =
    new JacksonJsonPayloadConverter(objectMapper);

DefaultDataConverter ddc =
    DefaultDataConverter.newDefaultInstance()
        .withPayloadConverterOverrides(jackson2Converter);

WorkflowClientOptions options =
    WorkflowClientOptions.newBuilder().setDataConverter(ddc).build();
```

### Constraints on input shapes

- Workflow method parameters must be serializable by the default Jackson JSON Payload Converter.
- Activity method parameters must be serializable by the default Jackson JSON Payload Converter.
- Pass a single parameter object containing all input fields to preserve backward compatibility when fields are added.

These constraints are version-agnostic: a Jackson-3-backed converter that produces the same wire format must satisfy the same constraints.

## What is NOT yet documented (Jackson 3)

The following questions are open against the local docs clone. Each is the kind of name that an AI is most tempted to fabricate — do not write any of them as if they were factual until they appear verbatim in `../documentation/`.

### The opt-in / startup API

The topic description says Jackson 3 is enabled through "a new startup API". The name of that API is **not** in `../documentation/`.

### The converter class

### Artifact coordinates

### Encoding-type identifier and wire compatibility

### ObjectMapper vs JsonMapper construction

## Anti-fabrication checklist (read before writing code in this area)

Until the items above land in `../documentation/`:

1. Do not write a class name like `Jackson3JsonPayloadConverter` as if it existed.
2. Do not write a method like `useJackson3()`, `withJackson3()`, or `newJackson3Instance()` as if it existed.
3. Do not write an artifact ID like `io.temporal:temporal-jackson-3`.
4. Do not claim Temporal docs say payloads are wire-compatible across Jackson 2 and Jackson 3. (The topic-planning info.json claims this; the user-facing docs do not, in this session's clone.)
5. Do not chain unverified facts into a migration recipe ("first do A, then do B"). Per the template's §3.6, recipes must chain documented facts only.
6. Do not import from `tools.jackson.*` in example code unless the example is explicitly framed as "what Jackson 3 itself looks like upstream" with a Jackson-project citation — not a Temporal one.

## Where to look when 1.35.0 docs land

When the Java SDK 1.35.0 documentation is merged into `temporalio/documentation`, the most likely landing zones for the Jackson 3 prose are:

- `docs/develop/java/best-practices/converters-and-encryption.mdx` — the current Jackson 2 page; a Jackson 3 section is the natural place to add the opt-in API and the wire-compatibility note. Re-read §"Using custom Payload conversion".
- A new file under `docs/develop/java/best-practices/` if Jackson 3 gets a dedicated page.
- Release notes / migration notes that may live elsewhere in `docs/develop/java/`.

After confirming names in those files, the right edits to this page are:

1. Replace each `` block with the documented name plus an inline citation comment.
2. Add a working "opt in to Jackson 3" example next to the existing Jackson 2 example.
3. If wire compatibility is documented, restate it with a citation; if it is documented with caveats (e.g. specific encoding-type values, specific date/time module behavior), surface those caveats verbatim.
4. Update `references/integrations.md` only if the catalog row's one-clause description is no longer accurate.

## See also

- `references/java/data-handling.md` — full Java data-converter overview (default chain, payload codec, encryption). Jackson is the JSON layer; the codec layer (encryption/compression) is unaffected by Jackson version.
- `references/java/java.md` — Java SDK quick start and reference index.
