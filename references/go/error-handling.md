# Cadence Go Error Handling

## Activity Errors

Activities return ordinary Go errors. Cadence wraps them so workflow code can inspect failure type and retry behavior.

## Timeout Basics

Set activity timeouts explicitly:

```go
ao := workflow.ActivityOptions{
	StartToCloseTimeout: time.Minute,
	ScheduleToCloseTimeout: 10 * time.Minute,
}
```

Use `StartToCloseTimeout` for one attempt and `ScheduleToCloseTimeout` for total retry window.

## Long-Running Activities

Use heartbeats from activity code so cancellation and liveness work correctly.

## Workflow Error Strategy

- Handle expected activity failures explicitly
- Let truly fatal business failures terminate the workflow
- Put side effects in activities so retries remain safe
