# Nexus — TypeScript SDK

This reference covers the TypeScript-SDK-specific programming model for Temporal Nexus. Shared concepts (lifecycle, timeouts, retries, circuit breaking, cancellation vs termination, deployment patterns, security, debugging, metrics) are covered in `references/core/nexus.md` — they are not repeated here.

## Support status

Temporal TypeScript SDK support for Nexus is in **Public Preview** — it is not GA. <!-- docs/develop/typescript/nexus/feature-guide.mdx:21 -->

Recommended dependency floors from the feature-guide prerequisites:

- Temporal CLI `v1.3.0` or higher. <!-- docs/develop/typescript/nexus/feature-guide.mdx:51 -->
- Temporal TypeScript SDK `v1.12.3` or higher. <!-- docs/develop/typescript/nexus/feature-guide.mdx:52 -->

## Packages and imports

Nexus in TypeScript spans three packages:

- `nexus-rpc` — the third-party Nexus framework. Provides `service`, `operation`, `serviceHandler`, `OperationError`, `HandlerError`, and `HandlerErrorType`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:105 -->
- `@temporalio/nexus` — Temporal-specific helpers used in handler code: `WorkflowRunOperationHandler`, `startWorkflow`, `getClient`, and `NexusOperationFailure`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:151 -->
- `@temporalio/workflow` — caller-side API: `createNexusServiceClient`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:303 -->

```ts
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';
import * as wf from '@temporalio/workflow';
import { Worker, NativeConnection } from '@temporalio/worker';
```

## Defining the Service contract

A Nexus Service contract is declared with `nexus.service(name, operations)`, and each Operation is declared with `nexus.operation<TInput, TOutput>()`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:107 -->

```ts
// src/api.ts
import * as nexus from 'nexus-rpc';

export const helloService = nexus.service('hello', {
  echo: nexus.operation<EchoInput, EchoOutput>(),
  hello: nexus.operation<HelloInput, HelloOutput>(),
});

export interface EchoInput { message: string; }
export interface EchoOutput { message: string; }
export interface HelloInput { name: string; language: LanguageCode; }
export interface HelloOutput { message: string; }
export type LanguageCode = 'en' | 'fr' | 'de' | 'es' | 'tr';
```

Inputs and outputs are plain TypeScript objects, serialized as JSON by the default Data Converter. For Protobuf payloads, configure `ProtobufJsonPayloadConverter` instead — JSON encoding is not supported for Protobuf by default. <!-- docs/develop/typescript/nexus/feature-guide.mdx:100 -->

## Handler basics

A Service handler is created with `nexus.serviceHandler(service, operations)`. It must supply an implementation for each Operation declared by the Service. Each property of the object is the handler for one Operation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:144 -->

```ts
export const helloServiceHandler = nexus.serviceHandler(helloService, {
  echo: async (ctx, input: EchoInput): Promise<EchoOutput> => { /* sync */ return input; },
  hello: new temporalNexus.WorkflowRunOperationHandler<HelloInput, HelloOutput>(/* async */),
});
```

Service handlers are typically registered in the same Worker as the underlying Workflows and Activities they front. <!-- docs/develop/typescript/nexus/feature-guide.mdx:145 -->

## Synchronous Operation handler

A synchronous Operation handler in TypeScript is a **plain `async` function** placed on the `serviceHandler` object — there is no separate class. The function signature is `async (ctx, input: TIn): Promise<TOut>`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:159 -->

```ts
echo: async (ctx, input: EchoInput): Promise<EchoOutput> => {
  // Short computations or short downstream calls. Must complete within
  // the Nexus request deadline (10s).
  return input;
},
```

Synchronous handlers must complete within the Nexus operation request timeout. Handlers should be reliable since the circuit breaker trips after 5 consecutive retryable errors, blocking all Operations from the caller to that Endpoint. <!-- docs/develop/typescript/nexus/feature-guide.mdx:149 -->

## AbortSignal and request deadline

The handler context exposes two timeout-related fields:

- `ctx.abortSignal` — an `AbortSignal` that is triggered when the deadline is exceeded. Pass it to Temporal Client calls (and any other cancellable downstream calls) so they cancel cleanly when the timeout fires. <!-- docs/develop/typescript/nexus/feature-guide.mdx:193 -->
- `ctx.requestDeadline` — an optional `Date` representing the time by which the **current request** must complete. Note that this is the deadline for the current request, not the overall operation. Use it to decide whether to start work that may not finish in time, or to set timeouts on downstream calls. <!-- docs/develop/typescript/nexus/feature-guide.mdx:197 -->

