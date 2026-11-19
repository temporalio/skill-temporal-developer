# Task Queue Priority and Fairness in Go

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

Go represents Priority and Fairness metadata with `temporal.Priority`. Zero-value fields inherit independently. Set only `PriorityKey` for Priority-only use, or only the Fairness fields to use the default Priority.

```go
tenantPriority := temporal.Priority{
	PriorityKey:    1,
	FairnessKey:    "tenant-123",
	FairnessWeight: 2.0,
}
```

## Start a Workflow

Set `Priority` in `client.StartWorkflowOptions`:

```go
options := client.StartWorkflowOptions{
	ID:        "my-workflow-id",
	TaskQueue: "my-task-queue",
	Priority:  tenantPriority,
}

run, err := temporalClient.ExecuteWorkflow(
	context.Background(), options, MyWorkflow, "input",
)
```

## Override an Activity

Set `Priority` in `workflow.ActivityOptions`:

```go
options := workflow.ActivityOptions{
	StartToCloseTimeout: 30 * time.Second,
	Priority:            tenantPriority,
}
activityCtx := workflow.WithActivityOptions(ctx, options)

var result string
err := workflow.ExecuteActivity(
	activityCtx, ProcessOrder, "order-123",
).Get(activityCtx, &result)
```

## Override a Child Workflow

Set `Priority` in `workflow.ChildWorkflowOptions`:

```go
options := workflow.ChildWorkflowOptions{
	WorkflowID: "my-child-workflow-id",
	Priority:   tenantPriority,
}
childCtx := workflow.WithChildOptions(ctx, options)

var result string
err := workflow.ExecuteChildWorkflow(
	childCtx, MyChildWorkflow, "input",
).Get(childCtx, &result)
```

If an Activity or Child Workflow uses zero-value Priority fields, those fields inherit from the parent Workflow.
