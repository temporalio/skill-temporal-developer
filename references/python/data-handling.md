# Python SDK Data Handling

## Overview

The Python SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters.

## Default Data Converter

The default converter handles:
- `None`
- `bytes` (as binary)
- Protobuf messages
- JSON-serializable types (dict, list, str, int, float, bool)

## Pydantic Integration

Use Pydantic models for validated, typed data.

```python
from pydantic import BaseModel
from temporalio.contrib.pydantic import pydantic_data_converter

class OrderInput(BaseModel):
    order_id: str
    items: list[str]
    total: float
    customer_email: str

class OrderResult(BaseModel):
    order_id: str
    status: str
    tracking_number: str | None = None

@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, input: OrderInput) -> OrderResult:
        # Pydantic validation happens automatically
        return OrderResult(
            order_id=input.order_id,
            status="completed",
            tracking_number="TRK123",
        )

# Configure client with Pydantic support
client = await Client.connect(
    "localhost:7233",
    data_converter=pydantic_data_converter,
)
```

## Custom Data Converter

Create custom converters for special serialization needs.

```python
from temporalio.converter import (
    DataConverter,
    PayloadConverter,
    DefaultPayloadConverter,
)

class CustomPayloadConverter(PayloadConverter):
    # Implement encoding_payload_converters and decoding_payload_converters
    pass

custom_converter = DataConverter(
    payload_converter_class=CustomPayloadConverter,
)

client = await Client.connect(
    "localhost:7233",
    data_converter=custom_converter,
)
```

## Payload Encryption

Encrypt sensitive workflow data.

```python
from temporalio.converter import PayloadCodec
from temporalio.api.common.v1 import Payload
from cryptography.fernet import Fernet
from typing import Sequence

class EncryptionCodec(PayloadCodec):
    def __init__(self, key: bytes):
        self._fernet = Fernet(key)

    async def encode(self, payloads: Sequence[Payload]) -> list[Payload]:
        return [
            Payload(
                metadata={"encoding": b"binary/encrypted"},
                data=self._fernet.encrypt(p.SerializeToString()),
            )
            for p in payloads
        ]

    async def decode(self, payloads: Sequence[Payload]) -> list[Payload]:
        result = []
        for p in payloads:
            if p.metadata.get("encoding") == b"binary/encrypted":
                decrypted = self._fernet.decrypt(p.data)
                decoded = Payload()
                decoded.ParseFromString(decrypted)
                result.append(decoded)
            else:
                result.append(p)
        return result

# Apply encryption codec
client = await Client.connect(
    "localhost:7233",
    data_converter=DataConverter(
        payload_codec=EncryptionCodec(encryption_key),
    ),
)
```

## Search Attributes

Custom searchable fields for workflow visibility.

```python
from temporalio.common import SearchAttributes, SearchAttributeKey

# Define typed keys
ORDER_ID = SearchAttributeKey.for_keyword("OrderId")
ORDER_STATUS = SearchAttributeKey.for_keyword("OrderStatus")
ORDER_TOTAL = SearchAttributeKey.for_float("OrderTotal")
CREATED_AT = SearchAttributeKey.for_datetime("CreatedAt")

# Set at workflow start
await client.execute_workflow(
    OrderWorkflow.run,
    order,
    id=f"order-{order.id}",
    task_queue="orders",
    search_attributes=SearchAttributes.from_pairs([
        (ORDER_ID, order.id),
        (ORDER_STATUS, "pending"),
        (ORDER_TOTAL, order.total),
        (CREATED_AT, datetime.now(timezone.utc)),
    ]),
)

# Upsert from within workflow
workflow.upsert_search_attributes([
    (ORDER_STATUS, "completed"),
])
```

## Workflow Memo

Store arbitrary metadata with workflows (not searchable).

```python
# Set memo at workflow start
await client.execute_workflow(
    OrderWorkflow.run,
    order,
    id=f"order-{order.id}",
    task_queue="orders",
    memo={
        "customer_name": order.customer_name,
        "notes": "Priority customer",
    },
)

# Read memo from workflow
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        memo = workflow.memo()
        notes = memo.get("notes", "")
        ...
```

## Large Payloads

For large data, consider:

1. **Store externally**: Put large data in S3/GCS, pass references in workflows
2. **Use Payload Codec**: Compress payloads automatically
3. **Chunk data**: Split large lists across multiple activities

```python
# Example: Reference pattern for large data
@activity.defn
async def upload_to_storage(data: bytes) -> str:
    """Upload data and return reference."""
    key = f"data/{uuid.uuid4()}"
    await storage_client.upload(key, data)
    return key

@activity.defn
async def download_from_storage(key: str) -> bytes:
    """Download data by reference."""
    return await storage_client.download(key)
```

## Deterministic APIs for Values

Use these APIs within workflows for deterministic random values and UUIDs:

```python
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        # Deterministic UUID (same on replay)
        unique_id = workflow.uuid4()

        # Deterministic random (same on replay)
        rng = workflow.random()
        value = rng.randint(1, 100)

        return str(unique_id)
```

## Best Practices

1. Use Pydantic for input/output validation
2. Keep payloads small (< 2MB recommended)
3. Encrypt sensitive data with PayloadCodec
4. Store large data externally with references
5. Use dataclasses for simple data structures
6. Use `workflow.uuid4()` and `workflow.random()` for deterministic values
