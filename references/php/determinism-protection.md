# PHP Determinism Protection

The SDK has no sandbox that blocks nondeterministic PHP operations. Laravel's application sandbox isolates framework state; it does not enforce replay determinism. Read [determinism.md](determinism.md) for the rules and [workers.md](workers.md) for persistent process state.

`WorkflowPanicPolicy` controls the response to detected workflow panics/nondeterminism:

```php
use Temporal\Worker\WorkerOptions;
use Temporal\Worker\WorkflowPanicPolicy;

$options = WorkerOptions::new()
    ->withWorkflowPanicPolicy(WorkflowPanicPolicy::BlockWorkflow);
```

`BlockWorkflow` is the default and allows a corrected deployment to recover the execution. `FailWorkflow` makes it terminal; use it deliberately in disposable tests or where terminal failure is the intended policy. It is not a debugging switch that makes nondeterministic code safe. Validate command compatibility with [replay tests](testing.md).

Source: [WorkerOptions](https://github.com/temporalio/sdk-php/blob/v2.18/src/Worker/WorkerOptions.php).
