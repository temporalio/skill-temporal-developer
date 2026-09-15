# Signal-With-Start

Signal-With-Start lets a caller send a Signal and start a Workflow Execution in one operation if it is not already running.

## What it does

- Lazy initialization: if a Workflow with the given Workflow Id is running, it’s signaled; otherwise it is started and immediately signaled.
- Atomicity: the “start then signal” happens as a single atomic operation.
- Signals are asynchronous and do not return a value to the caller.

## Where to call it

- Use a Temporal Client API for Signal-With-Start. Do not attempt to call Signal-With-Start directly from Workflow code; from a Workflow you can send an External Signal to another running Workflow.

## When to use it

- To lazily initialize per-entity Workflows (e.g., carts, user sessions) while sending the first state-changing message.
- When you do not need a synchronous result from the message handler. For synchronous writes with a result, prefer an Update or Update-With-Start.

## CLI

Temporal CLI supports this via `temporal workflow signal-with-start` (see flags like `--signal-name`, `--type`, `--task-queue`).

## See also

- Python: `references/python/signal-with-start.md`
- .NET: `references/dotnet/signal-with-start.md`
- Related: `references/core/cli-workflow-commands.md`, `references/core/patterns.md`

