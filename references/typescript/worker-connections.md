# TypeScript SDK Worker Connections

## `NativeConnection` vs `Connection`

Use `NativeConnection` from `@temporalio/worker` when supplying a connection to `Worker.create()`. `Client` accepts a `ConnectionLike`, so it can use a `Connection` from `@temporalio/client` or share the Worker's `NativeConnection`.

Both connection types accept `address` in `host:port` form, `tls: true` for standard TLS or a `tls` object for custom settings, `metadata` for gRPC headers, and `apiKey` for API key authentication. `connectTimeout` is a client `Connection` option. It takes milliseconds or a duration string and defaults to 10 seconds.

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

An explicit `authorization` entry in the connection metadata takes precedence over the new key.

## HTTP/2 keepalive (experimental)

`NativeConnection.connect()` accepts a `keepAlive` option that controls HTTP/2 keepalive on the connection. Pass a `KeepAliveConfig` or `false`:

- `interval`: the time between HTTP/2 keepalive pings.
- `timeout`: how long to wait for a ping response before closing the connection.
- `keepAlive: false` disables keepalive.

Keepalive is on by default, with a 30-second ping interval and a 15-second response timeout. Both fields take a `Duration`, either milliseconds or a duration string:

```typescript
const connection = await NativeConnection.connect({
  address: 'localhost:7233',
  keepAlive: { interval: '30s', timeout: '15s' }, // illustrative values
});
```

## Poller behavior

`Worker.create()` accepts `workflowTaskPollerBehavior`, `activityTaskPollerBehavior`, and `nexusTaskPollerBehavior`. Each takes a `PollerBehavior`, which is one of:

- `{ type: 'simple-maximum' }`
- `{ type: 'autoscaling' }`: scales the number of pollers based on feedback from the server. A slot must be available before polling begins.

Each option defaults to a fixed maximum of 5 pollers.

## Lifecycle and shutdown

Workers begin shutdown on `SIGINT`, `SIGTERM`, `SIGQUIT`, or `SIGUSR2` by default. For programmatic shutdown, call `worker.shutdown()` to begin draining. Wait for `worker.run()` to settle, then close the connection in `finally` as shown above.

`worker.run()` can reject if graceful shutdown fails. Wait for every Worker sharing the connection to stop before closing it. `NativeConnection.close()` rejects with `IllegalStateError` if a Worker still uses the connection.
