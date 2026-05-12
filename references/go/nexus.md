# Nexus — Go SDK

This file covers building Nexus Services and Operation handlers, registering them in a Worker, and calling Operations from caller Workflows using the Temporal Go SDK. Go SDK support for Nexus is Generally Available <!-- docs/develop/go/nexus/feature-guide.mdx:23 -->. For cross-SDK concepts (lifecycle, retries, circuit breaking, timeouts, security, registry, debugging), see `references/core/nexus.md`.

## Prerequisites

- Temporal CLI v1.3.0 or higher recommended <!-- docs/develop/go/nexus/feature-guide.mdx:50 -->
- Temporal Go SDK v1.33.0 or higher recommended <!-- docs/develop/go/nexus/feature-guide.mdx:51-52 -->

Start a local development server with Nexus enabled using `temporal server start-dev` <!-- docs/develop/go/nexus/feature-guide.mdx:57 -->.

## Define the Service contract

A Nexus Service is defined by string constants for the Service name and Operation names along with input and output Go types. A Nexus Operation can only take one input parameter <!-- docs/develop/go/nexus/feature-guide.mdx:231 -->; multi-argument handler Workflows are supported through a separate builder (see below).

```go
package service

const HelloServiceName = "my-hello-service"

// Echo operation
const EchoOperationName = "echo"

type EchoInput struct {
    Message string
}

type EchoOutput EchoInput
```

The default Data Converter encodes payloads in the order Null, Byte array, Protobuf JSON, and JSON; native Go types work for single-language deployments, while Protobuf or JSON is recommended for polyglot setups <!-- docs/develop/go/nexus/feature-guide.mdx:95-98 -->.

## Synchronous Operation handler

The `nexus.NewSyncOperation` <!-- docs/develop/go/nexus/feature-guide.mdx:136 --> builder exposes simple RPC handlers. Inside a sync handler you can call other services or compute a result directly, or use `temporalnexus.GetClient(ctx)` <!-- docs/develop/go/nexus/feature-guide.mdx:137 --> to obtain the Temporal Client the Worker was initialized with for Signals, Queries, Updates, Signal-With-Start, or Update-With-Start.

```go
import (
    "context"

    "github.com/nexus-rpc/sdk-go/nexus"

    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/temporalnexus"
    "go.temporal.io/sdk/workflow"

    "github.com/temporalio/samples-go/nexus/service"
)

var EchoOperation = nexus.NewSyncOperation(
    service.EchoOperationName,
    func(ctx context.Context, input service.EchoInput, options nexus.StartOperationOptions) (service.EchoOutput, error) {
        return service.EchoOutput(input), nil
    },
)
```

<!-- docs/develop/go/nexus/feature-guide.mdx:159-164 -->

All calls inside a sync handler must complete within the Nexus request timeout; the `ctx` passed to the handler already carries this deadline, so passing it directly to Temporal Client calls propagates it correctly <!-- docs/develop/go/nexus/feature-guide.mdx:173-174 -->. Keep Updates short-lived so they fit within the deadline <!-- docs/develop/go/nexus/feature-guide.mdx:175 -->.

Handlers should be reliable — the circuit breaker trips after 5 consecutive retryable errors, blocking all Operations from the caller to that Endpoint <!-- docs/develop/go/nexus/feature-guide.mdx:124 -->. See `references/core/nexus.md` for the full circuit-breaking behavior.

### Sync handler using the Temporal Client

```go
var GetLanguagesOperation = nexus.NewSyncOperation(
    service.GetLanguagesOperationName,
    func(ctx context.Context, input service.GetLanguagesInput, options nexus.StartOperationOptions) (service.GetLanguagesOutput, error) {
        c := temporalnexus.GetClient(ctx)
        workflowID := GetWorkflowID(input.UserID)
        // ... use c.SignalWorkflow / c.QueryWorkflow / c.UpdateWorkflow ...
    },
)
```

