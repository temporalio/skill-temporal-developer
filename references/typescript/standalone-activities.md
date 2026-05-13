# Standalone Activities — TypeScript SDK

## Overview

Standalone Activities are Activities that run independently, without being orchestrated by a Workflow; instead of starting an Activity from within a Workflow Definition, you start a Standalone Activity directly from a Temporal Client. <!-- docs/develop/typescript/activities/standalone-activities.mdx:29 --> The way you write the Activity and register it with a Worker is identical to Workflow Activities — the only difference is that you execute a Standalone Activity directly from your Temporal Client. <!-- docs/develop/typescript/activities/standalone-activities.mdx:33 --> In fact, an Activity can be executed both as a Standalone Activity and as a Workflow Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:127 -->

## Support stage

Temporal TypeScript SDK support for Standalone Activities is at **Pre-release**. <!-- docs/develop/typescript/activities/standalone-activities.mdx:24 -->

Prerequisites:

- **Temporal TypeScript SDK** v1.17.0 or higher. <!-- docs/develop/typescript/activities/standalone-activities.mdx:62 -->
- **Temporal CLI** v1.7.0 or higher. <!-- docs/develop/typescript/activities/standalone-activities.mdx:64 -->

Start the Temporal development server:

```bash
temporal server start-dev
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:82 -->

The Temporal Server will be available for client connections on `localhost:7233`, and the Temporal Web UI at [http://localhost:8233](http://localhost:8233). Standalone Activities are available from the nav bar item located towards the top left of the page. <!-- docs/develop/typescript/activities/standalone-activities.mdx:101 -->

## Write the Activity

The way you write a Standalone Activity is identical to how you write an Activity to be orchestrated by a Workflow. <!-- docs/develop/typescript/activities/standalone-activities.mdx:126 -->

```typescript
import { ApplicationFailure } from '@temporalio/activity';

export async function greet(name: string): Promise<string> {
  if (typeof name !== 'string') {
    throw ApplicationFailure.create({ message: 'name must be a string', nonRetryable: true });
  }
  return `Hello, ${name}!`;
}
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:132 -->

## Worker

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — you create a Worker, register the Activity, and run the Worker. The Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:145 -->

```typescript
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';
import { loadClientConnectConfig } from '@temporalio/envconfig';

async function run() {
  const config = loadClientConnectConfig();
  const connection = await NativeConnection.connect(config.connectionOptions);
  try {
    const worker = await Worker.create({
      connection,
      namespace: 'default',
      taskQueue: 'hello-standalone-activities',
      activities,
    });
    await worker.run();
  } finally {
    await connection.close();
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:153 -->

## Execute with type checking

Start by creating a Temporal Client. Then call `client.activity.typed()` to get a typed Activity Client interface. Any TypeScript type can be used as the type argument as long as it has Activity functions as its methods. An easy way to provide such a type is to use the `typeof` operator on imported activities. Note that calling `typed` does not create a new Client object — it only adjusts the type annotation of the existing Client. `typed` can be called multiple times with different type arguments to use the same Client for multiple Activity interfaces. <!-- docs/develop/typescript/activities/standalone-activities.mdx:206 -->

```typescript
import { Connection, Client, ActivityExecutionFailedError } from '@temporalio/client';
import { loadClientConnectConfig } from '@temporalio/envconfig';
import * as activities from './activities';
import { nanoid } from 'nanoid';

const config = loadClientConnectConfig();
const connection = await Connection.connect(config.connectionOptions);
const client = new Client({ connection });

const activitiesClient = client.activity.typed<typeof activities>();
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:214 -->

Call the `execute` method of the typed client to execute a Standalone Activity. Call this from your application code, not from inside a Workflow Definition. This durably enqueues your Standalone Activity in the Temporal Server, waits for it to be executed on your Worker, and then fetches the result. An unknown or mistyped Activity name, or wrong argument types, will cause compilation to fail. <!-- docs/develop/typescript/activities/standalone-activities.mdx:227 -->

