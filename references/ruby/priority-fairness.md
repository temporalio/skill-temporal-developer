# Task Queue Priority and Fairness in Ruby

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

Ruby represents Priority and Fairness metadata with `Temporalio::Priority`. Constructor keywords are optional and inherit independently. Set only `priority_key` for Priority-only use, or only the Fairness values to use the default Priority.

```ruby
tenant_priority = Temporalio::Priority.new(
  priority_key: 1,
  fairness_key: 'tenant-123',
  fairness_weight: 2.0
)
```

## Start a Workflow

Set `priority` in the Client's Workflow start options:

```ruby
handle = client.start_workflow(
  MyWorkflow,
  'input',
  id: 'my-workflow-id',
  task_queue: 'my-task-queue',
  priority: tenant_priority
)
```

## Override an Activity

Set `priority` on the Workflow-side Activity call:

```ruby
result = Temporalio::Workflow.execute_activity(
  ProcessOrderActivity,
  'order-123',
  start_to_close_timeout: 30,
  priority: tenant_priority
)
```

## Override a Child Workflow

Set `priority` on the Child Workflow call:

```ruby
result = Temporalio::Workflow.execute_child_workflow(
  MyChildWorkflow,
  'input',
  id: 'my-child-workflow-id',
  priority: tenant_priority
)
```

If an Activity or Child Workflow omits `priority`, it inherits the parent Workflow's values.
