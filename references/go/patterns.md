# Cadence Go Patterns

## Signals

```go
signalCh := workflow.GetSignalChannel(ctx, "approve")
var approved bool
signalCh.Receive(ctx, &approved)
```

Use `workflow.NewSelector` when waiting on multiple events.

## Queries

```go
status := "waiting"
err := workflow.SetQueryHandler(ctx, "status", func() (string, error) {
	return status, nil
})
```

Query handlers must be read-only and non-blocking.

## Child Workflows

```go
var childResult string
err := workflow.ExecuteChildWorkflow(ctx, ChildWorkflow, input).Get(ctx, &childResult)
```

## Continue As New

```go
return workflow.NewContinueAsNewError(ctx, MyWorkflow, nextState)
```

Use it to cap history size.

## SignalWithStart

Use client-side `SignalWithStartWorkflow` when callers do not know whether the target workflow is already running.

## No Updates

Cadence Go does not use Temporal-style Update handlers in this skill. Use signals plus queries instead.
