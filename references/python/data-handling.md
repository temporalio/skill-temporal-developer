# Python SDK Data Handling

## Overview

The Python SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters. Data conversion happens in three layers — PayloadConverter, PayloadCodec, and ExternalStorage; see `## External Storage` below for offloading large payloads.

## Default Data Converter

The default converter handles:

- `None`
- `bytes` (as binary)
- Protobuf messages
- JSON-serializable types (dict, list, str, int, float, bool)

## Pydantic Integration

Use Pydantic models for validated, typed data.

In your workflow definition, just use input and result types that subclass `pydantic.BaseModel`:

```python
from pydantic import BaseModel

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
```

And when you configure the client, pass the `pydantic_data_converter`:

```python
from temporalio.contrib.pydantic import pydantic_data_converter
# Configure client with Pydantic support
client = await Client.connect(
    "localhost:7233",
    namespace="default",
    data_converter=pydantic_data_converter,
)
```

## Custom Data Conversion

Usually the easiest way to do this is via implementing an EncodingPayloadConverter and CompositePayloadConverter. See:

- https://raw.githubusercontent.com/temporalio/samples-python/refs/heads/main/custom_converter/shared.py
- https://raw.githubusercontent.com/temporalio/samples-python/refs/heads/main/custom_converter/starter.py

for an extended example.

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
                # Since encryption uses C extensions that give up the GIL, we can avoid blocking the async event loop here.
                data=await asyncio.to_thread(self._fernet.encrypt, p.SerializeToString()),
            )
            for p in payloads
        ]

    async def decode(self, payloads: Sequence[Payload]) -> list[Payload]:
        result = []
        for p in payloads:
            if p.metadata.get("encoding") == b"binary/encrypted":
                decrypted = await asyncio.to_thread(self._fernet.decrypt, p.data)
                decoded = Payload()
                decoded.ParseFromString(decrypted)
                result.append(decoded)
            else:
                result.append(p)
        return result

# Apply encryption codec
client = await Client.connect(
    "localhost:7233",
    namespace="default",
    data_converter=DataConverter(
        payload_codec=EncryptionCodec(encryption_key),
    ),
)
```

## External Storage

> **Pre-Release.** External Storage is in Pre-Release; APIs and configuration may change before the stable release.

External Storage implements the claim check pattern: payloads larger than a configured threshold are uploaded to an external store (such as Amazon S3) and a small reference token is written to the Event History in their place.

External Storage sits at the end of the Data Converter pipeline, after both the PayloadConverter and the PayloadCodec. The SDK uploads and downloads referenced payloads concurrently when a single Task carries multiple large payloads.

### Configure the built-in S3 storage driver

Install the `aioboto3` extra:

```python
python -m pip install "temporalio[aioboto3]"
```

Create an `S3StorageDriver` from an `aioboto3` S3 client, then wire it into a `DataConverter` and pass that converter to your Client (and Worker):

```python
# (See temporalio SDK docs for canonical import paths for S3StorageDriver,
# new_aioboto3_client, DataConverter, ExternalStorage, and StorageDriver-related types.)
import dataclasses
import aioboto3
from temporalio.client import Client

session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )

    data_converter = dataclasses.replace(
        DataConverter.default,
        external_storage=ExternalStorage(drivers=[driver]),
    )

    client = await Client.connect(
        "localhost:7233",
        namespace="default",
        data_converter=data_converter,
    )
```

All Workflows and Activities on a Worker that uses this converter offload payloads automatically; no business-logic changes are required.

### Configure the payload size threshold

By default, payloads larger than 256 KiB are offloaded. Set `payload_size_threshold` to adjust the cutoff, or set it to `0` to externalize all payloads regardless of size.

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```

### Implement a custom storage driver

Extend `StorageDriver` and implement exactly three abstract methods:

- `name()` — returns a unique driver identifier; the SDK stores this in the claim reference so retrievals route to the right driver. Changing it after payloads have been stored breaks retrieval.

- `store()` — receives a list of `Payload` protobuf messages and returns one `StorageDriverClaim` per payload (a set of string key-value pairs the driver uses to locate the payload later).

- `retrieve()` — receives those claims and returns the original `Payload` list.

In `store()`, serialize each payload with `Payload.SerializeToString()`; in `retrieve()`, reconstruct it with `Payload.ParseFromString()`. The `context.target` provides identity info — use `isinstance(context.target, StorageDriverWorkflowInfo)` to read `.namespace` and `.id` when structuring storage keys.

