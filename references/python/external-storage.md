# External Storage (Python SDK)

External Storage offloads large payloads to a backend such as Amazon S3, passing
only a small claim-check reference through Event History. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:22-25 -->

> **Pre-Release.** External Storage is in Pre-Release. APIs and configuration
> may change before the stable release. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:14-20 -->

For the cross-SDK concept overview, see
[`references/core/external-storage.md`](../core/external-storage.md). For Codec
Server integration, see
[`references/core/external-storage-codec-server.md`](../core/external-storage-codec-server.md).

## Install the aioboto3 extra

Install the `aioboto3` extra to use the built-in S3 driver: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 -->

```sh
python -m pip install "temporalio[aioboto3]"
```

## Built-in S3 storage driver

The Python SDK ships with `S3StorageDriver`. The driver uses your standard AWS
credentials from the environment (environment variables, IAM role, or AWS
config file). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:31,41-42 -->

### 1. Create the driver

Create an `aioboto3.Session`, open an `s3` client, and wrap it with
`new_aioboto3_client` before passing it to `S3StorageDriver`: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:41-53 -->

```py
session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )
```

### 2. Wire the driver into a Data Converter

Configure the driver on a `DataConverter` via `ExternalStorage`, then pass the
converter to both your Client and Worker: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:56,61-76 -->

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(drivers=[driver]),
)

client_config = ClientConfig.load_client_connect_config()

client = await Client.connect(**client_config, data_converter=data_converter)

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[],
    activities=[],
)
```

All Workflows and Activities running on the Worker use the storage driver
automatically without changes to your business logic. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:83-84 -->

The driver uploads and downloads payloads concurrently and validates payload
integrity on retrieve. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:84-85 -->

## Configure `payload_size_threshold`

By default, payloads larger than 256 KiB are offloaded to external storage.
Adjust the threshold with the `payload_size_threshold` parameter, or set it to
**0** to externalize **all** payloads regardless of size. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:79-81,195-197 -->

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```

> **Cross-SDK note.** In Python, `payload_size_threshold=0` means
> "externalize every payload". This is the **opposite** of the Go SDK, where 0
> means "use the default". Do not transcribe a Go example literally.

## Custom storage driver

If you need a backend that is not provided out of the box, extend the
`StorageDriver` abstract class and implement **three** methods: `name()`,
`store()`, and `retrieve()`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:148-156 -->

- `name()` returns a unique string that identifies the driver. The SDK stores
  this name in the claim-check reference so it can route retrieval requests to
  the correct driver. **Changing the name after payloads have been stored
  breaks retrieval.** <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:152-153 -->
- `store()` receives a list of `Payload` protobuf messages and returns one
  `StorageDriverClaim` per payload. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:154-155 -->
- `retrieve()` receives the claims that `store()` produced and returns the
  original payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:156 -->

Both `store()` and `retrieve()` are `async def`.

### Skeleton

```py
class LocalDiskStorageDriver(StorageDriver):
    def name(self) -> str:
        return "local-disk"

    async def store(
        self,
        context: StorageDriverStoreContext,
        payloads: Sequence[Payload],
    ) -> list[StorageDriverClaim]:
        claims = []
        for payload in payloads:
            # Serialize the protobuf Payload to bytes before persisting.
            raw = payload.SerializeToString()
            key = self._write(raw, context)
            claims.append(StorageDriverClaim(claim_data={"path": key}))
        return claims

    async def retrieve(
        self,
        context: StorageDriverRetrieveContext,
        claims: Sequence[StorageDriverClaim],
    ) -> list[Payload]:
        payloads = []
        for claim in claims:
            raw = self._read(claim.claim_data["path"])
            payload = Payload()
            payload.ParseFromString(raw)
            payloads.append(payload)
        return payloads
```

<!-- Signatures and serialization patterns: docs/develop/python/best-practices/data-handling/external-storage.mdx:105-109,123-124,127-131,134,138,160-162,172-173 -->

### Payload serialization

The application data has already been processed by the Payload Converter and
Payload Codec before it reaches your driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:161-162 -->

- In `store()`: serialize each `Payload` to bytes with
  `payload.SerializeToString()`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:160-161 -->
- In `retrieve()`: reconstruct each `Payload` with
  `Payload()` plus `payload.ParseFromString(data)`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:172-173 -->

### Identity from `context.target`

`context.target` provides identity information for the operation. When it is a
`StorageDriverWorkflowInfo`, you can read `namespace` and `id` (the Workflow
ID): <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:113-115,165-167 -->

```py
target = context.target
if isinstance(target, StorageDriverWorkflowInfo) and target.id:
    prefix = os.path.join(self._store_dir, target.namespace, target.id)
```

Structuring your storage keys around this identity makes it easy to find
which Workflow owns each payload. Within that scope, content-addressable keys
(such as a SHA-256 hash of the payload bytes) can help deduplicate identical
payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:166-168 -->

### Claims

A `StorageDriverClaim` is constructed with the keyword `claim_data`, a set of
string key-value pairs the driver uses to locate the payload later: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:124,134,154-155 -->

```py
StorageDriverClaim(claim_data={"path": file_path})
```

Read those values back in `retrieve()` via `claim.claim_data[...]`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:134 -->

### Register the custom driver

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```

<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:184-189 -->

You can also package your driver as a plugin for easier reuse across
services. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:178-179 -->

## Multiple drivers and migration

Register multiple drivers when you need to migrate between storage backends or
route payloads based on environment. When more than one driver is registered,
you must provide a `driver_selector` function that chooses which driver stores
each payload. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:213-216 -->

- Return `None` from the selector to keep a specific payload inline in Event
  History. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:216 -->
- **Any driver in the list that is not selected for storing is still
  available for retrieval.** This is what makes safe driver migration
  possible. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:214-215 -->

```py
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```

<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:233-239 -->

Use cases include driver migration (always pick the preferred driver for new
payloads while keeping the old driver registered for retrieval) and
multi-cloud routing (for example, S3 on AWS and GCS on GCP). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:220-225 -->

## Common pitfalls

- **Don't rename a driver.** `name()` is the key used to route retrievals;
  changing it breaks access to already-stored payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:152-153 -->
- **`payload_size_threshold=0` externalizes everything** in Python. This is
  the opposite of Go. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:79-80,196-197 -->
- **Return `None`, not `nil`,** from `driver_selector` to keep a payload
  inline. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:216 -->
- **There is no `type()` method** on the Python `StorageDriver` abstract
  class. The three methods are `name()`, `store()`, and `retrieve()`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:148-156 -->
- **Always pass the same `data_converter`** to both `Client.connect()` and
  the `Worker` so retrieval works on both sides. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:56,68-75 -->

## See also

- [`references/core/external-storage.md`](../core/external-storage.md) -
  cross-SDK concept overview, lifecycle, and data-pipeline details.
- [`references/core/external-storage-codec-server.md`](../core/external-storage-codec-server.md) -
  decoding externalized payloads in the Web UI and CLI.