```ts
sayHello: async (ctx, input) => {
  const client = temporalNexus.getClient();
  const handle = client.workflow.getHandle(workflowIdForUser(input.userId));
  return await handle.query(getLanguagesQuery /*, { abortSignal: ctx.abortSignal } */);
},
```

## Using the Temporal Client from a sync handler

`temporalNexus.getClient()` returns a Temporal Client connected using the same `NativeConnection` as the Worker hosting the Nexus Service. Use it from a sync handler to Signal, Query, Update, or list Workflows — including Signal-with-Start and Update-with-Start patterns. <!-- docs/develop/typescript/nexus/feature-guide.mdx:154 -->

```ts
import * as temporalNexus from '@temporalio/nexus';

function workflowIdForUser(userId: string): string {
  return `GreetingWorkflow_for_${userId}`;
}

export const nexusGreetingServiceHandler = nexus.serviceHandler(nexusGreetingService, {
  getLanguages: async (ctx, input: GetLanguagesInput) => {
    const client = temporalNexus.getClient();
    const handle = client.workflow.getHandle(workflowIdForUser(input.userId));
    return await handle.query(getLanguagesQuery);
  },
});
```

All such calls must complete within the Nexus request timeout. Updates should be short-lived to stay within this deadline. <!-- docs/develop/typescript/nexus/feature-guide.mdx:192 -->

## Asynchronous Workflow-Run Operation

For long-running Operations backed by a Workflow, use `new temporalNexus.WorkflowRunOperationHandler<TIn, TOut>(delegate)`. The delegate is `async (ctx, input) => { ... }`; inside it, call `await temporalNexus.startWorkflow(ctx, workflowFn, options)` to actually start the Workflow. The delegate may also validate or transform input and customize Workflow start options. <!-- docs/develop/typescript/nexus/feature-guide.mdx:230 -->

```ts
import { randomUUID } from 'crypto';
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';
import { helloService, HelloInput, HelloOutput } from '../api';
import { helloWorkflow } from './workflows';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  hello: new temporalNexus.WorkflowRunOperationHandler<HelloInput, HelloOutput>(
    async (ctx, input: HelloInput) => {
      return await temporalNexus.startWorkflow(ctx, helloWorkflow, {
        args: [input],
        // Workflow IDs should typically be business-meaningful and dedupe starts.
        // ctx.requestId is allocated by Temporal when the caller schedules the
        // operation and is stable across retries of this operation.
        workflowId: ctx.requestId ?? randomUUID(),
        // Task queue defaults to the task queue the Operation is handled on.
      });
    },
  ),
});
```

Notes:

- Workflow IDs should be business-meaningful and are used to dedupe Workflow starts; passing the ID in the Operation input as part of the Service contract is the typical approach. <!-- docs/develop/typescript/nexus/feature-guide.mdx:269 -->
- `ctx.requestId` is guaranteed to be stable across retries of the same Operation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:258 -->
- The Task Queue defaults to the Task Queue the Operation is handled on. <!-- docs/develop/typescript/nexus/feature-guide.mdx:261 -->
- Multiple Nexus callers can attach to a single handler Workflow via a Conflict-Policy of Use-Existing (see core reference). <!-- docs/develop/typescript/nexus/feature-guide.mdx:274 -->

### Multiple Workflow arguments

A Nexus Operation accepts a single input value. To pass multiple positional arguments through to the Workflow, place them as properties on the input object and unpack them into the `args` array when calling `startWorkflow`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:231 -->

```ts
async (ctx, input: { userId: string; greeting: string }) => {
  return await temporalNexus.startWorkflow(ctx, helloWorkflow, {
    args: [input.userId, input.greeting],
    workflowId: `hello-${input.userId}`,
  });
}
```

## Registering with a Worker

Pass Service handlers via the `nexusServices` option on `Worker.create`. The Worker uses its `connection`, `namespace`, `taskQueue`, and `workflowsPath` for both Workflows and Nexus Operations. <!-- docs/develop/typescript/nexus/feature-guide.mdx:285 -->

