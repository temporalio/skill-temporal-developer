# Task Queue Priority and Fairness in Python

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

Python represents Priority and Fairness metadata with `temporalio.common.Priority`. The three fields are optional and inherit independently. Omit `fairness_key` and `fairness_weight` for Priority-only use, or omit `priority_key` for Fairness at the default Priority.

```python
from temporalio.common import Priority

tenant_priority = Priority(
    priority_key=1,
    fairness_key="tenant-123",
    fairness_weight=2.0,
)
```

## Start a Workflow

Set `priority` in the Client's Workflow start options:

```python
handle = await client.start_workflow(
    MyWorkflow.run,
    args=["input"],
    id="my-workflow-id",
    task_queue="my-task-queue",
    priority=tenant_priority,
)
```

## Override an Activity

Set `priority` on the Workflow-side Activity call. A timeout is still required:

```python
from datetime import timedelta
from temporalio import workflow

result = await workflow.execute_activity(
    process_order,
    "order-123",
    start_to_close_timeout=timedelta(seconds=30),
    priority=tenant_priority,
)
```

## Override a Child Workflow

Set `priority` on the Child Workflow call:

```python
result = await workflow.execute_child_workflow(
    MyChildWorkflow.run,
    args=["input"],
    id="my-child-workflow-id",
    priority=tenant_priority,
)
```

If an Activity or Child Workflow omits `priority`, it inherits the parent Workflow's values.