<!-- docs/develop/go/nexus/feature-guide.mdx:189-193 -->

The Go samples include `nexus-messaging/callerpattern/` (Signals/Queries against an existing Workflow) and `nexus-messaging/ondemandpattern/` (start a Workflow through Nexus, then signal it) <!-- docs/develop/go/nexus/feature-guide.mdx:195-196 -->.

## Asynchronous Operation handler (start a Workflow)

The `temporalnexus.NewWorkflowRunOperation` <!-- docs/develop/go/nexus/feature-guide.mdx:128 --> constructor is the easiest way to expose a Workflow as an Operation <!-- docs/develop/go/nexus/feature-guide.mdx:200 -->. The third argument is a function that returns `client.StartWorkflowOptions`; use `options.RequestID` as the Workflow ID for stable dedupe across retries of the same Operation scheduling.

```go
var HelloOperation = temporalnexus.NewWorkflowRunOperation(
    service.HelloOperationName,
    HelloHandlerWorkflow,
    func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
        return client.StartWorkflowOptions{
            // RequestID is stable across retries of this operation.
            ID: options.RequestID,
            // Task queue defaults to the task queue this operation is handled on.
        }, nil
    },
)
```

<!-- docs/develop/go/nexus/feature-guide.mdx:207-215 -->

Workflow IDs should be business-meaningful and are used to dedupe Workflow starts <!-- docs/develop/go/nexus/feature-guide.mdx:220 -->. Multiple Nexus callers can attach to the same handler Workflow with a Conflict-Policy of Use-Existing <!-- docs/develop/go/nexus/feature-guide.mdx:225 -->.

### Mapping one Nexus input to multiple Workflow arguments

A Nexus Operation only accepts one input parameter. To start a Workflow that takes multiple arguments, use `NewWorkflowRunOperationWithOptions` or `MustNewWorkflowRunOperationWithOptions` <!-- docs/develop/go/nexus/feature-guide.mdx:232 --> with `temporalnexus.WorkflowRunOperationOptions[Input, Output]` <!-- docs/develop/go/nexus/feature-guide.mdx:237 -->. The handler returns a `temporalnexus.WorkflowHandle[Output]` <!-- docs/develop/go/nexus/feature-guide.mdx:239 --> typically via `temporalnexus.ExecuteUntypedWorkflow` <!-- docs/develop/go/nexus/feature-guide.mdx:240 -->.

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

## Register the Service in a Worker

Nexus Operation handlers are typically defined in the same Worker as the underlying Temporal primitives they abstract <!-- docs/develop/go/nexus/feature-guide.mdx:121 -->. Register the Service with `nexus.NewService` <!-- docs/develop/go/nexus/feature-guide.mdx:298 -->, then call `service.Register(...)` <!-- docs/develop/go/nexus/feature-guide.mdx:299 --> with each Operation, and `w.RegisterNexusService(service)` <!-- docs/develop/go/nexus/feature-guide.mdx:303 -->.

```go
package main

import (
    "log"

    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "github.com/nexus-rpc/sdk-go/nexus"
    "github.com/temporalio/samples-go/nexus/handler"
    "github.com/temporalio/samples-go/nexus/service"
)

const taskQueue = "my-handler-task-queue"

func main() {
    c, err := client.Dial(client.Options{})
    if err != nil {
        log.Fatalln("Unable to create client", err)
    }
    defer c.Close()

    w := worker.New(c, taskQueue, worker.Options{})

    service := nexus.NewService(service.HelloServiceName)
    err = service.Register(handler.EchoOperation, handler.HelloOperation)
    if err != nil {
        log.Fatalln("Unable to register operations", err)
    }
    w.RegisterNexusService(service)
    w.RegisterWorkflow(handler.HelloHandlerWorkflow)

    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatalln("Unable to start worker", err)
    }
}
```

<!-- docs/develop/go/nexus/feature-guide.mdx:266-311 -->

## Call a Nexus Operation from a caller Workflow

