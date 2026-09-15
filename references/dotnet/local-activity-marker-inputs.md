## Local Activity Marker Inputs (.NET)

### Overview

Workers can record Local Activity input arguments in the Local Activity marker written to Workflow Event History by enabling a .NET option on the call site. The marker is the persistence mechanism for Local Activity completion; only the marker is stored in history for Local Activities.

- On Local Activity completion, the Worker records a `MarkerRecorded` event containing the Local Activity result.
- Once the marker is written, replay uses the recorded result instead of re-executing the Local Activity.
- The marker’s `details` field holds serialized information recorded in the marker.

### When to enable it

Enable argument recording when you need to see the inputs that produced a Local Activity result for debugging, auditability, or richer UI introspection.

- Pro: Inputs appear alongside the result in the `MarkerRecorded` event’s details, improving explainability during replay and inspection.
- Con: Arguments become visible in history and increase history size; avoid including secrets/PII, or filter/redact before passing to the Local Activity.

### How to enable it (.NET)

Set `LocalActivityOptions.IncludeArgumentsInMarker = true` when invoking a Local Activity from a Workflow. Default is `false`.

```csharp
using Temporalio.Workflows;

[Workflow]
public class ExampleWorkflow
{
    [WorkflowRun]
    public async Task RunAsync(string name)
    {
        var options = new LocalActivityOptions
        {
            StartToCloseTimeout = TimeSpan.FromSeconds(5),
            IncludeArgumentsInMarker = true, // record inputs in Local Activity marker
        };

        // Type-safe invocation (instance method)
        var result = await Workflow.ExecuteLocalActivityAsync(
            (MyActivities a) => a.Greet(name),
            options);

        // Or by activity name and args
        await Workflow.ExecuteLocalActivityAsync(
            "Greet",
            new object?[] { name },
            options);
    }
}
```

### Where it shows up

- Event type: `MarkerRecorded`.
- Fields: `marker_name`, `details`, `workflow_task_completed_event_id`, `header`, `failure` (the arguments, when enabled, are serialized into `details`).

You can view the marker and its details in your cluster’s UI (Event History for a Workflow run) or via CLI history exports.

### Notes and limitations

- Applies to Local Activities only; regular Activities follow the standard Activity event sequence, not markers. See Local Activity vs Activity.
- Local Activities gain durability only when the marker is recorded; before that, inputs/results exist only in Worker memory.
- Consider privacy and cost: storing arguments in history may surface sensitive data and grow history size. Default is disabled.

### Related references

- Concept: `references/core/standalone-activities.md` (comparison context for Activities) and `docs/encyclopedia/activities/local-activity.mdx` (concept).
- Event: `docs/references/events.mdx#markerrecorded`.
