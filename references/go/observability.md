# Cadence Go Observability

## Workflow Logging

Use replay-safe workflow logging:

```go
logger := workflow.GetLogger(ctx)
logger.Info("processing request")
```

## Activity Logging

Use your normal application logger in activities.

## Useful Signals For Troubleshooting

- Workflow stack traces via CLI queries
- Workflow history via `cadence workflow show`
- Task list health via `cadence tasklist desc`

## Visibility

Use memo for display metadata and search attributes for indexed filtering when advanced visibility is enabled.
