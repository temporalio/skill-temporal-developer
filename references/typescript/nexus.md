# Temporal Nexus — TypeScript SDK

Temporal TypeScript SDK support for Nexus is in **Public Preview** <!-- docs/develop/typescript/nexus/feature-guide.mdx:19-23 -->. Cross-SDK concepts (Endpoints, Services, Operations, sync vs. async semantics) are documented in `references/core/nexus.md`; this file covers only the TypeScript surface.

Minimum versions: Temporal CLI `v1.3.0` or higher, Temporal TypeScript SDK `v1.12.3` or higher <!-- docs/develop/typescript/nexus/feature-guide.mdx:51-52 -->.

## Package imports

Two distinct packages provide Nexus primitives — keep them straight:

- **`nexus-rpc`** (cross-language Nexus SDK): `nexus.service`, `nexus.operation<I, O>()`, `nexus.serviceHandler`, `OperationError`, `HandlerError`, `HandlerErrorType` <!-- docs/develop/typescript/nexus/feature-guide.mdx:105-119,144,347-348 -->.
- **`@temporalio/nexus`** (Temporal binding): `WorkflowRunOperationHandler`, `getClient()`, `startWorkflow()`, `NexusOperationFailure` <!-- docs/develop/typescript/nexus/feature-guide.mdx:151-156,230,240,253,349 -->.
- **`@temporalio/workflow`**: `wf.createNexusServiceClient` for caller Workflows <!-- docs/develop/typescript/nexus/feature-guide.mdx:303,317 -->.
- **`@temporalio/worker`**: `Worker.create({ nexusServices: [...] })` for handler registration <!-- docs/develop/typescript/nexus/feature-guide.mdx:285,291-297 -->.
- **`@temporalio/interceptors-opentelemetry`**: `OpenTelemetryPlugin` auto-registers Nexus interceptors alongside Activity and Workflow interceptors <!-- docs/develop/typescript/nexus/feature-guide.mdx:476-493 -->.

## Defining the Service contract

`nexus.service('name', { ... })` declares a named Service; `nexus.operation<I, O>()` declares a typed Operation slot <!-- docs/develop/typescript/nexus/quickstart.mdx:75-76 -->.

```ts
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
<!-- docs/develop/typescript/nexus/feature-guide.mdx:105-139 -->

## Synchronous Operation handlers

A synchronous handler is a plain `async (ctx, input) => result` function registered as a value on the `nexus.serviceHandler(service, { ... })` object <!-- docs/develop/typescript/nexus/feature-guide.mdx:159,172-184 -->. `getClient()` from `@temporalio/nexus` returns a Temporal Client connected through the same `NativeConnection` as the Worker, useful for Signal/Query/Update/list calls inside a sync handler <!-- docs/develop/typescript/nexus/feature-guide.mdx:153-156,160,217-219 -->.

```ts
import * as nexus from 'nexus-rpc';
import * as temporalNexus from '@temporalio/nexus';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  echo: async (ctx, input: EchoInput): Promise<EchoOutput> => {
    return input;
  },
  // ...
});
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:172-184 -->

