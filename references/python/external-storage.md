# External Storage (Python SDK)

> **Pre-Release.** External Storage is in Pre-Release. APIs and configuration may change before the stable release. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:14-20 --> <!-- docs/encyclopedia/data-conversion/external-storage.mdx:24-30 -->

External Storage offloads large payloads to an external store (such as Amazon S3) and passes a small reference token through the Event History instead. This is the claim check pattern. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:32-33 -->

### At a glance

| Concept | Token / Value |
| --- | --- |
| Configure on | `DataConverter` via `dataclasses.replace(DataConverter.default, external_storage=...)` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:61-64 --> |
| Top-level type | `ExternalStorage(drivers=[...], driver_selector=..., payload_size_threshold=...)` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:63 --> <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:204-207 --> <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:236-239 --> |
| Default threshold | 256 KiB <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:79 --> |
| Externalize all payloads | `payload_size_threshold=0` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:196-197 --> |
| Built-in driver | `S3StorageDriver(client=new_aioboto3_client(s3_client), bucket=...)` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:49-52 --> |
| S3 install extra | `python -m pip install "temporalio[aioboto3]"` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 --> |
| Custom driver base | `StorageDriver` with `name()`, `store()`, `retrieve()` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:148-156 --> |
| Claim type | `StorageDriverClaim(claim_data={...})` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:124 --> |
| Store context type | `StorageDriverStoreContext` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:107 --> |
| Retrieve context type | `StorageDriverRetrieveContext` <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:129 --> |
| Workflow identity on `context.target` | `StorageDriverWorkflowInfo` (use `isinstance`) <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:114 --> |

## When to use

The Temporal Service enforces a maximum per-payload size. The default and recommended limit is 2 MB. Self-hosted users can configure this limit, but it is fixed at 2 MB on Temporal Cloud. Payloads that exceed this limit fail the operation. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:42-45 -->

Even when individual payloads stay under the hard limit, payload data accumulates in Event History. Every Activity input and output is persisted, so Workflows that pass data through many Activities can see history size grow quickly. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:47-49 -->

Common scenarios: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:51-63 -->

- **Data processing pipelines.** Workflows that process documents, images, or other large blobs can exceed the per-payload limit.
- **AI agent conversations.** Long conversation histories grow with each turn, and the cumulative size can degrade Workflow performance.
- **Spiky data sizes.** Some Workflows handle data that is usually small but occasionally large. The claim check pattern handles these spikes transparently, offloading only the payloads that exceed the size threshold.
- **Migration to Temporal Cloud.** Self-hosted deployments may have higher configured payload limits. External Storage lets you migrate to Cloud without restructuring Workflows that exceed the 2 MB limit.
- **Data governance.** Store payload data in infrastructure you control; set the offload size threshold to zero to externalize all payloads regardless of size.

## Pipeline placement

External Storage sits at the end of the Data Conversion pipeline, after both the Payload Converter and the Payload Codec. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:70-73 -->

When a Client sends a payload that exceeds the configured size threshold, the storage driver uploads the payload to your external store and replaces it with a lightweight reference. Payloads below the threshold stay inline in the Event History. When the Service dispatches Tasks to the Worker, the process reverses: the Worker downloads the referenced payloads from external storage in parallel, then passes them back through the Payload Codec and Payload Converter to reconstruct the original data. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:82-88 -->

The SDK parallelizes uploads and downloads to minimize latency. When a single Workflow Task involves multiple payloads that exceed the threshold, the SDK uploads or downloads all of them concurrently rather than one at a time. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:90-92 -->

When a payload is offloaded, the Temporal UI displays a reference token instead of the actual data. This is expected. Your application code receives the fully decoded result because the SDK transparently retrieves the payload from external storage before returning it to your Workflow or Client. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:94-96 -->

Because External Storage runs after the Payload Codec, if you use an encryption codec, payloads are already encrypted before upload to your store. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:98-99 -->

## S3 driver setup

The Python SDK includes a built-in S3 storage driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:31 -->

### Prerequisites

- An Amazon S3 bucket that you have read and write access to. Configure a lifecycle policy so payloads remain available for the entire lifetime of the Workflow. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:35-36 -->
- Install the `aioboto3` extra: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 -->

```bash
python -m pip install "temporalio[aioboto3]"
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 -->

### Create the driver

Create an S3 client using `aioboto3` and pass it to the `S3StorageDriver`. The driver uses your standard AWS credentials from the environment (environment variables, IAM role, or AWS config file). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:41-43 -->

```python
session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:47-53 -->

