# Cadence Error Reference

## Common Failure Classes

| Area | Typical symptom | Common cause | First check |
|---|---|---|---|
| Non-determinism | Repeated decision task failure | Incompatible workflow code change | Workflow history and recent deployment |
| Activity timeout | Activity failure after waiting | Timeout too short or worker unavailable | Activity options and worker health |
| Activity heartbeat timeout | Long-running activity fails | Missing heartbeats | Activity heartbeat logic |
| Workflow already started | Start request rejected | Reused workflow ID | Workflow ID reuse policy |
| Query failure | Query cannot complete | No worker, no handler, blocking handler | Query registration and worker state |
| Signal appears ineffective | Workflow state unchanged | Wrong signal name or no matching logic | Signal handler wiring |

## Timeouts

Cadence activity troubleshooting often starts with timeout selection:

- `StartToCloseTimeout`: Time for one activity task execution
- `ScheduleToCloseTimeout`: Total time including retries
- `ScheduleToStartTimeout`: Time waiting in a task list before a worker picks it up
- `HeartbeatTimeout`: Max time between heartbeats for long-running activities

## Workflow States To Inspect

Use CLI and visibility to understand whether a workflow is:

- Open and blocked waiting on a timer or signal
- Failing repeatedly on replay
- Completed, failed, timed out, canceled, terminated, or continued as new

## Useful Commands

```bash
cadence workflow describe --workflow_id <id>
cadence workflow show --workflow_id <id>
cadence workflow stack --workflow_id <id>
cadence workflow list --query 'WorkflowType = "MyWorkflow" AND CloseTime = missing'
```
