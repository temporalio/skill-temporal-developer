# PHP SDK Observability

## Overview

The PHP SDK provides observability through PSR-3 logging (with replay-aware Workflow logger), and visibility via Search Attributes.

## Logging

### Workflow Logging

Use `Workflow::getLogger()` for replay-safe logging inside Workflows:

```php
use Temporal\Workflow;

class OrderWorkflow implements OrderWorkflowInterface
{
    public function run(array $order): \Generator
    {
        Workflow::getLogger()->info('Workflow started', ['orderId' => $order['id']]);

        $result = yield $this->activity->processPayment($order);

        Workflow::getLogger()->info('Payment processed', ['result' => $result]);

        return $result;
    }
}
```

The Workflow logger automatically suppresses duplicate log messages during replay by default.

### Activity Logging

Activities are not replayed, so use any standard PSR-3 logger (injected via constructor or DI):

```php
use Psr\Log\LoggerInterface;

class OrderActivity implements OrderActivityInterface
{
    public function __construct(private LoggerInterface $logger) {}

    public function processPayment(array $order): string
    {
        $this->logger->info('Processing payment', ['orderId' => $order['id']]);

        // Perform work...

        $this->logger->info('Payment complete');
        return 'completed';
    }
}
```

### Enabling Logging During Replay

By default, `Workflow::getLogger()` suppresses logs during replay. To enable logging during replay (useful for debugging):

```php
use Temporal\Worker\WorkerOptions;

$worker = $factory->newWorker(
    taskQueue: 'orders',
    options: WorkerOptions::new()->withEnableLoggingInReplay(true)
);
```

## Customizing the Logger

Pass a custom PSR-3 logger when creating the Worker:

```php
use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Temporal\WorkerFactory;

$logger = new Logger('temporal');
$logger->pushHandler(new StreamHandler('php://stderr'));

$factory = WorkerFactory::create();

$worker = $factory->newWorker(
    taskQueue: 'my-task-queue',
    logger: $logger
);
```

Any PSR-3 compatible logger (Monolog, etc.) can be used.

## Search Attributes (Visibility)

See the Search Attributes section of `references/php/data-handling.md`

## Best Practices

1. Use `Workflow::getLogger()` inside Workflow code for replay-safe logging
2. Do not use `echo` or `print()` in worker code — replay duplicates output and stdout may carry the RoadRunner protocol
3. Use standard PSR-3 loggers in Activities (no replay concern)
4. Use Search Attributes for business-level visibility and querying across Workflow executions

## Metrics and tracing

The course distinguishes two pipelines: `temporal.metrics` exposes SDK/Go metrics through RoadRunner; the top-level `metrics` plugin accepts application metrics through RoadRunner RPC. Configure and scrape them separately. Use queue latency/backlog, execution duration, retries/timeouts, worker capacity and RSS for operations. Check actual metric names/labels in the installed version before writing dashboards or autoscaling rules.

The course emits business counters through an Activity to keep direct RPC I/O out of workflow code. Such a counter can still increment more than once on Activity retry after a lost completion. Use a business-event ledger/deduplication when exact counts matter; do not present a retried metrics Activity as exactly-once accounting. Avoid high-cardinality metric labels such as order IDs or trace IDs; keep those in logs/traces.

The optional `temporal/open-telemetry-interceptors` package supplies tracing integration. Register the client, workflow-outbound and Activity-inbound interceptors appropriate to the installed version, and configure the exporter/propagator consistently. The course keeps an HTTP span active while starting a workflow to propagate one trace context; verify incoming distributed-context extraction and cleanup as well. A generated `X-Trace-Id` header is correlation, not proof of end-to-end parent propagation.

Exporting each span synchronously is a demo tradeoff, not a universal long-running-worker rule. If batching, configure and test periodic flushing, shutdown flushing and bounded queues. Never manually export spans over HTTP in deterministic workflow code. Redact sensitive payloads and SQL bindings. Workflow logs are process logs; they are not automatically shown in Temporal Web UI or stored as history events.

Sources: [course telemetry configuration](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/config/temporal.php), [provider](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Providers/AppServiceProvider.php), [metrics Activity](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Activities/MetricsActivity.php).