The `new_aioboto3_client` wrapper around the raw `aioboto3` client is required when constructing the `S3StorageDriver`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:50 -->

### Wire the driver into a DataConverter, Client, and Worker

Configure the driver on your `DataConverter` and pass the converter to both your Client and Worker: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:56 -->

```python
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
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:61-75 -->

Notes:

- `ExternalStorage` is configured on the `DataConverter` via `dataclasses.replace(DataConverter.default, external_storage=...)`. The data converter is then passed to `Client.connect` and `Worker`. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:61-68 -->
- All Workflows and Activities running on the Worker use the storage driver automatically without changes to your business logic. The driver uploads and downloads payloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:83-84 -->
- By default, payloads larger than 256 KiB are offloaded to external storage. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:79 -->

## `payload_size_threshold`

Configure the payload size threshold that triggers external storage. By default, payloads larger than 256 KiB are offloaded. Adjust the `payload_size_threshold` parameter, or set it to `0` to externalize all payloads regardless of size. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:193-197 -->

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:202-208 -->

Setting `payload_size_threshold=0` offloads every payload, which is the pattern to use when your data governance policy requires that all payloads live in infrastructure you control. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:60-63 --> <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:196-197 -->

## Custom storage driver

If you need a storage backend other than the built-in drivers, implement your own driver. Store payloads durably so that they survive process crashes and remain available for debugging and auditing after the Workflow completes. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:86-90 -->

A custom driver extends the `StorageDriver` abstract class and implements three methods: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:148-150 -->

- `name()` returns a unique string that identifies the driver. The SDK stores this name in the claim check reference so it can route retrieval requests to the correct driver. **Changing the name after payloads have been stored breaks retrieval.** <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:152-153 -->
- `store()` receives a list of payloads and returns one `StorageDriverClaim` per payload. A claim is a set of string key-value pairs that the driver uses to locate the payload later. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:154-155 -->
- `retrieve()` receives the claims that `store()` produced and returns the original payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:156 -->

### `store()`

In `store()`, convert each `Payload` protobuf message to bytes with `payload.SerializeToString()` and write the bytes to your storage system. The application data has already been serialized by the Payload Converter and Payload Codec before it reaches the driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:160-163 -->

Return a `StorageDriverClaim` for each payload with enough information to retrieve it later. The `context.target` provides identity information (namespace, Workflow ID, or Activity ID) depending on the operation. Consider structuring your storage keys to include this information so that you can identify which Workflow owns each payload. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:165-168 -->

Use `isinstance(target, StorageDriverWorkflowInfo)` to discriminate the target type and unpack Workflow identity. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:114 -->

### `retrieve()`

In `retrieve()`, download the bytes using the claim data, then reconstruct the `Payload` protobuf message with `payload.ParseFromString(data)`. The Payload Converter handles deserializing the application data after the driver returns the payload. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:172-174 -->

### Worked example

The following driver writes payloads to local disk. Use it for local development and testing only; in production, use a durable storage system accessible to all Workers. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:92-93 -->

```python
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
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:98-140 -->

Wire the custom driver into the `DataConverter` the same way as the S3 driver. You can also package your driver as a plugin for easier reuse across services. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:178-179 -->

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:184-189 -->

### Claim shape

A `StorageDriverClaim` carries a `claim_data` mapping of string key-value pairs you choose. Within the scope of a Workflow's identity, content-addressable keys (such as a SHA-256 hash of the payload bytes) can help deduplicate identical payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:124 --> <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:165-168 -->

```python
StorageDriverClaim(claim_data={"path": file_path})
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:124 -->

On `retrieve()`, read the same keys back from `claim.claim_data`: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:134 -->

```python
file_path = claim.claim_data["path"]
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:134 -->

## Multiple drivers and driver migration

When you register multiple drivers, you must provide a `driver_selector` function that chooses which driver stores each payload. Any driver in the list that is not selected for storing is still available for retrieval, which is useful when migrating between storage backends. Return `None` from the selector to keep a specific payload inline in Event History. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:214-216 -->

Multiple drivers are useful in scenarios such as: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:218-225 -->

- **Driver migration.** Your Worker needs to retrieve payloads created by clients that use a different driver than the one you prefer. Register both drivers and use the selector to always pick your preferred driver for new payloads. The old driver remains available for retrieving existing claims.
- **Multi-cloud storage.** Route payloads to different storage backends based on your cloud environment. The selector chooses the appropriate driver based on the runtime environment.

The following example registers two drivers but always selects `preferred_driver` for new payloads. The `legacy_driver` is only registered so the Worker can retrieve payloads that were previously stored with it: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:227-228 -->

