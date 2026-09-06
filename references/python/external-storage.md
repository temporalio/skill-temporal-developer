# Python SDK External Storage

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## What this is

External Storage uses the **claim check pattern**: it offloads each Payload to an external store (e.g. Amazon S3), records a small reference token (the "claim check") in Event History, and uses that token to retrieve the Payload when needed. The SDK handles storage and retrieval transparently.

## When to use it

- A Workflow input, Activity input, Activity result, or Workflow result will exceed the **2 MB** per-payload limit (fixed at 2 MB on Temporal Cloud; configurable on self-hosted only).
- Long Event Histories degrade Workflow Task latency (e.g. AI agent conversations growing per turn).
- The user wants payload data to live in storage **they** control. Set `payload_size_threshold=0` to externalize all payloads.
- The user is migrating from self-hosted (with a larger configured limit) to Temporal Cloud.

## Where it sits in the pipeline

Order: **Payload Converter → Payload Codec → External Storage**. Storage runs last on outbound; it reverses on inbound.

Consequences:

- If a Payload Codec encrypts data, the bytes are already encrypted **before** upload.
- The Temporal UI displays the reference token, not the data; the SDK retrieves the payload transparently before handing it to your Workflow or Client.
- Every Client and Worker that might read an offloaded payload needs the same External Storage configuration.

## Setup with the built-in S3 driver

The Python SDK ships an Amazon S3 driver (there is no built-in GCS driver — use a custom driver for other backends). Install the `aioboto3` extra:

```bash
python -m pip install "temporalio[aioboto3]"
```

Create the driver, attach it to a `DataConverter`, and pass the converter to `Client.connect`. A Worker inherits the Data Converter from the Client it is created with — `Worker` takes no `data_converter` argument of its own:

```python
import asyncio
import dataclasses

import aioboto3
from temporalio.client import Client
from temporalio.contrib.aws.s3driver import S3StorageDriver
from temporalio.contrib.aws.s3driver.aioboto3 import new_aioboto3_client
from temporalio.converter import DataConverter, ExternalStorage
from temporalio.envconfig import ClientConfig
from temporalio.worker import Worker

from activities.greet import greet
from workflows.greeting import GreetingWorkflow


async def main() -> None:
    session = aioboto3.Session(region_name="us-east-2")
    async with session.client("s3") as s3_client:
        driver = S3StorageDriver(
            client=new_aioboto3_client(s3_client),
            bucket="my-temporal-payloads",
        )

        data_converter = dataclasses.replace(
            DataConverter.default,
            external_storage=ExternalStorage(drivers=[driver]),
        )

        connect_config = ClientConfig.load_client_connect_config()
        connect_config.setdefault("target_host", "localhost:7233")
        client = await Client.connect(**connect_config, data_converter=data_converter)

        worker = Worker(
            client,
            task_queue="my-task-queue",
            workflows=[GreetingWorkflow],
            activities=[greet],
        )
        await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
```

`ClientConfig` for connection settings comes from `temporalio.envconfig`, not `temporalio.client`. The S3 driver uses standard AWS credentials from the environment (env vars, IAM role, or AWS config file); pass `profile_name=` to `aioboto3.Session` to select a named profile. Keep the `async with session.client("s3")` block open for as long as the Worker runs — the driver uses that client for every upload and download.

Workflows and Activities on the Worker use the driver automatically — no business-logic changes.

## Built-in driver behavior

The S3 driver:

- Uploads and downloads payloads **concurrently**. Multiple offloaded payloads in a single Workflow Task are stored or retrieved in parallel, not sequentially.
- Addresses objects by a SHA-256 hash of their contents, segmented by Namespace and Workflow/Activity identifiers, and validates payload integrity on retrieval.
- Rejects any single payload larger than `max_payload_size`, which defaults to **50 MiB**. `payload_size_threshold` does not raise this ceiling — set `max_payload_size` for the largest payload the application must support, and size the backing store to match.
- Includes diagnostic metadata, such as the AWS region, in error messages.

## Payload size threshold

