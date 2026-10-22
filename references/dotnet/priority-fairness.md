# Task Queue Priority and Fairness in .NET

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

.NET represents Priority and Fairness metadata with `Temporalio.Common.Priority`. Constructor arguments are optional and inherit independently. Set only `priorityKey` for Priority-only use, or only the Fairness values to use the default Priority.

```csharp
var tenantPriority = new Priority(
    priorityKey: 1,
    fairnessKey: "tenant-123",
    fairnessWeight: 2.0f);
```

## Start a Workflow

Set `Priority` in `WorkflowOptions`:

```csharp
var handle = await Client.StartWorkflowAsync(
    (MyWorkflow wf) => wf.RunAsync("input"),
    new(id: "my-workflow-id", taskQueue: "my-task-queue")
    {
        Priority = tenantPriority,
    });
```

## Override an Activity

Set `Priority` in `ActivityOptions`:

```csharp
var result = await Workflow.ExecuteActivityAsync(
    () => MyActivities.ProcessOrder("order-123"),
    new()
    {
        StartToCloseTimeout = TimeSpan.FromSeconds(30),
        Priority = tenantPriority,
    });
```

## Override a Child Workflow

Set `Priority` in `ChildWorkflowOptions`:

```csharp
var result = await Workflow.ExecuteChildWorkflowAsync(
    (MyChildWorkflow wf) => wf.RunAsync("input"),
    new()
    {
        Id = "my-child-workflow-id",
        Priority = tenantPriority,
    });
```

If an Activity or Child Workflow omits `Priority`, it inherits the parent Workflow's values.
