# PHP SDK Error Handling

## Overview

Application errors use `Temporal\Exception\Failure\ApplicationFailure`. Retry behavior is configured with `Temporal\Common\RetryOptions`. In an Activity, any PHP exception is converted to an `ApplicationFailure`, with the exception class name as its type. A `TypeError` is different: the SDK wraps it, and the type is `Temporal\Exception\InvalidArgumentException`.

## Application Errors

```php
use Temporal\Exception\Failure\ApplicationFailure;

throw new ApplicationFailure('Payment declined', 'PaymentDeclined', false);
```

## Non-Retryable Errors

```php
use Temporal\DataConverter\EncodedValues;
use Temporal\Exception\Failure\ApplicationFailure;

throw new ApplicationFailure(
    message: 'Card is expired',
    type: 'CardExpired',
    nonRetryable: true,
    details: EncodedValues::fromValues([['cardId' => $cardId]]),
);
```

`details` takes a `ValuesInterface`, not an array. Each element of the list given to `fromValues()` is one detail.

Override the next retry interval with `nextRetryDelay`:

```php
throw new ApplicationFailure(
    message: 'Rate limited',
    type: 'RateLimited',
    nonRetryable: false,
    nextRetryDelay: new \DateInterval('PT30S'),
);
```

## Handling Activity Errors

The Workflow receives an `ActivityFailure` after all retries are done. The original failure is in `getPrevious()`.

```php
use Temporal\Exception\Failure\ActivityFailure;
use Temporal\Exception\Failure\ApplicationFailure;
use Temporal\Exception\Failure\CanceledFailure;
use Temporal\Workflow;

try {
    yield $this->activities->charge($orderId);
} catch (ActivityFailure $e) {
    // Let cancellation propagate so the workflow is cancelled, not failed.
    if ($e->getPrevious() instanceof CanceledFailure) {
        throw $e;
    }

    Workflow::getLogger()->error('Charge failed', ['error' => $e->getMessage()]);
    throw new ApplicationFailure('Order failed: charge was not done', 'OrderFailed', true, null, $e);
}
```

With the default `TryCancel`, a cancelled Activity gives a bare `CanceledFailure`, which this `catch` does not receive. With `WaitCancellationCompleted`, it arrives as an `ActivityFailure` with a previous `CanceledFailure`.

## Retry Policy Configuration

```php
use Temporal\Activity\ActivityOptions;
use Temporal\Common\RetryOptions;

$options = ActivityOptions::new()
    ->withStartToCloseTimeout(30)
    ->withRetryOptions(
        RetryOptions::new()
            ->withMaximumInterval(60)
            ->withMaximumAttempts(5)
            ->withNonRetryableExceptions([\InvalidArgumentException::class]),
    );
```

`withNonRetryableExceptions()` takes `Throwable` class names. To stop retries for an `ApplicationFailure` type such as `PaymentDeclined`, throw it with `nonRetryable: true`.

Only set retry policies when you have a domain-specific reason. Prefer the defaults otherwise.

## Timeout Configuration

```php
$activities = Workflow::newActivityStub(
    PaymentActivityInterface::class,
    ActivityOptions::new()
        ->withStartToCloseTimeout(30)
        ->withScheduleToCloseTimeout('5 minutes')
        ->withHeartbeatTimeout(10),
);
```

A timeout value is an `int` (seconds), a `\DateInterval`, or a string such as `'5 minutes'`. Set at least Start-To-Close or Schedule-To-Close. Options belong to the stub: create another stub for other options.

| Timeout | Meaning |
| -- | -- |
| Start-To-Close | One Activity attempt, after a worker accepts the task |
| Schedule-To-Close | Total Activity time, including queue waits and retries |
| Schedule-To-Start | Queue wait. Usually leave it unset. It is not retryable |
| Heartbeat | Maximum time between heartbeats |

A timeout does not stop the PHP code of an attempt. An old attempt can run at the same time as its retry. Set I/O timeouts in the Activity, and use a stable idempotency key across attempts.

## Workflow Failure

PHP differs from other SDKs here. The default `ExceptionInterceptor` treats PHP `\Error` (`TypeError`, `Error`, etc.) as a panic. With the default `BlockWorkflow` policy, the Workflow Task fails and retries until the code is fixed. With `FailWorkflow`, the Workflow Execution fails. A `CanceledFailure` closes the Workflow as cancelled. Any other `\Exception`, including `ApplicationFailure`, fails the Workflow Execution.

A client that waits for the result receives `WorkflowFailedException`, with the Workflow failure as the previous exception.

```php
#[WorkflowMethod]
public function run(Order $order): \Generator
{
    if ($order->items === []) {
        throw new ApplicationFailure('Order has no items', 'EmptyOrder', true);
    }

    return yield $this->activities->process($order);
}
```

To change which exceptions only fail the Workflow Task, give an exception interceptor to the worker:

```php
use Temporal\Exception\ExceptionInterceptor;

$worker = $factory->newWorker(
    'orders',
    exceptionInterceptor: new ExceptionInterceptor([\Error::class, \LogicException::class]),
);
```

## Activity Cancellation Type

The default `ActivityCancellationType::TryCancel` returns cancellation to the Workflow immediately, while the Activity can still run. For compensation that must wait until the Activity stops, use `WaitCancellationCompleted` with a heartbeat timeout:

```php
use Temporal\Activity\ActivityCancellationType;

ActivityOptions::new()
    ->withStartToCloseTimeout(60)
    ->withHeartbeatTimeout(10)
    ->withCancellationType(ActivityCancellationType::WaitCancellationCompleted);
```

After `$scope->cancel()`, `yield $scope` rejects at once, also with `WaitCancellationCompleted`. To wait until the Activity stops, catch the failure inside the scope and run the compensation there, or `yield` the Activity in the main Workflow method.

With `TryCancel`, a compensation such as a refund can run before the original charge finishes, and miss it. A cancellation request or a timeout does not prove that the external system did not apply the operation. Use a stable operation ID, and reconcile or fence late side effects at the external boundary.

## Best Practices

- Use specific error types (`type` argument) for differentiation.
- Mark permanent failures as `nonRetryable: true`.
- Set retry policies only when defaults are insufficient.
- Let `CanceledFailure` propagate unless a cancellation result is intended.
- Design Activities for idempotency so retries are safe.
