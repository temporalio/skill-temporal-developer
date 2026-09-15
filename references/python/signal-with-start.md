# Signal-With-Start (Python)

Use the Client to start a Workflow if needed and send it a Signal in the same call.

## API surface

- `Client.start_workflow` with `start_signal` and `start_signal_args` sends a Signal and starts the Workflow if necessary.

Example tokens to use in generated code (adapt names/values to the user’s app):

- `Client.start_workflow`
- `start_signal`
- `start_signal_args`

## Don’t do this from Workflow code

- Workflows can send External Signals to other running Workflows using a handle from `workflow.get_external_workflow_handle_for(...)`, but there is no workflow-side Signal-With-Start API. Use a Client (often from an Activity) if you must perform Signal-With-Start from Workflow-driven logic.

## Behavior notes

- Signals are asynchronous and do not return values; if the caller needs a result, prefer an Update or Update-With-Start.
- Signal-With-Start is atomic: “start then signal” happens as one operation.

## Links

- SDK guide section: https://python.temporal.io/ (Client reference in docs page)
- Core concept: `references/core/signal-with-start.md`

