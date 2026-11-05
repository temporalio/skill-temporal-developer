# PHP SDK Observability

## Overview

The PHP SDK uses PSR-3 loggers, with a replay-aware logger for Workflow code. RoadRunner exports SDK metrics. The `temporal/open-telemetry-interceptors` package adds tracing.

## Logging

### Workflow Logging (Replay-Safe)

Use `Workflow::getLogger()` inside Workflows. It does not write log records again during replay:

```php
use Temporal\Workflow;

final class OrderWorkflow implements OrderWorkflowInterface
{
    public function run(OrderInput $order): \Generator
    {
        Workflow::getLogger()->info('Workflow started', ['orderId' => $order->orderId]);

        $result = yield $this->activities->processPayment($order);

        Workflow::getLogger()->info('Payment processed', ['result' => $result]);

        return $result;
    }
}
```

### Activity Logging

Activities are not replayed. Use a PSR-3 logger from the container:

```php
use Psr\Log\LoggerInterface;

final class PaymentActivity implements PaymentActivityInterface
{
    public function __construct(private readonly LoggerInterface $logger) {}

    public function processPayment(OrderInput $order): string
    {
        $this->logger->info('Processing payment', ['orderId' => $order->orderId]);
        return 'completed';
    }
}
```

Do not write directly to the `STDOUT` stream: RoadRunner uses it for its protocol. Write to STDERR, or use `roadrunner/psr-logger`, which sends logs to the RoadRunner logger.

### Customizing the Logger

Give a PSR-3 logger to the worker. The Workflow logger and SDK messages use it:

```php
use Monolog\Handler\StreamHandler;
use Monolog\Logger;
use Temporal\Worker\WorkerOptions;
use Temporal\WorkerFactory;

$logger = new Logger('temporal');
$logger->pushHandler(new StreamHandler('php://stderr'));

$factory = WorkerFactory::create();
$worker = $factory->newWorker(
    'orders',
    WorkerOptions::new()->withEnableLoggingInReplay(false),
    logger: $logger,
);
```

`withEnableLoggingInReplay(true)` writes Workflow log records also during replay. Use it only for debugging.

## Metrics

### Enabling SDK Metrics

The Go SDK inside RoadRunner records the SDK metrics. Configure a Prometheus endpoint in `.rr.yaml`:

```yaml
temporal:
  address: "127.0.0.1:7233"
  metrics:
    driver: prometheus
    prometheus:
      address: "127.0.0.1:9091"
      type: summary
```

The `statsd` driver is also available.

### Key SDK Metrics

- `temporal_request` - Client requests to server
- `temporal_workflow_task_execution_latency` - Workflow task processing time
- `temporal_activity_execution_latency` - Activity execution time
- `temporal_workflow_task_replay_latency` - Replay duration
- `temporal_activity_schedule_to_start_latency` - Time an Activity waited in the Task Queue

Application metrics can use the separate RoadRunner `metrics` plugin through RPC from Activity code. Do not call it from Workflow code.

## Tracing

Install the OpenTelemetry interceptors:

```bash
composer require temporal/open-telemetry-interceptors
```

Register the tracing interceptors on the client and the worker with a `SimplePipelineProvider`:

```php
use Temporal\Interceptor\SimplePipelineProvider;
use Temporal\OpenTelemetry\Interceptor\OpenTelemetryActivityInboundInterceptor;
use Temporal\OpenTelemetry\Interceptor\OpenTelemetryWorkflowClientCallsInterceptor;
use Temporal\OpenTelemetry\Interceptor\OpenTelemetryWorkflowOutboundRequestInterceptor;
use Temporal\OpenTelemetry\Tracer;

$tracer = new Tracer($tracerProvider->getTracer('temporal'), $propagator);

$client = WorkflowClient::create(
    ServiceClient::create('127.0.0.1:7233'),
    interceptorProvider: new SimplePipelineProvider([
        new OpenTelemetryWorkflowClientCallsInterceptor($tracer),
    ]),
);

$worker = $factory->newWorker(
    'orders',
    interceptorProvider: new SimplePipelineProvider([
        new OpenTelemetryActivityInboundInterceptor($tracer),
        new OpenTelemetryWorkflowOutboundRequestInterceptor($tracer),
    ]),
);
```

## Search Attributes (Visibility)

Register custom Search Attributes in the namespace before use. Set them when the Workflow starts:

```php
use Temporal\Client\WorkflowOptions;
use Temporal\Common\SearchAttributes\SearchAttributeKey;
use Temporal\Common\TypedSearchAttributes;

$options = WorkflowOptions::new()
    ->withTaskQueue('orders')
    ->withTypedSearchAttributes(
        TypedSearchAttributes::empty()
            ->withValue(SearchAttributeKey::forKeyword('OrderId'), 'order-123')
            ->withValue(SearchAttributeKey::forKeyword('OrderStatus'), 'pending'),
    );
```

Change them from the Workflow:

```php
Workflow::upsertTypedSearchAttributes(
    SearchAttributeKey::forKeyword('OrderStatus')->valueSet('completed'),
);
```

### Querying Workflows by Search Attributes

Find Workflows by Search Attributes from a client:

```php
foreach ($client->listWorkflowExecutions('OrderStatus = "pending"') as $execution) {
    echo $execution->execution->getID(), PHP_EOL;
}
```

## Best Practices

1. Use `Workflow::getLogger()` inside Workflow code for replay-safe logging.
2. Do not write directly to the `STDOUT` stream in worker code.
3. Use standard PSR-3 loggers in Activities.
4. Monitor `rr_activities_pool_queue_size` and Schedule-To-Start latency to find workers without free capacity.
5. Do not use high-cardinality values (order IDs, trace IDs) as metric labels.