```python
import os, uuid
from typing import Sequence
from temporalio.api.common.v1 import Payload

class LocalDiskStorageDriver(StorageDriver):
    def __init__(self, store_dir: str = "/tmp/temporal-payload-store") -> None:
        self._store_dir = store_dir

    def name(self) -> str:
        return "local-disk"

    async def store(
        self,
        context: StorageDriverStoreContext,
        payloads: Sequence[Payload],
    ) -> list[StorageDriverClaim]:
        prefix = self._store_dir
        target = context.target
        if isinstance(target, StorageDriverWorkflowInfo) and target.id:
            prefix = os.path.join(self._store_dir, target.namespace, target.id)
        os.makedirs(prefix, exist_ok=True)
        claims = []
        for payload in payloads:
            file_path = os.path.join(prefix, f"{uuid.uuid4()}.bin")
            with open(file_path, "wb") as f:
                f.write(payload.SerializeToString())
            claims.append(StorageDriverClaim(claim_data={"path": file_path}))
        return claims

    async def retrieve(
        self,
        context: StorageDriverRetrieveContext,
        claims: Sequence[StorageDriverClaim],
    ) -> list[Payload]:
        out = []
        for claim in claims:
            with open(claim.claim_data["path"], "rb") as f:
                p = Payload()
                p.ParseFromString(f.read())
                out.append(p)
        return out
```

Local disk is shown for clarity; use a durable, Worker-accessible store in production.

### Use multiple storage drivers (driver migration)

Register multiple drivers when you need driver migration (clients wrote with an old driver, but you want new payloads to use a new one) or multi-cloud routing (different backends per cloud environment). Any registered driver remains available for retrieval; only storage is selected.

A `driver_selector` callable is **required** when more than one driver is registered. It receives the context and the payload and returns a `StorageDriver`, or `None` to keep that payload inline in Event History.

```python
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```

### Codec Server with External Storage

Because External Storage runs after the Payload Codec, payloads produced by an encryption codec are already encrypted before they are uploaded to your store.

A Codec Server fronting External Storage exposes storage-aware `/encode`, `/decode`, and `/download` endpoints. The Web UI and CLI use `/download` to fetch the payload behind a reference; `/decode` can be called with `?preserveStorageRefs=true` to return references as-is rather than fetching them.

The full handler protocol (including helper APIs documented on the Go side) is described in `docs/encyclopedia/data-conversion/codec-server.mdx#external-storage`. For a Python codec server example, see `https://github.com/temporalio/samples-python/blob/main/encryption/codec_server.py`.

### Lifecycle management

Temporal does not delete payloads from your external store. Configure a lifecycle policy on the store itself, with a TTL satisfying:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

For example, a longest Run Timeout of 14 days plus a Namespace retention period of 30 days means objects should expire after at least 44 days.

For Workflows with no Run Timeout (indefinite runs), there is no finite TTL that guarantees safety; set a generous TTL based on operational needs and use Continue-as-New so each run's payloads only need to survive that run's retention window.

## Search Attributes

Custom searchable fields for workflow visibility. These can be created at workflow start:

```python
from temporalio.common import (
    SearchAttributeKey,
    SearchAttributePair,
    TypedSearchAttributes,
)
from datetime import datetime
from datetime import timezone

ORDER_ID = SearchAttributeKey.for_keyword("OrderId")
ORDER_STATUS = SearchAttributeKey.for_keyword("OrderStatus")
ORDER_TOTAL = SearchAttributeKey.for_float("OrderTotal")
CREATED_AT = SearchAttributeKey.for_datetime("CreatedAt")

# At workflow start
handle = await client.start_workflow(
    OrderWorkflow.run,
    order,
    id=f"order-{order.id}",
    task_queue="orders",
    search_attributes=TypedSearchAttributes([
        SearchAttributePair(ORDER_ID, order.id),
        SearchAttributePair(ORDER_STATUS, "pending"),
        SearchAttributePair(ORDER_TOTAL, order.total),
        SearchAttributePair(CREATED_AT, datetime.now(timezone.utc)),
    ]),
)
```

Or upserted during workflow execution:

```python
from temporalio import workflow
from temporalio.common import SearchAttributeKey, SearchAttributePair, TypedSearchAttributes

ORDER_STATUS = SearchAttributeKey.for_keyword("OrderStatus")

@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        # ... process order ...

        # Update search attribute
        workflow.upsert_search_attributes(TypedSearchAttributes([
            SearchAttributePair(ORDER_STATUS, "completed"),
        ]))
        return "done"
```

### Querying Workflows by Search Attributes

```python
# List workflows using search attributes
async for workflow in client.list_workflows(
    'OrderStatus = "processing" OR OrderStatus = "pending"'
):
    print(f"Workflow {workflow.id} is still processing")
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
```

```python
# Read memo from workflow
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        notes: str = workflow.memo_value("notes", type_hint=str)
        ...
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
2. Keep payloads small—see `references/core/gotchas.md` for limits
3. Encrypt sensitive data with PayloadCodec
4. Use dataclasses for simple data structures
5. Use `workflow.uuid4()` and `workflow.random()` for deterministic values
6. When payloads risk approaching the 2 MB per-payload limit, offload them via External Storage (see `## External Storage` above) instead of restructuring Workflows around the limit

7. Configure a lifecycle policy on your external store with `TTL > Maximum Workflow Run Timeout + Namespace Retention Period`

