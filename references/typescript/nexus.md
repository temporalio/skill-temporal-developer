# Temporal Nexus — TypeScript SDK

> See `references/core/nexus.md` for cross-SDK concepts (lifecycle, retries, circuit breaker, timeouts). This file documents TypeScript SDK identifiers only.

**Support stage: Public Preview** (not GA). <!-- docs/develop/typescript/nexus/feature-guide.mdx:21 -->

Recommended: CLI `v1.3.0` or higher, TypeScript SDK `v1.12.3` or higher. <!-- docs/develop/typescript/nexus/feature-guide.mdx:51 -->

## Packages

- `nexus-rpc` <!-- docs/develop/typescript/nexus/feature-guide.mdx:105 --> — service/operation contract, handler builder, exception classes.
- `@temporalio/nexus` <!-- docs/develop/typescript/nexus/feature-guide.mdx:151 --> — `WorkflowRunOperationHandler`, `startWorkflow`, `getClient`, `NexusOperationFailure`.
- `@temporalio/workflow` <!-- docs/develop/typescript/nexus/feature-guide.mdx:303 --> — caller-side `createNexusServiceClient`.
- `@temporalio/worker` <!-- docs/develop/typescript/nexus/feature-guide.mdx:285 --> — `nexusServices` Worker option.
- `@temporalio/interceptors-opentelemetry` <!-- docs/develop/typescript/nexus/feature-guide.mdx:476 --> — OpenTelemetry plugin with Nexus support.

## Define a service contract

Use `nexus-rpc`'s `nexus.service` and `nexus.operation` to declare the Service and Operation names along with their input/output types. <!-- docs/develop/typescript/nexus/feature-guide.mdx:107 -->

```ts
import * as nexus from 'nexus-rpc';

export const helloService = nexus.service('hello', {
  echo: nexus.operation<EchoInput, EchoOutput>(),
  hello: nexus.operation<HelloInput, HelloOutput>(),
});
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:105-119 -->

## Develop operation handlers

A Nexus Service handler is defined using `nexus-rpc`'s `serviceHandler` function. <!-- docs/develop/typescript/nexus/feature-guide.mdx:144 --> A Service handler must provide Operation handlers for each Operation declared by the Service. <!-- docs/develop/typescript/nexus/feature-guide.mdx:146 -->

The `@temporalio/nexus` package provides utilities to help create Nexus Operations that interact with a Temporal namespace: <!-- docs/develop/typescript/nexus/feature-guide.mdx:151 -->

- `WorkflowRunOperationHandler` — Create an asynchronous operation handler that starts a Workflow. <!-- docs/develop/typescript/nexus/feature-guide.mdx:153 -->
- `getClient()` — Get a Temporal Client connected using the same `NativeConnection` as the present Temporal Worker. <!-- docs/develop/typescript/nexus/feature-guide.mdx:154 -->

### Synchronous Nexus Operation handler

A synchronous Nexus Operation handler is defined in TypeScript as a simple async function. <!-- docs/develop/typescript/nexus/feature-guide.mdx:159 -->

```ts
import * as nexus from 'nexus-rpc';
import { helloService, EchoInput, EchoOutput } from '../api';

export const helloServiceHandler = nexus.serviceHandler(helloService, {
  echo: async (ctx, input: EchoInput): Promise<EchoOutput> => {
    return input;
  },
});
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:172-184 -->

- Use `temporalNexus.getClient()` from `@temporalio/nexus` to get the Temporal Client for signaling, querying, and listing Workflows. <!-- docs/develop/typescript/nexus/feature-guide.mdx:160 -->
- All calls must complete within the Nexus request timeout. <!-- docs/develop/typescript/nexus/feature-guide.mdx:192 -->
- The handler receives an AbortSignal via `ctx.abortSignal` that is triggered when the deadline is exceeded — pass it to Temporal Client calls to ensure they are canceled if the timeout is reached. <!-- docs/develop/typescript/nexus/feature-guide.mdx:193 -->
- `ctx.requestDeadline` is an optional `Date` representing the time by which the current request must complete. Use it to make decisions about whether to start work that may not finish in time, or to set timeouts on downstream calls. <!-- docs/develop/typescript/nexus/feature-guide.mdx:197 -->
- Updates should be short-lived to stay within this deadline. <!-- docs/develop/typescript/nexus/feature-guide.mdx:195 -->

