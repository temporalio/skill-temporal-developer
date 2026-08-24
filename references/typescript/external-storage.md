# TypeScript SDK External Storage

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## What this is

External Storage uses the **claim check pattern**: it offloads each Payload to an external store (e.g. Amazon S3 or Google Cloud Storage), records a small reference token (the "claim check") in Event History, and uses that token to retrieve the Payload when needed. The SDK handles storage and retrieval transparently.

## When to use it

- A Workflow input, Activity input, Activity result, or Workflow result will exceed the **2 MB** per-payload limit (fixed at 2 MB on Temporal Cloud; configurable on self-hosted only).
- Long Event Histories degrade Workflow Task latency (e.g. AI agent conversations growing per turn).
- The user wants payload data to live in storage **they** control. Set `payloadSizeThreshold: 0` to externalize all payloads.
- The user is migrating from self-hosted (with a larger configured limit) to Temporal Cloud.

## Where it sits in the pipeline

Order: **Payload Converter → Payload Codec → External Storage**. Storage runs last on outbound; it reverses on inbound.

Consequences:

- If a Payload Codec encrypts data, the bytes are already encrypted **before** upload.
- The Temporal UI displays the reference token, not the data; the SDK retrieves the payload transparently before handing it to your Workflow or Client.
- Every Client and Worker that might read an offloaded payload needs the same External Storage configuration.

## Setup with a built-in driver

The TypeScript SDK provides first-party drivers for Amazon S3 and Google Cloud Storage. Install one driver, its SDK adapter, and the cloud provider's SDK. Keep all `@temporalio/*` packages on the same version.

Amazon S3:

```bash
npm install @temporalio/external-storage-s3 \
  @temporalio/external-storage-s3-aws-sdk \
  @temporalio/envconfig \
  @aws-sdk/client-s3
```

Google Cloud Storage:

```bash
npm install @temporalio/external-storage-gcs \
  @temporalio/external-storage-gcs-google-sdk \
  @temporalio/envconfig \
  @google-cloud/storage
```

### Amazon S3 driver

```typescript
import { S3Client } from '@aws-sdk/client-s3';
import { S3StorageDriver } from '@temporalio/external-storage-s3';
import { AwsSdkS3StorageDriverClient } from '@temporalio/external-storage-s3-aws-sdk';

const s3Client = new S3Client({ region: 'us-east-2' });

const driver = new S3StorageDriver({
  client: new AwsSdkS3StorageDriverClient(s3Client),
  bucket: 'my-temporal-payloads',
});
```

The AWS SDK reads standard credentials from environment variables, an IAM role, or the AWS config file.

### Google Cloud Storage driver

```typescript
import { Storage } from '@google-cloud/storage';
import { GcsStorageDriver } from '@temporalio/external-storage-gcs';
import { GoogleCloudGcsStorageDriverClient } from '@temporalio/external-storage-gcs-google-sdk';

const storage = new Storage();

const driver = new GcsStorageDriver({
  client: new GoogleCloudGcsStorageDriverClient(storage),
  bucket: 'my-temporal-payloads',
});
```

The Google Cloud SDK reads Application Default Credentials.

For either driver, `bucket` can be a function instead of a string. The function receives the store context and Payload and returns a bucket name, allowing runtime routing.

### Configure the Client and Worker

Create one Data Converter configuration and pass it to both the Client and Worker. Load connection settings with `loadClientConnectConfig()`, and remember that `NativeConnection` carries no namespace, so the Worker needs `namespace` passed explicitly:

```typescript
import { Client, Connection } from '@temporalio/client';
import { ExternalStorage } from '@temporalio/common';
import { loadClientConnectConfig } from '@temporalio/envconfig';
import { NativeConnection, Worker } from '@temporalio/worker';

const dataConverter = {
  externalStorage: new ExternalStorage({ drivers: [driver] }),
};

const config = loadClientConnectConfig();

const connection = await Connection.connect(config.connectionOptions);
const client = new Client({ connection, namespace: config.namespace, dataConverter });

const workerConnection = await NativeConnection.connect(config.connectionOptions);
const worker = await Worker.create({
  connection: workerConnection,
  namespace: config.namespace,
  workflowsPath: require.resolve('./workflows'),
  taskQueue: 'my-task-queue',
  dataConverter,
});
```

External Storage runs outside the Workflow sandbox, so pass the driver object directly. Workflows and Activities use it automatically; business logic does not change.

## Built-in driver behavior

The S3 and GCS drivers:

- Upload and download Payloads concurrently.
- Address objects by a SHA-256 hash of their contents, deduplicating identical Payloads.
- Verify the content hash during retrieval.
- Reject any single Payload larger than `maxPayloadSize`, which defaults to **50 MiB**.
- Include diagnostic metadata in storage errors.

The External Storage threshold does not override `maxPayloadSize`. Configure the backing store and driver for the largest Payload the application needs to support.

## Payload size threshold

- Default: **256 KiB**.
- Set `payloadSizeThreshold: 0` to externalize **all** Payloads regardless of size.
- Payloads whose serialized size is **greater than or equal to** the threshold are eligible for external storage.
- The measured size includes Payload metadata after Payload Converter and Payload Codec processing, not only the raw application value.

```typescript
const dataConverter = {
  externalStorage: new ExternalStorage({
    drivers: [driver],
    payloadSizeThreshold: 0,
  }),
};
```

## Multiple drivers and migration

When registering more than one driver, supply a `driverSelector`. The selector chooses which driver stores each Payload. Unselected registered drivers remain available for **retrieval**, which supports migrations without losing access to existing claims.

