# PHP SDK Error Handling

Source: [ApplicationFailure](https://github.com/temporalio/sdk-php/blob/v2.18/src/Exception/Failure/ApplicationFailure.php), [ActivityOptions](https://github.com/temporalio/sdk-php/blob/v2.18/src/Activity/ActivityOptions.php), [RetryOptions](https://github.com/temporalio/sdk-php/blob/v2.18/src/Common/RetryOptions.php).

## Failure boundaries

An Activity's ordinary PHP exception is encoded as `ApplicationFailure` (normally using the exception's full class name as its type). The workflow sees an `ActivityFailure` wrapper after retries are exhausted or a terminal failure occurs; inspect its previous exception for `ApplicationFailure`, `TimeoutFailure` or cancellation. The external client normally sees `WorkflowFailedException` for a failed workflow. Do not expect a raw Activity exception at every boundary.

Throw `ApplicationFailure` for an intentional workflow/business failure. An ordinary programming error in workflow code normally fails a Workflow Task and can keep retrying/blocking the workflow; catching every `Throwable` and returning success hides defects. Cancellation is not an ordinary item failure: propagate it unless completing with a cancellation business result is deliberate.

## Terminal and transient errors

```php
use Temporal\DataConverter\EncodedValues;
use Temporal\Exception\Failure\ApplicationFailure;

throw new ApplicationFailure(
    message: 'Payment declined',
    type: 'PaymentDeclined',
    nonRetryable: true,
    details: EncodedValues::fromValues([['reason' => 'insufficient_funds']]),
);
```

`details` accepts `?ValuesInterface`, not a raw array. `fromValues()` takes a list of positional detail values: the outer list above makes `getValue(0)` return the whole reason map. `nextRetryDelay: new \DateInterval('PT30S')` can override the next retry interval where supported by the locked SDK/server. Classify the actual failure: a permanent business refusal differs from a temporary API outage. Do not blanket-classify every authentication failure without understanding credential refresh and recovery.

## Options and timeouts

```php
use Temporal\Activity\ActivityOptions;
use Temporal\Common\RetryOptions;
use Temporal\Workflow;

$activities = Workflow::newActivityStub(
    PaymentActivities::class,
    ActivityOptions::new()
        ->withStartToCloseTimeout(30)
        ->withScheduleToCloseTimeout(300)
        ->withRetryOptions(
            RetryOptions::new()->withNonRetryableExceptions(['PaymentDeclined'])
        ),
);
```

Set at least Start-To-Close or Schedule-To-Close. Pass options when creating the stub, or use the SDK's supported stub-options mechanism for the installed version; a typed Activity proxy does not expose a generic `withOptions()` method.

| Timeout | Meaning |
| --- | --- |
| Start-To-Close | One Activity attempt, after the worker accepts the task |
| Schedule-To-Close | Total Activity execution budget including queue waits and retries |
| Schedule-To-Start | Queue wait; generally leave unset unless explicit routing/failover needs it; this timeout is non-retryable |
| Heartbeat | Maximum heartbeat silence when configured |

A timeout does not reliably kill an external HTTP call or PHP process. An old attempt can overlap a retry. Bound I/O timeouts and use a stable operation idempotency key across attempts. Heartbeats do not extend other timeouts and may be throttled; checkpoint only completed durable work, expect repeated work since the last persisted checkpoint.

Default Activity retries already exist; add attempt limits/backoff only for a business or operational reason. A workflow retry re-executes a whole run and is not a substitute for per-Activity retries. Stable workflow IDs help deduplicate starts, but do not make a payment, DB write or notification exactly-once. Put deduplication at that side-effect boundary.

`Activity::heartbeat()` reports cancellation inside PHP Activity code with `Temporal\Exception\Client\ActivityCanceledException`; workflow-side cancellation uses failure types such as `CanceledFailure`. Do not catch only the workflow failure type inside the Activity.

## Compensation

Use [the Saga and cancellation patterns](patterns.md). Register idempotent compensation before an operation that may succeed without reporting success. The compensation must tolerate both “nothing happened” and “already compensated.” The SDK's `Saga::compensate()` already uses detached cancellation scopes; a handwritten cleanup generator must explicitly use `Workflow::asyncDetached()` when its parent is cancelled. Decide how to report compensation failure; logging it and reporting success is usually misleading.

Cancellation also needs an ordering policy. The default Activity cancellation mode is `TryCancel`: the workflow can enter compensation while the original Activity still runs. A refund that sees no charge yet can miss a later charge. Where appropriate, configure `ActivityCancellationType::WaitCancellationCompleted`, heartbeat delivery and finite timeout budgets, then reconcile uncertain external outcomes. A cancellation-intent/fencing protocol at the payment or reservation boundary must prevent or detect late side effects; detached cleanup and idempotency alone do not establish this ordering.
