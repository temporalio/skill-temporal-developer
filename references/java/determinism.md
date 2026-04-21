# Cadence Java Determinism

Cadence Java replays workflow code against event history. Workflow code must avoid non-deterministic behavior.

## Use Workflow APIs

- `Workflow.currentTimeMillis()` instead of wall-clock time
- `Workflow.sleep()` instead of `Thread.sleep`
- `Promise` and Cadence workflow constructs instead of arbitrary async frameworks
- Activities for external I/O

## Avoid

- Direct network or database calls in workflow code
- Randomness without a replay-safe capture pattern
- Blocking code in query methods
- Changing command order without `Workflow.getVersion`
