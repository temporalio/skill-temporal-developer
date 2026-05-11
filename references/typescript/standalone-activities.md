# TypeScript: Standalone Activities

Standalone Activities are Activities that run independently of a Workflow. <!-- docs/develop/typescript/activities/standalone-activities.mdx:29-31 --> Instead of starting an Activity from inside a Workflow Definition, you start it directly from a Temporal Client. The way you write the Activity function and register it with a Worker is identical to a Workflow Activity; the only difference is how it is invoked. <!-- docs/develop/typescript/activities/standalone-activities.mdx:33-35 -->

## Prerequisites

- Temporal TypeScript SDK v1.17.0 or higher. <!-- docs/develop/typescript/activities/standalone-activities.mdx:62 -->
- Temporal CLI v1.7.0 or higher. <!-- docs/develop/typescript/activities/standalone-activities.mdx:64 -->
- TypeScript SDK support for Standalone Activities is at Pre-release. <!-- docs/develop/typescript/activities/standalone-activities.mdx:22-27 -->

## Write an Activity

An Activity used as a Standalone Activity is written exactly like any other Activity. The example below throws a non-retryable `ApplicationFailure` for invalid input. <!-- docs/develop/typescript/activities/standalone-activities.mdx:124-141 -->

```typescript
import { ApplicationFailure } from '@temporalio/activity'; // docs/develop/typescript/activities/standalone-activities.mdx:133

export async function greet(name: string): Promise<string> {
  if (typeof name !== 'string') {
    throw ApplicationFailure.create({ message: 'name must be a string', nonRetryable: true });
  }
  return `Hello, ${name}!`;
}
```

## Run a Worker

Workers for Standalone Activities are configured exactly like Workers for Workflow Activities — the Worker does not need to know whether the Activity will be invoked from a Workflow or directly from a Client. <!-- docs/develop/typescript/activities/standalone-activities.mdx:145-149 -->

```typescript
import { NativeConnection, Worker } from '@temporalio/worker'; // docs/develop/typescript/activities/standalone-activities.mdx:154
import * as activities from './activities';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await NativeConnection.connect(config.connectionOptions);
const worker = await Worker.create({
  connection,
  namespace: 'default',
  taskQueue: 'hello-standalone-activities',
  activities,
}); // docs/develop/typescript/activities/standalone-activities.mdx:162-167
await worker.run();
```

## Typed vs untyped client

Call `client.activity.typed<typeof activities>()` to obtain a typed Activity Client interface. <!-- docs/develop/typescript/activities/standalone-activities.mdx:207-212 --> Any TypeScript type whose methods are Activity functions works as the type argument; using `typeof` on imported Activities is the easy path. Calling `typed` does not create a new Client object — it only adjusts the type annotation of the existing Client, and `typed` may be called multiple times with different type arguments against the same Client. <!-- docs/develop/typescript/activities/standalone-activities.mdx:209-212 -->

An unknown or mistyped Activity name, or wrong argument types, causes compilation to fail when using the typed interface. <!-- docs/develop/typescript/activities/standalone-activities.mdx:230-231 -->

```typescript
import { Connection, Client } from '@temporalio/client'; // docs/develop/typescript/activities/standalone-activities.mdx:215
import { loadClientConnectConfig } from '@temporalio/envconfig';
import * as activities from './activities';

const config = loadClientConnectConfig();
const connection = await Connection.connect(config.connectionOptions);
const client = new Client({ connection });

const activitiesClient = client.activity.typed<typeof activities>(); // docs/develop/typescript/activities/standalone-activities.mdx:224
```

## Execute a Standalone Activity (typed)

Call `execute` on the typed Activity Client from your application code (not from inside a Workflow Definition). This durably enqueues the Standalone Activity in the Temporal Server, waits for it to run on a Worker, and returns the result. <!-- docs/develop/typescript/activities/standalone-activities.mdx:227-231 -->

```typescript
const taskQueue = 'hello-standalone-activities';
const activityOptions = {
  taskQueue,
  startToCloseTimeout: '10s',
}; // docs/develop/typescript/activities/standalone-activities.mdx:234-238

const activityId = nanoid(); // use a meaningful business identifier in practice

const result = await activitiesClient.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: ['World'],
}); // docs/develop/typescript/activities/standalone-activities.mdx:243-247
```

