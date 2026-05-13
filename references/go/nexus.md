# Temporal Nexus — Go SDK

Temporal Go SDK support for Nexus is Generally Available <!-- docs/develop/go/nexus/feature-guide.mdx:21-25 -->. This file documents the Go SDK surface only; cross-SDK concepts (Endpoints, Services, Operations, lifecycle, timeouts, errors, retries, circuit breaking) are in `references/core/nexus.md`. Recommended minimums: Temporal CLI v1.3.0 or higher, Temporal Go SDK v1.33.0 or higher <!-- docs/develop/go/nexus/feature-guide.mdx:50-52 -->.

## Package imports

- `github.com/nexus-rpc/sdk-go/nexus` — `nexus.NewSyncOperation`, `nexus.NewService`, `nexus.StartOperationOptions` <!-- docs/develop/go/nexus/feature-guide.mdx:149; docs/develop/go/nexus/feature-guide.mdx:159; docs/develop/go/nexus/feature-guide.mdx:275; docs/develop/go/nexus/feature-guide.mdx:298 -->.
- `go.temporal.io/sdk/temporalnexus` — `temporalnexus.NewWorkflowRunOperation`, `temporalnexus.MustNewWorkflowRunOperationWithOptions`, `temporalnexus.WorkflowRunOperationOptions`, `temporalnexus.GetClient`, `temporalnexus.WorkflowHandle`, `temporalnexus.ExecuteUntypedWorkflow` <!-- docs/develop/go/nexus/feature-guide.mdx:152; docs/develop/go/nexus/feature-guide.mdx:207; docs/develop/go/nexus/feature-guide.mdx:237-240 -->.
- `go.temporal.io/sdk/workflow` — `workflow.NewNexusClient`, `workflow.NexusOperationOptions`, `workflow.NexusOperationExecution`, `workflow.WithCancel` <!-- docs/develop/go/nexus/feature-guide.mdx:334; docs/develop/go/nexus/feature-guide.mdx:336; docs/develop/go/nexus/feature-guide.mdx:355; docs/develop/go/nexus/feature-guide.mdx:560 -->.
- `go.temporal.io/sdk/client` — `client.StartWorkflowOptions` (returned by the async Options function) <!-- docs/develop/go/nexus/feature-guide.mdx:207-215 -->.
- `go.temporal.io/sdk/worker` — `worker.New`, `worker.Options`, and the Worker's `RegisterNexusService` method <!-- docs/develop/go/nexus/feature-guide.mdx:297-304 -->.

## Defining the Service contract

A Service is a plain Go package that names the Service and Operations and declares input/output types. The same package is imported by both handler and caller code so they agree on the contract <!-- docs/develop/go/nexus/feature-guide.mdx:89-98 -->.

```go
// nexus/service/api.go
const HelloServiceName = "my-hello-service"

// Echo operation
const EchoOperationName = "echo"

type EchoInput struct {
    Message string
}

type EchoOutput EchoInput
```

<!-- docs/develop/go/nexus/feature-guide.mdx:100-117 -->

## Synchronous Operation handlers

`nexus.NewSyncOperation(name, fn)` builds a synchronous Operation. The handler function has the signature `func(ctx context.Context, input I, options nexus.StartOperationOptions) (O, error)` <!-- docs/develop/go/nexus/feature-guide.mdx:136; docs/develop/go/nexus/feature-guide.mdx:159 -->. Use `temporalnexus.GetClient(ctx)` to get the Temporal Client the Worker was initialized with for Signal, Query, Update, Signal-With-Start, or Update-With-Start <!-- docs/develop/go/nexus/feature-guide.mdx:137; docs/develop/go/nexus/feature-guide.mdx:171-175; docs/develop/go/nexus/feature-guide.mdx:190 -->. All calls must complete within the Nexus request timeout; the `ctx` passed to the handler is set with this deadline, so passing it directly to Temporal Client calls correctly propagates the timeout <!-- docs/develop/go/nexus/feature-guide.mdx:173-175 -->.

