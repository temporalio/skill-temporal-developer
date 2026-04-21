# Cadence Java Observability

## Workflow Inspection

Useful CLI commands:

```bash
cadence workflow describe --workflow_id <id>
cadence workflow show --workflow_id <id>
cadence workflow stack --workflow_id <id>
```

## Logging

Use the workflow logger inside workflow code and standard application logging inside activities.

## Visibility

Use memo and search attributes for list and query use cases. Search attributes require Cadence advanced visibility support.
