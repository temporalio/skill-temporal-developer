# Nexus — .NET

Use Temporal Nexus from .NET with APIs in the `Temporalio.Nexus` namespace.

## Key APIs

- `NexusOperationExecutionContext.Current.TemporalClient` — obtain the Worker’s Temporal Client for Signals/Queries/Updates in sync handlers.
- `WorkflowRunOperationHandler.FromHandleFactory(...)` — expose a Workflow as an asynchronous Nexus Operation.
- `OperationHandler.Sync<In,Out>(...)` — simple synchronous handler implementation.

## Choosing Sync vs Async

- Sync handler: use only for reliable, short work that finishes well within 10s.
- Async handler: use when latency/availability is uncertain or work can exceed 10s.

## Constraints and Behavior

- Sync handlers must complete within the 10‑second Nexus request timeout.
- Circuit breaker trips after 5 consecutive retryable errors (per caller‑Namespace/Endpoint pair).
- Caller‑side timeouts: Schedule‑to‑Close (overall), Schedule‑to‑Start, Start‑to‑Close (async only).

## Quick Checklist

- Register Nexus Service handlers in a Worker polling the Endpoint’s target Task Queue.
- Ensure the Endpoint’s allowlist includes the caller Namespace.
- Prefer async Operation when in doubt about finishing under 10s.

Resources: https://docs.temporal.io/develop/dotnet/nexus/feature-guide
