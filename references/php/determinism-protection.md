# PHP Workflow Determinism Protection

## Overview

The PHP SDK does not have a sandbox like Python or illegal call tracing like Ruby. Workflow code runs as ordinary PHP inside the RoadRunner worker process. The SDK gives these protections:

1. **Read-only callback guard** - a command from a callback that must be read-only throws.
2. **Workflow panic policy** - selects the result of a non-determinism error or a panic.
3. **Replay testing** - finds command mismatches before a deployment.

Read [determinism.md](determinism.md) for the rules.

## Read-Only Workflow Callbacks

Some callbacks run outside the Workflow command sequence. A command created there is not part of history and breaks replay. Since SDK 2.20, these calls throw:

- Query handlers (`#[QueryMethod]`, `Workflow::registerQuery()`)
- Update validators (`#[UpdateValidatorMethod]`)
- `Workflow::await()` / `awaitWithTimeout()` conditions
- `Workflow::sideEffect()` callbacks

```php
// BAD - A query handler starts an Activity. SDK 2.20+ throws.
#[QueryMethod]
public function getStatus(): string
{
    $this->activities->refreshStatus($this->orderId);
    return $this->status;
}

// GOOD - A query handler only reads state.
#[QueryMethod]
public function getStatus(): string
{
    return $this->status;
}
```

The guard is on by default. A legacy application can disable it while the code is fixed:

```php
\Temporal\Worker\FeatureFlags::$readOnlyWorkflowCallbacks = false;
```

With the guard off, an Update validator, an await condition and a `sideEffect()` callback can create commands again. A Query handler that creates a command still fails, with a less clear error.

## Workflow Panic Policy

```php
use Temporal\Worker\WorkerOptions;
use Temporal\Worker\WorkflowPanicPolicy;

$worker = $factory->newWorker(
    'orders',
    WorkerOptions::new()->withWorkflowPanicPolicy(WorkflowPanicPolicy::BlockWorkflow),
);
```

- `BlockWorkflow` (default) - the Workflow Task fails and retries. The Workflow continues after a deployment of the corrected code.
- `FailWorkflow` - the Workflow Execution fails. Use it only when a terminal failure is the intended result.

## Convention-Based Enforcement

Without a sandbox, use conventions and static analysis:

- Keep Workflow classes in a separate namespace (for example `App\Workflow`). Do not inject services into them.
- Add a static analysis rule (PHPStan, Psalm or Deptrac) that forbids `sleep`, `time`, `rand`, `random_int`, `DateTime` construction, database and HTTP clients in that namespace.
- Code review every change to Workflow code for new commands and changed command order.

## Best Practices

- Keep the read-only guard on.
- Keep the default `BlockWorkflow` policy in production.
- Run [replay tests](testing.md#workflow-replay-testing) in CI against histories of every Workflow version that is still open.
