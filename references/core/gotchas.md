# Cadence Gotchas

## Putting I/O In Workflow Code

Workflow code must not call databases, filesystems, HTTP services, or any other external system directly.

Use activities for all external side effects.

## Using Native Concurrency Primitives

Do not use normal language concurrency primitives inside workflow code when the SDK provides deterministic alternatives.

Examples:

- Go: avoid native goroutines, channels, `select`, `time.Now`, `time.Sleep`
- Java: avoid normal thread management and blocking constructs outside Cadence workflow APIs

## Refactoring Command Order Without Versioning

Changing the order of activity calls, timer creation, child workflows, or continue-as-new logic can break replay.

Use Cadence versioning APIs when changing workflow command structure.

## Mutating State In Query Handlers

Queries are read-only. They must not:

- Change workflow state
- Call activities
- Sleep or block waiting for work

## Assuming Temporal Features Exist In Cadence

This repository now follows official Cadence scope only.

Do not use Temporal-only guidance for:

- Updates
- Worker Versioning / Build IDs
- Schedule APIs
- Temporal Cloud

See `references/non-compatible/README.md`.

## Letting History Grow Unbounded

Long-running workflows can become slow or expensive to replay if they keep accumulating history forever.

Use continue-as-new for loops, heavy signal traffic, or periodic orchestration.

## Forgetting Search Attribute Prerequisites

Search attributes depend on advanced visibility and server-side allowlisting. Starting a workflow with search attributes does not automatically make them searchable in every Cadence deployment.

## Using Workflow IDs Poorly

Workflow IDs are often business identifiers. Reuse policy matters.

Choose explicit reuse behavior and avoid accidental duplicate-start assumptions.
