# Python SDK Payload Validation

This file covers how the Python SDK validates payload size, what happens when
limits are exceeded, and how to mitigate oversized payloads with External
Storage. For the cross-language failure-cause matrix and conceptual framing,
see [`references/core/payload-validation.md`](../core/payload-validation.md).

## Size limits

A single Activity argument is limited to a maximum size of 2 MB. <!-- docs/develop/python/activities/basics.mdx:72-73 -->
The total size of a gRPC message, which includes all the arguments, is limited
to a maximum of 4 MB. <!-- docs/develop/python/activities/basics.mdx:72-73 -->

Activity return values are subject to the same payload size limits: the default
payload size limit is 2 MB, and there is a hard limit of 4 MB for any gRPC
message size in the Event History transaction. <!-- docs/develop/python/activities/basics.mdx:115-117 -->

All Payload data is recorded in the Workflow Execution Event History, and large
Event Histories can affect Worker performance because the entire Event History
could be transferred to a Worker Process with a Workflow Task. <!-- docs/develop/python/activities/basics.mdx:75-78 -->

## Eager validation in Python SDK 1.23.0+

The Python SDK 1.23.0+ performs eager local validation when a payload would
exceed the size limit. This is the Python-distinctive behavior and the most
important thing to understand for Python developers.

### Payload size limit (oversized single payload)

In Python SDK 1.23.0+, the SDK fails the Workflow Task with cause
`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is not terminated
and remains open, so you can deploy a fix and allow the Workflow to continue. <!-- docs/troubleshooting/blob-size-limit-error.mdx:46-47 -->

Possible error messages reported by the Temporal Service or surfaced in the
SDK include: <!-- docs/troubleshooting/blob-size-limit-error.mdx:31-40 -->

- `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 -->
- `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.` <!-- docs/troubleshooting/blob-size-limit-error.mdx:36 -->
- `BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:37 -->
- `Complete result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:38 -->
- `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit` <!-- docs/troubleshooting/blob-size-limit-error.mdx:39 -->
- `WORKFLOW_TASK_FAILED_CAUSE_BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:40 -->

### gRPC message size limit (oversized combined message)

A Workflow can hit the 4 MB gRPC message limit even when every individual
payload is under 2 MB. Scheduling several Activities with moderate-sized inputs,
or hundreds of Activities with tiny inputs in the same Workflow Task, can push
the combined request past 4 MB. Activity results are also subject to this limit. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->

In Python SDK 1.23.0+, the SDK fails the Workflow Task with cause
`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. The Workflow is not terminated
and remains open, so you can deploy a fix and allow the Workflow to continue.
For Activities, the Activity fails with an explicit error instead of timing out
silently. <!-- docs/troubleshooting/blob-size-limit-error.mdx:106-108 -->

Possible error messages for oversized gRPC messages: <!-- docs/troubleshooting/blob-size-limit-error.mdx:96-100 -->

- `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:99 -->
- `ScheduleToCloseTimeout` (Activities only, on older SDKs) <!-- docs/troubleshooting/blob-size-limit-error.mdx:100 -->

### Why eager validation matters

Because the Python 1.23.0+ SDK fails the Workflow Task locally rather than
letting an oversized request reach the server, the Workflow remains in an open
state. You can fix the underlying code path (for example, switch the offending
argument to a reference produced by External Storage), redeploy your Worker,
and the Workflow continues from the failed Workflow Task without manual
intervention.

For the contrast with older Python SDKs and non-Python SDKs (which can
terminate the Workflow, stick it in a retry loop, or cause silent Activity
timeouts), see [`references/core/payload-validation.md`](../core/payload-validation.md). <!-- docs/troubleshooting/blob-size-limit-error.mdx:49-55, 110-123 -->

<!-- VERIFY: Do Python SDK 1.23.0+ docs describe a Worker option to disable or tune the eager validation check? The docs reviewed describe this as SDK behavior, not as a configurable option. -->

<!-- VERIFY: Is there a separate memo-size validation option on the Python Worker? The docs reviewed do not describe one. -->

## Mitigation: External Storage

The Python SDK ships External Storage, an implementation of the claim check
pattern that offloads large payloads to an external store (such as Amazon S3)
and passes a small reference token through the Event History instead. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:22-25 -->

External Storage is currently in Pre-Release; APIs and configuration may change
before the stable release. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:14-20 -->

### Installation

Install the `aioboto3` extra: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:37 -->

```sh
python -m pip install "temporalio[aioboto3]"
```

### Construct the S3 storage driver

Create an S3 client using `aioboto3` and pass it to the `S3StorageDriver`. The
driver uses your standard AWS credentials from the environment (environment
variables, IAM role, or AWS config file): <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:41-43 -->

```py
session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:46-53 -->

