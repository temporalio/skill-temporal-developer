# Cadence Java Error Handling

## Activity Failures

Model expected business errors clearly and let retry policy handle transient failures.

## Activity Options

```java
ActivityOptions options =
    new ActivityOptions.Builder()
        .setStartToCloseTimeout(Duration.ofMinutes(1))
        .setScheduleToCloseTimeout(Duration.ofMinutes(10))
        .build();
```

## Workflow Failures

- Catch and handle expected activity failures where business logic can recover
- Let unrecoverable logic fail the workflow visibly
- Keep side effects in activities

## Long-Running Activities

Use activity heartbeats for cancellation and liveness tracking.
