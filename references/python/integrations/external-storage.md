# External Storage — Python SDK

:::info Pre-Release feature

External Storage is in [Pre-Release](https://docs.temporal.io/evaluate/development-production-features/release-stages#pre-release). APIs and configuration may change before the stable release.

:::

## When to reach for it

The Temporal Service enforces a 2 MB per-payload limit by default. The limit is configurable on self-hosted deployments and fixed at 2 MB on Temporal Cloud. External Storage offloads payloads larger than a configured threshold to an external store (such as Amazon S3) and threads a small reference token through the Event History instead — the [claim-check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern).

Common drivers:

- Data processing pipelines that push documents, images, or large blobs through Workflows.
- AI agent conversations whose cumulative history grows with each turn.
- Spiky payload sizes where only occasional payloads exceed the threshold.
- Migrations to Temporal Cloud from a self-hosted deployment with a higher configured limit.
- Data governance: keep payload bytes in infrastructure you control by setting the threshold to externalize all payloads.

If you are already hitting size errors (`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, `[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.`, `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`), External Storage is the recommended fix.

## Where it sits in the data pipeline

External Storage runs at the end of the Data Conversion pipeline, after the [Payload Converter](https://docs.temporal.io/develop/python/data-handling/data-conversion) and the [Payload Codec](https://docs.temporal.io/develop/python/data-handling/data-encryption). The implication: by the time a `StorageDriver` receives a `Payload`, the application data has already been serialized and (if you use an encryption codec) encrypted.

The SDK parallelizes uploads and downloads when a single Workflow Task involves multiple offloaded payloads, and it validates payload integrity on retrieve.

## Built-in S3 driver

The Python SDK ships an S3 driver behind an `aioboto3` extra.

### Prerequisites

- An Amazon S3 bucket you have read/write access to.
- Install the extra:

  ```text
  python -m pip install "temporalio[aioboto3]"
  ```


The S3 driver uses standard AWS credentials from the environment (environment variables, IAM role, or AWS config file).

### Create the driver

```python
session = aioboto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
async with session.client("s3") as s3_client:
    driver = S3StorageDriver(
        client=new_aioboto3_client(s3_client),
        bucket="my-temporal-payloads",
    )
```


Key tokens — `S3StorageDriver`, `new_aioboto3_client`, the `bucket=` kwarg — appear verbatim in the docs snippet.

### Wire the driver into the Client and Worker

Unlike Go, Python plugs External Storage into a `DataConverter`, then passes the converter to **both** the Client and Worker:

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


The configuration shape: `ExternalStorage(drivers=[...])` is the value of the `external_storage` field on a `DataConverter`. Use `dataclasses.replace(DataConverter.default, external_storage=...)` to start from the default converter. All Workflows and Activities running on the Worker use the driver automatically — no changes to business logic.

## Payload size threshold

By default, payloads larger than **256 KiB** are offloaded. Tune with the `payload_size_threshold` parameter on `ExternalStorage`:

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[driver],
        payload_size_threshold=0,
    ),
)
```


Documented value:

- `payload_size_threshold=0` — externalize **all** payloads regardless of size.

> **Trap:** the "externalize everything" sentinel differs between SDKs. Python uses `payload_size_threshold=0`. Go uses `PayloadSizeThreshold: 1` (and Go's `0` means "use default"). Do not transpose them.

## Custom `StorageDriver`

Extend the `StorageDriver` abstract class if the built-in drivers don't cover your backend. Store payloads durably — they must survive process crashes and remain available for debugging and auditing after the Workflow completes.

The interface has **three** methods.

| Method | Returns | Constraint |
|---|---|---|
| `name() -> str` | Unique driver identifier | Stored in the claim-check reference. Changing it after payloads have been stored breaks retrieval. |
| `async store(context, payloads) -> list[StorageDriverClaim]` | One `StorageDriverClaim` per payload | A claim is a set of string key-value pairs the driver uses to locate the payload later. |
| `async retrieve(context, claims) -> list[Payload]` | The original payloads | Receives the claims that `store()` produced. |


> **Trap:** the Python interface does **not** define a `type()` method — that is Go-only.

### Local-disk sample (development only)

The docs ship a `LocalDiskStorageDriver` sample. It is documented as **"for local development and testing only"** — use a durable, Worker-accessible store in production.

Key shapes from the sample:

- `store()` receives a `StorageDriverStoreContext`. Its `target` attribute may be a `StorageDriverWorkflowInfo` (with `namespace` and `id` attributes for the Workflow ID) or `StorageDriverActivityInfo` — distinguish with `isinstance(target, StorageDriverWorkflowInfo)`.
- Serialize each `Payload` with `payload.SerializeToString()`.
- A `StorageDriverClaim` is constructed with a `claim_data` mapping (`StorageDriverClaim(claim_data={"path": file_path})`).
- `retrieve()` reverses the process: read the bytes by `claim.claim_data[...]`, instantiate a fresh `Payload()`, then call `payload.ParseFromString(raw)`.

The docs additionally note that within a per-Workflow scope, content-addressable keys (such as a SHA-256 hash of the payload bytes) can help deduplicate identical payloads.

### Plug the custom driver in

```python
data_converter = dataclasses.replace(
    DataConverter.default,
    external_storage=ExternalStorage(
        drivers=[LocalDiskStorageDriver()],
    ),
)
```


You can also package a driver as a [plugin](https://docs.temporal.io/develop/plugins-guide) for reuse across services.

## Multiple drivers and migration

Register multiple drivers when you need to read from one backend while writing to another (storage-backend migration, or multi-cloud routing). You **must** provide a `driver_selector` callable that chooses which driver stores each payload — without it, multi-driver setups are not valid.

The selector chooses which driver stores each payload. Drivers in the list that the selector never picks are still consulted for **retrieval**, which is what makes migration work. Return `None` from the selector to keep a specific payload **inline** in Event History.

Documented use cases:

- **Driver migration.** Register the legacy driver alongside the preferred one. The selector always returns the preferred driver; the legacy driver stays in the list so existing claims still resolve.
- **Multi-cloud storage.** Route payloads to different backends based on runtime (e.g., S3 on AWS Workers, GCS on GCP Workers).

```python
preferred_driver = S3StorageDriver(client=s3_client, bucket="my-bucket")
legacy_driver = LegacyStorageDriver()

ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```


The selector signature in the sample is `lambda context, payload: ...` — it receives the store context and the payload and returns a `StorageDriver` (or `None` to keep inline).


## Codec Server interaction

When your Workers and Clients use External Storage, the Temporal Service and Web UI only see small references — not the actual payload data. A Codec Server that the Web UI and CLI use to decode payloads must therefore become **storage-aware** to display real data.

### The three endpoints

A storage-aware Codec Server exposes three POST endpoints (the `/download` endpoint is added when the handler is configured with storage drivers):

- **`/encode`** — applies the Payload Codec, then uploads payloads that exceed the size threshold to external storage and replaces them with reference tokens.
- **`/decode`** — decodes encoded payloads and also handles storage references. By default, `/decode` retrieves and decodes any storage references alongside regular payloads. With the `?preserveStorageRefs=true` query parameter, `/decode` skips retrieval and returns storage references as-is.
- **`/download`** — retrieves the actual payload data from external storage and decodes it through the Payload Codec. Used internally by `/decode` when it encounters storage references, and called directly by the Web UI when a user clicks to view the full payload for a storage reference.

The end-to-end flow the docs walk through: CLI sends plaintext input to `/encode` → server encodes, exceeds threshold, uploads, returns a reference token → CLI sends the reference to the Temporal Service → later, the Web UI calls `/decode?preserveStorageRefs=true` to render the event history with reference metadata → user clicks a reference → Web UI calls `/download` to fetch the decoded payload.

> **Note on handler choice.** The storage-aware handler API (`NewPayloadHTTPHandler` + `PayloadHTTPHandlerOptions`) is described in the **Go-flavored** docs section of `docs/encyclopedia/data-conversion/codec-server.mdx`. The same caution applies in spirit across SDKs: the handler that drives `/encode` + `/decode` + `/download` for the Web UI and CLI is **not** the same as a remote-codec target for Workers. Refer to the Python Codec Server sample [`codec_server.py`](https://github.com/temporalio/samples-python/blob/main/encryption/codec_server.py) for an implementation pattern.
>
>

## Lifecycle management

Temporal does **not** automatically delete payloads from your external store. Payloads can also be orphaned if a request fails after upload completes. Configure a lifecycle policy on your store with a TTL that satisfies:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```


Worked example from the docs: a 14-day Run Timeout plus a 30-day retention period → expire objects after **at least 44 days**.

For Workflows with no Run Timeout, there is no finite TTL that guarantees safety. Set a generous TTL and use [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) for indefinitely-running Workflows — the new run uploads fresh payloads, and the old run's payloads only need to outlive its retention period.

## Common mistakes (anti-patterns)

| Wrong | Right |
|---|---|
| `Client.connect(..., external_storage=ExternalStorage(...))` | Wrap in a `DataConverter`: `data_converter = dataclasses.replace(DataConverter.default, external_storage=ExternalStorage(...))`, then pass `data_converter=data_converter` to **both** `Client.connect(...)` and the `Worker(...)`. |
| `payload_size_threshold=1` to externalize all payloads | `payload_size_threshold=0` externalizes all payloads in Python. |
| Expecting a `type()` method on the Python `StorageDriver` class | Python interface defines `name()`, `store()`, `retrieve()` only — no `type()`. |
| Renaming a driver after payloads have been stored | The SDK stores `name()` in the claim-check reference; changing it breaks retrieval. |
| Registering multiple drivers without a `driver_selector` | When you register multiple drivers, you **must** provide a `driver_selector` function. |
| Installing the S3 driver via `pip install boto3` | Driver uses `aioboto3`; install via `python -m pip install "temporalio[aioboto3]"`. |
| Promoting the `LocalDiskStorageDriver` sample as a production driver | Documented as "for local development and testing only". Use a durable, Worker-accessible store in production. |
| Assuming Temporal cleans up the external store | Temporal does not delete payloads — set a lifecycle policy with TTL > Run Timeout + Namespace Retention. |
| Treating the External Storage API as stable | Pre-Release; APIs and configuration may change. |

## Cross-references

- Concept overview: [External Storage](https://docs.temporal.io/external-storage) (`docs/encyclopedia/data-conversion/external-storage.mdx`).
- Codec Server with External Storage: [Codec Server](https://docs.temporal.io/codec-server#external-storage) (`docs/encyclopedia/data-conversion/codec-server.mdx`).
- Why this matters: [Troubleshoot payload and gRPC message size limit errors](https://docs.temporal.io/troubleshooting/blob-size-limit-error) (`docs/troubleshooting/blob-size-limit-error.mdx`).
- Data Conversion pipeline framing: `references/python/data-handling.md` (this skill).