- Return `null` from the selector to keep a specific Payload inline in Event History.
- Every registered driver must have a distinct `name`.
- `S3StorageDriver` defaults its name to `"aws.s3driver"`; when registering two S3 drivers, set `driverName` on at least one.

```typescript
const preferredDriver = new S3StorageDriver({
  client: new AwsSdkS3StorageDriverClient(s3Client),
  bucket: 'my-bucket',
});
const legacyDriver = new LegacyStorageDriver();

const externalStorage = new ExternalStorage({
  drivers: [preferredDriver, legacyDriver],
  driverSelector: () => preferredDriver,
});
```

Useful routing patterns include driver migration, hot/cold storage tiers, per-tenant storage, and selecting S3 or GCS based on the runtime environment.

## Custom storage driver

Implement the `StorageDriver` interface with two readonly properties and two methods:

- `name: string` — unique identifier for **this driver instance**, stored in the reference so the SDK can route retrieval. Changing it after Payloads are stored **breaks retrieval**.
- `type: string` — stable identifier for the driver implementation, shared by all instances of that implementation and reported in Worker heartbeats (e.g. `"aws.s3driver"`).
- `store(context, payloads): Promise<StorageDriverClaim[]>` — serialize and upload each Payload, then return one claim per Payload. Each claim contains string key-value data sufficient to find the object later.
- `retrieve(context, claims): Promise<Payload[]>` — download and reconstruct one Payload per claim, preserving input order.

The `store()` context includes an optional `abortSignal` and `target`. The target is a discriminated union:

- Check `target.kind` for `"workflow"` or `"activity"`.
- Read `namespace`, `id`, `runId`, and `type` to scope storage keys.

Honor `abortSignal` in storage calls so sibling operations can be cancelled after the first failure. Content-addressable keys can make retries idempotent and deduplicate identical Payloads.

Return exactly one claim for each Payload passed to `store()` and exactly one Payload for each claim passed to `retrieve()`. Store the complete serialized Payload protobuf: application data has already passed through the Payload Converter and Payload Codec before reaching the driver.

## Multi-region durability with Amazon S3

For regional-failure tolerance, configure S3 Cross-Region Replication and an S3 Multi-Region Access Point (MRAP), then use the MRAP ARN as `bucket`.

MRAP requests require a SigV4A signer. The AWS SDK for JavaScript does not bundle one, so install and register it at application startup:

```bash
npm install @aws-sdk/signature-v4a
```

```typescript
import '@aws-sdk/signature-v4a';
```

Then configure the driver with the MRAP ARN:

```typescript
const driver = new S3StorageDriver({
  client: new AwsSdkS3StorageDriverClient(s3Client),
  bucket: 'arn:aws:s3::123456789012:accesspoint/mfzwi23gnjvgw.mrap',
});
```

`@aws-sdk/signature-v4-crt` is an alternative backed by the AWS Common Runtime. The AWS SDK prefers it when both signer implementations are installed.

Cross-region replication is eventually consistent. Activities reading newly written Payloads from another region need an appropriate Retry Policy. Replication, versioning, and Replication Time Control can add significant cost.

## Codec Server with External Storage

When Workers and Clients use External Storage, Event History contains reference tokens — not payload data. A plain codec server that only implements `/encode` and `/decode` leaves the Web UI and CLI showing raw reference tokens.

The TypeScript SDK does not ship a codec-server handler, so implement the routes yourself (e.g. with Express), wiring in your storage drivers, your pre-storage codecs (the Payload Codecs your Workers use), and any post-storage codecs (applied by a proxy after external storage):

- **`/download`** — retrieves payload data from external storage and decodes it through the Payload Codec. The Web UI calls this when a user clicks to view the full payload behind a reference.
- **`/decode`** — decodes encoded payloads and, by default, retrieves storage references inline. Support `?preserveStorageRefs=true` to return storage references as-is without retrieval; the Web UI uses it to render history without downloading every blob.
- **`/encode`** — applies the Payload Codec, then uploads payloads exceeding the threshold and replaces them with reference tokens.

**Don't point a Worker's remote codec at the storage-aware handler** — it runs the full encode-store-encode and decode-retrieve-decode pipeline. Serve remote codecs from a separate non-storage endpoint, configured with the same codecs.

## Lifecycle and failure handling

Temporal does **not** automatically delete Payloads from the external store. Configure a bucket lifecycle policy with:

```
TTL > Maximum Workflow Run Timeout + Namespace Retention Period
```

Example: Run Timeout 14 days + Namespace retention 30 days → set TTL to at least 44 days.

For Workflows with no finite Run Timeout, there is no safe finite TTL. Use Continue-as-New so the new run uploads fresh Payloads and the old run's Payloads only need to survive its retention period.

The SDK does not retry a failed `store()` or `retrieve()` call within the same Task attempt. The failure fails the current Workflow Task or Activity Task attempt; Temporal then retries the Task as a whole. Storage operations should therefore be idempotent.

## Anti-patterns

- **Don't change a driver's `name` after Payloads have been stored.** The name is embedded in references; changing it breaks retrieval.
- **Don't register duplicate driver names.** Give each instance a unique `name` or `driverName`.
- **Don't register multiple drivers without a `driverSelector`.** Construction fails when more than one driver is registered without one.
- **Don't omit External Storage configuration from a Client or Worker that may retrieve offloaded data.** It cannot resolve the reference without the matching driver.
- **Don't assume the 2 MB Temporal limit is the built-in driver's maximum.** The S3 and GCS drivers default `maxPayloadSize` to 50 MiB.
- **Don't point a Worker's remote codec at a storage-aware codec-server handler.** Serve remote codecs from a separate non-storage endpoint.
- **Don't omit a lifecycle policy.** Payloads are otherwise retained indefinitely, and failed requests can leave orphaned objects.
