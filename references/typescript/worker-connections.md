# Worker Connections (TypeScript SDK)

How a TypeScript Worker connects to the Temporal Service, and how its connection is owned and shut down.

## TL;DR

A TypeScript Worker connects to the Temporal Service through a **`NativeConnection`** object, imported from `@temporalio/worker`. The connection is created with `NativeConnection.connect(options)`, passed to `Worker.create({ connection, ... })`, and closed after the Worker stops.

```ts
import { NativeConnection, Worker } from '@temporalio/worker';

const connection = await NativeConnection.connect({ address: 'localhost:7233' });
try {
  const worker = await Worker.create({
    connection,
    namespace: 'default',
    taskQueue: 'hello-world',
    workflowsPath: require.resolve('./workflows'),
    activities,
  });
  await worker.run();
} finally {
  await connection.close();
}
```

## `NativeConnection` vs. `Connection`

The TypeScript SDK exposes two connection classes against the same Temporal Service:

| Class | Imported from | Used by |
|---|---|---|
| `NativeConnection` | `@temporalio/worker` | Worker code |
| `Connection` | `@temporalio/client` | Application code or code inside an Activity, typically through a `Client` |

"Both connection classes accept the same set of connection options."

The two are not interchangeable in imports — `import { NativeConnection } from '@temporalio/client'` will not work, and neither will `import { Connection } from '@temporalio/worker'`.

## Creating the connection

`NativeConnection.connect(options)` is `async`; it returns a `NativeConnection` after the connection is established.

The documented options shown in `docs/develop/typescript/`:

- `address` — the Temporal Service gRPC endpoint, e.g. `'localhost:7233'`.
- `tls` — TLS configuration; `true` to enable, or an object with cert/key data for mTLS.
- `apiKey` — API key value for Temporal Cloud API-key authentication.

The worker.ts skeleton from the setup guide reminds readers: `// TLS and gRPC metadata configuration goes here.` — additional connection knobs exist on the connection options object, but only the keys above are shown in `docs/develop/typescript/`.

### Three ways to supply options

The TypeScript client docs document the same three input modes for both `Connection` and `NativeConnection`: a TOML configuration file (loaded via `loadClientConnectConfig` from `@temporalio/envconfig`), environment variables, or in-code values.

**Config file or env vars (via `@temporalio/envconfig`):**

```ts
import { NativeConnection } from '@temporalio/worker';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await NativeConnection.connect(config.connectionOptions);
```

**In code (Temporal Cloud with API key):**

```ts
import { NativeConnection } from '@temporalio/worker';

const connection = await NativeConnection.connect({
  address: '<endpoint>',
  tls: true,
  apiKey: '<APIKey>',
});
```

## Passing the connection to the Worker

A `Worker` consumes a `NativeConnection` via the `connection` option of `Worker.create`:

```ts
const worker = await Worker.create({
  connection,
  namespace: 'default',
  taskQueue: 'hello-world',
  workflowsPath: require.resolve('./workflows'),
  activities,
});
```

For Temporal Cloud, set `namespace` to `<namespace_id>.<account_id>`.

## Closing the connection

The documented pattern is: open the connection, register and run the Worker inside `try`, and close the connection in `finally` once the Worker has stopped.

```ts
try {
  const worker = await Worker.create({ connection, /* … */ });
  await worker.run();
} finally {
  // Close the connection once the worker has stopped
  await connection.close();
}
```

`await worker.run()` returns when the Worker reaches the `STOPPED` state — only then is it safe to close the connection.

## Updating credentials on a live connection

The docs explicitly show one mutation method, **on the client-side `Connection` only**:

```ts
// connection here is a `Connection` from `@temporalio/client`, not a `NativeConnection`.
connection.setApiKey(<APIKey>);
```

Until those APIs are documented, the documented lifecycle for changing credentials is: stop the Worker, close the existing `NativeConnection`, create a new `NativeConnection` with the updated options, and start a new Worker.

## Connecting from inside an Activity

Activities use the client-side classes, not `NativeConnection`. From within an Activity, you typically use a `Client` (which manages a `Connection`), not the Worker's `NativeConnection`.

## Quick checklist

- Worker code: `import { NativeConnection, Worker } from '@temporalio/worker'`.
- Client/Activity code: `import { Connection, Client } from '@temporalio/client'`.
- Always `await connection.close()` after `await worker.run()` resolves, inside `finally`.
- Prefer `loadClientConnectConfig()` from `@temporalio/envconfig` over hard-coding options — the same code then works against a local dev server and Temporal Cloud.
- For Worker tuning options (`maxConcurrentWorkflowTaskExecutions`, `shutdownGraceTime`, etc.), see `references/typescript/advanced-features.md`; they are separate from connection lifecycle.
- For the matching client-side connection (Connection, Client, `setApiKey` rotation), see `docs/develop/typescript/client/temporal-client.mdx`.

## Sources

- `docs/develop/typescript/set-up.mdx` (Worker creation skeleton, close pattern).
- `docs/develop/typescript/client/temporal-client.mdx` (`Connect to Temporal Service from a Worker`, `NativeConnection vs. Connection`, `setApiKey` on the client `Connection`).
- `docs/develop/typescript/activities/standalone-activities.mdx` (worker wired through `loadClientConnectConfig`).
- `docs/develop/typescript/workers/run-process.mdx` (Worker shutdown states; `worker.run()` resolves on `STOPPED`).
