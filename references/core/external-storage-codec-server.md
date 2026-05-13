# Codec Server with External Storage

External Storage is a **Pre-Release** Temporal feature; APIs, option names, and
endpoint shapes may change before general availability. This reference is
SDK-agnostic and covers how a Codec Server must be set up to handle External
Storage references in addition to its usual encode/decode duties.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:82-88 -->

## Why the Codec Server needs to be External-Storage aware

When your Workers and Clients use External Storage, your storage drivers
replace large payloads in the Event History with small reference tokens that
point at data in an external store (for example, Amazon S3). The Temporal
Service and the Web UI only ever see those references — never the actual
payload bytes.

Without External Storage awareness in the Codec Server:

- The Web UI cannot show the real payload when a user clicks through to a
  reference; it can only display the reference token.
- The CLI cannot render decoded inputs and results for offloaded payloads.
- If you additionally run codecs in a proxy that encodes payloads *after* the
  Data Converter returns on the Worker, the ordering of "decode then download"
  versus "download then decode" matters, and only a storage-aware handler gets
  it right.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:84-88 -->

## The `NewPayloadHTTPHandler` factory

To make a Codec Server External-Storage aware, build the HTTP handler with
`NewPayloadHTTPHandler` and pass it `PayloadHTTPHandlerOptions`. Those options
accept:

- your **storage drivers** (the same ones your Workers use),
- your **pre-storage codecs** — the Payload Codecs configured in your Worker's
  Data Converter (typically encryption or compression),
- any **post-storage codecs** — codecs applied by a proxy *after* External
  Storage has already replaced large payloads with references.

The handler chains them together in the correct order across every endpoint.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-94 -->

## Endpoints when storage drivers are configured

A plain Codec Server exposes `/encode` and `/decode`. When the handler is built
through `NewPayloadHTTPHandler` *with storage drivers configured*, those two
endpoints become storage-aware and a third endpoint, `/download`, becomes
available. `/download` is **not** a default Codec Server endpoint — it only
exists when storage drivers are configured.

### `/encode`

Applies the Payload Codec, then uploads payloads that exceed the size
threshold to external storage and replaces them with reference tokens before
returning to the caller.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:112-113 -->

### `/decode`

Still decodes encoded payloads, but is now also aware of storage references.
By default, `/decode` uses the same retrieval logic as `/download` internally
to fetch and decode any storage references found in the request alongside
regular inline payloads.

With the `?preserveStorageRefs=true` query parameter, `/decode` **skips
retrieval** and returns storage references as-is. Inline payloads are still
decoded normally. This is the mode the Web UI uses for the initial Event
History view: it shows reference metadata until the user explicitly asks for
the underlying payload.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:109-111 -->

### `/download`

Retrieves the actual payload bytes from external storage and decodes them
through the Payload Codec. `/download` is used in two ways:

- **Internally by `/decode`** whenever `/decode` encounters a storage
  reference and `?preserveStorageRefs=true` was *not* supplied.
- **Directly from the Web UI** when a user clicks a reference to view the
  full payload. The data-encryption reference documents this endpoint as
  "retrieves and decodes payloads from External Storage. This endpoint is
  only needed if your Workers use External Storage."

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:105-108 -->
<!-- docs/production-deployment/data-encryption.mdx:78-80 -->

## `?preserveStorageRefs=true` and the Web UI two-step flow

The Web UI uses `?preserveStorageRefs=true` to keep Event History views cheap
and responsive: it does not pull every offloaded payload up front. Instead,
when the user clicks a reference token, the UI follows up with a `/download`
request for just that payload. Spell the parameter exactly as
`?preserveStorageRefs=true` — including the leading `?` and `=true`.

## `NewPayloadHTTPHandler` vs `NewPayloadCodecHTTPHandler`

These two factories are **not interchangeable**.

`NewPayloadHTTPHandler` runs the full **encode-store-encode** and
**decode-retrieve-decode** pipeline. It is intended for the Web UI and CLI,
which want fully decoded plaintext (or storage references plus a path back to
plaintext via `/download`). The docs are emphatic on this:

> Do not use it as a target for a remote Data Converter or remote codec on
> your Workers.

For remote codecs running against your Workers, use
`NewPayloadCodecHTTPHandler` separately. If you need both — that is, your
Workers use a remote codec **and** you want the Web UI/CLI to read offloaded
payloads — stand up two handlers side by side:

- `NewPayloadHTTPHandler` for the Web UI and CLI traffic, configured with your
  storage drivers and codecs.
- `NewPayloadCodecHTTPHandler` for your Workers' remote codec traffic,
  configured with the same codecs.

Configure them with the same codecs so encoding stays consistent across both
paths.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:96-103 -->

## End-to-end walkthrough

The following sequence (from the encyclopedia) shows how `/encode`, `/decode`,
and `/download` cooperate:

1. A user starts a Workflow from the CLI with a plaintext input. The CLI
   sends the input to the Codec Server's `/encode` endpoint.
2. The Codec Server encodes the payload through the Payload Codec. The
   encoded payload exceeds the storage threshold, so the Codec Server uploads
   it to external storage and returns a small reference token.
3. The CLI sends the reference token to the Temporal Service, which stores it
   in the Event History.
4. Later, a user views the Workflow in the Web UI. The Web UI retrieves the
   Event History from the Temporal Service and sends the payloads to the
   Codec Server's `/decode` endpoint with `?preserveStorageRefs=true`.
5. The Codec Server decodes any non-reference payloads through the Payload
   Codec, but returns storage references as-is. The Web UI displays the
   reference metadata, indicating the payload is stored externally.
6. The user clicks to view the full payload. The Web UI sends the storage
   reference to the `/download` endpoint.
7. The Codec Server retrieves the encoded payload from external storage,
   decodes it through the Payload Codec, and returns the plaintext result to
   the Web UI.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:122-135 -->

## Encryption codec ordering

The Payload Codec runs **before** External Storage on the encode side, and
**after** External Storage retrieval on the decode side. That means payloads
are already encrypted (or otherwise transformed by your codec) before they
are uploaded to the external store, and they are decrypted only after they
have been downloaded. This is why `PayloadHTTPHandlerOptions` distinguishes
pre-storage codecs from post-storage codecs — the handler must apply each set
on the correct side of the storage boundary.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-94, 112-113 -->

## CLI and Web UI configuration

CLI flags (`--codec-endpoint`, `--codec-auth`) and Web UI Namespace
configuration are the same whether or not the Codec Server is
storage-aware — point them at the same host. Those flags are covered in the
data-encryption reference and are not repeated here.

<!-- docs/production-deployment/data-encryption.mdx:306-333 -->

## Where to look next

- The "SDK Codec Server samples" section of
  `docs/encyclopedia/data-conversion/codec-server.mdx` lists per-SDK sample
  implementations (Go, Java, Python, TypeScript, .NET). Start there for a
  language-specific template that you can extend with
  `PayloadHTTPHandlerOptions`.
- `references/core/external-storage.md` — overview of External Storage,
  storage drivers, thresholds, and the Pre-Release status.
- `references/go/external-storage.md` — Go-specific External Storage and
  Codec Server wiring.
- `references/python/external-storage.md` — Python-specific External Storage
  and Codec Server wiring.

<!-- docs/encyclopedia/data-conversion/codec-server.mdx:194-202 -->
