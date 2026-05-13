# Worker connections (TypeScript SDK)

This reference covers the Worker-side connection object — `NativeConnection` — and its lifecycle: how to create it, pass it to a `Worker`, and close it on shutdown.

## `NativeConnection` vs. `Connection`

The TypeScript SDK ships two connection classes. `NativeConnection` is used to connect a Worker to the Temporal Service; `Connection` is used to connect a Temporal Client (typically from application code or from within an Activity). <!-- docs/develop/typescript/client/temporal-client.mdx:610-615 -->

- `NativeConnection` is imported from `@temporalio/worker`. <!-- docs/develop/typescript/client/temporal-client.mdx:487-489 -->
- `Connection` is imported from `@temporalio/client`. <!-- docs/develop/typescript/client/temporal-client.mdx:54 -->
- Both connection classes accept the same set of connection options. <!-- docs/develop/typescript/client/temporal-client.mdx:614-615 -->

The two connection types are not interchangeable. A Worker takes a `NativeConnection`; a `Client` takes a `Connection`. <!-- docs/develop/typescript/client/temporal-client.mdx:485-490 -->

`Client` is a higher-level abstraction built on top of `Connection` — you pass a `Connection` to the `Client` constructor; you do not pass a `Client` to `Worker.create()`. <!-- docs/develop/typescript/client/temporal-client.mdx:619-630 -->

## Connection lifecycle

The documented Worker connection lifecycle is:

1. Call `await NativeConnection.connect({...})` to create the connection. <!-- docs/develop/typescript/set-up.mdx:207-210 -->
2. Pass the resulting connection to `Worker.create({ connection, ... })`. <!-- docs/develop/typescript/set-up.mdx:213-220 -->
3. `await worker.run()` inside a `try` block. <!-- docs/develop/typescript/set-up.mdx:230 -->
4. `await connection.close()` in the `finally` block, after the Worker has stopped. <!-- docs/develop/typescript/set-up.mdx:231-234 -->

The canonical worker example from the Quickstart:

```ts
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';

async function run() {
  // Step 1: Establish a connection with Temporal server.
  //
  // Worker code uses `@temporalio/worker.NativeConnection`.
  // (But in your application code it's `@temporalio/client.Connection`.)
  const connection = await NativeConnection.connect({
    address: 'localhost:7233',
    // TLS and gRPC metadata configuration goes here.
  });
  try {
    // Step 2: Register Workflows and Activities with the Worker.
    const worker = await Worker.create({
      connection,
      namespace: 'default',
      taskQueue: 'hello-world',
      workflowsPath: require.resolve('./workflows'),
      activities,
    });

    // Step 3: Start accepting tasks on the `hello-world` queue
    await worker.run();
  } finally {
    // Close the connection once the worker has stopped
    await connection.close();
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

<!-- docs/develop/typescript/set-up.mdx:198-241 -->

The Standalone Activities sample uses the same pattern with `loadClientConnectConfig()`:

```ts
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
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:153-178 -->

## Configuration sources

Connection options for `NativeConnection` can come from three sources: a TOML configuration file, environment variables, or directly in code. <!-- docs/develop/typescript/client/temporal-client.mdx:492-496 -->

### TOML configuration file

Use `loadClientConnectConfig` from `@temporalio/envconfig` to load a named profile and pass the resulting `connectionOptions` to `NativeConnection.connect`. <!-- docs/develop/typescript/client/temporal-client.mdx:514-540 -->

```ts
import { NativeConnection } from '@temporalio/worker';
import { loadClientConnectConfig } from '@temporalio/envconfig';
import { resolve } from 'path';

async function main() {
  const configFile = resolve(__dirname, '../config.toml');
  const profileName = 'staging'

  const config = loadClientConnectConfig({
    profile: profileName,
    configSource: { path: configFile },
  });

  const connection = await NativeConnection.connect(config.connectionOptions);

  const worker = await Worker.create({
    connection,
    namespace: <namespace_id>.<account_id>,
    // ...
  });
}
```

<!-- docs/develop/typescript/client/temporal-client.mdx:517-540 -->

If you don't provide a configuration file path, the SDK looks for it at `~/.config/temporalio/temporal.toml` or the equivalent standard config directory on your OS. You can also set the path via the `TEMPORAL_CONFIG_FILE` environment variable. <!-- docs/develop/typescript/client/temporal-client.mdx:88-91 -->

Environment variables take precedence over values in the configuration file. <!-- docs/develop/typescript/client/temporal-client.mdx:93-99 -->

### Environment variables

Call `loadClientConnectConfig()` with no arguments to load values from the environment, then pass the resulting `connectionOptions` to `NativeConnection.connect`: <!-- docs/develop/typescript/client/temporal-client.mdx:558-573 -->

```ts
import { NativeConnection } from '@temporalio/worker';
import { loadClientConnectConfig } from '@temporalio/envconfig';

async function main() {
  const config = loadClientConnectConfig();

  const connection = await NativeConnection.connect(config.connectionOptions);

  const worker = await Worker.create({
    connection,
    namespace: process.env.TEMPORAL_NAMESPACE,
    // ...
  });
}
```

<!-- docs/develop/typescript/client/temporal-client.mdx:558-573 -->

### Directly in code

Pass connection options directly to `NativeConnection.connect`: <!-- docs/develop/typescript/client/temporal-client.mdx:583-597 -->

```ts
import { NativeConnection } from '@temporalio/worker';

const connection = await NativeConnection.connect({
    address: <endpoint>,
    tls: true,
    apiKey: <APIKey>,
});
const worker = await Worker.create({
    connection,
    namespace: <namespace_id>.<account_id>,
    // ...
});
```

