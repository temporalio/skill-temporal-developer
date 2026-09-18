# Task Queue Priority and Fairness in Java

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

Java represents Priority and Fairness metadata with `io.temporal.common.Priority`. Unset fields inherit independently. Set only the Priority key for Priority-only use, or only the Fairness fields to use the default Priority.

```java
Priority tenantPriority = Priority.newBuilder()
    .setPriorityKey(1)
    .setFairnessKey("tenant-123")
    .setFairnessWeight(2.0f)
    .build();
```

## Start a Workflow

Set `Priority` in `WorkflowOptions`:

```java
WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("my-workflow-id")
    .setTaskQueue("my-task-queue")
    .setPriority(tenantPriority)
    .build();

MyWorkflow workflow = workflowClient.newWorkflowStub(MyWorkflow.class, options);
workflow.run("input");
```

## Override an Activity

Set `Priority` in `ActivityOptions`:

```java
ActivityOptions options = ActivityOptions.newBuilder()
    .setStartToCloseTimeout(Duration.ofSeconds(30))
    .setPriority(tenantPriority)
    .build();

MyActivities activities = Workflow.newActivityStub(MyActivities.class, options);
String result = activities.processOrder("order-123");
```

## Override a Child Workflow

Set `Priority` in `ChildWorkflowOptions`:

```java
ChildWorkflowOptions options = ChildWorkflowOptions.newBuilder()
    .setWorkflowId("my-child-workflow-id")
    .setPriority(tenantPriority)
    .build();

MyChildWorkflow child =
    Workflow.newChildWorkflowStub(MyChildWorkflow.class, options);
String result = child.run("input");
```

If an Activity or Child Workflow omits `Priority`, it inherits the parent Workflow's values.