A caller Workflow imports only the Service contract package (names + input/output types) and uses `workflow.NewNexusClient(endpointName, serviceName)` <!-- docs/develop/go/nexus/feature-guide.mdx:334 --> to build a client bound to a Nexus Endpoint and Service. `c.ExecuteOperation(ctx, operationName, input, workflow.NexusOperationOptions{})` <!-- docs/develop/go/nexus/feature-guide.mdx:336 --> returns a future. For async Operations, `fut.GetNexusOperationExecution()` <!-- docs/develop/go/nexus/feature-guide.mdx:356 --> resolves once the Operation has started, yielding a `workflow.NexusOperationExecution` <!-- docs/develop/go/nexus/feature-guide.mdx:355 --> that contains the Operation token used for follow-up actions such as cancellation.

```go
package caller

import (
    "github.com/temporalio/samples-go/nexus/service"
    "go.temporal.io/sdk/workflow"
)

const (
    TaskQueue    = "my-caller-workflow-task-queue"
    endpointName = "my-nexus-endpoint-name"
)

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

    var exec workflow.NexusOperationExecution
    if err := fut.GetNexusOperationExecution().Get(ctx, &exec); err != nil {
        return "", err
    }

    var res service.HelloOutput
    if err := fut.Get(ctx, &res); err != nil {
        return "", err
    }
    return res.Message, nil
}
```

<!-- docs/develop/go/nexus/feature-guide.mdx:321-364 -->

## Operation timeouts

Nexus Operations support three timeout types set on `workflow.NexusOperationOptions` when calling `ExecuteOperation` <!-- docs/develop/go/nexus/feature-guide.mdx:371-372 -->. See `references/core/nexus.md` for the semantics and Server version requirements that apply across SDKs.

### Schedule-to-Close