```python
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:233-239 -->

Migration is **driver registration plus selector preference**, not automatic format conversion. The legacy driver stays in the `drivers` list for retrieval of pre-existing claims; the selector routes every new payload to the preferred driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:214-228 -->

## Codec Server interplay

When your Workers and Clients use External Storage, your storage drivers replace some payloads in the Event History with small references that point to data in an external store like Amazon S3. The Temporal Service and the Web UI only see these references, not the actual payload data. Your Codec Server must be able to handle downloading and decoding in the correct order for you to view the Workflow data in the UI or CLI. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:83-88 -->

A Codec Server configured for External Storage exposes the following HTTP POST endpoints: <!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-113 -->

- **`/encode`** applies the Payload Codec, then uploads payloads that exceed the size threshold to external storage and replaces them with reference tokens. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:112-113 -->
- **`/decode`** decodes encoded payloads and also handles storage references. By default, `/decode` uses the download logic internally to retrieve and decode any storage references in the request alongside regular payloads. With the **`?preserveStorageRefs=true`** query parameter, `/decode` skips retrieval and returns storage references as-is. Non-reference payloads are still decoded — `preserveStorageRefs` only skips external retrieval. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:109-111 -->
- **`/download`** retrieves the actual payload data from external storage and decodes it through the Payload Codec. This endpoint is used internally by `/decode` when it encounters storage references; the Web UI calls it directly when you click to view the full payload for a storage reference. <!-- docs/encyclopedia/data-conversion/codec-server.mdx:105-108 -->

The encyclopedia codec-server documentation describes the encode-store-encode and decode-retrieve-decode pipeline in language-neutral terms and references handler constructors (`NewPayloadHTTPHandler` with `PayloadHTTPHandlerOptions`, with a caution that `NewPayloadHTTPHandler` must not be used as a target for a remote Data Converter or remote codec on your Workers — use `NewPayloadCodecHTTPHandler` separately for that). <!-- docs/encyclopedia/data-conversion/codec-server.mdx:90-103 -->

<!-- VERIFY: The Python SDK external-storage docs do not describe a Python-specific HTTP handler constructor for codec servers with External Storage. The codec-server encyclopedia page references constructors using Go-style naming (NewPayloadHTTPHandler / NewPayloadCodecHTTPHandler). Confirm whether the Python SDK ships an equivalent constructor, and if so, name it. Not documented in the three source files. -->

Walkthrough of how the three endpoints work together: <!-- docs/encyclopedia/data-conversion/codec-server.mdx:122-135 -->

1. A user starts a Workflow from the CLI with a plaintext input. The CLI sends the input to the Codec Server's `/encode` endpoint.
2. The Codec Server encodes the payload through the Payload Codec. The encoded payload exceeds the storage threshold, so the Codec Server uploads it to external storage and returns a small reference token.
3. The CLI sends the reference token to the Temporal Service, which stores it in the Event History.
4. Later, a user views the Workflow in the Web UI. The Web UI retrieves the Event History from the Temporal Service and sends the payloads to the Codec Server's `/decode` endpoint with the `?preserveStorageRefs=true` query parameter.
5. The Codec Server decodes any non-reference payloads through the Payload Codec, but returns storage references as-is. The Web UI displays the reference metadata, indicating the payload is stored externally.
6. The user clicks to view the full payload. The Web UI sends the storage reference to the `/download` endpoint.
7. The Codec Server retrieves the encoded payload from external storage, decodes it through the Payload Codec, and returns the plaintext result to the Web UI.

## Lifecycle

Temporal does not automatically delete payloads from your external store. Configure a lifecycle policy on your bucket that both cleans up old payloads and provides a grace period for debugging and recovery. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:131-133 -->

Your TTL must be long enough that payloads remain available for the entire lifetime of the Workflow plus its retention window: <!-- docs/encyclopedia/data-conversion/external-storage.mdx:135-136 -->

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```
<!-- docs/encyclopedia/data-conversion/external-storage.mdx:138-140 -->

For example, a 14-day Run Timeout plus a 30-day Namespace retention period requires a lifecycle rule that expires objects after at least 44 days. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:142-143 -->

If your Workflows run indefinitely (no Run Timeout), there is no finite TTL that guarantees safety. Set a generous TTL based on your operational needs, and use Continue-as-New for Workflows that need to run longer. The new run uploads fresh payloads, and the old run's payloads only need to survive through its retention period. <!-- docs/encyclopedia/data-conversion/external-storage.mdx:145-148 -->

See the encyclopedia [External Storage](https://docs.temporal.io/external-storage) page for the full lifecycle and pipeline-placement prose.
