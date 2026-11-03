# PHP SDK Advanced Features

## Schedules

Create recurring Workflow executions with the `ScheduleClient`:

```php
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\Schedule\Action\StartWorkflowAction;
use Temporal\Client\Schedule\Policy\ScheduleOverlapPolicy;
use Temporal\Client\Schedule\Policy\SchedulePolicies;
use Temporal\Client\Schedule\Schedule;
use Temporal\Client\Schedule\Spec\ScheduleSpec;
use Temporal\Client\ScheduleClient;

$scheduleClient = ScheduleClient::create(ServiceClient::create('127.0.0.1:7233'));

// Create a schedule
$handle = $scheduleClient->createSchedule(
    Schedule::new()
        ->withAction(
            StartWorkflowAction::new('DailyReport')
                ->withTaskQueue('reports')
                ->withInput(['account-1']),
        )
        ->withSpec(
            ScheduleSpec::new()
                ->withAddedCronString('0 9 * * MON-FRI')
                ->withTimezoneName('Europe/Berlin'),
        )
        ->withPolicies(SchedulePolicies::new()->withOverlapPolicy(ScheduleOverlapPolicy::Skip)),
    scheduleId: 'daily-report',
);

// Manage schedules
$handle = $scheduleClient->getHandle('daily-report');
$handle->pause('Maintenance window');
$handle->unpause();
$handle->trigger();
$handle->delete();
```

Use `withAddedInterval('1 hour')` for a fixed interval, or `withAddedCalendar()` / `withAddedStructuredCalendar()` for calendar rules. Use the registered Workflow Type name in `StartWorkflowAction::new()`.

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks):

```php
use Temporal\Activity;

final class ApprovalActivity implements ApprovalActivityInterface
{
    public function requestApproval(string $requestId): string
    {
        $taskToken = Activity::getInfo()->taskToken;
        $this->approvalQueue->send($requestId, base64_encode($taskToken));

        // The return value is ignored. The activity stays open until completion.
        Activity::doNotCompleteOnReturn();
        return '';
    }
}
```

Later, complete the Activity from another process:

```php
$completion = $client->newActivityCompletionClient();

$completion->completeByToken($taskToken, 'approved');
// or
$completion->completeExceptionallyByToken($taskToken, new \RuntimeException('Rejected'));
```

`complete()` and `completeExceptionally()` take the Workflow ID, Run ID and Activity ID instead of the token. For a human approval, a Signal or an Update with a timer is often more simple than an open Activity.

## Worker Tuning

The PHP worker has two levels of capacity:

1. **RoadRunner pool** - the number of PHP processes that execute Activities. Set it in `.rr.yaml`.
2. **WorkerOptions** - the limits of the Go SDK inside RoadRunner: concurrency, pollers and rates.

```yaml
temporal:
  address: "127.0.0.1:7233"
  activities:
    num_workers: 8        # PHP processes for Activities
    max_jobs: 1000        # restart a process after this number of tasks
    supervisor:
      max_worker_memory: 256   # MB, soft limit: restart a process above it
```

```php
use Temporal\Worker\WorkerOptions;

$worker = $factory->newWorker(
    'my-queue',
    WorkerOptions::new()
        // Max concurrent Activity executions (keep near num_workers)
        ->withMaxConcurrentActivityExecutionSize(8)
        // Max concurrent workflow task executions
        ->withMaxConcurrentWorkflowTaskExecutionSize(200)
        // Max concurrent local activity executions
        ->withMaxConcurrentLocalActivityExecutionSize(200)
        // Pollers
        ->withMaxConcurrentWorkflowTaskPollers(5)
        ->withMaxConcurrentActivityTaskPollers(5)
        // Activities per second for the whole Task Queue
        ->withTaskQueueActivitiesPerSecond(100),
);
```

More pollers do not give more PHP execution capacity. If `withMaxConcurrentActivityExecutionSize()` is much larger than `num_workers`, tasks wait in the worker while their Start-To-Close timeout runs.

