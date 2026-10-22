# PHP SDK Advanced Features

See [workers.md](workers.md) for tuning and RoadRunner configuration, and [patterns.md](patterns.md) for messages, child workflows and cancellation.

## Schedules

Use Schedules for independently managed recurring starts. Use a durable timer for a wait within one workflow; Continue-As-New preserves a long-lived workflow identity while rotating history. These solve different lifecycle problems.

```php
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\Schedule\Action\StartWorkflowAction;
use Temporal\Client\Schedule\Policy\ScheduleOverlapPolicy;
use Temporal\Client\Schedule\Policy\SchedulePolicies;
use Temporal\Client\Schedule\Schedule;
use Temporal\Client\Schedule\Spec\ScheduleSpec;
use Temporal\Client\ScheduleClient;

$scheduleClient = ScheduleClient::create(ServiceClient::create('127.0.0.1:7233'));
$handle = $scheduleClient->createSchedule(
    Schedule::new()
        ->withAction(StartWorkflowAction::new('DailyReport')
            ->withTaskQueue('reports')
            ->withInput(['report-account-id']))
        ->withSpec(ScheduleSpec::new()->withAddedInterval(new \DateInterval('P1D')))
        ->withPolicies(SchedulePolicies::new()
            ->withOverlapPolicy(ScheduleOverlapPolicy::Skip)),
    scheduleId: 'daily-report',
);
```

Use registered Workflow Type names and a converter compatible with the worker. `withAddedInterval()` is the verified API; there is no `ScheduleIntervalSpec`/`withIntervals()` combination in the reviewed SDK. Intervals are epoch/phase based, not necessarily “N days after creation.” For “Monday at 09:00,” use calendar/structured-calendar rules plus an explicit IANA timezone and test DST behavior. Jitter distributes scheduled load; it does not replace rate limits.

Choose overlap deliberately: `Skip`, `BufferOne`, `BufferAll`, `CancelOther`, `TerminateOther`, or `AllowAll`. Termination does not run workflow cleanup. Set catchup window and pause-on-failure behavior where required. Handles support pause/unpause, trigger, describe, update, backfill and delete; backfill starts actions and can repeat business side effects. Use stable schedule identity and per-occurrence idempotency, especially for payments. Do not retry the whole scheduled workflow merely to retry one Activity.

Sources: [ScheduleSpec](https://github.com/temporalio/sdk-php/blob/v2.18/src/Client/Schedule/Spec/ScheduleSpec.php), [Schedule client](https://github.com/temporalio/sdk-php/blob/v2.18/src/Client/ScheduleClient.php), [course schedule assessment](sources.md).

## Asynchronous Activity completion

An Activity can hand work to an external process and finish later:

```php
use Temporal\Activity;

// Inside an Activity; persist/correlate securely before handing off.
$taskToken = Activity::getInfo()->taskToken;
$this->storeCompletionToken($requestId, $taskToken);
Activity::doNotCompleteOnReturn();
```

From a client process with an explicitly connected `$client`:

```php
$completion = $client->newActivityCompletionClient();
$completion->completeByToken($taskToken, 'approved');
// Or: $completion->completeExceptionallyByToken($taskToken, $error);
```

`complete()` takes Workflow ID, Run ID, Activity ID and result; token completion uses **`completeByToken()`**. Treat the token as opaque sensitive data; it identifies an Activity attempt. Plan timeout, retry, heartbeat and cancellation behavior for stale/duplicate callbacks. For a human approval that naturally belongs to workflow state, Signal or Update plus a timer is often simpler than holding an Activity open.

Source: [ActivityCompletionClientInterface](https://github.com/temporalio/sdk-php/blob/v2.18/src/Client/ActivityCompletionClientInterface.php).
