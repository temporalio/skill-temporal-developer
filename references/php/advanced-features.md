# PHP SDK Advanced Features

## Schedules

Create recurring workflow executions.

```php
use Temporal\Client\Schedule\Schedule;
use Temporal\Client\Schedule\Action\StartWorkflowAction;
use Temporal\Client\Schedule\Spec\ScheduleSpec;
use Temporal\Client\Schedule\Spec\ScheduleIntervalSpec;

$handle = $scheduleClient->createSchedule(
    Schedule::new()
        ->withAction(StartWorkflowAction::new('DailyReportWorkflow')
            ->withTaskQueue('reports')
        )
        ->withSpec(ScheduleSpec::new()
            ->withIntervals(new ScheduleIntervalSpec(every: new \DateInterval('P1D')))
        ),
    scheduleId: 'daily-report',
);

// Manage schedules
$handle->pause();
$handle->unpause();
$handle->trigger();  // Run immediately
$handle->delete();
```

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks).

```php
use Temporal\Activity;

#[ActivityMethod]
public function requestApproval(string $requestId): void
{
    // Get task token for async completion
    $taskToken = Activity::getInfo()->taskToken;

    // Store task token for later completion (e.g., in database)
    $this->storeTaskToken($requestId, $taskToken);

    // Mark this activity as waiting for external completion
    Activity::doNotCompleteOnReturn();
}
```

Complete the activity from another process:

```php
use Temporal\Client\WorkflowClient;

$client = WorkflowClient::create();
$taskToken = getStoredTaskToken($requestId);

$completionClient = $client->newActivityCompletionClient();
$completionClient->complete($taskToken, 'approved');

// Or fail it:
// $completionClient->completeExceptionally($taskToken, new \Exception('Rejected'));
```

**Note:** If the external system can reliably signal back with the result and doesn't need to heartbeat or receive cancellation, consider using **signals** instead.

## Worker Tuning

Configure worker performance settings.

```php
use Temporal\Worker\WorkerOptions;

$worker = $factory->newWorker(
    taskQueue: 'my-queue',
    options: WorkerOptions::new()
        ->withMaxConcurrentWorkflowTaskPollers(5)
        ->withMaxConcurrentActivityTaskPollers(5)
        ->withMaxConcurrentWorkflowTaskExecutionSize(100)
        ->withMaxConcurrentActivityExecutionSize(100)
);
```

PHP workers run as RoadRunner processes — the number of concurrent activities is also bounded by the number of RoadRunner worker processes configured in `.rr.yaml`.

## RoadRunner Configuration

PHP uses [RoadRunner](https://roadrunner.dev/) as the process supervisor. Configure it in `.rr.yaml`:

```yaml
version: "3"

temporal:
  address: "localhost:7233"
  namespace: "default"
  activities:
    num_workers: 10         # Number of PHP processes for activities
    max_jobs: 100           # Restart worker after N jobs (prevents memory leaks)
    memory_limit: 128MB     # Restart worker if it exceeds this memory limit

server:
  command: "php worker.php"
  relay: "pipes"
```

Key settings:
- `num_workers` — controls activity concurrency (set based on available CPU/memory)
- `max_jobs` — prevents memory leaks by recycling PHP processes after N executions
- `memory_limit` — safety net for runaway memory usage
