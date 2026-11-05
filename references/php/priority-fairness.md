# Task Queue Priority and Fairness in PHP

Read [Temporal Task Queue priority and fairness guide](../core/priority-fairness.md) first for the cross-SDK behavior, configuration, and limitations.

PHP represents Priority and Fairness metadata with `Temporal\Common\Priority`. The API is stable since SDK 2.20. Each value is optional and inherits independently. Set only the priority key for Priority-only use, or only the Fairness values to use the default Priority.

```php
use Temporal\Common\Priority;

$tenantPriority = Priority::new(1)
    ->withFairnessKey('tenant-123')
    ->withFairnessWeight(2.0);
```

## Start a Workflow

Set the priority in the Client's Workflow start options:

```php
use Temporal\Client\WorkflowOptions;

$workflow = $client->newWorkflowStub(
    MyWorkflowInterface::class,
    WorkflowOptions::new()
        ->withWorkflowId('my-workflow-id')
        ->withTaskQueue('my-task-queue')
        ->withPriority($tenantPriority),
);
$client->start($workflow, 'input');
```

## Override an Activity

Set the priority in the options of the Workflow-side Activity stub:

```php
use Temporal\Activity\ActivityOptions;

$activities = Workflow::newActivityStub(
    ProcessOrderActivityInterface::class,
    ActivityOptions::new()
        ->withStartToCloseTimeout(30)
        ->withPriority($tenantPriority),
);
$result = yield $activities->process('order-123');
```

## Override a Child Workflow

Set the priority in the options of the Child Workflow stub:

```php
use Temporal\Workflow\ChildWorkflowOptions;

$child = Workflow::newChildWorkflowStub(
    MyChildWorkflowInterface::class,
    ChildWorkflowOptions::new()
        ->withWorkflowId('my-child-workflow-id')
        ->withPriority($tenantPriority),
);
$result = yield $child->run('input');
```

If an Activity or Child Workflow omits the priority, it inherits the parent Workflow's values. `Activity::getInfo()->priority` shows only the value set on the Activity, not an inherited value.