- Default: **256 KiB**.
- Set `payload_size_threshold=0` to externalize **all** payloads regardless of size.
- Payloads whose serialized size is **greater than or equal to** the threshold are eligible; smaller ones stay inline. The measured size includes Payload metadata, not just your data.

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```

## Multiple drivers and migration

When you register more than one driver, you **must** supply a `driver_selector` function. The selector chooses which driver stores each payload. Unselected drivers remain available for **retrieval** — this is how you migrate between storage backends without losing access to existing claims.

- Return `None` from the selector to keep a specific payload inline in Event History.
- Every registered driver must have a distinct name; duplicates raise `ValueError` at construction. `S3StorageDriver` defaults its name to `"aws.s3driver"`, so registering two S3 drivers requires passing `driver_name=` to at least one.

```python
preferred_driver = S3StorageDriver(
    client=new_aioboto3_client(s3_client),
    bucket="my-bucket",
    driver_name="s3-primary",
)
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```

Useful routing patterns include driver migration, hot/cold storage tiers, and per-tenant storage.

## Custom storage driver

Extend `StorageDriver` and implement **three** methods:

- `name() -> str` — unique identifier for the driver, stored in the claim reference so the SDK can route retrieval. Renaming after payloads are stored **breaks retrieval**.
- `async store(context, payloads) -> list[StorageDriverClaim]` — upload each Payload and return one claim per payload, in the same order. A claim is a `dict[str, str]` the driver uses to locate the payload later.
- `async retrieve(context, claims) -> list[Payload]` — download bytes using claim data and reconstruct each Payload, one per claim, in the same order.

`type() -> str` is optional and defaults to the class name. Override it with a stable identifier shared by every instance of the implementation (e.g. `"aws.s3driver"`) so the driver reports the same type as its equivalents in other languages.

Inside `store()`, serialize each payload with `payload.SerializeToString()`; in `retrieve()`, reconstruct with `payload.ParseFromString(data)`. The application data has already been serialized by the Payload Converter and Payload Codec before reaching the driver.

`context.target` provides identity information (namespace, Workflow ID, or Activity ID). Check the target type with `isinstance(target, StorageDriverWorkflowInfo)`; the Workflow info exposes `target.namespace` and `target.id`. Use this to scope storage keys per Workflow, but hash or encode identifiers before using them as path segments because identifiers can contain path separators or traversal sequences. Within that scope, content-addressable keys (such as a SHA-256 hash of the payload bytes) deduplicate identical payloads and make retries idempotent.

Treat claim data in `retrieve()` as untrusted input. A driver that resolves a filesystem path, object key, or URL straight out of the claim will follow whatever a hand-crafted reference payload puts there, so re-check that the resolved location stays inside the store the driver owns.

Worked example — local-disk driver (development/testing only):

```python
import hashlib
import os
from typing import Sequence

from temporalio.api.common.v1 import Payload
from temporalio.converter import (
    StorageDriver,
    StorageDriverClaim,
    StorageDriverRetrieveContext,
    StorageDriverStoreContext,
    StorageDriverWorkflowInfo,
)


