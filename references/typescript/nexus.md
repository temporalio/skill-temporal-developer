# Nexus — TypeScript SDK

Temporal Nexus connects Temporal Applications within and across Namespaces using a Nexus Endpoint, a Nexus Service contract, and Nexus Operations. <!-- docs/develop/typescript/nexus/feature-guide.mdx:25 --> TypeScript SDK support for Nexus is in **Public Preview**. <!-- docs/develop/typescript/nexus/feature-guide.mdx:19-23 -->

Cross-SDK concepts (Endpoints, Registry, Operation lifecycle, retries, timeouts, circuit breaking, security, patterns) live in `references/core/nexus.md`. This page covers the TypeScript-specific API surface only.

## Prerequisites

- Install the latest Temporal CLI (`v1.3.0` or higher recommended). <!-- docs/develop/typescript/nexus/feature-guide.mdx:51 -->
- Install the latest Temporal TypeScript SDK (`v1.12.3` or higher). <!-- docs/develop/typescript/nexus/feature-guide.mdx:52 -->

Start a local dev server with `temporal server start-dev`, then create caller/handler Namespaces and a Nexus Endpoint via `temporal operator nexus endpoint create` — see `references/core/nexus.md`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:57, 69-71, 81-85 -->

## Define the Service contract

The Service contract lives in a shared module imported by both caller and handler. Declare it with `nexus.service` and `nexus.operation<In, Out>()` from `nexus-rpc`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:105-119 -->

```ts
import * as nexus from 'nexus-rpc';

export const helloService = nexus.service('hello', {
  echo: nexus.operation<EchoInput, EchoOutput>(),
  hello: nexus.operation<HelloInput, HelloOutput>(),
});

export interface EchoInput { message: string }
export interface EchoOutput { message: string }
export interface HelloInput { name: string; language: LanguageCode }
export interface HelloOutput { message: string }
export type LanguageCode = 'en' | 'fr' | 'de' | 'es' | 'tr';
```

Plain TypeScript objects are serialized as JSON by the default Data Converter. <!-- docs/develop/typescript/nexus/feature-guide.mdx:95-98 --> Protobuf JSON encoding is not supported by default; use `ProtobufJsonPayloadConverter` from `@temporalio/common` if passing Protobuf payloads. <!-- docs/develop/typescript/nexus/feature-guide.mdx:100 -->

A Nexus Operation can only take **one input parameter**; multi-arg Workflows must pack args into one input object. <!-- docs/develop/typescript/nexus/feature-guide.mdx:231-233 -->

## Synchronous Operation handler

A synchronous Operation handler is defined as a plain `async` function inside the object passed to `nexus.serviceHandler`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:144, 159 -->

```ts
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';
import { helloService, EchoInput, EchoOutput } from '../api';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  echo: async (ctx, input: EchoInput): Promise<EchoOutput> => {
    // Optionally: const client = temporalNexus.getClient();
    return input;
  },
  // ...
});
```

Inside a sync handler, call `temporalNexus.getClient()` to obtain a Temporal Client connected via the same `NativeConnection` as the Worker. Use it for Signals, Queries, Updates, Signal-With-Start, Update-With-Start, or `listWorkflows`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:154-155, 188-191 -->

All sync handler work must complete within the **Nexus request timeout** (the 10-second handler request deadline — see `references/core/nexus.md`). <!-- docs/develop/typescript/nexus/feature-guide.mdx:192 --> The context exposes:

- `ctx.abortSignal` — an `AbortSignal` triggered when the deadline is exceeded. Pass it to Temporal Client calls so they cancel on timeout. <!-- docs/develop/typescript/nexus/feature-guide.mdx:193-194 -->
- `ctx.requestDeadline` — an optional `Date` representing when the current request must complete. Use it to decide whether to start work that may not finish in time, or to set downstream call timeouts. <!-- docs/develop/typescript/nexus/feature-guide.mdx:197-199 -->

