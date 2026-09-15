# Continue-As-New Backoff (Start Delay)

One-sentence description: Continue-as-new supports a backoff start interval to delay the next run’s start time.

## Summary

Continue-As-New can start the next Workflow run after a delay by applying a start backoff on the new run. The new run is created immediately, but its first Workflow Task is not scheduled until the backoff expires. This delay is recorded as first_workflow_task_backoff on the new run’s WorkflowExecutionStartedEventAttributes.

- No Workflow code runs during the backoff; this is server-enforced. (docs/design-patterns/delayed-start.mdx)
- Use cases: cooldown between runs, align to a boundary, smooth load, or defer follow-up processing without a Schedule.

## How it works

- When you Continue-As-New, you can set a start-delay or backoff on the new run via per-SDK options. The Temporal Server records the delay as first_workflow_task_backoff on the new run’s WorkflowExecutionStartedEventAttributes. (docs/encyclopedia/retry-policies.mdx – Event History)
- The new run exists and is visible immediately, but the Worker won’t receive a task until the delay elapses. (docs/design-patterns/delayed-start.mdx)
- During the delay:
  - Signal-With-Start or Update-With-Start bypasses the remaining delay and dispatches a Workflow Task immediately. Regular Signals do not bypass the delay. (docs/design-patterns/delayed-start.mdx)

## When to use

- Long-running chains that should pause briefly between runs.
- After rollover to reduce instantaneous pressure on a Task Queue or external systems.
- To align with external maintenance windows or time boundaries.

## Interactions and constraints

- Distinct from retry backoff: Workflow Retry Policy backoff delays a new run after failure; Continue-As-New backoff delays a new run after success. Both surface as first_workflow_task_backoff on the started event. (docs/encyclopedia/retry-policies.mdx)
- Cron: Cron also computes a firstWorkflowTaskBackoff for the next run. Do not rely on undocumented precedence when combining Cron with a custom start delay on Continue-As-New.  (docs/encyclopedia/workflow/cron-job.mdx)
- Observability: Inspect the started event’s attributes or history listing to confirm the backoff. (docs/references/events.mdx)

## SDK references

- .NET: docs/develop/dotnet/workflows/continue-as-new.mdx
- Go: docs/develop/go/workflows/continue-as-new.mdx
- Java: docs/develop/java/workflows/continue-as-new.mdx
- Python: docs/develop/python/workflows/continue-as-new.mdx
- Ruby: docs/develop/ruby/workflows/continue-as-new.mdx
- TypeScript: docs/develop/typescript/workflows/continue-as-new.mdx

## Sources

- Delayed Start semantics and bypass rules: docs/design-patterns/delayed-start.mdx
- Event History and first_workflow_task_backoff: docs/encyclopedia/retry-policies.mdx
- Cron next-run backoff: docs/encyclopedia/workflow/cron-job.mdx
