# Temporal Nexus — Go SDK

> See `references/core/nexus.md` for cross-SDK concepts (lifecycle, retries, circuit breaker, timeouts, error handling, security, cancellation semantics). This file documents Go SDK identifiers only.

Support stage: Temporal Go SDK support for Nexus is Generally Available (GA). <!-- docs/develop/go/nexus/feature-guide.mdx:23 -->

Recommended versions: Temporal CLI v1.3.0 or higher <!-- docs/develop/go/nexus/feature-guide.mdx:50 -->, Temporal Go SDK v1.33.0 or higher. <!-- docs/develop/go/nexus/feature-guide.mdx:51-52 -->

## Packages

- `go.temporal.io/sdk/temporalnexus` — workflow-run operation builders and the client accessor for sync handlers. <!-- docs/develop/go/nexus/feature-guide.mdx:152 -->
- `github.com/nexus-rpc/sdk-go/nexus` — Nexus service constructor and sync operation builder. <!-- docs/develop/go/nexus/feature-guide.mdx:149 -->
- `go.temporal.io/sdk/client` — `client.StartWorkflowOptions` used inside workflow-run operation handlers. <!-- docs/develop/go/nexus/feature-guide.mdx:151 -->
- `go.temporal.io/sdk/workflow` — caller-side Nexus client and options. <!-- docs/develop/go/nexus/feature-guide.mdx:153 -->

The `temporalnexus` package exposes builders and helpers for authoring Operation handlers, including: <!-- docs/develop/go/nexus/feature-guide.mdx:126 -->

- `NewWorkflowRunOperation` — run a Workflow as an asynchronous Nexus Operation. <!-- docs/develop/go/nexus/feature-guide.mdx:128 -->
- `GetClient` — get the Temporal Client that the Worker was initialized with, for synchronous handlers backed by Temporal primitives such as Signals and Queries. <!-- docs/develop/go/nexus/feature-guide.mdx:129-130 -->

## Define the Nexus Service contract

The Service name, Operation names, and input/output types are exported from a shared package (no annotations — Go uses constants and plain structs). <!-- docs/develop/go/nexus/feature-guide.mdx:91-98 -->

```go
const HelloServiceName = "my-hello-service"
const EchoOperationName = "echo"

type EchoInput struct {
    Message string
}

type EchoOutput EchoInput
```
<!-- docs/develop/go/nexus/feature-guide.mdx:105-114 -->

## Develop Operation handlers

Operation handlers are typically defined in the same Worker as the underlying Temporal primitives they abstract. Handlers decide whether the Operation is synchronous or asynchronous. They can invoke underlying Temporal primitives such as Queries, Signals, or Updates using the Temporal SDK Client, or run other reliable code. <!-- docs/develop/go/nexus/feature-guide.mdx:121-124 -->

### Synchronous operation

Use the `nexus.NewSyncOperation` builder for simple RPC-style handlers. <!-- docs/develop/go/nexus/feature-guide.mdx:136 -->

```go
var EchoOperation = nexus.NewSyncOperation(
    service.EchoOperationName,
    func(ctx context.Context, input service.EchoInput, options nexus.StartOperationOptions) (service.EchoOutput, error) {
        return service.EchoOutput(input), nil
    },
)
```
<!-- docs/develop/go/nexus/feature-guide.mdx:159-164 -->

The handler signature takes `context.Context`, the typed input, and `nexus.StartOperationOptions`, returning the typed output and an error. <!-- docs/develop/go/nexus/feature-guide.mdx:159 -->

### Using the Temporal Client inside a sync handler

Use `temporalnexus.GetClient(ctx)` to get the Client that the Worker was initialized with for Signal, Query, Update, Signal-With-Start, and Update-With-Start calls. <!-- docs/develop/go/nexus/feature-guide.mdx:137 --> <!-- docs/develop/go/nexus/feature-guide.mdx:171-172 -->

```go
var GetLanguagesOperation = nexus.NewSyncOperation(
    service.GetLanguagesOperationName,
    func(ctx context.Context, input service.GetLanguagesInput, options nexus.StartOperationOptions) (service.GetLanguagesOutput, error) {
        c := temporalnexus.GetClient(ctx)
        workflowID := GetWorkflowID(input.UserID)
        // ...
    },
)
```
<!-- docs/develop/go/nexus/feature-guide.mdx:189-192 -->