```ts
const client = temporalNexus.getClient();
const handle = client.workflow.getHandle(workflowIdForUser(input.userId));
return await handle.query(getLanguagesQuery);
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:217-219 -->

All Client calls inside a sync handler must complete within the Nexus request timeout <!-- docs/develop/typescript/nexus/feature-guide.mdx:192 -->.

## Handler context: deadline propagation

The handler context exposes:

- **`ctx.abortSignal`** — an `AbortSignal` triggered when the deadline is exceeded. Pass it to Temporal Client calls so they are canceled if the timeout is reached <!-- docs/develop/typescript/nexus/feature-guide.mdx:193-194 -->.
- **`ctx.requestDeadline`** — an optional `Date` representing the time by which the current _request_ must complete (not the overall operation). Use it to gate work that may not finish in time or to set downstream timeouts <!-- docs/develop/typescript/nexus/feature-guide.mdx:197-199 -->.
- **`ctx.requestId`** — a request ID allocated by Temporal when the caller schedules the operation; stable across retries, so it's a good default for Workflow IDs <!-- docs/develop/typescript/nexus/feature-guide.mdx:256-259 -->.

## Asynchronous Operation handlers (Workflow-Run Operations)

Use `@temporalio/nexus`'s `WorkflowRunOperationHandler` class to expose a Workflow as a Nexus Operation <!-- docs/develop/typescript/nexus/feature-guide.mdx:230 -->. It is constructed with `new` and takes a delegate function that calls `temporalNexus.startWorkflow(ctx, workflow, options)` <!-- docs/develop/typescript/nexus/feature-guide.mdx:246-264 -->.

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
        workflowId: ctx.requestId ?? randomUUID(),
        // Task queue defaults to the task queue this Operation is handled on.
      });
    },
  ),
});
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:238-265 -->

If multiple arguments need to reach the underlying Workflow, pack them into properties of the single input object and unpack them into the `args` array on `startWorkflow` <!-- docs/develop/typescript/nexus/feature-guide.mdx:231-233 -->. Task Queue defaults to the Task Queue this Operation is handled on <!-- docs/develop/typescript/nexus/feature-guide.mdx:261 -->.

## Registering the Service handler on a Worker

Pass handlers as `nexusServices` on `Worker.create` <!-- docs/develop/typescript/nexus/feature-guide.mdx:296 -->.

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
<!-- docs/develop/typescript/nexus/feature-guide.mdx:285-297 -->

## Calling Nexus Operations from a Workflow

A caller Workflow uses `wf.createNexusServiceClient({ service, endpoint })` (both keys required) to obtain a typed client bound to the Service contract and a Nexus Endpoint name, then calls `executeOperation(name, input, options)` <!-- docs/develop/typescript/nexus/feature-guide.mdx:303,317-326 -->. Duration values in `options` can be passed as strings such as `'10s'` <!-- docs/develop/typescript/nexus/feature-guide.mdx:325 -->.

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
    { scheduleToCloseTimeout: '10s' }
  );

  return helloResult.message;
}
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:310-329 -->

## Exceptions in Nexus Operations

Three Nexus-specific exception classes <!-- docs/develop/typescript/nexus/feature-guide.mdx:344-349 -->:

- **`nexus-rpc`'s `OperationError`** — throw inside a Nexus Operation to indicate it has failed according to its own application logic and should not be retried <!-- docs/develop/typescript/nexus/feature-guide.mdx:347 -->.
- **`nexus-rpc`'s `HandlerError`** — throw with a specific `HandlerErrorType`; the error is marked retryable or non-retryable per the type <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->.
  - Non-retryable: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED` <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->.
  - Retryable: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT` <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->.
- **`@temporalio/nexus`'s `NexusOperationFailure`** — thrown inside a Workflow when a Nexus Operation fails for any reason; use the `cause` attribute to walk the cause chain <!-- docs/develop/typescript/nexus/feature-guide.mdx:349 -->.

Handlers should be reliable: the [circuit breaker](https://docs.temporal.io/nexus/operations#circuit-breaking) trips after 5 consecutive retryable errors, blocking all Operations from the caller to that Endpoint <!-- docs/develop/typescript/nexus/feature-guide.mdx:149,161 -->.

## Cancellation

Nexus Operations execute within Cancellation Scopes provided by `@temporalio/workflow` <!-- docs/develop/typescript/nexus/feature-guide.mdx:353 -->. Requesting cancellation of a Cancellation Scope requests cancellation for all cancellable operations owned by that scope; the Workflow itself defines the root Cancellation Scope, so cancelling the Workflow propagates cancellation to every Nexus Operation it started <!-- docs/develop/typescript/nexus/feature-guide.mdx:353-356 -->.

For more granular control, explicitly create a new Cancellation Scope and start the Nexus Operation from within it <!-- docs/develop/typescript/nexus/feature-guide.mdx:358-359 -->.

Only asynchronous operations can actually be canceled, since cancellation is sent using an operation token; the Workflow or other resources backing the operation may also choose to ignore the cancellation request <!-- docs/develop/typescript/nexus/feature-guide.mdx:361-362 -->. Once the caller Workflow completes, the caller's Nexus Machinery makes no further attempts to cancel operations that are still running — wait for pending operations to finish before exiting if you need cancellation to be delivered <!-- docs/develop/typescript/nexus/feature-guide.mdx:364-366 -->.

## Tracing with OpenTelemetry

`@temporalio/interceptors-opentelemetry` supports Nexus Operations and automatically propagates trace context across Nexus boundaries from caller to handler <!-- docs/develop/typescript/nexus/feature-guide.mdx:476-477 -->. Enable it via `OpenTelemetryPlugin`, which auto-registers Nexus interceptors alongside Activity and Workflow interceptors <!-- docs/develop/typescript/nexus/feature-guide.mdx:478 -->.

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

Spans created:

- **Caller side:** `StartNexusOperation:service/operation` — created when the caller Workflow starts a Nexus Operation <!-- docs/develop/typescript/nexus/feature-guide.mdx:497 -->.
- **Handler side:** `RunStartNexusOperation:service/operation` and `RunCancelNexusOperation:service/operation` — created when the handler processes the operation; children of the caller span, linked via trace context propagated in Nexus request headers <!-- docs/develop/typescript/nexus/feature-guide.mdx:498 -->.

## Worker development against a local server

Start the dev server (Nexus is enabled by default) <!-- docs/develop/typescript/nexus/feature-guide.mdx:54-58 -->:

```
temporal server start-dev
```

Create caller and handler Namespaces <!-- docs/develop/typescript/nexus/feature-guide.mdx:69-71 -->:

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```

Create a Nexus Endpoint to route requests <!-- docs/develop/typescript/nexus/feature-guide.mdx:81-85 -->:

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

## See also

- `references/core/nexus.md` — cross-SDK Nexus concepts (Endpoints, Services, Operations, sync/async semantics, retry/circuit-breaker behavior).
- TypeScript Nexus sample: <https://github.com/temporalio/samples-typescript/tree/main/nexus-hello> <!-- docs/develop/typescript/nexus/feature-guide.mdx:43 -->.
