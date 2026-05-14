<!-- The TypeScript SDK marks this feature as Pre-release in docs/develop/typescript/activities/standalone-activities.mdx:25; the encyclopedia page marks the cross-SDK feature as Public Preview in docs/encyclopedia/activities/standalone-activity.mdx:23. -->

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are top-level Activity Executions started directly by a Temporal Client without a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:50-51 --> Use them when you need to run a single durable, retryable Activity instead of orchestrating multiple steps in a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:31-32 --> See the cross-SDK concept page at [/standalone-activity](/standalone-activity) for the full feature overview. <!-- docs/encyclopedia/activities/standalone-activity.mdx:6 -->

The Activity Function itself is written the same way as a Workflow Activity; the same function can run as either with no code changes. <!-- docs/develop/typescript/activities/standalone-activities.mdx:33-35 -->

## Hard guardrail

Don't call `client.activity.execute` / `client.activity.start` from inside a Workflow Definition — use Workflow-side activity invocation (`proxyActivities`) instead. <!-- docs/develop/typescript/activities/standalone-activities.mdx:228-229 -->

## Prerequisites

- Temporal TypeScript SDK v1.17.0 or higher. <!-- docs/develop/typescript/activities/standalone-activities.mdx:62 -->
- All `@temporalio/*` packages must be pinned to the same version (heads-up — install/upgrade them together).
- Temporal CLI v1.7.0 or higher; see [references/core/install_cli.md](../core/install_cli.md). <!-- docs/develop/typescript/activities/standalone-activities.mdx:64 -->

## Worker setup

Worker registration is identical to a Workflow-Activity Worker — register the Activity functions and run the Worker. <!-- docs/develop/typescript/activities/standalone-activities.mdx:145-149 -->

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
<!-- docs/develop/typescript/activities/standalone-activities.mdx:153-178 -->

## Execute with type checking

Call `client.activity.typed<typeof activities>()` to obtain a typed Activity Client interface. <!-- docs/develop/typescript/activities/standalone-activities.mdx:207-212 --> Calling `typed` does not create a new Client object — it only adjusts the type annotation of the existing Client. <!-- docs/develop/typescript/activities/standalone-activities.mdx:210-212 --> Unknown or mistyped Activity names, or wrong argument types, fail at compile time. <!-- docs/develop/typescript/activities/standalone-activities.mdx:230-231 -->

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
<!-- docs/develop/typescript/activities/standalone-activities.mdx:214-248 -->

## Execute without type checking

Call `execute` or `start` directly on `client.activity` when Activity types aren't available. Neither the Activity name nor argument types are checked client-side. <!-- docs/develop/typescript/activities/standalone-activities.mdx:252-256 -->

```typescript
await client.activity.execute('greet', {
  ...activityOptions,
  id: activityId,
  args: [1],
});
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:259-264 -->

## Start without waiting

Use `client.activity.start(...)` (or `activitiesClient.start(...)` on the typed interface) to durably enqueue the Activity and get back a handle without waiting for completion. <!-- docs/develop/typescript/activities/standalone-activities.mdx:279-284 -->

```typescript
const handle = await activitiesClient.start('greet', {
  ...activityOptions,
  id: activityId,
  args: ['Temporal'],
});
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:287-292 -->

## Get a handle to an existing Activity

Use `client.activity.getHandle<string>(activityId)` to construct a handle to a previously started Standalone Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:307-314 --> `getHandle` is not available on the typed interface. <!-- docs/develop/typescript/activities/standalone-activities.mdx:308-309 --> The optional type argument constrains the result type but correctness is not verified. <!-- docs/develop/typescript/activities/standalone-activities.mdx:310-311 -->

```typescript
const newHandle = client.activity.getHandle<string>(activityId);
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:314 -->

The handle can be used to wait for the result, describe, cancel, or terminate the Activity. <!-- docs/develop/typescript/activities/standalone-activities.mdx:317 -->

## Wait for the result later

`execute` is equivalent to `start` followed by `await handle.result()`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:321-324 -->

```typescript
console.log(await handle.result());
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:327 -->

## List Standalone Activities

`client.activity.list(query)` returns an `AsyncIterable<ActivityExecutionInfo>` of entries that match a [List Filter](/list-filter) query. <!-- docs/develop/typescript/activities/standalone-activities.mdx:339-342 --> Only Standalone Activity Executions are included; Activities running inside Workflows are not. <!-- docs/develop/typescript/activities/standalone-activities.mdx:344 --> Each entry exposes `activityId`, `activityRunId`, `activityType`, `status`, and `closeTime`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:349-353 -->

```typescript
const query = 'TaskQueue="hello-standalone-activities"';

for await (const a of client.activity.list(query)) {
  console.log(
    `${a.activityId} | ${a.activityRunId} | ${a.activityType} | ${a.status} | ${a.closeTime?.toISOString()}`,
  );
}
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:347-354 -->

## Count Standalone Activities

`client.activity.count(query)` returns `{ count }` — the total count of executions (running, completed, failed, etc.) matching a List Filter query, not the number of queued tasks. <!-- docs/develop/typescript/activities/standalone-activities.mdx:378-383 -->

```typescript
const { count } = await client.activity.count(query);
console.log(`Total activities: ${count}`);
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:386-387 -->

## Temporal CLI mirror

The `temporal activity` subcommand supports `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:136-137 -->

Execute (wait for result):

```bash
temporal activity execute \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:269-275 -->

Start (do not wait):

```bash
temporal activity start \
  --type greet \
  --activity-id my-standalone-activity-id \
  --task-queue hello-standalone-activities \
  --start-to-close-timeout 10s \
  --input '"World"'
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:297-303 -->

Fetch a result by Activity Id:

```bash
temporal activity result --activity-id my-standalone-activity-id
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:333 -->

List and count:

```bash
temporal activity list
temporal activity count
```
<!-- docs/develop/typescript/activities/standalone-activities.mdx:369 --><!-- docs/develop/typescript/activities/standalone-activities.mdx:403 -->

The `--input` value is JSON-encoded, so a string argument is passed as `'"World"'` (single-quoted JSON string). <!-- docs/develop/typescript/activities/standalone-activities.mdx:274 -->

## Temporal Cloud

The same code works against Temporal Cloud because `loadClientConnectConfig()` reads TOML profiles and environment variables, so no code changes are needed. <!-- docs/develop/typescript/activities/standalone-activities.mdx:408-410 --> For mTLS or API-key environment variable setup, see the "Connect with mTLS" and "Connect with an API key" sections of `docs/develop/typescript/activities/standalone-activities.mdx`. <!-- docs/develop/typescript/activities/standalone-activities.mdx:416-435 -->

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview but scheduled for GA. <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->

## Activity context inside a Standalone Activity

<!-- VERIFY: Which fields of the `@temporalio/activity` `Context` (e.g., `Context.current().info`) and which payload-converter / data-converter context fields change nullability when the Activity runs as a Standalone Activity (no parent Workflow)? Docs are silent in `docs/encyclopedia/activities/standalone-activity.mdx` and `docs/develop/typescript/activities/standalone-activities.mdx` as of this authoring pass. -->
