# Nexus — Go SDK

This file covers the Go SDK programming model for Temporal Nexus: import paths, builders, options structs, the caller-side client API, and futures-style result handling. Shared concepts (lifecycle, timeout semantics, retries, circuit breaking, cancellation vs termination, deployment, security, debugging, metrics) live in `references/core/nexus.md`.

## Support status

Temporal Go SDK support for Nexus is **Generally Available**. <!-- docs/develop/go/nexus/feature-guide.mdx:23 -->

Recommended prerequisites from the feature guide: <!-- docs/develop/go/nexus/feature-guide.mdx:50-52 -->

- Temporal CLI v1.3.0 or higher.
- Temporal Go SDK v1.33.0 or higher.

## Packages

Nexus in Go spans four packages:

- `github.com/nexus-rpc/sdk-go/nexus` — the cross-SDK Nexus primitives (`NewSyncOperation`, `NewService`, `StartOperationOptions`). <!-- docs/develop/go/nexus/feature-guide.mdx:149 -->
- `go.temporal.io/sdk/temporalnexus` — Temporal-specific helpers and builders (`GetClient`, `NewWorkflowRunOperation`, `MustNewWorkflowRunOperationWithOptions`, `WorkflowRunOperationOptions`, `WorkflowHandle`, `ExecuteUntypedWorkflow`). <!-- docs/develop/go/nexus/feature-guide.mdx:126-130 -->
- `go.temporal.io/sdk/workflow` — caller-side `NewNexusClient`, `NexusOperationOptions`, `NexusOperationExecution`. <!-- docs/develop/go/nexus/feature-guide.mdx:334-356 -->
- `go.temporal.io/sdk/worker` and `go.temporal.io/sdk/client` — worker creation and Temporal Client. <!-- docs/develop/go/nexus/feature-guide.mdx:272-273 -->

## Defining the Service contract

A Nexus Service contract is a shared Go package that declares the Service and Operation **name constants** plus the input/output Go types. Callers and handlers both import this package so they speak the same wire contract. <!-- docs/develop/go/nexus/feature-guide.mdx:91-98 -->

```go
// service/api.go  --  docs/develop/go/nexus/feature-guide.mdx:100-116
package service

const HelloServiceName = "my-hello-service"

// Echo operation
const EchoOperationName = "echo"

type EchoInput struct {
    Message string
}

type EchoOutput EchoInput
```

The default Data Converter encodes payloads in order: Null, Byte array, Protobuf JSON, then JSON; in polyglot setups prefer Protobuf or JSON-friendly types. <!-- docs/develop/go/nexus/feature-guide.mdx:95-98 -->

## Synchronous Operation handler

Use `nexus.NewSyncOperation` to expose a simple RPC-style handler. The handler signature is `func(ctx context.Context, input TIn, options nexus.StartOperationOptions) (TOut, error)`. <!-- docs/develop/go/nexus/feature-guide.mdx:136-167 -->

```go
// handler/app.go  --  docs/develop/go/nexus/feature-guide.mdx:142-166
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

Sync handlers should be **reliable** — the circuit breaker trips after 5 consecutive retryable errors and blocks all Operations from the caller to that Endpoint. <!-- docs/develop/go/nexus/feature-guide.mdx:124 -->

## Using the Temporal Client from a sync handler

Inside a sync handler, call `temporalnexus.GetClient(ctx)` to get the same Temporal `client.Client` the Worker was initialized with. Typical uses are Signal, Query, Update, Signal-With-Start, and Update-With-Start. <!-- docs/develop/go/nexus/feature-guide.mdx:137,170-175 -->

The `ctx` passed to the handler is already set with the Nexus request deadline. Pass that `ctx` straight into Temporal Client calls so the deadline propagates; Updates in particular should be short-lived to fit within the deadline. <!-- docs/develop/go/nexus/feature-guide.mdx:173-175 -->

```go
// docs/develop/go/nexus/feature-guide.mdx:184-193
func GetWorkflowID(userID string) string {
    return WorkflowIDPrefix + userID
}

