# Common Error Types Reference

| Error Type | Where to Find | What Happened | Recovery |
|------------|---------------|---------------|----------|
| **Non-determinism** | `WorkflowTaskFailed` in history | Replay doesn't match history | Analyze error first. **If accidental**: fix code to match history → restart worker. **If intentional v2 change**: terminate → start fresh workflow. |
| **Workflow code bug** | `WorkflowTaskFailed` in history | Bug in workflow logic | Fix code → Restart worker → Workflow auto-resumes |
| **Missing workflow** | Worker logs | Workflow not registered | Add to worker.py → Restart worker |
| **Missing activity** | Worker logs | Activity not registered | Add to worker.py → Restart worker |
| **Activity bug** | `ActivityTaskFailed` in history | Bug in activity code | Fix code → Restart worker → Auto-retries |
| **Activity retries** | `ActivityTaskFailed` (count >2) | Repeated failures | Fix code → Restart worker → Auto-retries |
| **Sandbox violation** | Worker logs | Bad imports in workflow | Fix workflow.py imports → Restart worker |
| **Task queue mismatch** | Workflow never starts | Different queues in starter/worker | Align task queue names |
| **Timeout** | Status = TIMED_OUT | Operation too slow | Increase timeout config |

## Workflow Status Reference

| Status | Meaning | Action |
|--------|---------|--------|
| `RUNNING` | Workflow in progress | Wait, or check if stalled |
| `COMPLETED` | Successfully finished | Get result, verify correctness |
| `FAILED` | Error during execution | Analyze error |
| `CANCELED` | Explicitly canceled | Review reason |
| `TERMINATED` | Force-stopped | Review reason |
| `TIMED_OUT` | Exceeded timeout | Increase timeout |