All calls must complete within the Nexus request timeout. The `ctx` provided to the handler is automatically set with this deadline, so passing it directly to Temporal Client calls correctly propagates the timeout. Updates should be short-lived to stay within this deadline. <!-- docs/develop/go/nexus/feature-guide.mdx:173-175 -->

### Asynchronous workflow-run operation

Use `temporalnexus.NewWorkflowRunOperation` — the easiest way to expose a Workflow as a Nexus Operation. <!-- docs/develop/go/nexus/feature-guide.mdx:200 -->

```go
var HelloOperation = temporalnexus.NewWorkflowRunOperation(
    service.HelloOperationName,
    HelloHandlerWorkflow,
    func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
        return client.StartWorkflowOptions{
            // Workflow IDs should be business-meaningful and are used to dedupe Workflow starts.
            // options.RequestID is the request ID allocated by Temporal when the caller Workflow
            // schedules the operation, and is guaranteed to be stable across retries.
            ID: options.RequestID,
            // Task queue defaults to the task queue this operation is handled on.
        }, nil
    },
)
```
<!-- docs/develop/go/nexus/feature-guide.mdx:207-215 -->

The third argument is a function returning `client.StartWorkflowOptions`. Using `options.RequestID` as the Workflow ID is the recommended default for dedup, because it is stable across retries of the operation. <!-- docs/develop/go/nexus/feature-guide.mdx:209-212 --> If the task queue is not set, it defaults to the task queue the operation is handled on. <!-- docs/develop/go/nexus/feature-guide.mdx:213 -->

### Multi-argument workflow start

A Nexus Operation can only take one input parameter. To start a Workflow that takes multiple arguments, use `NewWorkflowRunOperationWithOptions` or `MustNewWorkflowRunOperationWithOptions`. <!-- docs/develop/go/nexus/feature-guide.mdx:231-232 -->

The options type is `temporalnexus.WorkflowRunOperationOptions[InputType, OutputType]`, with a `Name` field and a `Handler` returning `temporalnexus.WorkflowHandle[OutputType]`. <!-- docs/develop/go/nexus/feature-guide.mdx:237-239 -->

```go
var HelloOperation = temporalnexus.MustNewWorkflowRunOperationWithOptions(
    temporalnexus.WorkflowRunOperationOptions[service.HelloInput, service.HelloOutput]{
        Name: service.HelloOperationName,
        Handler: func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (temporalnexus.WorkflowHandle[service.HelloOutput], error) {
            return temporalnexus.ExecuteUntypedWorkflow[service.HelloOutput](
                ctx,
                options,
                client.StartWorkflowOptions{
                    ID: options.RequestID,
                },
                HelloHandlerWorkflow,
                input.Name,
                input.Language,
            )
        },
    },
)
```
<!-- docs/develop/go/nexus/feature-guide.mdx:237-254 -->

`temporalnexus.ExecuteUntypedWorkflow[OutputType]` is the helper used inside the handler to start the underlying Workflow with multiple positional arguments. <!-- docs/develop/go/nexus/feature-guide.mdx:240 -->

## Register a Nexus Service in a Worker

Create the service with `nexus.NewService`, register Operation handlers on it via `service.Register(...)`, then attach it to the Worker with `w.RegisterNexusService(service)`. <!-- docs/develop/go/nexus/feature-guide.mdx:298-303 -->

```go
w := worker.New(c, taskQueue, worker.Options{})
service := nexus.NewService(service.HelloServiceName)
err = service.Register(handler.EchoOperation, handler.HelloOperation)
if err != nil {
    log.Fatalln("Unable to register operations", err)
}
w.RegisterNexusService(service)
w.RegisterWorkflow(handler.HelloHandlerWorkflow)

err = w.Run(worker.InterruptCh())
```
<!-- docs/develop/go/nexus/feature-guide.mdx:297-306 -->

## Caller side: invoke a Nexus Operation from a Workflow

