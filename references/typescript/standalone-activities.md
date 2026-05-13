# Standalone Activities — TypeScript SDK

Read `references/core/standalone-activities.md` first for the concept, CLI inventory, prerequisites, and Public Preview limitations. This file covers the TypeScript SDK API.

TypeScript SDK support for Standalone Activities is at **Pre-release**.

## Prerequisites

- **Temporal TypeScript SDK v1.17.0 or higher.**
- **Temporal CLI v1.7.0 or higher.**

All `@temporalio/*` packages must share the same version (general TypeScript SDK rule — see `references/typescript/typescript.md`).

Start the dev server:

```bash
temporal server start-dev
```

The Temporal Server is then on `localhost:7233` and the Web UI on `http://localhost:8233`; Standalone Activities are listed in the top-left nav-bar item.

## Writing the Activity

A Standalone Activity is written exactly the same as an Activity orchestrated by a Workflow — the same Activity can be executed both ways.

```typescript
import { ApplicationFailure } from '@temporalio/activity';

export async function greet(name: string): Promise<string> {
  if (typeof name !== 'string') {
    throw ApplicationFailure.create({ message: 'name must be a string', nonRetryable: true });
  }
  return `Hello, ${name}!`;
}
```

## Running the Worker

Worker setup is the same as for Workflow-driven Activities — create a Worker, register the Activity, run the Worker. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

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

`loadClientConnectConfig()` reads environment variables and TOML profiles, so the same code works against a local dev server and Temporal Cloud without changes.

## Typed Activity Client

Call `client.activity.typed<typeof activities>()` to get a typed Activity Client interface. Any TypeScript type whose methods are Activity functions can be used as the type argument — using `typeof` on the imported activities module is the easiest way. Calling `typed` does **not** create a new Client object; it only adjusts the type annotation of the existing Client. `typed` can be called multiple times with different type arguments.

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

## Execute (typed)

Call `execute` on the typed client. An unknown or mistyped Activity name or wrong argument types will cause **compilation** to fail.

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

## Execute (untyped)

When Activity types are not available, call `start` / `execute` directly on `ActivityClient`. Neither the Activity name nor argument types are checked client-side in that mode.

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
});
```

CLI:

```bash
temporal activity execute \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

## Start without waiting for the result

Use the `start` method (on the typed client or the underlying `ActivityClient`) to durably enqueue the Activity without waiting:

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
});
```

CLI:

```bash
temporal activity start \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

## Get a handle to an existing Standalone Activity

`client.activity.getHandle<T>(activityId)` returns a handle. Because the client does not know how the Activity was started, this method is **not** available on the typed interface. The optional type argument constrains the Activity result type but its correctness is not verified.

```typescript
const newHandle = client.activity.getHandle<string>(activityId);
```

Use the handle to wait for the result, describe, cancel, or terminate.

## Wait for the result

`execute` is `start` followed by `await handle.result()`:

```typescript
console.log(await handle.result()); // Hello, Temporal!
```

CLI:

```bash
temporal activity result --activity-id my-standalone-activity-id
```

## List Standalone Activities

`client.activity.list(query)` returns an `AsyncIterable` of `ActivityExecutionInfo` entries matching a List Filter. **These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included.**

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
}
```

The query parameter accepts the same [List Filter](/list-filter) syntax used for Workflow Visibility. Example: `"ActivityType = 'MyActivity' AND Status = 'Running'"`.

## Count Standalone Activities

`client.activity.count(query)` returns the total count of executions (running, completed, failed, etc.) — **not** the number of queued tasks. The same query works for both `list` and `count`.

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`);
```

## Run with Temporal Cloud

`loadClientConnectConfig` lets the same code work against Temporal Cloud — set the connection via env vars or TOML, no code changes.

mTLS:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

API key:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

## Common mistakes

1. **Calling `client.activity.execute` / `start` from inside a Workflow Definition.** These are for application code. Inside a Workflow, use `proxyActivities` (see `references/typescript/typescript.md`).
2. **Expecting the typed client to validate `getHandle`.** `getHandle` is intentionally not on the typed interface — its result type argument is not verified.
3. **Expecting `client.activity.list` / `count` to include Workflow-driven Activities.** They don't.
4. **Forgetting that the `args` array is sent as the Activity arguments.** In the typed `execute` / `start`, the Activity inputs go in `args: [...]`, not in positional parameters.