#### Using the Temporal Client for Signals, Queries, and Updates

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
  // ...
});
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:208-222 -->

Signal-With-Start or Update-With-Start can also be used to ensure the Workflow is started and send it a Signal or Update. <!-- docs/develop/typescript/nexus/feature-guide.mdx:191 -->

### Asynchronous workflow-run operation handler

Use `@temporalio/nexus`'s `WorkflowRunOperationHandler` helper class to expose a Temporal Workflow as a Nexus Operation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:230 --> Even though a Nexus operation can only take one input parameter, multiple workflow arguments can be passed through by using multiple properties of the input object and placing them in the array provided to the `args` option when calling `startWorkflow`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:231 -->

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

- `WorkflowRunOperationHandler` takes a function that receives the Operation's context and input. <!-- docs/develop/typescript/nexus/feature-guide.mdx:247 -->
- Call `temporalNexus.startWorkflow()` to actually start the Workflow from inside the `WorkflowRunOperationHandler`'s delegate function. <!-- docs/develop/typescript/nexus/feature-guide.mdx:250 -->
- `ctx.requestId` is the request ID allocated by Temporal when the caller workflow schedules the operation; this ID is guaranteed to be stable across retries of this operation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:257 -->
- The task queue for the started Workflow defaults to the task queue this Operation is handled on. <!-- docs/develop/typescript/nexus/feature-guide.mdx:261 -->

## Register the service handler in a Worker

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

## Caller side: invoke an operation from a Workflow

To execute a Nexus Operation from a Workflow, use `@temporalio/workflow`'s `createNexusServiceClient` to create a Nexus client for that service. You must provide the Nexus Endpoint name registered previously. <!-- docs/develop/typescript/nexus/feature-guide.mdx:303 -->

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
<!-- docs/develop/typescript/nexus/feature-guide.mdx:311-329 -->

The caller Workflow can be registered with a Worker and started using `client.startWorkflow()` or `client.executeWorkflow()`, as usual. <!-- docs/develop/typescript/nexus/feature-guide.mdx:336 -->

## Exceptions

There are three Nexus-specific exception classes in TypeScript: <!-- docs/develop/typescript/nexus/feature-guide.mdx:345 -->

- `nexus-rpc`'s `OperationError` — throw in a Nexus operation to indicate that it has failed according to its own application logic and should not be retried. <!-- docs/develop/typescript/nexus/feature-guide.mdx:347 -->
- `nexus-rpc`'s `HandlerError` with a specific `HandlerErrorType`. The error will be marked as retryable or non-retryable according to the type. <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->
  - Non-retryable: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->
  - Retryable: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->
- `@temporalio/nexus`'s `NexusOperationFailure` — thrown inside a Workflow when a Nexus operation fails for any reason. Use the `cause` attribute on the exception to access the cause chain. <!-- docs/develop/typescript/nexus/feature-guide.mdx:349 -->

## Cancellation

Nexus Operations, just like other cancellable APIs provided by the `@temporalio/workflow` package, execute within Cancellation Scopes. Requesting cancellation of a Cancellation Scope results in requesting cancellation for all cancellable operations owned by that scope. <!-- docs/develop/typescript/nexus/feature-guide.mdx:353-354 -->

The Workflow itself defines the root Cancellation Scope. Requesting cancellation of the Workflow therefore propagates the cancellation request to all cancellable operations started by that workflow, including Nexus Operations. <!-- docs/develop/typescript/nexus/feature-guide.mdx:355-356 -->

