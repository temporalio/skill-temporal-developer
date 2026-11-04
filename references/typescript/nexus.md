# Nexus — TypeScript

Use Temporal Nexus from TypeScript with the `@temporalio/nexus` package.

## Key APIs

- `getClient()` — obtain a Temporal Client that shares the same connection as the current Worker; use for Signals, Queries, Updates from sync handlers.
- `WorkflowRunOperationHandler` — start a Workflow as an asynchronous Nexus Operation.

## Choosing Sync vs Async

- Sync handler: only for highly reliable, predictably low‑latency work that completes well within 10s.
- Async handler: use when latency/availability is uncertain, the work may exceed the 10s deadline, or depends on unreliable systems.

## Patterns

- From a sync handler, use `getClient()` to Signal/Query/Update existing Workflows (pass `ctx.abortSignal` to propagate request deadline).
- From an async handler, wrap a Workflow via `new WorkflowRunOperationHandler<In,Out>(...)`.

## Constraints and Behavior

- Sync handlers must complete within the 10‑second Nexus request timeout.
- Circuit breaker trips after 5 consecutive retryable errors for a caller‑Namespace/Endpoint pair.
- Timeouts available to callers: Schedule‑to‑Close, Schedule‑to‑Start, Start‑to‑Close (async only).

## Quick Checklist

- Register the Nexus Service in a Worker listening on the Endpoint’s target Task Queue.
- Ensure the Endpoint’s allowlist includes the caller Namespace.
- Prefer async Operation for anything not comfortably under 10s.

Resources: https://docs.temporal.io/develop/typescript/nexus/feature-guide