`ScheduleToCloseTimeout` <!-- docs/develop/go/nexus/feature-guide.mdx:381 --> limits the total duration of the Operation from scheduling to completion; the Nexus Machinery retries failed requests until this timeout is exceeded <!-- docs/develop/go/nexus/feature-guide.mdx:377 -->.

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, input, workflow.NexusOperationOptions{
    ScheduleToCloseTimeout: 10 * time.Minute,
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:380-383 -->

### Schedule-to-Start

`ScheduleToStartTimeout` <!-- docs/develop/go/nexus/feature-guide.mdx:392 --> limits how long the caller will wait for the Operation to be started by the handler. If not set, no Schedule-to-Start timeout is enforced <!-- docs/develop/go/nexus/feature-guide.mdx:388 -->.

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, input, workflow.NexusOperationOptions{
    ScheduleToStartTimeout: 2 * time.Minute,
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:391-394 -->

### Start-to-Close

`StartToCloseTimeout` <!-- docs/develop/go/nexus/feature-guide.mdx:404 --> limits how long the caller waits for an asynchronous Operation to complete after it has been started. It only applies to asynchronous Operations; if not set, no Start-to-Close timeout is enforced <!-- docs/develop/go/nexus/feature-guide.mdx:398-400 -->.

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, input, workflow.NexusOperationOptions{
    StartToCloseTimeout: 5 * time.Minute,
})
```

<!-- docs/develop/go/nexus/feature-guide.mdx:403-406 -->

## Cancelling an Operation

To cancel a Nexus Operation from within a caller Workflow, derive a new context with `workflow.WithCancel` <!-- docs/develop/go/nexus/feature-guide.mdx:560 -->. Calling the returned cancel function cancels the context and any SDK call that was passed this context. The future returned by `NexusClient.ExecuteOperation` resolves when the Operation finishes — succeeds, fails, times out, or is canceled <!-- docs/develop/go/nexus/feature-guide.mdx:562 -->.

Only asynchronous Operations can be canceled, because cancellation is sent using an Operation token <!-- docs/develop/go/nexus/feature-guide.mdx:564 -->. The Workflow or other resources backing the Operation may choose to ignore the cancellation request; if ignored, the Operation may enter a terminal state <!-- docs/develop/go/nexus/feature-guide.mdx:565-566 -->.

Once the caller Workflow completes, the caller's Nexus Machinery makes no further attempts to cancel running Operations <!-- docs/develop/go/nexus/feature-guide.mdx:568 -->. To ensure cancellations are delivered, wait for all pending Operations to finish before exiting the Workflow <!-- docs/develop/go/nexus/feature-guide.mdx:570 -->.

See the [Nexus cancellation sample](https://github.com/temporalio/samples-go/tree/main/nexus-cancelation) <!-- docs/develop/go/nexus/feature-guide.mdx:572 -->.

## Caller and handler Workers across Namespaces

A typical cross-Namespace setup runs:

- A **handler Worker** polling the handler Task Queue in the target Namespace; it registers the Nexus Service and the handler Workflow.
- A **caller Worker** polling the caller Task Queue in the caller Namespace; it registers the caller Workflow.
- A **starter** program that schedules the caller Workflow.

<!-- docs/develop/go/nexus/feature-guide.mdx:412-451, 457-510, 515-548 -->

Connecting Workers to Temporal Cloud uses mTLS client certificates or API keys; see the Cloud sections of the feature guide <!-- docs/develop/go/nexus/feature-guide.mdx:574-721 -->.

## Creating the Endpoint

A Nexus Endpoint routes requests from a caller Namespace to a target Namespace and Task Queue. For local development:

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

<!-- docs/develop/go/nexus/feature-guide.mdx:81-85 -->

For Temporal Cloud the equivalent is `tcld nexus endpoint create` <!-- docs/develop/go/nexus/feature-guide.mdx:625 -->. Refer to `references/core/nexus.md` for the full CLI and `tcld` flag coverage, Access Policy requirements, and Registry behavior.

## Observability

In the Temporal Web UI and Workflow history, a **synchronous** Nexus Operation surfaces in the caller Workflow as `NexusOperationScheduled` followed by `NexusOperationCompleted` <!-- docs/develop/go/nexus/feature-guide.mdx:727, 763-764 -->. An **asynchronous** Nexus Operation surfaces as `NexusOperationScheduled`, `NexusOperationStarted`, and `NexusOperationCompleted` <!-- docs/develop/go/nexus/feature-guide.mdx:734, 757-759 -->. `NexusOperationStarted` is not reported in the caller's history for synchronous Operations <!-- docs/develop/go/nexus/feature-guide.mdx:768 -->.

From the CLI:

```
temporal workflow describe -w <ID>
```

shows pending Nexus Operations in the caller Workflow and attached callbacks on the handler Workflow <!-- docs/develop/go/nexus/feature-guide.mdx:743-746 -->.

```
temporal workflow show -w <ID>
```

includes Nexus events in the caller's Workflow history <!-- docs/develop/go/nexus/feature-guide.mdx:749-752 -->.

For metrics, tracing, and bi-directional linking across the caller and handler Workflows, see `references/core/nexus.md`.

## Samples

The Go SDK Nexus samples live at <https://github.com/temporalio/samples-go/tree/main/nexus> <!-- docs/develop/go/nexus/feature-guide.mdx:42 -->. Notable related samples:

- `nexus-messaging` — caller-pattern and on-demand-pattern Signals/Queries through sync Operations <!-- docs/develop/go/nexus/feature-guide.mdx:177, 195 -->
- `nexus-multiple-arguments` — mapping one Nexus input to multi-arg Workflows <!-- docs/develop/go/nexus/feature-guide.mdx:235 -->
- `nexus-cancelation` — canceling an async Nexus Operation from a caller Workflow <!-- docs/develop/go/nexus/feature-guide.mdx:572 -->

## See also

- `references/core/nexus.md` — concepts, lifecycle, registry, security, debugging, metrics
- `references/go/error-handling.md`
- `references/go/observability.md`
