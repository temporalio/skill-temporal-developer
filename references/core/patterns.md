# Cadence Patterns

This document covers Cadence patterns that are shared across supported SDKs in this repository.

## Signals

Signals are asynchronous, durable messages sent to a running workflow.

Use signals when you need to:

- Push external events into a workflow
- Pause until a human or system responds
- Change workflow behavior without restarting it

Signals mutate workflow state, but they do not directly return a result to the caller.

## Queries

Queries expose workflow state to the outside world.

Use queries when you need to:

- Inspect workflow state
- Fetch progress or status
- Retrieve diagnostic information such as a stack trace

Query handlers must be read-only and non-blocking.

## Signal Plus Query

Cadence does not have Temporal-style Updates in the official scope used by this skill.

When you need “change state and then observe the result”, use:

1. A signal to request the state change
2. A query to observe the resulting state

See `references/non-compatible/README.md` for the compatibility gap.

## Child Workflows

Use child workflows when:

- A single workflow would grow too large
- You need a separate workflow lifecycle per resource
- You want clearer ownership boundaries between workflow types

Prefer a single workflow first when the problem size is bounded. Child workflows add coordination complexity.

## Continue As New

Use continue-as-new to keep workflow history from growing without bound.

Good triggers:

- Long-running loops
- High signal volume
- Periodic workflows that should conceptually keep running

When continuing as new, carry forward the state needed for the next run.

## Sagas

Use compensating activities when a business process spans multiple side effects that may need rollback.

Typical shape:

1. Execute activity A
2. Register compensation for A
3. Execute activity B
4. Register compensation for B
5. On failure, run compensations in reverse order

Compensation code belongs in activities, not workflow-local side effects.

## Search Attributes And Memo

Use memo for non-indexed metadata visible in list results.

Use search attributes for indexed fields you want to query through advanced visibility.

Search attributes require Cadence visibility infrastructure support.

## Distributed Cron

For recurring workflow execution in Cadence, use distributed cron where the SDK supports it.

Do not assume Temporal Schedule APIs exist in Cadence.

## Human Tasks

A common Cadence pattern is:

1. Activity creates or publishes a human task in an external system
2. Workflow blocks on a signal
3. External system signals the workflow after user action

This keeps the durable waiting logic inside the workflow and all external integration in activities.
