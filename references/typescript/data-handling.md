# TypeScript SDK Data Handling

## Overview

The TypeScript SDK uses a `DataConverter` to move values between the SDK and the Temporal Service. It combines three components:

- `PayloadConverter` serializes values to and from payload bytes. The default converter handles `undefined`, `null`, `Uint8Array`, and JSON-serializable types.
- `PayloadCodec` transforms payloads, for example to encrypt or compress them.
- `failureConverter` converts exceptions to and from Temporal `Failure` protobufs.

Most serialization customization belongs in a `PayloadConverter`; encryption and compression belong in a `PayloadCodec`; and custom exception serialization belongs in a `failureConverter`.

## Payload size validation

Since SDK 1.21, Workers validate outbound payload sizes, log `[TMPRL1103]`, and fail oversized Workflow/Activity Tasks retryably before sending them. Prefer smaller payloads or [External Storage](external-storage.md). If a downstream proxy transforms payloads after the Worker (for example, compression or externalization), `WorkerOptions.disablePayloadErrorLimit: true` defers enforcement to the server; it does not raise the server limit.

## Experimental payload cache

`WorkerOptions.payloadCache` (experimental) sets the payload cache shared by the Worker. Pass a `PayloadCache` object to enable caching, or `false` to disable it. The default is `false`.

`PayloadCache` (from `@temporalio/common`) has two async methods:

- `get(key: string): Promise<Payload | undefined>` resolves to the stored payload, or `undefined` on a miss.
- `set(key: string, payload: Payload): Promise<boolean>` resolves to whether the cache accepted the payload.

Implementations should not throw or reject. Return `undefined` or `false` instead. The SDK treats a failed `get` as a miss and ignores a failed `set`.

```typescript
import type { Payload, PayloadCache } from '@temporalio/common';

// Illustrative in-memory cache; not a built-in or default.
class MapPayloadCache implements PayloadCache {
  private readonly entries = new Map<string, Payload>();

  async get(key: string): Promise<Payload | undefined> {
    return this.entries.get(key);
  }

  async set(key: string, payload: Payload): Promise<boolean> {
    this.entries.set(key, payload);
    return true;
  }
}

const worker = await Worker.create({
  payloadCache: new MapPayloadCache(),
  // ...
});
```

## Default Payload Converter

The default payload converter handles:

- `undefined` and `null`
- `Uint8Array` (as binary)
- JSON-serializable types

Note: Protobuf support requires using a data converter (`DefaultPayloadConverterWithProtobufs`). See the Protobuf Support section below.

## Custom Payload Converter

Customize serialization by replacing the `PayloadConverter` component in the `DataConverter` configuration. The SDK keeps the default codec and failure converter unless you configure replacements.

```typescript
// payload-converter.ts
import {
  PayloadConverter,
  Payload,
  defaultPayloadConverter,
} from '@temporalio/common';

class CustomPayloadConverter implements PayloadConverter {
  toPayload<T>(value: T): Payload | undefined {
    // Custom serialization logic
    return defaultPayloadConverter.toPayload(value);
  }

  fromPayload<T>(payload: Payload): T {
    // Custom deserialization logic
    return defaultPayloadConverter.fromPayload(payload);
  }
}

export const payloadConverter = new CustomPayloadConverter();
```

```typescript
// client.ts
import { Client } from '@temporalio/client';

const client = new Client({
  dataConverter: {
    payloadConverterPath: require.resolve('./payload-converter'),
  },
});
```

```typescript
// worker.ts
import { Worker } from '@temporalio/worker';

const worker = await Worker.create({
  dataConverter: {
    payloadConverterPath: require.resolve('./payload-converter'),
  },
  // ...
});
```

## Composition of Payload Converters

```typescript
import { CompositePayloadConverter } from '@temporalio/common';

// The order matters — converters are tried in sequence until one returns a non-null Payload
export const payloadConverter = new CompositePayloadConverter(
  new PayloadConverterFoo(),
  new PayloadConverterBar(),
);
```

## Protobuf Support

Configure a Protobuf payload converter when Workflow, Signal, or Activity payloads contain Protobuf message instances. Export `payloadConverter` from a module with the generated Protobuf root and pass the same `payloadConverterPath` to the Client and Worker. Also pass that path to `bundleWorkflowCode` if building the Workflow bundle separately.

```typescript
// payload-converter.ts
import { DefaultPayloadConverterWithProtobufs } from '@temporalio/common/protobufs';
import root from './generated/root';

export const payloadConverter = new DefaultPayloadConverterWithProtobufs({ protobufRoot: root });
```

```typescript
const dataConverter = { payloadConverterPath: require.resolve('./payload-converter') };
```

### Protobuf.js compatibility

Use Protobuf.js v8 when supplying a custom root to the current SDK's Protobuf payload converter. A v7 root can decode binary payloads, but Protobuf JSON decoding fails with `TypeError: type must be a Type`. If your package manager leaves `protobufjs` or `long` unresolved, install them using the peer dependency ranges declared by your installed `@temporalio/common`.

- Construct generated messages with `Message.create({...})`.
- Read default-valued fields directly. They can return the default even when the field is missing from `Object.keys()` or an object spread.

### Older SDK import path

If your installed `@temporalio/common` only provides the converter at `@temporalio/common/lib/protobufs`, import it from that path.

## Payload Codec (Encryption)

Encrypt sensitive workflow data.

```typescript
import { PayloadCodec, Payload } from '@temporalio/common';

class EncryptionCodec implements PayloadCodec {
  private readonly encryptionKey: Uint8Array;

  constructor(key: Uint8Array) {
    this.encryptionKey = key;
  }

  async encode(payloads: Payload[]): Promise<Payload[]> {
    return Promise.all(
      payloads.map(async (payload) => ({
        metadata: {
          encoding: 'binary/encrypted',
        },
        data: await this.encrypt(payload.data ?? new Uint8Array()),
      }))
    );
  }

  async decode(payloads: Payload[]): Promise<Payload[]> {
    return Promise.all(
      payloads.map(async (payload) => {
        if (payload.metadata?.encoding === 'binary/encrypted') {
          return {
            ...payload,
            data: await this.decrypt(payload.data ?? new Uint8Array()),
          };
        }
        return payload;
      })
    );
  }

  private async encrypt(data: Uint8Array): Promise<Uint8Array> {
    // Implement encryption (e.g., using Web Crypto API)
    return data;
  }

  private async decrypt(data: Uint8Array): Promise<Uint8Array> {
    // Implement decryption
    return data;
  }
}

// Apply codec
const dataConverter: DataConverter = {
  payloadCodecs: [new EncryptionCodec(encryptionKey)],
};
```

## Workflow Memo

Store arbitrary metadata with workflows (not searchable).

```typescript
// Set memo at workflow start
await client.workflow.start('orderWorkflow', {
  taskQueue: 'orders',
  workflowId: `order-${orderId}`,
  args: [order],
  memo: {
    customerName: order.customerName,
    notes: 'Priority customer',
  },
});

// Read memo from workflow
import { workflowInfo } from '@temporalio/workflow';

export async function orderWorkflow(): Promise<void> {
  const info = workflowInfo();
  const customerName = info.memo?.customerName;
  // ...
}
```

## Best Practices

1. Keep payloads small—see [Temporal common pitfalls](../core/gotchas.md) for limits
2. Encrypt sensitive data with PayloadCodec
3. Use memo for non-searchable metadata
4. Configure the same data converter on both client and worker
