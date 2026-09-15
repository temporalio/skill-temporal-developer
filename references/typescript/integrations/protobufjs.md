# Temporal Protobuf.js Integration (TypeScript) — v8 Migration

## Overview
Use Protocol Buffers with the Temporal TypeScript SDK by configuring a protobuf‑aware Payload Converter. The TypeScript SDK does not include Protobuf JSON by default; enable it explicitly or use binary encoding. This page focuses on migrating existing apps as projects adopt protobufjs v8.

- TypeScript SDK does not support Protobuf JSON by default. Use `ProtobufJsonPayloadConverter` when passing Protobuf payloads.
- For general TypeScript data conversion and protobuf helpers (`DefaultPayloadConverterWithProtobufs`, `patchProtobufRoot`), see the TypeScript data‑conversion guide.
- Cross‑SDK defaults include protobuf JSON, but TypeScript is an exception and requires configuration.

## Prerequisites
- Temporal TypeScript SDK installed (`@temporalio/*`).
- Protobuf schema compiled or loadable into a `protobufjs` Root.

## Configure a protobuf Root
If you load descriptors at runtime, use the SDK helper to patch the root for compatibility:

```ts
// root.ts
import { Root } from protobufjs;
import { patchProtobufRoot } from @temporalio/common/lib/protobufs; // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:318 -->

const unpatched = new Root();
export const root = patchProtobufRoot(unpatched); // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:320 -->
```

## Enable protobuf support (JSON or binary)
Create a protobuf‑aware Payload Converter and provide it to the Worker and Client.

```ts
// payload-converter.ts
import { DefaultPayloadConverterWithProtobufs } from @temporalio/common/lib/protobufs; // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:335 -->
import { root } from ./root;

export const payloadConverter = new DefaultPayloadConverterWithProtobufs({ protobufRoot: root }); // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:338 -->
```

Worker and Client configuration (path-based registration):

```ts
// worker.ts
import { Worker } from @temporalio/worker;

const worker = await Worker.create({
  workflowsPath: require.resolve(./workflows),
  taskQueue: protobufs,
  dataConverter: { payloadConverterPath: require.resolve(./payload-converter) },
});
```

```ts
// client.ts
import { Client } from @temporalio/client;

const client = new Client({
  dataConverter: { payloadConverterPath: require.resolve(./payload-converter) },
});
```

### Binary encoding option
If you prefer protobuf binary payloads, use the binary converter:

```ts
import { ProtobufBinaryPayloadConverter } from @temporalio/common/lib/protobufs; // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:346 -->
import { CompositePayloadConverter } from @temporalio/common;
import { root } from ./root;

export const payloadConverter = new CompositePayloadConverter(
  new ProtobufBinaryPayloadConverter(root), // <!-- docs/develop/typescript/best-practices/data-handling/data-conversion.mdx:349,367 -->
);
```

### Protobuf JSON note
The TypeScript SDK does not support Protobuf JSON by default. Use `ProtobufJsonPayloadConverter` if your data must be proto3‑JSON.

## v8 migration notes (protobufjs)
When upgrading to protobufjs v8, projects often see stricter typings and helper API adjustments that affect how messages are constructed and converted to/from JSON.

- Expect type changes that can impact message construction in TypeScript (e.g., stricter field typing); update call sites accordingly.
- Re‑check any usage of JSON helpers (`fromObject` / `toObject` / `toJSON`) against v8 behavior; align with Temporal’s configured converter (JSON vs binary).
- Prefer constructing and passing actual message instances to Temporal APIs, letting the configured Payload Converter handle encoding.

> VERIFY: Confirm exact v8 helper signatures and typing changes in the official protobufjs v8 migration notes; adjust examples if the project relied on deprecated helpers.

## Hard constraints
- Do not assume protobuf JSON support without configuring a protobuf‑aware converter.
- Keep converter tokens verbatim; do not substitute or infer names.

## Common mistakes
- Using the default TypeScript converter and expecting protobuf JSON encoding. Use `ProtobufJsonPayloadConverter` or `DefaultPayloadConverterWithProtobufs`.
- Forgetting to provide a `protobufRoot` when constructing the converter.
- Mixing binary and JSON encodings inadvertently; decide on one per interface and configure consistently.

## Resources
- TypeScript Payload conversion (protobufs, helpers): `docs/develop/typescript/best-practices/data-handling/data-conversion.mdx`.
- Default vs custom Data Converters (cross‑SDK): `docs/encyclopedia/data-conversion/default-custom-data-converter.mdx`.
- Protobuf JSON support note: `docs/develop/typescript/nexus/feature-guide.mdx`.
- protobufjs v8 release notes / API docs (for helper/type deltas).