Create the Nexus Client with `workflow.NewNexusClient(endpointName, serviceName)` — endpoint first, then service. Then call `ExecuteOperation` with the context, operation name, input, and a `workflow.NexusOperationOptions` value. <!-- docs/develop/go/nexus/feature-guide.mdx:334-336 -->

```go
func EchoCallerWorkflow(ctx workflow.Context, message string) (string, error) {
    c := workflow.NewNexusClient(endpointName, service.HelloServiceName)

    fut := c.ExecuteOperation(ctx, service.EchoOperationName, service.EchoInput{Message: message}, workflow.NexusOperationOptions{})

    var res service.EchoOutput
    if err := fut.Get(ctx, &res); err != nil {
        return "", err
    }

    return res.Message, nil
}
```
<!-- docs/develop/go/nexus/feature-guide.mdx:333-344 -->

### Wait for the operation to start

`fut.GetNexusOperationExecution()` returns a future that resolves once the operation has started. Calling `.Get(ctx, &exec)` on it yields a `workflow.NexusOperationExecution` value, which contains the operation token (used for cancellation and other handle actions on asynchronous operations). <!-- docs/develop/go/nexus/feature-guide.mdx:352-358 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{})
var res service.HelloOutput

var exec workflow.NexusOperationExecution
if err := fut.GetNexusOperationExecution().Get(ctx, &exec); err != nil {
    return "", err
}
if err := fut.Get(ctx, &res); err != nil {
    return "", err
}
```
<!-- docs/develop/go/nexus/feature-guide.mdx:349-361 -->

## Timeouts

Nexus Operations support three timeout types set in `workflow.NexusOperationOptions` when calling `ExecuteOperation`. The fields use Go's `time.Duration`. <!-- docs/develop/go/nexus/feature-guide.mdx:371-372 -->

### Schedule-to-Close

`ScheduleToCloseTimeout` limits the total duration of the Operation from when it is scheduled to when it completes. The Nexus Machinery automatically retries failed requests until this timeout is exceeded. <!-- docs/develop/go/nexus/feature-guide.mdx:376-377 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{
    ScheduleToCloseTimeout: 10 * time.Minute,
})
```
<!-- docs/develop/go/nexus/feature-guide.mdx:380-382 -->

### Schedule-to-Start

`ScheduleToStartTimeout` limits how long the caller will wait for the Operation to be started by the handler. If not set, no Schedule-to-Start timeout is enforced. <!-- docs/develop/go/nexus/feature-guide.mdx:387-388 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{
    ScheduleToStartTimeout: 2 * time.Minute,
})
```
<!-- docs/develop/go/nexus/feature-guide.mdx:391-393 -->

### Start-to-Close

`StartToCloseTimeout` limits how long the caller will wait for an asynchronous Operation to complete after it has been started. This timeout only applies to asynchronous Operations. If not set, no Start-to-Close timeout is enforced. <!-- docs/develop/go/nexus/feature-guide.mdx:398-400 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{
    StartToCloseTimeout: 5 * time.Minute,
})
```
<!-- docs/develop/go/nexus/feature-guide.mdx:403-405 -->

## Cancellation

To cancel a Nexus Operation from within a Workflow, create a cancellable context using `workflow.WithCancel`. It returns a new context and a function that, when called, cancels the context and any SDK method that was passed it. The future returned by `NexusClient.ExecuteOperation` resolves when the operation finishes, whether it succeeds, fails, times out, or is canceled. <!-- docs/develop/go/nexus/feature-guide.mdx:560-562 -->

```go
ctx, cancel := workflow.WithCancel(ctx)
// later...
cancel()
```

Only asynchronous Operations can be canceled, because cancellation is sent using an operation token. The Workflow or other resources backing the operation may choose to ignore the cancellation request; if ignored, the operation may enter a terminal state. <!-- docs/develop/go/nexus/feature-guide.mdx:564-566 -->

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations that are still running. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow. <!-- docs/develop/go/nexus/feature-guide.mdx:568-570 -->

