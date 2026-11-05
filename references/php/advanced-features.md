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

$taskToken = base64_decode($encodedToken);

$completion->completeByToken($taskToken, 'approved');
// or
$completion->completeExceptionallyByToken($taskToken, new \RuntimeException('Rejected'));
```

The task token is binary data. Encode it for transport and decode it before completion. `complete()` and `completeExceptionally()` take the Workflow ID, Run ID and Activity ID instead of the token. For a human approval, a Signal or an Update with a timer is often more simple than an open Activity.

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
    'my-task-queue',
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

| Control | What it limits |
| -- | -- |
| `temporal.activities.num_workers` | PHP processes for Activities and local Activities of all Task Queues (default: number of CPUs) |
| `withMaxConcurrentActivityExecutionSize()` | Concurrent Activity executions admitted by the worker |
| `withMaxConcurrentActivityTaskPollers()` / `withMaxConcurrentWorkflowTaskPollers()` | Concurrent polls, not PHP capacity |
| `withTaskQueueActivitiesPerSecond()` | Server-side Activity rate for the whole Task Queue |
| `withWorkerActivitiesPerSecond()` | Activity rate per worker |
| RoadRunner replicas | Total capacity, limited by shared databases and APIs |

**Process model:**

- All Workflow tasks of a RoadRunner instance run in **one** PHP process. `withMaxConcurrentWorkflowTaskExecutionSize()` does not add PHP capacity. A slow or blocking Workflow stalls all Workflows. `max_worker_memory` and `max_jobs` do not recycle this process.
- Activities and local Activities of all Task Queues share the `activities` pool.
- More pollers do not give more PHP execution capacity. If `withMaxConcurrentActivityExecutionSize()` is much larger than `num_workers`, tasks wait for a free process while their Start-To-Close timeout runs. A task that waits longer than `allocate_timeout` (default 60s) fails the attempt.

**Pool settings:**

- `supervisor.max_worker_memory` is a soft limit in MB. `memory_limit` is not a pool key.
- `max_jobs` restarts a process after a number of tasks. It does not fix a memory leak.
- `supervisor.exec_ttl` kills a process that runs a task too long. The Activity attempt fails and retries. It is not a replacement for Temporal timeouts.
- HTTP processes (`http.pool`) and Temporal processes (`temporal.activities`) are separate pools.

**Scaling:** Scale on backlog, CPU, memory and the `rr_activities_pool_queue_size` gauge. Activity Schedule-To-Start latency shows a shortage of worker slots, not of PHP processes: with the default slot limit, a task leaves the queue and then waits inside RoadRunner for a free process. Set `withMaxConcurrentActivityExecutionSize()` near `num_workers` so that Schedule-To-Start shows a full pool. High latency with idle processes means a polling, routing or registration problem. On Kubernetes, set a termination grace period, test scale-down with running Activities, and make Activities idempotent: an attempt on a stopped worker is retried elsewhere.

### Eager Activities

The worker can start an Activity in the same Workflow Task response, without a poll. Since SDK 2.20 (with RoadRunner v3), the number of eager Activities reserved per Workflow Task is configurable:

```php
WorkerOptions::new()->withMaxEagerActivityReservationsPerWorkflowTask(10);

// Turn eager execution off
WorkerOptions::new()->withDisableEagerActivities();
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

`Temporal\Worker\FeatureFlags` holds static switches for behavior changes. Set them at the top of the worker entrypoint, before `WorkerFactory::create()`. The main flags:

| Flag | Default | Effect |
| -- | -- | -- |
| `$readOnlyWorkflowCallbacks` | `true` | A command from a Query handler, an Update validator, an await condition or a `sideEffect()` callback throws (SDK 2.20) |
| `$settleAwaitOnFirstSettledCondition` | `false` | A multi-condition `await()` unblocks on the first settled condition and propagates a rejection (SDK 2.19, experimental) |
| `$propagateCancellationToNewScopes` | `false` | A nested scope, await or `onCancel` handler created after its scope was cancelled is cancelled immediately (SDK 2.18, experimental) |
| `$cancelAbandonedChildWorkflows` | `true` | Parent cancellation also cancels `ParentClosePolicy::Abandon` children. Set `false` to keep them running (SDK 2.16) |
| `$workflowDeferredHandlerStart` | `false` | The Workflow method starts after all Signals of the same Workflow Task are handled (experimental) |

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

The worker connects through RoadRunner. Without a `tls` section, RoadRunner connects without TLS:

```yaml
temporal:
  address: "my-namespace.a1b2c.tmprl.cloud:7233"
  namespace: "my-namespace.a1b2c"
  tls:
    server_name: "my-namespace.a1b2c.tmprl.cloud"
    # For mTLS: key, cert, root_ca
```

Give an API key to the worker factory:

```php
use Temporal\Worker\ServiceCredentials;
use Temporal\WorkerFactory;

$factory = WorkerFactory::create(credentials: ServiceCredentials::create()->withApiKey($apiKey));
```

## Environment Configuration

Since SDK 2.17, the client can load connection settings from a TOML profile and environment variables (`TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_API_KEY`, `TEMPORAL_TLS_*`, `TEMPORAL_PROFILE`, `TEMPORAL_CONFIG_FILE`), like the Temporal CLI. Remote codec settings are not supported.

Before loading a TOML profile, install the optional parser dependency. `temporal/sdk` only suggests it; Composer does not install it automatically:

```bash
composer require internal/toml
```

Load the profile with environment variable overrides:

```php
use Temporal\Client\WorkflowClient;
use Temporal\Common\EnvConfig\ConfigClient;

$profile = ConfigClient::load();
$client = WorkflowClient::create($profile->toServiceClient(), $profile->toClientOptions());
```

Environment-only configuration needs no TOML parser. Use `ConfigClient::loadFromEnv()` to load environment variables without reading a profile file:

```php
$profile = ConfigClient::loadFromEnv();
$client = WorkflowClient::create($profile->toServiceClient(), $profile->toClientOptions());
```

## Plugins

Since SDK 2.18, a plugin packages interceptors and configuration for the client, the schedule client and the worker. Extend `Temporal\Plugin\AbstractPlugin` and override only the hooks that you need:

```php
use Temporal\OpenTelemetry\Interceptor\OpenTelemetryActivityInboundInterceptor;
use Temporal\OpenTelemetry\Tracer;
use Temporal\Plugin\AbstractPlugin;
use Temporal\Plugin\PluginRegistry;
use Temporal\Plugin\WorkerPluginContext;
use Temporal\WorkerFactory;

final class TracingPlugin extends AbstractPlugin
{
    public function __construct(private readonly Tracer $tracer)
    {
        parent::__construct('acme.tracing');
    }

    public function configureWorker(WorkerPluginContext $context, callable $next): void
    {
        $context->addInterceptor(new OpenTelemetryActivityInboundInterceptor($this->tracer));
        $next($context);
    }
}

$factory = WorkerFactory::create(pluginRegistry: new PluginRegistry([new TracingPlugin($tracer)]));
```

`WorkflowClient::create()` and `ScheduleClient::create()` also take a `pluginRegistry`.
