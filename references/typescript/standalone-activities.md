

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are top-level Activity Executions started directly by a Temporal Client without a Workflow.  Use them when you need to run a single durable, retryable Activity instead of orchestrating multiple steps in a Workflow.  See the cross-SDK concept page at [/standalone-activity](/standalone-activity) for the full feature overview.

The Activity Function itself is written the same way as a Workflow Activity; the same function can run as either with no code changes.

## Hard guardrail

Don't call `client.activity.execute` / `client.activity.start` from inside a Workflow Definition — use Workflow-side activity invocation (`proxyActivities`) instead.

## Prerequisites

- Temporal TypeScript SDK v1.17.0 or higher.
- All `@temporalio/*` packages must be pinned to the same version (heads-up — install/upgrade them together).
- Temporal CLI v1.7.0 or higher; see [references/core/install_cli.md](../core/install_cli.md).

## Worker setup

Worker registration is identical to a Workflow-Activity Worker — register the Activity functions and run the Worker.

```typescript
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await NativeConnection.connect(config.connectionOptions);
const worker = await Worker.create({
  connection,
  namespace: 'default',
  taskQueue: 'hello-standalone-activities',
  activities,
});
await worker.run();
```

## Execute with type checking

Call `client.activity.typed<typeof activities>()` to obtain a typed Activity Client interface.  Calling `typed` does not create a new Client object — it only adjusts the type annotation of the existing Client.  Unknown or mistyped Activity names, or wrong argument types, fail at compile time.

```typescript
import { Connection, Client } from '@temporalio/client';
import { loadClientConnectConfig } from '@temporalio/envconfig';
import * as activities from './activities';
import { nanoid } from 'nanoid';

const config = loadClientConnectConfig();
const connection = await Connection.connect(config.connectionOptions);
const client = new Client({ connection });

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

## Execute without type checking

Call `execute` or `start` directly on `client.activity` when Activity types aren't available. Neither the Activity name nor argument types are checked client-side.

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
});
```

## Start without waiting

Use `client.activity.start(...)` (or `activitiesClient.start(...)` on the typed interface) to durably enqueue the Activity and get back a handle without waiting for completion.

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
});
```

## Get a handle to an existing Activity

Use `client.activity.getHandle<string>(activityId)` to construct a handle to a previously started Standalone Activity.  `getHandle` is not available on the typed interface.  The optional type argument constrains the result type but correctness is not verified.

```typescript
const newHandle = client.activity.getHandle<string>(activityId);
```

The handle can be used to wait for the result, describe, cancel, or terminate the Activity.

## Wait for the result later

`execute` is equivalent to `start` followed by `await handle.result()`.

```typescript
console.log(await handle.result());
```

## List Standalone Activities

`client.activity.list(query)` returns an `AsyncIterable<ActivityExecutionInfo>` of entries that match a [List Filter](/list-filter) query.  Only Standalone Activity Executions are included; Activities running inside Workflows are not.  Each entry exposes `activityId`, `activityRunId`, `activityType`, `status`, and `closeTime`.

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
}
```

## Count Standalone Activities

`client.activity.count(query)` returns `{ count }` — the total count of executions (running, completed, failed, etc.) matching a List Filter query, not the number of queued tasks.

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`);
```

## Temporal CLI mirror

The `temporal activity` subcommand supports `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate`.

Execute (wait for result):

```bash
temporal activity execute \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

Start (do not wait):

```bash
temporal activity start \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```

Fetch a result by Activity Id:

```bash
temporal activity result --activity-id my-standalone-activity-id
```

List and count:

```bash
temporal activity list
temporal activity count
```

The `--input` value is JSON-encoded, so a string argument is passed as `'"World"'` (single-quoted JSON string).

## Temporal Cloud

The same code works against Temporal Cloud because `loadClientConnectConfig()` reads TOML profiles and environment variables, so no code changes are needed.  For mTLS or API-key environment variable setup, see the "Connect with mTLS" and "Connect with an API key" sections of `docs/develop/typescript/activities/standalone-activities.mdx`.

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview but scheduled for GA.
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet.

## Activity context inside a Standalone Activity

