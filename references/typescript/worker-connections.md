# TypeScript SDK Worker Connections

How a TypeScript Worker connects to the Temporal Service, and what is documented about managing that connection over the Worker's lifetime.

## `NativeConnection` vs `Connection`

The TypeScript SDK has two connection classes:

- **`NativeConnection`** from `@temporalio/worker` — used by Workers.
- **`Connection`** from `@temporalio/client` — used by a Temporal Application or by code inside an Activity (typically wrapped by `Client`).

Both classes accept the same set of connection options.

Do not import `NativeConnection` from `@temporalio/client`, and do not pass a client `Connection` into `Worker.create()`. They are distinct types.

## Build a connection and hand it to the Worker

```typescript
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';

async function run() {
  const connection = await NativeConnection.connect({
    address: 'localhost:7233',
    // TLS and gRPC metadata configuration goes here.
  });
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
}
```

Key points:

- `NativeConnection.connect(options)` returns a `NativeConnection`.
- Pass the resulting object as the `connection` field of `Worker.create()`.
- Call `await connection.close()` in a `finally` block after `worker.run()` resolves.

If you omit `connection`, the Worker connects to `localhost` by default.

## Load options from `@temporalio/envconfig`

For deployments, load connection options from a TOML profile or environment variables instead of hard-coding them:

```typescript
import { NativeConnection } from '@temporalio/worker';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await NativeConnection.connect(config.connectionOptions);
```

`loadClientConnectConfig` reads `~/.config/temporalio/temporal.toml` (or the path in `TEMPORAL_CONFIG_FILE`) plus standard `TEMPORAL_*` environment variables; env vars take precedence over file values.

## Temporal Cloud

A Worker connecting to Temporal Cloud needs:

- Address of the form `<Namespace>.<ID>.tmprl.cloud:<port>`.
- An mTLS CA certificate.
- An mTLS private key.

API-key authentication is an alternative to mTLS:

```typescript
const connection = await NativeConnection.connect({
  address: '<endpoint>',
  tls: true,
  apiKey: '<APIKey>',
});
```

## Updating an API key at runtime (client `Connection` only)

On the client-side `Connection`, replace the API key without reconnecting:

```typescript
connection.setApiKey('<NewAPIKey>');
```

This is documented for the client `Connection` from `@temporalio/client`. Do not assume the same method exists on `NativeConnection` — the local docs do not describe it.

## Lifecycle and shutdown

- Workers shut down on `SIGINT`, `SIGTERM`, `SIGQUIT`, or `SIGUSR2`.
- After `worker.run()` resolves (graceful or forced), close the connection in a `finally`.
- For programmatic shutdown call `Worker.shutdown()`, then close the connection.

Do not close the connection while `worker.run()` is still pending — the Worker uses that connection for polling.

## Common mistakes

1. **Wrong import** — `NativeConnection` lives in `@temporalio/worker`, not `@temporalio/client`.
2. **Mixing the two classes** — `Worker.create({ connection })` expects a `NativeConnection`; `new Client({ connection })` expects a `Connection`.
3. **Skipping `close()`** — leaking the underlying gRPC connection on process exit; always `await connection.close()` in `finally`.
4. **Calling `connection.setApiKey()` on a `NativeConnection`** — only documented on the client `Connection`.
5. **Hard-coding Cloud credentials** — load them with `loadClientConnectConfig` from `@temporalio/envconfig` so the Worker reads them from env vars or a TOML profile at runtime.