### Eager Activities

The worker can start an Activity in the same Workflow Task response, without a poll. Since SDK 2.20 (with RoadRunner v3), the number of eager Activities reserved per Workflow Task is configurable:

```php
WorkerOptions::new()->withMaxEagerActivityReservationsPerWorkflowTask(10);

// Turn eager execution off
WorkerOptions::new()->withDisableEagerActivities();
```

### Payload Error Limit

By default, the worker fails the Workflow Task with `PAYLOADS_TOO_LARGE` when a payload exceeds the namespace limit. Since SDK 2.20, this check can be turned off:

```php
WorkerOptions::new()->withDisablePayloadErrorLimit();
```

### Activity Finalizer

A worker process runs many Activity tasks. Reset application state after each task:

```php
$worker->registerActivityFinalizer(fn() => $entityManager->clear());
```

## Workflow Init Attribute

Put state initialization in the constructor of your Workflow class, so that it happens before Signals and Updates arrive.

Normally, the constructor has no arguments. With the `#[WorkflowInit]` attribute, the constructor receives the same arguments as the Workflow method:

```php
use Temporal\Workflow\WorkflowInit;

#[WorkflowInterface]
class ClusterManagerWorkflow
{
    private readonly int $maxNodes;

    #[WorkflowInit]
    public function __construct(ClusterManagerInput $input)
    {
        $this->maxNodes = $input->maxNodes;
    }

    #[WorkflowMethod]
    public function run(ClusterManagerInput $input): \Generator
    {
        // $this->maxNodes is already initialized
    }
}
```

The constructor and the Workflow method must have the same parameters. Do not start Activities or timers in the constructor.

## Feature Flags

`Temporal\Worker\FeatureFlags` holds static switches for behavior changes that affect command sequences. Set them in the worker entrypoint, before `$factory->run()`:

| Flag | Default | Effect |
| -- | -- | -- |
| `$readOnlyWorkflowCallbacks` | `true` | A command from a Query handler, an Update validator, an await condition or a `sideEffect()` callback throws (SDK 2.20) |
| `$settleAwaitOnFirstSettledCondition` | `false` | A multi-condition `await()` unblocks on the first settled condition and propagates a rejection (SDK 2.19) |
| `$propagateCancellationToNewScopes` | `false` | A nested scope, await or `onCancel` handler created after its scope was cancelled is cancelled immediately (SDK 2.18) |

A flag that changes commands can break replay of open Workflows. Enable it for new deployments or together with [versioning](versioning.md).

## Cloud Operations API

Since SDK 2.19, `CloudClient` exposes the [Temporal Cloud Operations API](https://docs.temporal.io/ops) (namespaces, users, API keys):

```php
use Temporal\Api\Cloud\Cloudservice\V1\GetNamespacesRequest;
use Temporal\Client\GRPC\CloudClient;

$cloud = CloudClient::createSSL('saas-api.tmprl.cloud:443')
    ->withAuthKey($apiKey)
    ->withApiVersion('2024-05-13-00');

$response = $cloud->GetNamespaces(new GetNamespacesRequest());
```

## Connecting to Temporal Cloud

```php
use Temporal\Client\ClientOptions;
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\WorkflowClient;

$client = WorkflowClient::create(
    ServiceClient::createSSL('my-namespace.a1b2c.tmprl.cloud:7233')->withAuthKey($apiKey),
    (new ClientOptions())->withNamespace('my-namespace.a1b2c'),
);
```

The worker connects through RoadRunner. Set the address, namespace and `tls` in the `temporal` section of `.rr.yaml`. Give an API key to the worker factory:

```php
use Temporal\Worker\ServiceCredentials;
use Temporal\WorkerFactory;

$factory = WorkerFactory::create(credentials: ServiceCredentials::create()->withApiKey($apiKey));
```