```typescript
const taskQueue = 'hello-standalone-activities';
const activityOptions = {
  taskQueue,
  startToCloseTimeout: '10s',
};

// In practice, use a meaningful business identifier, like customer or transaction identifier
const activityId = nanoid();

const result = await activitiesClient.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: ['World'],
});
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:234 -->

## Execute without type checking

Since Activity types are not always available, the `start` and `execute` methods can be called on `ActivityClient` directly without using the typed interface. When called that way, neither the Activity name nor argument types are checked client-side. <!-- docs/develop/typescript/activities/standalone-activities.mdx:252 -->

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
});
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:258 -->

## Start without waiting for the result

Starting a Standalone Activity means sending a request to the Temporal Server to durably enqueue your Activity job, without waiting for it to be executed by your Worker. Use the `start` method of the client or the typed interface to start your Standalone Activity and get a handle. <!-- docs/develop/typescript/activities/standalone-activities.mdx:279 -->

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
});
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:286 -->

## Get a handle to an existing Standalone Activity

You can use `getHandle` to create a handle to a previously started Standalone Activity. Because the client doesn't know how the Activity was started, this method is not available in the typed interface. The method takes an optional type argument to constrain the Activity result type, but correctness of this argument is not verified. <!-- docs/develop/typescript/activities/standalone-activities.mdx:307 -->

```typescript
const newHandle = client.activity.getHandle<string>(activityId);
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:313 -->

You can then use the handle to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:317 -->

## Wait for the result

Calling `execute` is the same as calling `start` to durably enqueue the Standalone Activity, and then calling `await handle.result()` to wait for the Activity to be executed and fetch the result. <!-- docs/develop/typescript/activities/standalone-activities.mdx:321 -->

```typescript
console.log(await handle.result()); // Hello, Temporal!
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:327 -->

## List Standalone Activities

Use the `list` method of the client to list Standalone Activity Executions that match a List Filter query. The result is an `AsyncIterable` that yields `ActivityExecutionInfo` entries. <!-- docs/develop/typescript/activities/standalone-activities.mdx:338 --> These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included. <!-- docs/develop/typescript/activities/standalone-activities.mdx:344 -->

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
}
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:346 -->

The query parameter accepts the same List Filter syntax used for Workflow Visibility, for example `"ActivityType = 'MyActivity' AND Status = 'Running'"`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:372 -->

## Count Standalone Activities

Use the `count` method of the client to count Standalone Activity Executions that match a List Filter query. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. It works the same way as counting Workflow Executions; the same query will work for both listing and counting. <!-- docs/develop/typescript/activities/standalone-activities.mdx:378 -->

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`);
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:385 -->

## CLI parity

The Temporal CLI exposes the same set of operations for Standalone Activities.

### Execute

```bash
temporal activity execute \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:268 -->

### Start

```bash
temporal activity start \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:296 -->

### Wait for the result

```bash
temporal activity result --activity-id my-standalone-activity-id
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:332 -->

### List

```bash
temporal activity list
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:368 -->

### Count

```bash
temporal activity count
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:402 -->

## Connect via env config

The code samples use `loadClientConnectConfig()` from `@temporalio/envconfig` to configure the Temporal Client connection. It responds to environment variables and TOML configuration files, so the same code works against a local dev server and Temporal Cloud without changes. <!-- docs/develop/typescript/activities/standalone-activities.mdx:91 -->

The same `loadClientConnectConfig` mechanism applies to Temporal Cloud — just configure the connection via environment variables or a TOML profile; no code changes are needed. <!-- docs/develop/typescript/activities/standalone-activities.mdx:408 -->

### Connect with mTLS

Set these environment variables with values from your Temporal Cloud Namespace settings:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:420 -->

### Connect with an API key

Set these environment variables with values from your Temporal Cloud API key settings:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:431 -->
