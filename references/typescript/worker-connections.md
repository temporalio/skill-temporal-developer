# TypeScript SDK Worker Connections

## `NativeConnection` vs `Connection`

`Worker.create()` accepts a [`NativeConnection`](https://typescript.temporal.io/api/classes/worker.NativeConnection) from `@temporalio/worker`. `Client` accepts a [`ConnectionLike`](https://typescript.temporal.io/api/interfaces/client.ClientOptions#connection), including a `Connection` from `@temporalio/client` or a `NativeConnection`.

Both classes support address, TLS, and gRPC metadata settings. Check the [Worker options](https://typescript.temporal.io/api/interfaces/worker.NativeConnectionOptions) and [Client options](https://typescript.temporal.io/api/interfaces/client.ConnectionOptions) before sharing configuration. For example, `connectTimeout` is specific to `Connection`.

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

If you omit `connection`, the Worker connects to `localhost:7233` by default.

## Load options from `@temporalio/envconfig`

For deployments, load connection options from a TOML profile or environment variables instead of hard-coding them:

```typescript
import { NativeConnection } from '@temporalio/worker';
import { loadClientConnectConfig } from '@temporalio/envconfig';

const config = loadClientConnectConfig();
const connection = await NativeConnection.connect(config.connectionOptions);
```

Use `namespace: config.namespace` in `Worker.create()`. The Namespace is separate from `connectionOptions`.

`loadClientConnectConfig` reads `temporal.toml` from the platform's configuration directory or the path in `TEMPORAL_CONFIG_FILE`. Supported environment variables override values from the file. See the [Worker configuration examples](https://docs.temporal.io/develop/typescript/client/temporal-client#connect-to-temporal-service-from-a-worker).

## Temporal Cloud

Use your Namespace's gRPC endpoint as the address and pass the full Namespace ID (`<namespace>.<account-id>`) to `Worker.create()`. See [Temporal Cloud Namespaces](https://docs.temporal.io/cloud/namespaces#how-to-access-a-namespace-in-temporal-cloud).

For API key authentication, enable TLS and pass the API key:

```typescript
const connection = await NativeConnection.connect({
  address: '<endpoint>',
  tls: true,
  apiKey: '<APIKey>',
});
```

For mTLS, pass the client certificate and matching private key as `tls.clientCertPair` with `crt` and `key`. Configure the signing CA certificate on the Namespace. See [Temporal Cloud mTLS setup](https://docs.temporal.io/cloud/certificates).

## Rotate an API key at runtime

Update a Worker's API key without recreating its `NativeConnection`:

```typescript
await connection.setApiKey(newApiKey);
```

An explicit `authorization` entry in the connection metadata takes precedence. See [`NativeConnection.setApiKey()`](https://typescript.temporal.io/api/classes/worker.NativeConnection#setapikey).

## Lifecycle and shutdown

Workers begin shutdown on `SIGINT`, `SIGTERM`, `SIGQUIT`, or `SIGUSR2` by default. For programmatic shutdown, call `worker.shutdown()` to begin draining. Wait for `worker.run()` to settle, then close the connection in `finally` as shown above.

`worker.run()` can reject if graceful shutdown fails. If multiple Workers share a connection, wait for all of them to stop before closing it. See [Worker shutdown](https://typescript.temporal.io/api/classes/worker.Worker#shutdown) and [`NativeConnection.close()`](https://typescript.temporal.io/api/classes/worker.NativeConnection#close).