For more granular control over cancellation of a specific Nexus Operation, explicitly create a new Cancellation Scope and start the Nexus Operation from within that scope. See the [nexus-cancellation sample](https://github.com/temporalio/samples-typescript/tree/main/nexus-cancellation). <!-- docs/develop/typescript/nexus/feature-guide.mdx:358-359 -->

Only asynchronous operations can be canceled in Nexus, since cancellation is sent using an operation token. The Workflow or other resources backing the operation may choose to ignore the cancellation request. <!-- docs/develop/typescript/nexus/feature-guide.mdx:361-362 -->

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations that are still running. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow. <!-- docs/develop/typescript/nexus/feature-guide.mdx:364-366 -->

## OpenTelemetry tracing

The `@temporalio/interceptors-opentelemetry` package supports Nexus Operations, providing automatic trace context propagation across Nexus boundaries from the caller Workflow to the handler. <!-- docs/develop/typescript/nexus/feature-guide.mdx:476 -->

The easiest way to enable it is with `OpenTelemetryPlugin`, which auto-registers Nexus interceptors alongside Activity and Workflow interceptors: <!-- docs/develop/typescript/nexus/feature-guide.mdx:478 -->

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
<!-- docs/develop/typescript/nexus/feature-guide.mdx:481-493 -->

Spans created by the plugin: <!-- docs/develop/typescript/nexus/feature-guide.mdx:495 -->

- **Caller side:** `StartNexusOperation:service/operation` — created when the caller Workflow starts a Nexus Operation. <!-- docs/develop/typescript/nexus/feature-guide.mdx:497 -->
- **Handler side:** `RunStartNexusOperation:service/operation` and `RunCancelNexusOperation:service/operation` — created when the handler processes the operation. These spans are children of the caller span, linked via trace context propagated in Nexus request headers. <!-- docs/develop/typescript/nexus/feature-guide.mdx:498 -->

For custom interceptor logic beyond tracing (e.g., logging, authorization), see Nexus interceptor registration. <!-- docs/develop/typescript/nexus/feature-guide.mdx:502 -->

## CLI setup

Start the development server with Nexus enabled: <!-- docs/develop/typescript/nexus/feature-guide.mdx:54 -->

```
temporal server start-dev
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:57 -->

Create caller and handler Namespaces: <!-- docs/develop/typescript/nexus/feature-guide.mdx:64 -->

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:69-70 -->

Create a Nexus Endpoint: <!-- docs/develop/typescript/nexus/feature-guide.mdx:76 -->

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:81-85 -->

## Observability commands

Use `workflow describe` to show pending Nexus Operations in the caller Workflow and any attached callbacks on the handler Workflow: <!-- docs/develop/typescript/nexus/feature-guide.mdx:445 -->

```
temporal workflow describe -w <ID>
temporal workflow show -w <ID>
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:448,454 -->

History events in the caller's Workflow: <!-- docs/develop/typescript/nexus/feature-guide.mdx:451 -->

- Asynchronous operations: `NexusOperationScheduled`, `NexusOperationStarted`, `NexusOperationCompleted`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:459-461 -->
- Synchronous operations: `NexusOperationScheduled`, `NexusOperationCompleted`. `NexusOperationStarted` isn't reported in the caller's history for synchronous operations. <!-- docs/develop/typescript/nexus/feature-guide.mdx:465-466,470 -->

## Temporal Cloud (tcld)

For cross-Namespace Nexus calls in Temporal Cloud, use the `tcld` CLI to create Namespaces and the Nexus Endpoint, with mTLS client certificates for Worker authentication. <!-- docs/develop/typescript/nexus/feature-guide.mdx:370-371 -->

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --allow-namespace <my-caller-namespace.account> \
  --description-file description.md
```
<!-- docs/develop/typescript/nexus/feature-guide.mdx:419-424 -->

The `--allow-namespace` flag builds an Endpoint allowlist of caller Namespaces that can use the Nexus Endpoint. <!-- docs/develop/typescript/nexus/feature-guide.mdx:427 -->

To create a Nexus Endpoint you must have a Developer account role or higher, and have NamespaceAdmin permission on the `--target-namespace`. <!-- docs/develop/typescript/nexus/feature-guide.mdx:416 -->

## Samples

- [nexus-hello](https://github.com/temporalio/samples-typescript/tree/main/nexus-hello) <!-- docs/develop/typescript/nexus/feature-guide.mdx:43 -->
- [nexus-messaging](https://github.com/temporalio/samples-typescript/tree/main/nexus-messaging) — caller pattern and on-demand pattern for sending Updates and Queries through Nexus. <!-- docs/develop/typescript/nexus/feature-guide.mdx:201,225 -->
- [nexus-cancellation](https://github.com/temporalio/samples-typescript/tree/main/nexus-cancellation) — granular cancellation via explicit Cancellation Scopes. <!-- docs/develop/typescript/nexus/feature-guide.mdx:359 -->
- [interceptors-opentelemetry](https://github.com/temporalio/samples-typescript/tree/main/interceptors-opentelemetry) <!-- docs/develop/typescript/nexus/feature-guide.mdx:500 -->
