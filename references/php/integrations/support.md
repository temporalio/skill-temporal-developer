# temporal-php/support

Optional runtime helpers, not the Temporal runtime or a testing framework. Reviewed at [b177152](https://github.com/temporal-php/support/tree/b177152a2add479b0b3e83c1431517db8ce8184d), whose Composer requirements include PHP >=8.1 and SDK ^2.15. The course locks support 1.1.0. Respect the application's lockfile.

```bash
composer require temporal-php/support
```

Despite the README's “dev dependency” wording, keep the package available at runtime if the worker/client calls its factories or uses its runtime attributes. Do not install it solely for a native SDK example.

## Factories and default attributes

- `Temporal\Support\Factory\ActivityStub::activity()` creates an Activity stub with named timeout/retry/queue options.
- `Temporal\Support\Factory\WorkflowStub::workflow()` creates a client stub.
- `Temporal\Support\Factory\WorkflowStub::childWorkflow()` creates a child stub inside a workflow.
- `Temporal\Support\Attribute\TaskQueue` and `RetryPolicy` supply defaults **only when these factories read them**. Native `Workflow::newActivityStub()` does not automatically interpret support attributes.

Put attributes on the definition passed to the factory (usually the interface when separate). Explicit factory arguments override defaults; inspect the factory signature for available options. Avoid introducing retry policy on entire workflows just to simplify Activity defaults.

```php
use Temporal\Support\Factory\ActivityStub;

$activities = ActivityStub::activity(
    class: PaymentActivities::class,
    startToCloseTimeout: 30,
    taskQueue: 'payments',
);
$result = yield $activities->charge($paymentId);
```

## VirtualPromise

`Temporal\Support\VirtualPromise<T>` is an IDE/static-analysis annotation for the value yielded from a proxy call. Use it in PHPDoc where useful; never instantiate or implement it, and do not make a synchronous Activity return a promise merely to satisfy the annotation. The real Activity still returns its ordinary value; the stub returns an awaitable.

Analyzer support for the package's `@yield` annotation varies. Check the installed Psalm/PHPStorm/PHPStan integration instead of treating README capability notes as permanent facts. Laravel's PHPStan extension is a separate integration.

Sources: [factories](https://github.com/temporal-php/support/tree/b177152a2add479b0b3e83c1431517db8ce8184d/src/Factory), [factory tests](https://github.com/temporal-php/support/tree/b177152a2add479b0b3e83c1431517db8ce8184d/tests/Unit/Factory).