```go
var EchoOperation = nexus.NewSyncOperation(service.EchoOperationName, func(ctx context.Context, input service.EchoInput, options nexus.StartOperationOptions) (service.EchoOutput, error) {
    return service.EchoOutput(input), nil
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:159-164 -->

```go
var GetLanguagesOperation = nexus.NewSyncOperation(service.GetLanguagesOperationName, func(ctx context.Context, input service.GetLanguagesInput, options nexus.StartOperationOptions) (service.GetLanguagesOutput, error) {
    c := temporalnexus.GetClient(ctx)
    workflowID := GetWorkflowID(input.UserID)
    // ...
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:189-192 -->

## Asynchronous Operation handlers (Workflow-Run Operations)

`temporalnexus.NewWorkflowRunOperation(name, workflowFn, optsFn)` exposes a Workflow as an async Operation. The options callback returns `client.StartWorkflowOptions` <!-- docs/develop/go/nexus/feature-guide.mdx:200-201; docs/develop/go/nexus/feature-guide.mdx:207-215 -->. Setting `ID: options.RequestID` gives the handler Workflow a stable Workflow ID across retries of the same Operation — the request ID is allocated by Temporal when the caller Workflow schedules the Operation <!-- docs/develop/go/nexus/feature-guide.mdx:209-212 -->. Task Queue defaults to the Task Queue this Operation is handled on <!-- docs/develop/go/nexus/feature-guide.mdx:213 -->.

```go
var HelloOperation = temporalnexus.NewWorkflowRunOperation(service.HelloOperationName, HelloHandlerWorkflow, func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
    return client.StartWorkflowOptions{
        // Workflow IDs should typically be business meaningful IDs and are used to dedupe workflow starts.
        // For this example, we're using the request ID allocated by Temporal when the caller workflow schedules
        // the operation, this ID is guaranteed to be stable across retries of this operation.
        ID: options.RequestID,
        // Task queue defaults to the task queue this operation is handled on.
    }, nil
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:207-215 -->

Multiple callers can attach to the same handler Workflow via Workflow ID Conflict-Policy `Use-Existing`; see `references/core/nexus.md` <!-- docs/develop/go/nexus/feature-guide.mdx:223-227 -->.

## Multi-argument Workflows

A Nexus Operation accepts only one input. To bridge to a Workflow that takes multiple arguments use `temporalnexus.MustNewWorkflowRunOperationWithOptions` (or its non-`Must` form `NewWorkflowRunOperationWithOptions`) with a `WorkflowRunOperationOptions` value whose `Handler` calls `temporalnexus.ExecuteUntypedWorkflow` with the start options and the unpacked arguments <!-- docs/develop/go/nexus/feature-guide.mdx:229-232; docs/develop/go/nexus/feature-guide.mdx:237-254 -->.

```go
var HelloOperation = temporalnexus.MustNewWorkflowRunOperationWithOptions(temporalnexus.WorkflowRunOperationOptions[service.HelloInput, service.HelloOutput]{
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
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:237-254 -->

## Registering Nexus Services on a Worker

Build a Service with `nexus.NewService(name)`, add Operations with `service.Register(op1, op2, ...)`, register the Service on the Worker via `w.RegisterNexusService(service)`, and register the underlying handler Workflows with `w.RegisterWorkflow(...)` so the Worker can execute them <!-- docs/develop/go/nexus/feature-guide.mdx:297-304 -->.

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

<!-- docs/develop/go/nexus/feature-guide.mdx:297-309 -->

## Calling Nexus Operations from a Workflow

Inside a caller Workflow, build a `NexusClient` bound to an Endpoint and Service with `workflow.NewNexusClient(endpointName, serviceName)` (Endpoint first, then Service), then call `client.ExecuteOperation(ctx, operationName, input, workflow.NexusOperationOptions{...})` <!-- docs/develop/go/nexus/feature-guide.mdx:334-336 -->. Wait for the result with `fut.Get(ctx, &res)`. Optionally wait for the start with `fut.GetNexusOperationExecution().Get(ctx, &exec)` — `NexusOperationExecution` contains the operation token for async Operations, used for actions like cancellation <!-- docs/develop/go/nexus/feature-guide.mdx:351-358 -->.

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

func HelloCallerWorkflow(ctx workflow.Context, name string, language service.Language) (string, error) {
    c := workflow.NewNexusClient(endpointName, service.HelloServiceName)

    fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{})
    var res service.HelloOutput

    var exec workflow.NexusOperationExecution
    if err := fut.GetNexusOperationExecution().Get(ctx, &exec); err != nil {
        return "", err
    }
    if err := fut.Get(ctx, &res); err != nil {
        return "", err
    }
    return res.Message, nil
}
```

<!-- docs/develop/go/nexus/feature-guide.mdx:333-364 -->

## Setting per-Operation timeouts

`workflow.NexusOperationOptions` has three timeout fields (semantics in `references/core/nexus.md`) <!-- docs/develop/go/nexus/feature-guide.mdx:369-372 -->:

- `ScheduleToCloseTimeout` — total Operation duration; the Nexus Machinery retries failed requests internally until this is exceeded <!-- docs/develop/go/nexus/feature-guide.mdx:374-383 -->.
- `ScheduleToStartTimeout` — caller's bound on how long it will wait for the handler to start the Operation; if not set, none is enforced. Requires Temporal Server 1.31.0+ (see `references/core/nexus.md`) <!-- docs/develop/go/nexus/feature-guide.mdx:385-394 -->.
- `StartToCloseTimeout` — caller's bound on how long it will wait for an asynchronous Operation to complete after it has been started; applies only to async Operations; if not set, none is enforced. Requires Temporal Server 1.31.0+ <!-- docs/develop/go/nexus/feature-guide.mdx:396-406 -->.

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language}, workflow.NexusOperationOptions{
    ScheduleToCloseTimeout: 10 * time.Minute,
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:379-383 -->

## Cancelling a Nexus Operation

To cancel a Nexus Operation from within a caller Workflow, derive a Go context with `workflow.WithCancel`, which returns a new context and a cancel function; the future returned by `NexusClient.ExecuteOperation` resolves when the Operation finishes — succeeds, fails, times out, or is canceled <!-- docs/develop/go/nexus/feature-guide.mdx:558-562 -->. Only asynchronous Operations can be canceled, because cancellation is sent using an operation token; the Workflow or other resource backing the Operation may ignore the cancel request <!-- docs/develop/go/nexus/feature-guide.mdx:564-566 -->.

Important: once the caller Workflow completes, the caller's Nexus Machinery makes no further attempts to cancel running Operations. To ensure cancellations are delivered, wait for pending Operations to finish before exiting the Workflow <!-- docs/develop/go/nexus/feature-guide.mdx:568-570 -->. See also the [Nexus cancelation sample](https://github.com/temporalio/samples-go/tree/main/nexus-cancelation) <!-- docs/develop/go/nexus/feature-guide.mdx:572 -->.

## Registering the caller Workflow

The caller Worker is registered like any other Workflow Worker; the Endpoint is supplied at call time via `workflow.NewNexusClient`, not via Worker configuration <!-- docs/develop/go/nexus/feature-guide.mdx:334; docs/develop/go/nexus/feature-guide.mdx:438-448 -->.

```go
w := worker.New(c, caller.TaskQueue, worker.Options{})

w.RegisterWorkflow(caller.EchoCallerWorkflow)
w.RegisterWorkflow(caller.HelloCallerWorkflow)

err = w.Run(worker.InterruptCh())
```

<!-- docs/develop/go/nexus/feature-guide.mdx:440-447 -->

## Worker development against a local server

Run a development Temporal Service with `temporal server start-dev`, which serves the Web UI at `http://localhost:8233` and gRPC on `localhost:7233` and creates the `default` Namespace <!-- docs/develop/go/nexus/feature-guide.mdx:56-62 -->. Create caller/handler Namespaces and an Endpoint:

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace

temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

<!-- docs/develop/go/nexus/feature-guide.mdx:68-85 -->

Start the handler Worker pointed at the target Namespace and the caller Worker pointed at the caller Namespace <!-- docs/develop/go/nexus/feature-guide.mdx:519-535 -->.

## Errors

The cross-SDK error model is in `references/core/nexus.md`. On the caller side a failed Nexus Operation produces a Nexus Operation Failure carrying the operation name, token, failure reason, and a `cause` indicating the underlying type (Application Error, Canceled Error, etc.). In Go the relevant types come from `go.temporal.io/sdk/temporal` (error wrappers used inside Workflows) and from the `nexus-rpc` package's predefined Handler errors that handlers return for retryable vs. non-retryable failures. <!-- VERIFY: which Go type is raised inside a caller Workflow when a Nexus Operation fails? The Go-specific Nexus pages do not name a concrete `temporal.NexusOperationError` (or similar) type. -->

## See also

- `references/core/nexus.md` — cross-SDK concepts (Endpoints, Services, Operations, lifecycle, timeouts, retries, circuit breaking, errors, deployment patterns, Registry, security).
- Go Nexus samples: <https://github.com/temporalio/samples-go/tree/main/nexus> <!-- docs/develop/go/nexus/feature-guide.mdx:42 -->.