## Execute without type checking

`execute` and `start` are also available directly on `client.activity` (the `ActivityClient`) without going through the typed adapter. When called this way, neither the Activity name nor argument types are checked client-side. <!-- docs/develop/typescript/activities/standalone-activities.mdx:252-256 -->

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
}); // docs/develop/typescript/activities/standalone-activities.mdx:259-263
```

## Start without waiting for the result

Starting a Standalone Activity sends a request to the Temporal Server to durably enqueue the Activity job, without waiting for it to complete on a Worker. `start` returns a handle. <!-- docs/develop/typescript/activities/standalone-activities.mdx:279-284 -->

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
}); // docs/develop/typescript/activities/standalone-activities.mdx:287-291
```

CLI equivalent:

```bash
temporal activity start \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
# docs/develop/typescript/activities/standalone-activities.mdx:297-302
```

## Get a handle to an existing Standalone Activity

Use `client.activity.getHandle<T>(activityId)` to build a handle to a previously started Standalone Activity. Because the Client does not know how the Activity was started, this method is not available in the typed interface — only on the untyped `ActivityClient`. The optional type argument constrains the Activity result type, but its correctness is not verified. <!-- docs/develop/typescript/activities/standalone-activities.mdx:305-311 -->

```typescript
const newHandle = client.activity.getHandle<string>(activityId); // docs/develop/typescript/activities/standalone-activities.mdx:314
```

Handles let you wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:317 -->

## Wait for the result

`execute` is equivalent to `start` followed by `await handle.result()`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:321-324 -->

```typescript
console.log(await handle.result()); // docs/develop/typescript/activities/standalone-activities.mdx:327
```

CLI equivalent — wait for a result by Activity Id:

```bash
temporal activity result --activity-id my-standalone-activity-id
# docs/develop/typescript/activities/standalone-activities.mdx:333
```

## List Standalone Activities

`client.activity.list(query)` lists Standalone Activity Executions matching a List Filter query. It returns an `AsyncIterable` of `ActivityExecutionInfo` entries. <!-- docs/develop/typescript/activities/standalone-activities.mdx:338-342 -->

These APIs return ONLY Standalone Activity Executions. Activities running inside Workflows are not included. <!-- docs/develop/typescript/activities/standalone-activities.mdx:344 -->

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
} // docs/develop/typescript/activities/standalone-activities.mdx:347-353
```

The query parameter accepts the same List Filter syntax used for Workflow Visibility, e.g. `ActivityType = 'MyActivity' AND Status = 'Running'`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:372-373 -->

<!-- VERIFY: Are ActivityExecutionInfo fields like activityRunId / closeTime ever undefined at runtime? The doc uses `closeTime?.toISOString()` (optional chaining) but does not formally describe nullability. -->

## Count Standalone Activities

`client.activity.count(query)` returns the total count of Standalone Activity Executions matching a List Filter (running, completed, failed, etc.) — not the number of queued tasks. The same query works for both `list` and `count`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:378-383 -->

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`); // docs/develop/typescript/activities/standalone-activities.mdx:386-387
```

## CLI equivalents

```bash
temporal activity execute \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
# docs/develop/typescript/activities/standalone-activities.mdx:269-274

temporal activity list   # docs/develop/typescript/activities/standalone-activities.mdx:369
temporal activity count  # docs/develop/typescript/activities/standalone-activities.mdx:403
```

## Temporal Cloud

The samples on this page use `loadClientConnectConfig()`, which reads environment variables or a TOML profile, so the same code works against a local dev server and Temporal Cloud without changes. <!-- docs/develop/typescript/activities/standalone-activities.mdx:92-97 -->

Connect with mTLS — set:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
# docs/develop/typescript/activities/standalone-activities.mdx:421-424
```

Connect with an API key — set:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
# docs/develop/typescript/activities/standalone-activities.mdx:432-434
```

## See also

- `references/core/standalone-activities.md` — concepts, version compatibility matrix, CLI inventory, and Public Preview limitations (Pause / Reset / Update Options are not supported in Public Preview).