```ts
import { Worker, NativeConnection } from '@temporalio/worker';
import { helloServiceHandler } from './handler';

const namespace = 'my-target-namespace';
const serviceTaskQueue = 'my-handler-task-queue';
const worker = await Worker.create({
  connection,
  namespace,
  taskQueue: serviceTaskQueue,
  workflowsPath: require.resolve('./workflows'),
  nexusServices: [helloServiceHandler],
});
```

## Caller Workflow

Inside a Workflow, build a Nexus client with `wf.createNexusServiceClient({ service, endpoint })`, then call `nexusClient.executeOperation(name, input, options)`. The `endpoint` is the Nexus Endpoint name registered with the server. Callers reference Operations by their string name. <!-- docs/develop/typescript/nexus/feature-guide.mdx:303 -->

```ts
import * as wf from '@temporalio/workflow';
import { helloService, LanguageCode } from '../service/api';

const HELLO_SERVICE_ENDPOINT = 'hello-service-endpoint-name';

export async function helloCallerWorkflow(name: string, language: LanguageCode): Promise<string> {
  const nexusClient = wf.createNexusServiceClient({
    service: helloService,
    endpoint: HELLO_SERVICE_ENDPOINT,
  });

  const helloResult = await nexusClient.executeOperation(
    'hello',
    { name, language },
    { scheduleToCloseTimeout: '10s' },
  );

  return helloResult.message;
}
```

The caller Workflow is registered with a Worker and started with the standard `client.startWorkflow()` / `client.executeWorkflow()` flow. <!-- docs/develop/typescript/nexus/feature-guide.mdx:336 -->

## Exception classes

Three exception classes apply to Nexus in TypeScript: <!-- docs/develop/typescript/nexus/feature-guide.mdx:345 -->

- `nexus-rpc`'s `OperationError` — throw from a handler to signal application-level failure that should **not** be retried. <!-- docs/develop/typescript/nexus/feature-guide.mdx:347 -->
- `nexus-rpc`'s `HandlerError` — throw with a specific `HandlerErrorType`. Retryability is determined by the type per the Nexus spec. <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->
- `@temporalio/nexus`'s `NexusOperationFailure` — thrown inside a caller Workflow when a Nexus operation fails. Use the `cause` attribute to walk the cause chain to the underlying failure. <!-- docs/develop/typescript/nexus/feature-guide.mdx:349 -->

`HandlerErrorType` values and their retryability: <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->

| Type | Retryable |
| --- | --- |
| `RESOURCE_EXHAUSTED` | yes |
| `INTERNAL` | yes |
| `UNAVAILABLE` | yes |
| `UPSTREAM_TIMEOUT` | yes |
| `BAD_REQUEST` | no |
| `UNAUTHENTICATED` | no |
| `UNAUTHORIZED` | no |
| `NOT_FOUND` | no |
| `NOT_IMPLEMENTED` | no |

```ts
import { OperationError, HandlerError } from 'nexus-rpc';
import { NexusOperationFailure } from '@temporalio/nexus';

// In a handler:
throw new HandlerError('BAD_REQUEST', 'name must not be empty');
throw new OperationError('user does not have this feature enabled');

// In a caller Workflow:
try {
  await nexusClient.executeOperation('hello', input, { scheduleToCloseTimeout: '10s' });
} catch (err) {
  if (err instanceof NexusOperationFailure) {
    // Inspect err.cause for the underlying failure.
  }
  throw err;
}
```

<!-- VERIFY: exact constructor signatures of OperationError and HandlerError are not enumerated in feature-guide.mdx; the usage above follows the spec'd shape. -->

## Cancellation

Nexus Operations, like other cancellable APIs in `@temporalio/workflow`, execute within Cancellation Scopes. Requesting cancellation of a Cancellation Scope requests cancellation for all cancellable operations owned by that scope. The Workflow itself defines the root Cancellation Scope, so cancelling the Workflow propagates cancellation to every Nexus Operation started by it. <!-- docs/develop/typescript/nexus/feature-guide.mdx:353 -->

