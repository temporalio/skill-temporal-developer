# Go SDK — Cross-Namespace Deprecation

This page is the Go-specific view of the cross-Namespace command deprecation.
For the cross-language concept and the migration rationale, see
`references/core/cross-namespace-deprecation.md`.

## What's affected

Three Workflow Commands historically supported targeting another Namespace from
within a Workflow:

- `StartChildWorkflowExecution` <!-- docs/references/commands.mdx:49 -->
- `SignalExternalWorkflowExecution` <!-- docs/references/commands.mdx:58 -->
- `RequestCancelExternalWorkflowExecution` <!-- docs/references/commands.mdx:67 -->

On OSS, those Commands accept a target Namespace only when
`system.enableCrossNamespaceCommands` is enabled. That configuration is
disabled on Temporal Cloud, and any code using cross-Namespace calls must be
updated or removed prior to migration. <!-- docs/cloud/migrate/automated.mdx:419-422 -->

Nexus is the supported replacement for connecting Temporal Applications across
Namespaces; Child Workflows remain "Limited to the same Namespace." <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:51 -->

## Spotting the pattern in Go code

The Go SDK reference docs document only same-Namespace shapes for the three
APIs that map to these Commands. Use these as the baseline when auditing code
for what is and is not documented.

### `workflow.ExecuteChildWorkflow`

The documented Child Workflow shape uses `workflow.ChildWorkflowOptions`
applied to the workflow context with
`workflow.WithChildOptions`. <!-- docs/develop/go/workflows/child-workflows.mdx:36-41 -->

```go
func YourWorkflowDefinition(ctx workflow.Context, params ParentParams) (ParentResp, error) {

  childWorkflowOptions := workflow.ChildWorkflowOptions{}
  ctx = workflow.WithChildOptions(ctx, childWorkflowOptions)

  var result ChildResp
  err := workflow.ExecuteChildWorkflow(ctx, YourOtherWorkflowDefinition, ChildParams{}).Get(ctx, &result)
  if err != nil {
    // ...
  }
  // ...
  return resp, nil
}
```
<!-- docs/develop/go/workflows/child-workflows.mdx:47-60 -->

Note: the Go child-workflows reference does **not** document a Namespace field
on `workflow.ChildWorkflowOptions`. <!-- VERIFY: docs/develop/go/workflows/child-workflows.mdx does not document a Namespace field on workflow.ChildWorkflowOptions; consult go.temporal.io/sdk source if you need the historical field name --> Any code that set a target Namespace
in those options was relying on functionality that the OSS server gates with
`system.enableCrossNamespaceCommands`, which is disabled on Temporal Cloud. <!-- docs/cloud/migrate/automated.mdx:419-422 -->
Do not introduce such a field into new code; migrate to Nexus instead.

### `workflow.SignalExternalWorkflow`

The documented External Signal call from inside a Workflow takes a Workflow
Id, a Run Id (empty string if unknown), a Signal name, and the Signal
argument:

```go
err := workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal).Get(ctx, nil)
```
<!-- docs/develop/go/workflows/message-passing.mdx:295 -->

The third positional argument is the Run Id, not a Namespace. The Go
message-passing reference does not document a Namespace parameter on
`workflow.SignalExternalWorkflow`. <!-- VERIFY: docs/develop/go/workflows/message-passing.mdx documents the signature (ctx, workflowID, runID, signalName, arg); it does not document a Namespace argument --> Code that historically targeted another
Namespace via this API was likewise relying on the server-side gate described
above.

### Cancel External Workflow

The Go developer docs available here do not document a `workflow.*` API for
the `RequestCancelExternalWorkflowExecution` Command. <!-- VERIFY: no documented Go SDK example for RequestCancelExternalWorkflowExecution in docs/develop/go --> If your code triggers
this Command across Namespaces, the same server-side gate applies and the
migration target is Nexus.

## Migration: Temporal Nexus (Go)

Temporal Nexus connects Temporal Applications within and across Namespaces
using a Nexus Endpoint, a Nexus Service contract, and Nexus
Operations. <!-- docs/develop/go/nexus/feature-guide.mdx:27 --> Nexus is not a drop-in
replacement for child Workflows or external Signals — it is a different
programming model. The caller invokes an Operation through a Nexus client; the
handler decides whether the Operation is synchronous or backed by a handler
Workflow.

### Endpoint and Namespaces

Create caller and handler Namespaces, then create a Nexus Endpoint that points
the caller at the handler's Task Queue in the target Namespace:

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace

temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```
<!-- docs/develop/go/nexus/feature-guide.mdx:69-85 -->

For Temporal Cloud, the same Endpoint is created via `tcld nexus endpoint
create` with `--target-namespace <my-target-namespace.account>`. <!-- docs/develop/go/nexus/feature-guide.mdx:624-630 -->

### Service contract

Define the Service name, Operation names, and input/output types in a package
shared between caller and handler:

```go
const HelloServiceName = "my-hello-service"

// Echo operation
const EchoOperationName = "echo"

type EchoInput struct {
    Message string
}

type EchoOutput EchoInput
```
<!-- docs/develop/go/nexus/feature-guide.mdx:105-114 -->

### Handler

A synchronous handler is constructed with `nexus.NewSyncOperation`. Use
`temporalnexus.GetClient(ctx)` to reach the Temporal Client the Worker was
initialized with for Signals, Queries, and Updates against a Workflow in the
handler Namespace. <!-- docs/develop/go/nexus/feature-guide.mdx:136-137 -->

```go
var EchoOperation = nexus.NewSyncOperation(service.EchoOperationName, func(ctx context.Context, input service.EchoInput, options nexus.StartOperationOptions) (service.EchoOutput, error) {
    return service.EchoOutput(input), nil
})
```
<!-- docs/develop/go/nexus/feature-guide.mdx:159-164 -->

An asynchronous handler that starts a Workflow uses
`temporalnexus.NewWorkflowRunOperation`: <!-- docs/develop/go/nexus/feature-guide.mdx:200-201 -->

```go
var HelloOperation = temporalnexus.NewWorkflowRunOperation(service.HelloOperationName, HelloHandlerWorkflow, func(ctx context.Context, input service.HelloInput, options nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
    return client.StartWorkflowOptions{
        ID: options.RequestID,
    }, nil
})
```
<!-- docs/develop/go/nexus/feature-guide.mdx:207-215 -->

Register the Service on the handler Worker with
`worker.RegisterNexusService` after building it via
`nexus.NewService(...).Register(...)`. <!-- docs/develop/go/nexus/feature-guide.mdx:298-303 -->

### Caller Workflow

In the caller Namespace, build a Nexus client with
`workflow.NewNexusClient(endpointName, serviceName)` and invoke
`ExecuteOperation`. The returned future resolves when the Operation completes.

```go
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
```
<!-- docs/develop/go/nexus/feature-guide.mdx:328-344 -->

For asynchronous Operations, `fut.GetNexusOperationExecution().Get(ctx,
&exec)` yields a `workflow.NexusOperationExecution` containing the Operation
token; this token is what you use to cancel an asynchronous Operation later
via `workflow.WithCancel`. <!-- docs/develop/go/nexus/feature-guide.mdx:352-358 --> <!-- docs/develop/go/nexus/feature-guide.mdx:560-564 -->

### Mapping the old pattern

| Old (Go) | New (Go, Nexus) |
| --- | --- |
| `workflow.ExecuteChildWorkflow` targeting another Namespace | Caller calls `c.ExecuteOperation(...)`; handler returns `client.StartWorkflowOptions` from `NewWorkflowRunOperation`. <!-- docs/develop/go/nexus/feature-guide.mdx:207-215 --> |
| `workflow.SignalExternalWorkflow` targeting another Namespace | Sync Operation handler uses `temporalnexus.GetClient(ctx)` to signal the target Workflow. <!-- docs/develop/go/nexus/feature-guide.mdx:159-164 --> |
| `RequestCancelExternalWorkflowExecution` targeting another Namespace | Cancel an asynchronous Nexus Operation via `workflow.WithCancel`; the handler decides what cancelation means for the backing Workflow. <!-- docs/develop/go/nexus/feature-guide.mdx:560-565 --> |

Same-Namespace use of these three APIs is unaffected. The deprecation is
about *cross-Namespace* targeting only.

## Distinguish from `DeprecateNamespace`

Namespace deprecation as a lifecycle operation (the `UpdateNamespace`-family
APIs and the `temporal operator namespace update` CLI surface) is a separate
concept covered in `docs/develop/go/client/namespaces.mdx` and is unrelated to
the cross-Namespace command deprecation discussed
here. <!-- docs/develop/go/client/namespaces.mdx:90-94 --> Renaming, updating, or
deprecating a Namespace does not change whether
`system.enableCrossNamespaceCommands` is enabled on the server.
