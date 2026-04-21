# Cadence Go Determinism

Cadence Go has no sandbox. Determinism is enforced by using workflow-safe APIs and by carefully avoiding native nondeterministic constructs.

## Use These Workflow Primitives

- `workflow.Go()` instead of `go`
- `workflow.Channel` instead of `chan`
- `workflow.Selector` instead of `select`
- `workflow.Sleep()` instead of `time.Sleep()`
- `workflow.Now()` instead of `time.Now()`
- `workflow.SideEffect()` for captured nondeterministic values

## Common Mistakes

- Iterating over maps without sorting keys
- Calling HTTP, DB, or file I/O directly in workflows
- Logging with ordinary app logging instead of `workflow.GetLogger`
- Using random numbers without `workflow.SideEffect`

## Static Analysis

Use Cadence workflow checking and replay tests in CI where available in your codebase. At minimum, keep workflow code small, explicit, and tested with replay-sensitive cases.