### Wire External Storage onto the DataConverter

Configure the driver on your `DataConverter` and pass the converter to your
Client and Worker: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:56-57 -->

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
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:60-76 -->

All Workflows and Activities running on the Worker use the storage driver
automatically without changes to your business logic. The driver uploads and
downloads payloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:83-84 -->

### `payload_size_threshold` semantics

By default, payloads larger than 256 KiB are offloaded to external storage. You
can adjust this with the `payload_size_threshold` parameter, or set it to 0 to
externalize all payloads regardless of size. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:195-197 -->

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:201-209 -->

**Critical:** `payload_size_threshold` is an *offload* threshold, not a
validation limit. Setting it does not raise or lower the 2 MB per-payload limit
or the 4 MB gRPC message limit enforced by the Temporal Service; it only
controls which payloads the SDK transparently uploads to external storage
before they hit the wire. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:79-81, 195-197 -->

## Custom storage drivers

If you need a storage backend other than what the built-in drivers allow, you
can implement your own storage driver. Store payloads durably so that they
survive process crashes and remain available for debugging and auditing after
the Workflow completes. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:88-90 -->

A custom driver extends the `StorageDriver` abstract class and implements three
methods: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:150 -->

- `name()` returns a unique string that identifies the driver. The SDK stores
  this name in the claim check reference so it can route retrieval requests to
  the correct driver. Changing the name after payloads have been stored breaks
  retrieval. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:152-153 -->
- `store()` receives a list of payloads and returns one `StorageDriverClaim`
  per payload. A claim is a set of string key-value pairs that the driver uses
  to locate the payload later. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:154-155 -->
- `retrieve()` receives the claims that `store()` produced and returns the
  original payloads. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:156 -->

The following example shows a custom driver that uses local disk as the backing
store. This example is for local development and testing only. In production,
use a durable storage system that is accessible to all Workers: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:92-93 -->

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
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:98-140 -->

In `store()`, convert each Payload protobuf message to bytes with
`payload.SerializeToString()` and write the bytes to your storage system. The
application data has already been serialized by the Payload Converter and
Payload Codec before it reaches the driver. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:160-162 -->

In `retrieve()`, download the bytes using the claim data, then reconstruct the
Payload protobuf message with `payload.ParseFromString(data)`. The Payload
Converter handles deserializing the application data after the driver returns
the payload. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:172-174 -->

Pass an `ExternalStorage` instance to your `DataConverter` and use the
converter when creating your Client and Worker: <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:178-179 -->

```py
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:183-189 -->

## Multiple drivers and the `driver_selector`

When you register multiple drivers, you must provide a `driver_selector`
function that chooses which driver stores each payload. Any driver in the list
that is not selected for storing is still available for retrieval, which is
useful when migrating between storage backends. Return `None` from the selector
to keep a specific payload inline in Event History. <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:214-216 -->

Multiple drivers are useful for driver migration (your Worker needs to retrieve
payloads created by clients that use a different driver than the one you
prefer) and for multi-cloud storage (route payloads to different backends based
on cloud environment). <!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:218-225 -->

```py
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```
<!-- docs/develop/python/best-practices/data-handling/external-storage.mdx:233-239 -->

## See also

- [`references/core/payload-validation.md`](../core/payload-validation.md) for
  the full failure-cause matrix across SDK versions, including the behavior
  contrast between Python SDK 1.23.0+ and older / non-Python SDKs.
