# PHP SDK Observability

## Overview

The PHP SDK provides observability through PSR-3 logging (with replay-aware Workflow logger), and visibility via Search Attributes.

## Logging / Replay-Aware Logging

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
$logger->pushHandler(new StreamHandler('php://stdout'));

$factory = WorkerFactory::create();

$worker = $factory->newWorker(
    taskQueue: 'my-task-queue',
    logger: $logger
);
```

Any PSR-3 compatible logger (Monolog, etc.) can be used.

## Search Attributes (Visibility)

Use Search Attributes to make Workflow executions queryable by business fields. See `references/php/data-handling.md` for how to set and upsert Search Attributes.

Query Workflow executions using Search Attributes:

```php
$executions = $client->listWorkflowExecutions(
    'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND OrderStatus = "pending"'
);

foreach ($executions as $execution) {
    echo "Pending order: {$execution->getExecution()->getWorkflowId()}\n";
}
```

Or using the Temporal CLI:

```bash
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND OrderStatus = "pending"'
```

## Best Practices

1. Use `Workflow::getLogger()` inside Workflow code for replay-safe logging
2. Do not use `echo` or `print()` in Workflows — output appears on every replay
3. Use standard PSR-3 loggers in Activities (no replay concern)
4. Use Search Attributes for business-level visibility and querying across Workflow executions
