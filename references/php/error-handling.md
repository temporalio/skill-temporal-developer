# PHP SDK Error Handling

## Overview

The PHP SDK uses `ApplicationFailure` for application-specific errors and provides retry policy configuration via `RetryOptions`. Generally, the following information about errors and retryability applies across activities, child workflows, and Nexus operations.

## Application Errors

```php
use Temporal\Exception\Failure\ApplicationFailure;

#[ActivityMethod]
public function validateOrder(Order $order): void
{
    if (!$order->isValid()) {
        throw new ApplicationFailure(
            message: 'Invalid order',
            type: 'ValidationError',
            nonRetryable: false,
        );
    }
}
```

`ApplicationFailure` constructor: `new ApplicationFailure(string $message, string $type, bool $nonRetryable, array $details)`.

## Non-Retryable Errors

```php
use Temporal\Exception\Failure\ApplicationFailure;

#[ActivityMethod]
public function chargeCard(ChargeCardInput $input): string
{
    if (!$this->isValidCard($input->cardNumber)) {
        throw new ApplicationFailure(
            message: 'Permanent failure - invalid credit card',
            type: 'PaymentError',
            nonRetryable: true,  // Will not retry activity
        );
    }
    return $this->processPayment($input->cardNumber, $input->amount);
}
```

## Handling Activity Errors

```php
use Temporal\Exception\Failure\ApplicationFailure;
use Temporal\Exception\Failure\ActivityFailure;

#[WorkflowMethod]
public function run(): string
{
    try {
        return yield $this->myActivity->doSomething('input');
    } catch (ActivityFailure $e) {
        // $e->getPrevious() contains the original ApplicationFailure
        $cause = $e->getPrevious();
        throw new ApplicationFailure(
            message: 'Workflow failed due to activity error',
            type: 'WorkflowError',
            nonRetryable: false,
        );
    }
}
```

Activities throw exceptions; workflows catch `ActivityFailure` (which wraps the original exception).

## Retry Policy Configuration

```php
use Temporal\Activity\ActivityOptions;
use Temporal\Common\RetryOptions;
use Carbon\CarbonInterval;

$options = ActivityOptions::new()
    ->withRetryOptions(
        RetryOptions::new()
            ->withInitialInterval(CarbonInterval::seconds(1))
            ->withMaximumInterval(CarbonInterval::minutes(1))
            ->withMaximumAttempts(5)
            ->withNonRetryableExceptions(['ValidationError', 'PaymentError'])
    );

$result = yield $this->myActivityStub->withOptions($options)->doSomething('input');
```

Only set options such as `withMaximumInterval`, `withMaximumAttempts` etc. if you have a domain-specific reason to. If not, prefer to leave them at their defaults.

## Timeout Configuration

```php
use Temporal\Activity\ActivityOptions;
use Carbon\CarbonInterval;

$options = ActivityOptions::new()
    ->withScheduleToCloseTimeout(CarbonInterval::minutes(30))  // Including retries
    ->withStartToCloseTimeout(CarbonInterval::minutes(5))      // Single attempt
    ->withHeartbeatTimeout(CarbonInterval::minutes(2));        // Between heartbeats

$result = yield $this->myActivityStub->withOptions($options)->doSomething('input');
```

## Workflow Failure

```php
use Temporal\Exception\Failure\ApplicationFailure;

#[WorkflowMethod]
public function run(): string
{
    if ($someCondition) {
        throw new ApplicationFailure(
            message: 'Cannot process order',
            type: 'BusinessError',
            nonRetryable: false,
        );
    }
    return 'success';
}
```

## Best Practices

1. Use specific error types (the `type` parameter) for different failure modes
2. Mark permanent failures as non-retryable with `nonRetryable: true`
3. Configure appropriate retry policies for activities
4. Catch `ActivityFailure` in workflows — the original exception is in `$e->getPrevious()`
5. Design activity code to be idempotent for safe retries (see more at `references/core/patterns.md`)