<!-- docs/develop/typescript/client/temporal-client.mdx:583-597 -->

## Connecting a Worker to Temporal Cloud

A Worker connecting to Temporal Cloud needs the same set of connection options as a Client: <!-- docs/develop/typescript/workers/run-process.mdx:157-168 -->

- An address that includes your Cloud Namespace Name and a port number: `<Namespace>.<ID>.tmprl.cloud:<port>`. <!-- docs/develop/typescript/workers/run-process.mdx:162-163 -->
- mTLS CA certificate. <!-- docs/develop/typescript/workers/run-process.mdx:164 -->
- mTLS private key. <!-- docs/develop/typescript/workers/run-process.mdx:165 -->

API key authentication is also supported via the `apiKey` option to `NativeConnection.connect`. <!-- docs/develop/typescript/client/temporal-client.mdx:587-591 -->

For Standalone Activity Workers, the documented mTLS environment variables are:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:420-425 -->

And the API key variables:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

<!-- docs/develop/typescript/activities/standalone-activities.mdx:431-435 -->

## Updating credentials

The Client-side `Connection` class has a documented `setApiKey` method for rotating an API key on a live connection:

```ts
connection.setApiKey(<APIKey>);
```

<!-- docs/develop/typescript/client/temporal-client.mdx:473-477 -->

The Worker-side `NativeConnection` does **not** have an equivalent method documented in the local docs reviewed for this reference. Do not assume `setApiKey` is available on `NativeConnection`.

<!-- VERIFY: Does NativeConnection expose a setApiKey method (or any equivalent like setMetadata or setAddress) for rotating credentials on a live worker connection without restarting the Worker? The local docs only show setApiKey on the client-side Connection class. -->

<!-- VERIFY: Does the TypeScript SDK provide any documented worker-side connection replacement API (e.g. swapping the connection object on a running Worker) that corresponds to the planned-content description of "worker connection replacement APIs for managing a worker's service connection lifecycle"? The local docs reviewed (set-up.mdx, run-process.mdx, temporal-client.mdx, standalone-activities.mdx, nexus/quickstart.mdx) do not describe such an API. -->

## Shutdown and connection close

A Worker shuts down when it receives one of the configured shutdown signals (`SIGINT`, `SIGTERM`, `SIGQUIT`, `SIGUSR2`) or when `Worker.shutdown()` is called. <!-- docs/develop/typescript/workers/run-process.mdx:254-272 -->

`await worker.run()` resolves once the Worker has reached the `STOPPED` state. <!-- docs/develop/typescript/workers/run-process.mdx:283-291 -->

Always call `await connection.close()` **after** `await worker.run()` has resolved — the canonical pattern places `connection.close()` in a `finally` block following the `await worker.run()` line. <!-- docs/develop/typescript/set-up.mdx:230-234 --> Closing the connection before the Worker has stopped is not the pattern shown in the docs.

## Nexus Workers

A Worker that registers a Nexus Service Handler still uses `NativeConnection` the same way — the `nexusServices` option is added to `Worker.create()` alongside `connection`: <!-- docs/develop/typescript/nexus/quickstart.mdx:122-143 -->

```ts
import { NativeConnection, Worker } from '@temporalio/worker';
import * as activities from './activities';
import { sayHelloHandler } from './handler';

async function run() {
    const connection = await NativeConnection.connect({
      address: 'localhost:7233',
    });
    try {
      const worker = await Worker.create({
        connection,
        namespace: 'default',
        taskQueue: 'hello-world',
        workflowsPath: require.resolve('./workflows'),
        activities,
        nexusServices: [sayHelloHandler],
      });
      await worker.run();
    } finally {
      await connection.close();
    }
}
```

<!-- docs/develop/typescript/nexus/quickstart.mdx:122-148 -->

In a process that hosts both a Client and a Worker (such as the Nexus caller-starter sample), create them as separate connection objects: a `Connection` (from `@temporalio/client`) for the `Client`, and a `NativeConnection` (from `@temporalio/worker`) for the `Worker`. <!-- docs/develop/typescript/nexus/quickstart.mdx:244-289 -->

## Common pitfalls

- **Wrong import path.** `NativeConnection` lives in `@temporalio/worker`, not `@temporalio/client`. The client-side `Connection` lives in `@temporalio/client`, not `@temporalio/worker`. <!-- docs/develop/typescript/client/temporal-client.mdx:485-490 -->
- **Passing a `Client` to `Worker.create`.** `Worker.create({ connection })` expects a `NativeConnection`, not a high-level `Client`. <!-- docs/develop/typescript/client/temporal-client.mdx:489-490 -->
- **Constructing with `new`.** The documented constructor pattern is `await NativeConnection.connect({...})`, not `new NativeConnection({...})`. <!-- docs/develop/typescript/client/temporal-client.mdx:583-591 -->
- **Closing the connection too early.** Put `await connection.close()` in a `finally` block that runs after `await worker.run()` resolves. <!-- docs/develop/typescript/set-up.mdx:230-234 -->

## What is *not* documented here

The local docs reviewed for this reference do not describe:

<!-- VERIFY: Any worker-side `setApiKey`, `setMetadata`, or `setAddress` method on NativeConnection. -->

<!-- VERIFY: Reconnection / auto-retry semantics of the Rust core that backs NativeConnection — e.g. what happens when the underlying gRPC stream drops, whether the Worker reconnects transparently, and what backoff policy is used. -->

<!-- VERIFY: Failover behavior when the Temporal Service is unavailable, including any documented timeouts or health-check semantics for NativeConnection. -->

<!-- VERIFY: Whether you can swap the `connection` on a running Worker without recreating the Worker (the "worker connection replacement" capability mentioned in the planned-content description). -->
