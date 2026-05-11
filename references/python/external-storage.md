# Python SDK External Storage

This page covers Python SDK specifics for offloading large payloads to external storage. For conceptual background (claim check pattern, lifecycle/TTL, 2 MB Cloud limit), see `references/core/external-storage.md`. For Go-specific implementation details, see `references/go/external-storage.md`.

## Pre-Release banner

External Storage is in Pre-Release. APIs and configuration may change before the stable release. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:14-20 -->

The Temporal Service enforces a 2 MB per-payload limit by default; this limit is configurable on self-hosted deployments only (fixed at 2 MB on Cloud). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:22-23 -->

## Prerequisites

- An Amazon S3 bucket with read and write access. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:35-36 -->
- Install the `aioboto3` extra (verbatim): <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 -->

  ```sh
  python -m pip install "temporalio[aioboto3]"
  ```

Amazon S3 is the only built-in driver documented for the Python SDK. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:31 -->

## Set up Amazon S3 storage

### Create the S3 driver

Create an `aioboto3.Session`, get an S3 client via `session.client("s3")`, wrap the client with `new_aioboto3_client`, then pass it to `S3StorageDriver` along with the bucket name. The driver uses standard AWS credentials from the environment (environment variables, IAM role, or AWS config file). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:41-43 -->

<!-- SNIPSTART python-s3-driver-create -- docs/develop/python/best-practices/data-handling/external-storage.mdx:44-54 -->
```py
session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )
```

### Wire the driver into the Data Converter, Client, and Worker

Use `dataclasses.replace(DataConverter.default, external_storage=ExternalStorage(drivers=[driver]))` to attach the driver, then pass `data_converter=...` to `Client.connect` and use the same client on the `Worker`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:56-57 -->

<!-- SNIPSTART python-s3-external-storage-setup -- docs/develop/python/best-practices/data-handling/external-storage.mdx:58-77 -->
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

All Workflows and Activities running on the Worker use the storage driver automatically without changes to your business logic. The driver uploads and downloads payloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:83-84 -->

## Configure the payload size threshold

By default, payloads larger than 256 KiB are offloaded to external storage. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:195-196 -->

Adjust this with the `payload_size_threshold` parameter on `ExternalStorage`. Setting `payload_size_threshold=0` externalizes **ALL** payloads regardless of size. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:196-197 -->

<!-- SNIPSTART python-external-storage-threshold -- docs/develop/python/best-practices/data-handling/external-storage.mdx:199-210 -->
```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```

## Implement a custom storage driver

If you need a storage backend other than the built-in driver, implement your own. Store payloads durably so they survive process crashes and remain available for debugging and auditing after the Workflow completes. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:88-90 -->

### Extend the StorageDriver class

A custom driver extends the `StorageDriver` abstract class and implements **three** methods: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:148-156 -->

- `name()` returns a unique string identifying the driver. The SDK stores this name in the claim check reference so it can route retrieval requests to the correct driver. Changing the name after payloads have been stored breaks retrieval. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:152-153 -->
- `store()` receives a list of payloads and returns one `StorageDriverClaim` per payload. A claim is a set of string key-value pairs the driver uses to locate the payload later. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:154-155 -->
- `retrieve()` receives the claims that `store()` produced and returns the original payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:156 -->

### The target attribute and identity information

Inside `store()`, `context.target` provides identity information about the current operation. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:165-166 -->

The docs show `context.target` as an instance of `StorageDriverWorkflowInfo`, accessed via `isinstance(target, StorageDriverWorkflowInfo)`, with `.namespace` and `.id` attributes. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:114-115 -->

<!-- VERIFY: Does the Python SDK expose an Activity variant of the target (e.g., StorageDriverActivityInfo)? Only the Workflow variant is documented on the Python page. -->

### Store and retrieve mechanics

In `store()`, convert each `Payload` protobuf message to bytes with `payload.SerializeToString()` and write the bytes to your storage system. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:160-161 -->

In `retrieve()`, download the bytes using the claim data, then reconstruct the `Payload` protobuf message by calling `Payload()` and then `payload.ParseFromString(raw)`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:172-173 -->

Return one `StorageDriverClaim(claim_data={...})` per payload, where `claim_data` is a dict of string key-value pairs sufficient to locate the payload later. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:124 -->

The application data has already been serialized by the Payload Converter and Payload Codec before it reaches the driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:161-162 -->

<!-- SNIPSTART python-custom-storage-driver -- docs/develop/python/best-practices/data-handling/external-storage.mdx:95-143 -->
```py
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
        os.makedirs(self._store_dir, exist_ok=True)

        prefix = self._store_dir
        target = context.target
        if isinstance(target, StorageDriverWorkflowInfo) and target.id:
            prefix = os.path.join(self._store_dir, target.namespace, target.id)
            os.makedirs(prefix, exist_ok=True)

        claims = []
        for payload in payloads:
            key = f"{uuid.uuid4()}.bin"
            file_path = os.path.join(prefix, key)
            with open(file_path, "wb") as f:
                f.write(payload.SerializeToString())
            claims.append(StorageDriverClaim(claim_data={"path": file_path}))
        return claims

    async def retrieve(
        self,
        context: StorageDriverRetrieveContext,
        claims: Sequence[StorageDriverClaim],
    ) -> list[Payload]:
        payloads = []
        for claim in claims:
            file_path = claim.claim_data["path"]
            with open(file_path, "rb") as f:
                raw = f.read()
            payload = Payload()
            payload.ParseFromString(raw)
            payloads.append(payload)
        return payloads
```

The example uses local disk for clarity and is intended for local development and testing only. In production, use a durable storage system that is accessible to all Workers. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:92-93 -->

### Configure the Data Converter with a custom driver

Pass an `ExternalStorage` instance to your `DataConverter` and use the converter when creating your Client and Worker. Drivers can also be packaged as a plugin for easier reuse across services. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:178-179 -->

<!-- SNIPSTART python-custom-driver-data-converter -- docs/develop/python/best-practices/data-handling/external-storage.mdx:181-191 -->
```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```

## Use multiple storage drivers

When you register multiple drivers, you must provide a `driver_selector` callable that chooses which driver stores each payload. Any driver in the list that is not selected for storing remains available for retrieval, which is useful when migrating between storage backends. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:214-216 -->

Return `None` from the selector to **keep that payload inline in Event History** (not to externalize). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:216 -->

The `driver_selector` is provided as a callable, for example `lambda context, payload: preferred_driver`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:238 -->

### Motivating scenarios

The docs call out two scenarios where multiple drivers are useful: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:218-225 -->

- **Driver migration.** Your Worker needs to retrieve payloads created by clients that use a different driver than the one you prefer. Register both drivers and use the selector to always pick your preferred driver for new payloads. The old driver remains available for retrieving existing claims. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:220-222 -->
- **Multi-cloud storage.** Route payloads to different storage backends based on cloud environment. For example, use S3 for Workers running on AWS and GCS for Workers running on Google Cloud. The selector chooses the appropriate driver based on the runtime environment. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:223-225 -->

### Multiple drivers example

This snippet registers two drivers but always selects `preferred_driver` for new payloads. The `legacy_driver` is only registered so the Worker can retrieve payloads that were previously stored with it. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:227-228 -->

<!-- SNIPSTART python-external-storage-multiple-drivers -- docs/develop/python/best-practices/data-handling/external-storage.mdx:230-241 -->
```py
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```

## Plugin packaging

Drivers can be packaged as plugins for easier reuse across services. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:179 -->