For granular control over a specific Nexus Operation, create a new Cancellation Scope and start the Operation inside it. See the [nexus-cancellation sample](https://github.com/temporalio/samples-typescript/tree/main/nexus-cancellation). <!-- docs/develop/typescript/nexus/feature-guide.mdx:358 -->

```ts
import * as wf from '@temporalio/workflow';

await wf.CancellationScope.cancellable(async () => {
  const nexusClient = wf.createNexusServiceClient({
    service: helloService,
    endpoint: HELLO_SERVICE_ENDPOINT,
  });
  return await nexusClient.executeOperation(
    'hello',
    { name, language },
    { scheduleToCloseTimeout: '10s' },
  );
});
```

Key constraints:

- Only **asynchronous** Operations can be canceled, because cancellation is delivered using the operation token. <!-- docs/develop/typescript/nexus/feature-guide.mdx:361 -->
- The Workflow or other resource backing the operation may choose to ignore the cancellation request. <!-- docs/develop/typescript/nexus/feature-guide.mdx:362 -->
- Once the caller Workflow completes, the caller's Nexus Machinery will not make further attempts to cancel operations still running. To guarantee cancellation delivery, wait for pending operations to finish before exiting the Workflow. <!-- docs/develop/typescript/nexus/feature-guide.mdx:364 -->

## OpenTelemetry tracing

The `@temporalio/interceptors-opentelemetry` package supports Nexus Operations and provides automatic trace-context propagation across Nexus boundaries from the caller Workflow to the handler. The easiest way to enable it is via `OpenTelemetryPlugin`, which auto-registers Nexus interceptors alongside Activity and Workflow interceptors. <!-- docs/develop/typescript/nexus/feature-guide.mdx:476 -->

```ts
import { OpenTelemetryPlugin } from '@temporalio/interceptors-opentelemetry';

const plugin = new OpenTelemetryPlugin({
  resource: myResource,
  spanProcessor: mySpanProcessor,
});

const worker = await Worker.create({
  // ...
  plugins: [plugin],
  nexusServices: [myServiceHandler],
});
```

Spans produced by the plugin: <!-- docs/develop/typescript/nexus/feature-guide.mdx:495 -->

- **Caller side:** `StartNexusOperation:service/operation` — emitted when the caller Workflow starts a Nexus Operation.
- **Handler side:** `RunStartNexusOperation:service/operation` and `RunCancelNexusOperation:service/operation` — emitted when the handler processes the operation. These spans are children of the caller span, linked via trace context propagated in Nexus request headers.

For custom interceptor logic (logging, authorization) beyond tracing, see the Nexus interceptor registration docs. <!-- docs/develop/typescript/nexus/feature-guide.mdx:502 -->

## Quick end-to-end recipe

The feature-guide walkthrough is roughly: <!-- docs/develop/typescript/nexus/feature-guide.mdx:27 -->

1. `temporal server start-dev` to run the dev server with Nexus enabled. <!-- docs/develop/typescript/nexus/feature-guide.mdx:57 -->
2. Create caller and target Namespaces with `temporal operator namespace create --namespace ...`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:69 -->
3. Create a Nexus Endpoint with `temporal operator nexus endpoint create --name ... --target-namespace ... --target-task-queue ...`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:81 -->
4. Run the handler Worker (Nexus Service handlers registered via `nexusServices`).
5. Run the caller Worker and start the caller Workflow with a standard Temporal Client.

See the [nexus-hello sample](https://github.com/temporalio/samples-typescript/tree/main/nexus-hello) and the messaging samples ([caller pattern](https://github.com/temporalio/samples-typescript/tree/main/nexus-messaging/src/callerpattern), [on-demand pattern](https://github.com/temporalio/samples-typescript/tree/main/nexus-messaging/src/ondemandpattern)) for full code. <!-- docs/develop/typescript/nexus/feature-guide.mdx:225 -->

## Cross-Namespace in Temporal Cloud

Cross-Namespace Nexus calls in Temporal Cloud use the `tcld` CLI plus mTLS client certificates to connect caller and handler Workers to their respective Cloud Namespaces. Endpoint creation includes `--allow-namespace <caller-namespace.account>`, which builds an allowlist of caller Namespaces permitted to use the Endpoint (Runtime Access Control). <!-- docs/develop/typescript/nexus/feature-guide.mdx:419 -->

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --allow-namespace <my-caller-namespace.account> \
  --description-file description.md
```

See the feature guide for the full Cloud setup, including `tcld login`, `tcld namespace create`, and certificate generation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:368 -->
