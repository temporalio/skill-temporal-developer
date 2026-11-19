# Laravel Temporal Integration

## Overview

Use [keepsuit/laravel-temporal](https://github.com/keepsuit/laravel-temporal) when the application uses Laravel. It is a community package, not a requirement of the PHP SDK. The current release (v2.3.x) requires `temporal/sdk ~2.17.0`. Features of SDK 2.18+ in these references (for example the testing interactions and workflow mocks, `AwaitOptions` and serialization context) are not available with it.

## Setup

```bash
composer require keepsuit/laravel-temporal
php artisan temporal:install
php artisan vendor:publish --tag=temporal-config
```

Generate Workflows and Activities, and start a worker for a Task Queue:

```bash
php artisan temporal:make:workflow Order
php artisan temporal:make:activity Payment
php artisan temporal:work orders
```

The package discovers Workflows and Activities in the `app` directory and registers them on the worker. `temporal:work` starts RoadRunner with the worker of the package. This worker sets `FeatureFlags::$workflowDeferredHandlerStart = true` and `FeatureFlags::$cancelAbandonedChildWorkflows = false`, which differ from the SDK defaults.

## Starting Workflows

Use the `Keepsuit\LaravelTemporal\Facade\Temporal` facade (not the SDK `Temporal\Workflow` facade):

```php
use Keepsuit\LaravelTemporal\Facade\Temporal;

$workflow = Temporal::newWorkflow()
    ->withTaskQueue('orders')
    ->withWorkflowId('order-' . $order->id)
    ->build(OrderWorkflowInterface::class);

// Start and wait for the result
$result = $workflow->run($order->id);

// Or start and return immediately
Temporal::workflowClient()->start($workflow, $order->id);
```

Customize worker options per Task Queue:

```php
Temporal::buildWorkerOptionsUsing(
    fn(string $taskQueue) => WorkerOptions::new()->withMaxConcurrentActivityExecutionSize(8),
);
```

## Serialization

The package supports `TemporalSerializable` DTOs, Eloquent models (`TemporalEloquentSerialize`) and Spatie Laravel Data. Use the data converter of the package on both the client and the worker.

```php
// BAD - The workflow keeps a copy of the model, which becomes stale
public function run(Order $order): \Generator;

// GOOD - Pass the ID; Activities load fresh data
public function run(int $orderId): \Generator;
```

Lazy loading of an Eloquent relation in Workflow code is database I/O. Load data in Activities.

## Application Lifetime

The package runs each Activity in a scoped Laravel application and flushes it after the call. This isolates services that the Activity resolves from the container during the call. The worker builds the Activity and its constructor dependencies from the root application, so these keep their state between tasks. The sandbox does not make Workflow code deterministic. Static caches and process-wide listeners still keep their state between tasks.

## Testing

To test that application code starts a Workflow, mock the Workflow and assert its dispatch. The mock returns the configured result without executing the Workflow body:

```php
use Keepsuit\LaravelTemporal\Facade\Temporal;

Temporal::fake();

$workflowMock = Temporal::mockWorkflow(OrderWorkflowInterface::class)->andReturn('completed');

// ... code that starts the workflow ...

$workflowMock->assertDispatched();
```

To assert that a Workflow dispatches an Activity, run the real Workflow with a test server and worker. For an Order Workflow that calls `Payment.charge` once, mock only the Activity and wait for Workflow completion before asserting:

```php
use Keepsuit\LaravelTemporal\Facade\Temporal;
use Keepsuit\LaravelTemporal\Testing\WithTemporal;
use Tests\TestCase;

final class OrderWorkflowTest extends TestCase
{
    use WithTemporal;

    public function testChargesPayment(): void
    {
        Temporal::fake();

        $activityMock = Temporal::mockActivity([PaymentActivityInterface::class, 'charge'])
            ->andReturn('charged');

        $workflow = Temporal::newWorkflow()
            ->withTaskQueue(config('temporal.queue'))
            ->build(OrderWorkflowInterface::class);

        $workflow->run(123);

        $activityMock->assertDispatchedTimes(1);
    }
}
```

- `Temporal::fake()` returns the mock result only for a Workflow or Activity with a mock. A mocked call runs no timers, cancellation or replay. A Workflow without a mock starts on the real client and needs a server and a worker.
- The `WithTemporal` trait starts a test server and a worker for a test case.
- `WithTemporalWorker` starts only a worker against a server that is already running, for example one from `php artisan temporal:server`.
- `TEMPORAL_TESTING_SERVER=false` makes `WithTemporal` use an external server and start only the worker.
- `WithoutTimeSkipping` and `TemporalTestTime::sleep()` control time in interaction tests.

Add [replay tests](../testing.md#workflow-replay-testing) in addition to dispatch fakes.
