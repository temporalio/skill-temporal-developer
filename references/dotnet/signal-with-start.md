# Signal-With-Start (.NET)

Use the Client to start a Workflow if needed and send it a Signal in the same operation.

## API surface

- `WorkflowOptions.SignalWithStart((TWorkflow wf) => wf.YourSignalAsync(...))` configures Signal-With-Start for a start call.
- `TemporalClient.StartWorkflowAsync((TWorkflow wf) => wf.RunAsync(), options)` starts the Workflow (and sends the Signal if not already running).

Example tokens to use in generated code (adapt names/values to the user’s app):

- `WorkflowOptions.SignalWithStart(...)`
- `TemporalClient.ConnectAsync(...)`
- `StartWorkflowAsync(...)`

## Don’t do this from Workflow code

- Workflows can send External Signals to other running Workflows with `Workflow.GetExternalWorkflowHandle<T>(...)` and `handle.SignalAsync(...)`, but there is no workflow-side Signal-With-Start API. Use a Client (often from an Activity) if you must perform Signal-With-Start from Workflow-driven logic.

## Behavior notes

- Signals are asynchronous and do not return values; if the caller needs a result, prefer an Update or Update-With-Start.
- Signal-With-Start is atomic: “start then signal” happens as one operation.

## Links

- SDK guide section: https://dotnet.temporal.io/ (see message passing guide)
- Core concept: `references/core/signal-with-start.md`