def safe_path_segment(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class LocalDiskStorageDriver(StorageDriver):
    def __init__(self, store_dir: str = "/tmp/temporal-payload-store") -> None:
        self._store_dir = store_dir

    def _resolve_path(self, claim_path: str) -> str:
        """Reject claim data that points outside the store directory."""
        root = os.path.realpath(self._store_dir)
        resolved = os.path.realpath(claim_path)
        if resolved != root and not resolved.startswith(root + os.sep):
            raise ValueError(f"claim path {claim_path!r} escapes the store directory")
        return resolved

    def name(self) -> str:
        return "local-disk"

    def type(self) -> str:
        return "local-disk"

    async def store(
        self,
        context: StorageDriverStoreContext,
        payloads: Sequence[Payload],
    ) -> list[StorageDriverClaim]:
        os.makedirs(self._store_dir, exist_ok=True)

        prefix = self._store_dir
        target = context.target
        if isinstance(target, StorageDriverWorkflowInfo) and target.id:
            prefix = os.path.join(
                self._store_dir,
                safe_path_segment(target.namespace),
                safe_path_segment(target.id),
            )
            os.makedirs(prefix, exist_ok=True)

        claims = []
        for payload in payloads:
            data = payload.SerializeToString()
            key = f"{hashlib.sha256(data).hexdigest()}.bin"
            file_path = os.path.join(prefix, key)
            with open(file_path, "wb") as f:
                f.write(data)
            claims.append(StorageDriverClaim(claim_data={"path": file_path}))
        return claims

    async def retrieve(
        self,
        context: StorageDriverRetrieveContext,
        claims: Sequence[StorageDriverClaim],
    ) -> list[Payload]:
        payloads = []
        for claim in claims:
            file_path = self._resolve_path(claim.claim_data["path"])
            with open(file_path, "rb") as f:
                raw = f.read()
            payload = Payload()
            payload.ParseFromString(raw)
            payloads.append(payload)
        return payloads
```

Wire the custom driver into the Data Converter the same way as the S3 driver:

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```

You can package a custom driver as a [plugin](https://docs.temporal.io/develop/plugins-guide) for reuse across services.

## Multi-region durability with Amazon S3

For regional-failure tolerance, configure S3 Cross-Region Replication (CRR) and an S3 Multi-Region Access Point (MRAP), then pass the MRAP ARN as `bucket`:

```python
driver = S3StorageDriver(
    client=new_aioboto3_client(s3_client),
    bucket="arn:aws:s3::123456789012:accesspoint/mfzwi23gnjvgw.mrap",
)
```

`aioboto3` (via `botocore`) uses SigV4A signing automatically when the bucket value is an MRAP ARN. Make sure `botocore` is recent enough to support SigV4A.

Cross-region replication is eventually consistent. Activities reading newly written payloads from another region need an appropriate Retry Policy. Replication, versioning, and Replication Time Control can add significant cost.

## Codec Server with External Storage

When Workers and Clients use External Storage, Event History contains reference tokens — not payload data. For the Web UI and CLI to show decoded payloads, the Codec Server must download from external storage **and** decode through the Payload Codec in the correct order.

The Python SDK does not ship a storage-aware Codec Server handler — implement the routes yourself (e.g. with `aiohttp`), giving them your storage drivers, your pre-storage codecs (the Payload Codecs your Workers use), and any post-storage codecs (applied by a proxy after external storage). The [Python External Storage sample](https://github.com/temporalio/samples-python/tree/main/external_storage) has a working implementation (`payload_routes` in `handler.py`) to copy from.

Endpoints to expose when storage drivers are configured:

- **`/download`** — retrieves payload data from external storage and decodes it through the Payload Codec. The Web UI calls this when a user clicks to view the full payload behind a reference.
- **`/decode`** — decodes encoded payloads and, by default, retrieves storage references inline. Support `?preserveStorageRefs=true` to return storage references as-is without retrieval; the Web UI uses it to render history without downloading every blob.
- **`/encode`** — applies the Payload Codec, then uploads payloads exceeding the threshold and replaces them with reference tokens.

**Don't point a Worker's remote codec at the storage-aware handler** — it runs the full encode-store-encode and decode-retrieve-decode pipeline. Run a separate non-storage codec HTTP handler for remote codecs, configured with the same codecs.

## Lifecycle and failure handling

Temporal does **not** auto-delete payloads from your store. Configure a TTL on your bucket:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

Example: Run Timeout 14 days + Namespace retention 30 days → set TTL to at least 44 days.

For Workflows with no finite Run Timeout, there is no safe finite TTL. Use Continue-as-New so the new run uploads fresh payloads and the old run's payloads only need to survive its retention period.

The SDK does not retry a failed `store()` or `retrieve()` call within the same Task attempt. The failure fails the current Workflow Task or Activity Task attempt; Temporal then retries the Task as a whole, and the new attempt retries the storage operation along with it. For Activities, the Retry Policy controls the timing. Storage operations should therefore be idempotent — content-addressable keys are one way to get that.

## Anti-patterns

- **Don't change the value returned by `name()` after payloads have been stored.** The name is embedded in the claim reference; renaming breaks retrieval of existing claims.
- **Don't use `payload_size_threshold=1` to mean "externalize all"** — use `payload_size_threshold=0`. (This sentinel differs from Go, where `0` is the default and `1` externalizes all.)
- **Don't register multiple drivers without a `driver_selector`.** The selector is required when there is more than one driver.
- **Don't register duplicate driver names.** Two `S3StorageDriver` instances share a default name; pass `driver_name=` to at least one.
- **Don't omit External Storage configuration from a Client or Worker that may retrieve offloaded data.** It cannot resolve the reference without the matching driver.
- **Don't assume the 2 MB Temporal limit is the driver's maximum.** The S3 driver rejects payloads above `max_payload_size`, which defaults to 50 MiB.
- **Don't import `ClientConfig` from `temporalio.client` for connection settings.** `load_client_connect_config()` lives on `temporalio.envconfig.ClientConfig`.
- **Don't pass the storage-aware payload HTTP handler as a Worker's remote codec target.** Use a separate non-storage codec HTTP handler for that role.
- **Don't omit a TTL on the bucket.** Payloads can be orphaned if a request fails after upload.