var GetLanguagesOperation = nexus.NewSyncOperation(
    service.GetLanguagesOperationName,
    func(ctx context.Context, input service.GetLanguagesInput, options nexus.StartOperationOptions) (service.GetLanguagesOutput, error) {
        c := temporalnexus.GetClient(ctx)
        workflowID := GetWorkflowID(input.UserID)
        // ... use c with the same ctx so the Nexus deadline propagates
        _ = c
        _ = workflowID
        return service.GetLanguagesOutput{}, nil
    },
)
```

## Asynchronous Workflow-Run Operation

Use `temporalnexus.NewWorkflowRunOperation` to expose a Workflow as an asynchronous Nexus Operation. The third argument is an options function that returns `client.StartWorkflowOptions`. <!-- docs/develop/go/nexus/feature-guide.mdx:200-217 -->

```go
// handler/app.go  --  docs/develop/go/nexus/feature-guide.mdx:205-217
var HelloOperation = temporalnexus.NewWorkflowRunOperation(
    service.HelloOperationName,
    HelloHandlerWorkflow,
    func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
        return client.StartWorkflowOptions{
            // Workflow IDs should typically be business-meaningful and are used to dedupe Workflow starts.
            // RequestID is allocated by Temporal when the caller Workflow schedules the operation
            // and is guaranteed to be stable across retries of this operation.
            ID: options.RequestID,
            // Task queue defaults to the task queue this operation is handled on.
        }, nil
    },
)
```

Two key points:

- `options.RequestID` is **stable across retries** of the operation, which makes it a safe deterministic dedup key when no business ID is available. <!-- docs/develop/go/nexus/feature-guide.mdx:210-212 -->
- If `TaskQueue` is omitted, the handler Workflow is started on the same task queue this Nexus Operation is handled on. <!-- docs/develop/go/nexus/feature-guide.mdx:213 -->

For attaching multiple Nexus callers to a single handler Workflow, use a Conflict-Policy of Use-Existing (see core/nexus.md). <!-- docs/develop/go/nexus/feature-guide.mdx:223-227 -->

## Multiple Workflow arguments

A Nexus Operation accepts only one input parameter. To start a Workflow that takes multiple arguments, use `MustNewWorkflowRunOperationWithOptions` (or `NewWorkflowRunOperationWithOptions`) together with `temporalnexus.WorkflowRunOperationOptions[TIn, TOut]` and `temporalnexus.ExecuteUntypedWorkflow`. <!-- docs/develop/go/nexus/feature-guide.mdx:231-257 -->

```go
// nexus-multiple-arguments/handler/app.go
// docs/develop/go/nexus/feature-guide.mdx:237-256
var HelloOperation = temporalnexus.MustNewWorkflowRunOperationWithOptions(
    temporalnexus.WorkflowRunOperationOptions[service.HelloInput, service.HelloOutput]{
        Name: service.HelloOperationName,
        Handler: func(
            ctx context.Context,
            input service.HelloInput,
            options nexus.StartOperationOptions,
        ) (temporalnexus.WorkflowHandle[service.HelloOutput], error) {
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

`ExecuteUntypedWorkflow` returns a `temporalnexus.WorkflowHandle[TOut]`, which the framework uses to track the asynchronous result. <!-- docs/develop/go/nexus/feature-guide.mdx:239-242 -->

## Registering with a Worker

Construct a `nexus.Service`, register your operations on it, then attach it to a `worker.Worker`. Also register the handler Workflow itself. <!-- docs/develop/go/nexus/feature-guide.mdx:295-311 -->

```go
// handler/worker/main.go  --  docs/develop/go/nexus/feature-guide.mdx:266-310
package main

import (
    "log"
    "os"

    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "github.com/nexus-rpc/sdk-go/nexus"
    "github.com/temporalio/samples-go/nexus/handler"
    "github.com/temporalio/samples-go/nexus/options"
    "github.com/temporalio/samples-go/nexus/service"
)

const taskQueue = "my-handler-task-queue"

func main() {
    clientOptions, err := options.ParseClientOptionFlags(os.Args[1:])
    if err != nil {
        log.Fatalf("Invalid arguments: %v", err)
    }
    c, err := client.Dial(clientOptions)
    if err != nil {
        log.Fatalln("Unable to create client", err)
    }
    defer c.Close()

    w := worker.New(c, taskQueue, worker.Options{})

    svc := nexus.NewService(service.HelloServiceName)
    if err := svc.Register(handler.EchoOperation, handler.HelloOperation); err != nil {
        log.Fatalln("Unable to register operations", err)
    }
    w.RegisterNexusService(svc)
    w.RegisterWorkflow(handler.HelloHandlerWorkflow)

    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatalln("Unable to start worker", err)
    }
}
```

Order matters: register Workflows and the Nexus Service on the Worker **before** calling `w.Run`. <!-- docs/develop/go/nexus/feature-guide.mdx:303-309 -->

## Caller Workflow

A caller Workflow uses `workflow.NewNexusClient(endpointName, serviceName)` to build a Nexus client bound to a specific endpoint and service, then calls `ExecuteOperation`. The returned future is resolved when the operation finishes. <!-- docs/develop/go/nexus/feature-guide.mdx:333-343 -->

```go
// caller/workflows.go  --  docs/develop/go/nexus/feature-guide.mdx:320-344
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

    fut := c.ExecuteOperation(
        ctx,
        service.EchoOperationName,
        service.EchoInput{Message: message},
        workflow.NexusOperationOptions{},
    )

    var res service.EchoOutput
    if err := fut.Get(ctx, &res); err != nil {
        return "", err
    }
    return res.Message, nil
}
```

### Waiting for the operation to start

For async operations you can optionally wait for the start phase to complete by calling `fut.GetNexusOperationExecution()`. It resolves to a `workflow.NexusOperationExecution`, which carries the **operation token** — a handle suitable for follow-up actions like external cancellation. <!-- docs/develop/go/nexus/feature-guide.mdx:346-364 -->

```go
// docs/develop/go/nexus/feature-guide.mdx:346-364
func HelloCallerWorkflow(ctx workflow.Context, name string, language service.Language) (string, error) {
    c := workflow.NewNexusClient(endpointName, service.HelloServiceName)

    fut := c.ExecuteOperation(
        ctx,
        service.HelloOperationName,
        service.HelloInput{Name: name, Language: language},
        workflow.NexusOperationOptions{},
    )

    // Optional: wait for the operation to be started so we get the operation token.
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

## Setting timeouts

Pass timeouts on `workflow.NexusOperationOptions` when calling `ExecuteOperation`. The three timeouts cover different stages of the operation lifecycle — see `core/nexus.md` for what each one means. <!-- docs/develop/go/nexus/feature-guide.mdx:369-406 -->

### Schedule-to-Close

Limits the **total** duration of the operation, from scheduling through completion; the Nexus Machinery retries failed requests until this is exceeded. <!-- docs/develop/go/nexus/feature-guide.mdx:374-383 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language},
    workflow.NexusOperationOptions{
        ScheduleToCloseTimeout: 10 * time.Minute,
    })
```

### Schedule-to-Start

Limits how long the caller will wait for the operation to be **started** by the handler. If not set, no Schedule-to-Start timeout is enforced. <!-- docs/develop/go/nexus/feature-guide.mdx:386-394 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language},
    workflow.NexusOperationOptions{
        ScheduleToStartTimeout: 2 * time.Minute,
    })
```

### Start-to-Close

Limits how long the caller will wait for an **asynchronous** operation to complete after it has been started. Applies only to async operations; if not set, no Start-to-Close timeout is enforced. <!-- docs/develop/go/nexus/feature-guide.mdx:397-406 -->

```go
fut := c.ExecuteOperation(ctx, service.HelloOperationName, service.HelloInput{Name: name, Language: language},
    workflow.NexusOperationOptions{
        StartToCloseTimeout: 5 * time.Minute,
    })
```

## Cancellation

To cancel a Nexus Operation from within a caller Workflow, derive a new context with `workflow.WithCancel`. The returned cancel function cancels any SDK call that received that context. The `ExecuteOperation` future is resolved when the operation finishes — whether it succeeds, fails, times out, or is canceled. <!-- docs/develop/go/nexus/feature-guide.mdx:558-562 -->

```go
// docs/develop/go/nexus/feature-guide.mdx:558-562
cctx, cancel := workflow.WithCancel(ctx)
fut := c.ExecuteOperation(cctx, service.HelloOperationName, input, workflow.NexusOperationOptions{})
// later:
cancel()
var res service.HelloOutput
err := fut.Get(ctx, &res) // resolves when the operation finishes (success, failure, timeout, or cancel)
```

Key constraints from the Go feature guide: <!-- docs/develop/go/nexus/feature-guide.mdx:564-570 -->

- **Only asynchronous operations can be canceled** — cancellation is delivered using the operation token.
- The Workflow or other resource backing the operation may **ignore** the cancellation request; if ignored, the operation may end in a terminal state.
- Once the caller Workflow completes, the Nexus Machinery will not make further attempts to cancel operations that are still running. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow.

<!-- VERIFY: The Go feature guide does not enumerate cancellation-type enum names (ABANDON / TRY_CANCEL / WAIT_REQUESTED / WAIT_COMPLETED). If those names exist on `workflow.NexusOperationOptions` in the Go SDK API, they are not documented in feature-guide.mdx. -->

## History events

Nexus events are part of the **caller's** Workflow history. <!-- docs/develop/go/nexus/feature-guide.mdx:749-770 -->

For **asynchronous** Nexus Operations:

- `NexusOperationScheduled`
- `NexusOperationStarted`
- `NexusOperationCompleted`

For **synchronous** Nexus Operations:

- `NexusOperationScheduled`
- `NexusOperationCompleted`

`NexusOperationStarted` is **not** reported for synchronous operations. <!-- docs/develop/go/nexus/feature-guide.mdx:766-770 -->

Inspect them with the standard CLI commands:

```
temporal workflow describe -w <ID>
temporal workflow show -w <ID>
```

## End-to-end recipe pointer

The full local-dev flow from the feature guide: <!-- docs/develop/go/nexus/feature-guide.mdx:46-87,513-555 -->

1. `temporal server start-dev` to bring up the dev server with Nexus enabled.
2. `temporal operator namespace create --namespace my-target-namespace` and `--namespace my-caller-namespace`.
3. `temporal operator nexus endpoint create --name my-nexus-endpoint-name --target-namespace my-target-namespace --target-task-queue my-handler-task-queue`.
4. Run the handler Worker (`go run ./worker -target-host localhost:7233 -namespace my-target-namespace`).
5. Run the caller Worker against `my-caller-namespace`.
6. Run the starter against `my-caller-namespace`.

See the feature guide for the full sequence, including expected log output.

## Cross-Namespace in Temporal Cloud

For Temporal Cloud, the feature guide uses `tcld` to create caller/handler namespaces and the Nexus Endpoint, plus mTLS certs (or API keys) for the Workers. The endpoint-creation command in the Go feature guide is: <!-- docs/develop/go/nexus/feature-guide.mdx:622-632 -->

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --description-file description.md
```

Creating a Nexus Endpoint requires a Developer account role or higher and NamespaceAdmin permission on the `--target-namespace`. <!-- docs/develop/go/nexus/feature-guide.mdx:622 -->

<!-- VERIFY: The Go feature guide's tcld example does NOT include a `--allow-namespace` flag for restricting which caller namespaces may invoke the endpoint. Confirm whether that flag exists in the current tcld release before relying on it here; the core reference is the source of truth for any allow-list configuration. -->

For full Cloud setup (cert generation, `tcld namespace create`, connecting Workers with mTLS or API keys), see the feature guide and `core/nexus.md` rather than reproducing it here.