Handlers should be reliable: the [circuit breaker](/nexus/operations#circuit-breaking) trips after 5 consecutive retryable errors, blocking all Operations on the destination pair until it half-opens. <!-- docs/develop/typescript/nexus/feature-guide.mdx:149, 161 -->

Example using the Client to query a Workflow from a sync handler: <!-- docs/develop/typescript/nexus/feature-guide.mdx:206-223 -->

```ts
import * as temporalNexus from '@temporalio/nexus';

getLanguages: async (ctx, input: GetLanguagesInput) => {
  const client = temporalNexus.getClient();
  const handle = client.workflow.getHandle(workflowIdForUser(input.userId));
  return await handle.query(getLanguagesQuery);
},
```

## Asynchronous Operation handler

To expose a Workflow as a Nexus Operation, use the `WorkflowRunOperationHandler` class from `@temporalio/nexus`. The constructor takes an async delegate that receives `(ctx, input)` and returns the result of `temporalNexus.startWorkflow`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:230-265 -->

```ts
import { randomUUID } from 'crypto';
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';
import { helloService, HelloInput, HelloOutput } from '../api';
import { helloWorkflow } from './workflows';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  // ... sync ops ...
  hello: new temporalNexus.WorkflowRunOperationHandler<HelloInput, HelloOutput>(
    async (ctx, input: HelloInput) => {
      return await temporalNexus.startWorkflow(ctx, helloWorkflow, {
        args: [input],
        workflowId: ctx.requestId ?? randomUUID(),
        // Task queue defaults to the task queue this Operation is handled on.
      });
    },
  ),
});
```

- The delegate can validate/transform the input and customize Workflow start options before calling `startWorkflow`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:247-251 -->
- Pass multi-arg Workflow arguments through the `args` array. <!-- docs/develop/typescript/nexus/feature-guide.mdx:231-233, 254 -->
- `workflowId` should be a business-meaningful, deduping ID; using `ctx.requestId ?? randomUUID()` keeps it stable across operation retries. <!-- docs/develop/typescript/nexus/feature-guide.mdx:256-259, 269-270 -->
- The default Task Queue is the one the Operation was handled on. <!-- docs/develop/typescript/nexus/feature-guide.mdx:261 -->

To attach multiple Nexus callers to a single handler Workflow, use a Conflict-Policy of Use-Existing. <!-- docs/develop/typescript/nexus/feature-guide.mdx:272-276 -->

## Register the Service handler in a Worker

Pass handlers via the `nexusServices` option to `Worker.create`. Nexus Service handlers are typically defined in the same Worker that hosts the underlying Workflow/Activity primitives they abstract. <!-- docs/develop/typescript/nexus/feature-guide.mdx:145, 283-297 -->

```ts
import { Worker, NativeConnection } from '@temporalio/worker';
import { helloServiceHandler } from './handler';

const worker = await Worker.create({
  connection,
  namespace: 'my-target-namespace',
  taskQueue: 'my-handler-task-queue',
  workflowsPath: require.resolve('./workflows'),
  nexusServices: [helloServiceHandler],
});
```

## Call a Nexus Operation from a caller Workflow

Inside a caller Workflow, build a typed client with `wf.createNexusServiceClient` (from `@temporalio/workflow`) and call `executeOperation`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:303-329 -->

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

- The `endpoint` value must match the Nexus Endpoint name created via `temporal operator nexus endpoint create`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:304 -->
- `executeOperation(name, input, options)` accepts options such as `scheduleToCloseTimeout`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:322-326 -->

The caller Workflow is registered and started with a standard `Worker.create` and `client.startWorkflow()` / `client.executeWorkflow()`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:336 -->

## Exceptions

Three Nexus-specific exception types: <!-- docs/develop/typescript/nexus/feature-guide.mdx:345-349 -->

- **`OperationError`** (from `nexus-rpc`) — throw inside an Operation handler to indicate the Operation has failed by its own application logic and should **not** be retried. <!-- docs/develop/typescript/nexus/feature-guide.mdx:347 -->
- **`HandlerError`** (from `nexus-rpc`) with a `HandlerErrorType` — marked retryable or non-retryable per the Nexus spec. <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->
  - Non-retryable: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`.
  - Retryable: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`.
- **`NexusOperationFailure`** (from `@temporalio/nexus`) — thrown inside the caller Workflow when a Nexus Operation fails for any reason. Inspect the `cause` attribute for the underlying cause chain. <!-- docs/develop/typescript/nexus/feature-guide.mdx:349 -->

See `references/typescript/error-handling.md` for general Workflow/Activity error patterns and `references/core/error-reference.md` for cross-SDK Nexus failure semantics.

## Cancelling an Operation

Nexus Operations execute within Cancellation Scopes from `@temporalio/workflow`. The Workflow itself defines the root Cancellation Scope; cancelling the Workflow propagates cancellation to all cancellable operations it started, including Nexus Operations. <!-- docs/develop/typescript/nexus/feature-guide.mdx:353-356 -->

For finer-grained control, create a new Cancellation Scope and start the Nexus Operation within it. See the [nexus-cancellation sample](https://github.com/temporalio/samples-typescript/tree/main/nexus-cancellation). <!-- docs/develop/typescript/nexus/feature-guide.mdx:358-359 -->

Notes: <!-- docs/develop/typescript/nexus/feature-guide.mdx:361-366 -->

- Only **asynchronous** Operations can be cancelled (cancellation is sent using an operation token). The Workflow or other resources backing the Operation may choose to ignore the cancellation request.
- Once the caller Workflow completes, the caller's Nexus Machinery will not make further cancellation attempts. To ensure cancellations are delivered, await all pending Operations before the Workflow exits.

## OpenTelemetry tracing

The `@temporalio/interceptors-opentelemetry` package supports Nexus, propagating trace context across Nexus boundaries from caller to handler. <!-- docs/develop/typescript/nexus/feature-guide.mdx:476-477 --> The easiest entry point is `OpenTelemetryPlugin`, which auto-registers Nexus interceptors alongside Activity and Workflow interceptors. <!-- docs/develop/typescript/nexus/feature-guide.mdx:478-479 -->

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
<!-- docs/develop/typescript/nexus/feature-guide.mdx:480-493 -->

Spans emitted: <!-- docs/develop/typescript/nexus/feature-guide.mdx:496-499 -->

- **Caller side:** `StartNexusOperation:service/operation`.
- **Handler side:** `RunStartNexusOperation:service/operation` and `RunCancelNexusOperation:service/operation`. These are children of the caller span, linked via trace context propagated in Nexus request headers.

For non-tracing interceptor logic (logging, authorization), see the Nexus interceptor registration docs at `/develop/typescript/workers/interceptors#nexus-interceptor-registration`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:502 -->

## Creating the Endpoint

Endpoint management is not a TypeScript-specific concern. Use `temporal operator nexus endpoint create` (self-hosted) or `tcld nexus endpoint create` (Temporal Cloud). See `references/core/nexus.md` for the full reference, including the cross-Namespace Temporal Cloud flow with `tcld` and mTLS certificates. <!-- docs/develop/typescript/nexus/feature-guide.mdx:81-85, 368-425 -->

## Observability

In the caller Workflow history: <!-- docs/develop/typescript/nexus/feature-guide.mdx:457-472 -->

- **Synchronous Operations:** `NexusOperationScheduled`, `NexusOperationCompleted`. (`NexusOperationStarted` is not reported.)
- **Asynchronous Operations:** `NexusOperationScheduled`, `NexusOperationStarted`, `NexusOperationCompleted`.

CLI helpers: `temporal workflow describe -w <ID>` shows pending Nexus Operations on the caller and any attached callbacks on the handler Workflow; `temporal workflow show -w <ID>` lists the Nexus events. <!-- docs/develop/typescript/nexus/feature-guide.mdx:445-454 -->

See `references/typescript/observability.md` for general logging/metrics/tracing patterns.

## Samples

- [`nexus-hello`](https://github.com/temporalio/samples-typescript/tree/main/nexus-hello) — sync and async Operations, caller/handler Workers, starter. <!-- docs/develop/typescript/nexus/feature-guide.mdx:43, 337-340 -->
- [`nexus-messaging`](https://github.com/temporalio/samples-typescript/tree/main/nexus-messaging) — sync Operations issuing Updates and Queries; caller-pattern and on-demand-pattern variants. <!-- docs/develop/typescript/nexus/feature-guide.mdx:201, 225-226 -->
- [`nexus-cancellation`](https://github.com/temporalio/samples-typescript/tree/main/nexus-cancellation) — granular cancellation via explicit Cancellation Scopes. <!-- docs/develop/typescript/nexus/feature-guide.mdx:359 -->
- [`interceptors-opentelemetry`](https://github.com/temporalio/samples-typescript/tree/main/interceptors-opentelemetry) — end-to-end OTel tracing across Nexus boundaries. <!-- docs/develop/typescript/nexus/feature-guide.mdx:500 -->

## See also

- `references/core/nexus.md` — cross-SDK concepts, Endpoint/Registry, lifecycle, timeouts, retries, circuit breaking, security, patterns.
- `references/typescript/error-handling.md` — `ApplicationFailure`, retry policies, non-retryable errors.
- `references/typescript/observability.md` — logging, metrics, tracing.