See the [Nexus cancelation sample](https://github.com/temporalio/samples-go/tree/main/nexus-cancelation) for reference. <!-- docs/develop/go/nexus/feature-guide.mdx:572 -->

## Reliability and the circuit breaker

Handlers should be reliable, since the circuit breaker trips after 5 consecutive retryable errors, blocking all Operations from the caller to that Endpoint. <!-- docs/develop/go/nexus/feature-guide.mdx:124 --> <!-- docs/develop/go/nexus/feature-guide.mdx:138 --> See `references/core/nexus.md` for cross-SDK retry and circuit breaker semantics.

## Attaching multiple callers to a handler Workflow

Multiple Nexus callers can attach to a handler Workflow using a Conflict-Policy of Use-Existing. <!-- docs/develop/go/nexus/feature-guide.mdx:225 -->

## CLI setup

### Start the development server

```
temporal server start-dev
```
<!-- docs/develop/go/nexus/feature-guide.mdx:57 -->

This starts the Temporal development server with the Web UI and creates the `default` Namespace (in-memory database — not for production). The Web UI is at http://localhost:8233 and the server is at `localhost:7233`. <!-- docs/develop/go/nexus/feature-guide.mdx:60-62 -->

### Create caller and handler Namespaces

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```
<!-- docs/develop/go/nexus/feature-guide.mdx:69-70 -->

### Create a Nexus Endpoint

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```
<!-- docs/develop/go/nexus/feature-guide.mdx:81-84 -->

Flags: `--name`, `--target-namespace`, `--target-task-queue`. <!-- docs/develop/go/nexus/feature-guide.mdx:82-84 -->

### Temporal Cloud: create an Endpoint with `tcld`

To create a Nexus Endpoint in Cloud you must have a Developer account role or higher, and have NamespaceAdmin permission on the `--target-namespace`. <!-- docs/develop/go/nexus/feature-guide.mdx:622 -->

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --description-file description.md
```
<!-- docs/develop/go/nexus/feature-guide.mdx:625-629 -->

## Observability

### Caller's history events

For **asynchronous** Nexus Operations, the caller's Workflow history includes: <!-- docs/develop/go/nexus/feature-guide.mdx:755 -->

- `NexusOperationScheduled` <!-- docs/develop/go/nexus/feature-guide.mdx:757 -->
- `NexusOperationStarted` <!-- docs/develop/go/nexus/feature-guide.mdx:758 -->
- `NexusOperationCompleted` <!-- docs/develop/go/nexus/feature-guide.mdx:759 -->

For **synchronous** Nexus Operations, the caller's Workflow history includes only `NexusOperationScheduled` and `NexusOperationCompleted` (`NexusOperationStarted` is not reported for sync). <!-- docs/develop/go/nexus/feature-guide.mdx:761-768 -->

### CLI inspection

Use `temporal workflow describe -w <ID>` to show pending Nexus Operations in the caller Workflow and any attached callbacks on the handler Workflow. <!-- docs/develop/go/nexus/feature-guide.mdx:743-746 -->

Use `temporal workflow show -w <ID>` to view the caller's Workflow history with Nexus events. <!-- docs/develop/go/nexus/feature-guide.mdx:749-752 -->

## Samples to consult

- Main Nexus sample: https://github.com/temporalio/samples-go/tree/main/nexus <!-- docs/develop/go/nexus/feature-guide.mdx:42 -->
- Multiple-arguments sample: https://github.com/temporalio/samples-go/tree/main/nexus-multiple-arguments <!-- docs/develop/go/nexus/feature-guide.mdx:235 -->
- Messaging samples (Signal/Query/Update through Nexus): https://github.com/temporalio/samples-go/tree/main/nexus-messaging <!-- docs/develop/go/nexus/feature-guide.mdx:177 --> with [caller pattern](https://github.com/temporalio/samples-go/tree/main/nexus-messaging/callerpattern/) and [on-demand pattern](https://github.com/temporalio/samples-go/tree/main/nexus-messaging/ondemandpattern/) variants. <!-- docs/develop/go/nexus/feature-guide.mdx:195 -->
- Cancelation sample: https://github.com/temporalio/samples-go/tree/main/nexus-cancelation <!-- docs/develop/go/nexus/feature-guide.mdx:572 -->
