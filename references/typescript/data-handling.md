# TypeScript SDK Data Handling

## Overview

The TypeScript SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters.

## Default Data Converter

The default converter handles:
- `undefined` and `null`
- `Uint8Array` (as binary)
- Protobuf messages (if configured)
- JSON-serializable types

## Search Attributes

Custom searchable fields for workflow visibility.

### Setting Search Attributes at Start

```typescript
import { Client } from '@temporalio/client';

const client = new Client();

await client.workflow.start('orderWorkflow', {
  taskQueue: 'orders',
  workflowId: `order-${orderId}`,
  args: [order],
  searchAttributes: {
    OrderId: [orderId],
    CustomerType: ['premium'],
    OrderTotal: [99.99],
    CreatedAt: [new Date()],
  },
});
```

### Upserting Search Attributes from Workflow

```typescript
import { upsertSearchAttributes, workflowInfo } from '@temporalio/workflow';

export async function orderWorkflow(order: Order): Promise<string> {
  // Update status as workflow progresses
  upsertSearchAttributes({
    OrderStatus: ['processing'],
  });

  await processOrder(order);

  upsertSearchAttributes({
    OrderStatus: ['completed'],
  });

  return 'done';
}
```

### Reading Search Attributes

```typescript
import { workflowInfo } from '@temporalio/workflow';

export async function orderWorkflow(): Promise<void> {
  const info = workflowInfo();
  const searchAttrs = info.searchAttributes;
  const orderId = searchAttrs?.OrderId?.[0];
  // ...
}
```

### Querying Workflows by Search Attributes

```typescript
const client = new Client();

// List workflows using search attributes
for await (const workflow of client.workflow.list({
  query: 'OrderStatus = "processing" AND CustomerType = "premium"',
})) {
  console.log(`Workflow ${workflow.workflowId} is still processing`);
}
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

## Custom Data Converter

Create custom converters for special serialization needs.

```typescript
import {
  DataConverter,
  PayloadConverter,
  defaultPayloadConverter,
} from '@temporalio/common';

class CustomPayloadConverter implements PayloadConverter {
  toPayload(value: unknown): Payload | undefined {
    // Custom serialization logic
    return defaultPayloadConverter.toPayload(value);
  }

  fromPayload<T>(payload: Payload): T {
    // Custom deserialization logic
    return defaultPayloadConverter.fromPayload(payload);
  }
}

const dataConverter: DataConverter = {
  payloadConverter: new CustomPayloadConverter(),
};

// Apply to client
const client = new Client({
  dataConverter,
});

// Apply to worker
const worker = await Worker.create({
  dataConverter,
  // ...
});
```

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
  payloadCodec: new EncryptionCodec(encryptionKey),
};
```

## Protobuf Support

Using Protocol Buffers for type-safe serialization.

```typescript
import { DefaultPayloadConverterWithProtobufs } from '@temporalio/common/lib/protobufs';

const dataConverter: DataConverter = {
  payloadConverter: new DefaultPayloadConverterWithProtobufs({
    protobufRoot: myProtobufRoot,
  }),
};
```

## Large Payloads

For large data, consider:

1. **Store externally**: Put large data in S3/GCS, pass references in workflows
2. **Use compression codec**: Compress payloads automatically
3. **Chunk data**: Split large arrays across multiple activities

```typescript
// Example: Reference pattern for large data
import { proxyActivities } from '@temporalio/workflow';

const { uploadToStorage, downloadFromStorage } = proxyActivities<Activities>({
  startToCloseTimeout: '5 minutes',
});

export async function processLargeDataWorkflow(dataRef: string): Promise<void> {
  // Download data from storage using reference
  const data = await downloadFromStorage(dataRef);

  // Process data...
  const result = await processData(data);

  // Upload result and return reference
  const resultRef = await uploadToStorage(result);
}
```

## Best Practices

1. Keep payloads small (< 2MB recommended)
2. Use search attributes for business-level visibility and filtering
3. Encrypt sensitive data with PayloadCodec
4. Store large data externally with references
5. Use memo for non-searchable metadata
6. Configure the same data converter on both client and worker
