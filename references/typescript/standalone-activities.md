> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are Activities run independently of any Workflow, started directly from a Temporal Client — useful when you need a single durable, retryable task (job-queue style) and not multi-step orchestration. The same Activity method can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.

Standalone Activities are conceptually the same across all SDKs. Read the [cross-SDK concept file](references/core/standalone-activities.md) if you have not already, and then see below for the TypeScript SDK specific APIs for calling Standalone Activities.

## Prerequisites

- Temporal TypeScript SDK v1.17.0 or higher.
- All `@temporalio/*` packages must be pinned to the same version (heads-up — install/upgrade them together).
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](references/core/install_cli.md) if needed. Dev server includes Standalone Activities support.
- For production, Temporal Server v1.31.0 or higher (or Temporal Cloud).

## Hosting Activities on a Worker

The Activity is defined just as activities normally are in Temporal. Worker registration is also the same.

```typescript
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';
import { loadClientConnectConfig } from '@temporalio/envconfig';

async function run() {
  const config = loadClientConnectConfig();
  const connection = await NativeConnection.connect(config.connectionOptions);
  const worker = await Worker.create({
    connection,
    taskQueue: 'hello-standalone-activities',
    activities, // register whatever your activity(ies) is/are
  });
  await worker.run();
}

run().catch(console.error);
```

## Calling and managing Standalone Activities

Start and manage Standalone Activities from your application code using the Temporal Client.

### Do not call from inside a Workflow

Don't call `client.activity.execute` / `client.activity.start` or any other Standalone Activity APIs from inside a Workflow Definition — use Workflow-side activity invocation (`proxyActivities`) instead.

### Connect a Client

The Standalone Activity operations are methods on `client.activity`, where `client` is a connected `Client`. The examples below assume this `client`.

```typescript
import { Connection, Client } from '@temporalio/client';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await Connection.connect(config.connectionOptions);
const client = new Client({ connection });
```

### Execute with type checking

Call `client.activity.typed<typeof activities>()` to obtain a typed Activity Client interface.  Calling `typed` does not create a new Client object — it only adjusts the type annotation of the existing Client.  Unknown or mistyped Activity names, or wrong argument types, fail at compile time.

```typescript
import * as activities from './activities';
import { nanoid } from 'nanoid';

const activitiesClient = client.activity.typed<typeof activities>();

const activityOptions = {
  taskQueue: 'hello-standalone-activities',
  startToCloseTimeout: '10s',
};

const activityId = nanoid();

const result = await activitiesClient.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: ['World'],
});
```

### Execute without type checking

Call `execute` or `start` directly on `client.activity` when Activity types aren't available. Neither the Activity name nor argument types are checked client-side.

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
});
```

### Start without waiting

Use `client.activity.start(...)` (or `activitiesClient.start(...)` on the typed interface) to durably enqueue the Activity and get back a handle without waiting for completion.

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
});
```

### Get a handle to an existing Activity

Use `client.activity.getHandle<string>(activityId)` to construct a handle to a previously started Standalone Activity.  `getHandle` is not available on the typed interface.  The optional type argument constrains the result type but correctness is not verified.

```typescript
const newHandle = client.activity.getHandle<string>(activityId);
```

The handle can be used to wait for the result, describe, cancel, or terminate the Activity.

### Wait for the result later

`execute` is equivalent to `start` followed by `await handle.result()`.

```typescript
console.log(await handle.result());
```

### List Standalone Activities

`client.activity.list(query)` returns an `AsyncIterable<ActivityExecutionInfo>` of entries that match a [List Filter](/list-filter) query.  Only Standalone Activity Executions are included; Activities running inside Workflows are not.  Each entry exposes `activityId`, `activityRunId`, `activityType`, `status`, and `closeTime`.

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
}
```

### Count Standalone Activities

`client.activity.count(query)` returns `{ count }` — the total count of executions (running, completed, failed, etc.) matching a List Filter query, not the number of queued tasks.

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`);
```