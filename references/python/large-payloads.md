# Python SDK Large Payloads

## Payload Size Limits

Temporal enforces hard limits on payload sizes:

- **2 MB** max per single payload (workflow/activity input, output, signal, query, update, memo, etc.)
- **4 MB** max per gRPC message / Event History transaction

Exceeding these limits produces a `BlobSizeLimitError`. If a Workflow Task response exceeds the 4 MB gRPC limit, the workflow is terminated with `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE` — this is non-recoverable. See [Troubleshoot the blob size limit error](https://docs.temporal.io/troubleshooting/blob-size-limit-error).

## External Storage (Recommended)

**Available in `temporalio` 1.25.0+ (Pre-release / experimental).**

External Storage offloads large payloads to an external service (e.g., S3) and stores a small reference token in Event History. Applies transparently to all payloads: workflow inputs/outputs, activity inputs/outputs, signal/query/update arguments, memos, and failure details.

### Configure with the built-in Amazon S3 driver

```python
import aioboto3
import dataclasses
from temporalio.client import Client, ClientConfig
from temporalio.contrib.aws.s3driver import S3StorageDriver
from temporalio.contrib.aws.s3driver.aioboto3 import new_aioboto3_client
from temporalio.converter import DataConverter, ExternalStorage

client_config = ClientConfig.load_client_connect_config()

session = aioboto3.Session()
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-bucket",
    )
    client = await Client.connect(
        **client_config,
        data_converter=dataclasses.replace(
            DataConverter.default,
            external_storage=ExternalStorage(drivers=[driver]),
        ),
    )
```

Configure **the same `data_converter` on both client and worker** — anywhere a large payload may be uploaded or downloaded.

### Behavior

- Only payloads that meet or exceed `ExternalStorage.payload_size_threshold` are offloaded. Default threshold is **256 KiB**. Smaller payloads are stored inline as normal.
- Setting `payload_size_threshold` to `0` sends every payload through external storage.
- If you also configure a `payload_codec` (e.g., encryption), the codec is applied **before** the driver — the driver stores encoded bytes. The reference token written to history is not encoded by the codec.
- You can implement a custom `StorageDriver` for systems other than S3.

See the [Python SDK External Storage README](https://github.com/temporalio/sdk-python/blob/main/README.md#external-storage) and [Store and retrieve large payloads with Amazon S3](https://docs.temporal.io/develop/python/data-handling/large-payload-storage#store-and-retrieve-large-payloads-with-amazon-s3).

## Alternative: Claim-Check via Custom Codec or Converter

Before External Storage shipped, the standard pattern was a "claim-check" `PayloadCodec` or `DataConverter` that persists large payloads to object storage and swaps in a reference. DataDog's [temporal-large-payload-codec](https://github.com/DataDog/temporal-large-payload-codec) is a reference implementation.

This pattern still works, but prefer the first-party External Storage feature in new code.

## Alternative: Pass References Manually

The simplest approach when a single activity produces or consumes a large blob:

1. Activity writes the blob to S3/GCS/Redis and returns the object key.
2. Workflow passes that key into the next activity.
3. The next activity reads the blob from storage.

This avoids loading the payload into workflow memory during replay, which matters for workflows with many large payloads — a naive "transparent" approach forces every payload to be re-fetched on every replay.

## Other Mitigations

- **Compression** via a custom `PayloadCodec` can keep payloads under limit when they are only moderately oversized.
- **Batching / pagination**: split large batches of activity commands across multiple Workflow Tasks (iterate batches, await completion, then continue) to avoid exceeding the 4 MB Workflow Task response limit.
- **Return only what the workflow needs**: filter activity results before returning — workflows rarely need full raw payloads.
- **Heartbeating long streaming activities**: a long-running activity can stream from a paginated source and checkpoint cursor state via `activity.heartbeat(...)` instead of returning thousands of records at once. See `references/python/patterns.md`.

## Best Practices

1. Prefer the built-in **External Storage** + **S3 driver** for transparent offloading.
2. Configure external storage on **both client and worker**.
3. Keep payloads that the workflow itself inspects small — workflows replay, and large inline payloads cost memory and history size.
4. If using a custom claim-check codec, make sure the downstream storage can handle your throughput; backpressure on the store can trigger Workflow Task timeouts and deadlock detection.
5. Avoid raising the server's `system.transactionSizeLimit` to work around the 4 MB gRPC cap — it puts pressure on the database and proxies.
