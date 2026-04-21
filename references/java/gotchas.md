# Cadence Java Gotchas

## Workflow Constructors And State

Keep workflow state on the workflow implementation object and initialize it predictably.

## Query Methods

Do not mutate state or block from a `@QueryMethod`.

## Activity Calls In Workflows

Always go through activity stubs. Never call external systems directly.

## Versioning

Use `Workflow.getVersion` before changing workflow command order.

## Temporal-Only APIs

Do not use `@UpdateMethod`, Schedule APIs, or Worker Versioning guidance from Temporal examples.
