# PHP SDK Testing

## Overview

The `temporal/sdk` package contains a PHPUnit testing framework in the `Temporal\Testing` namespace. Tests run against a real worker that RoadRunner starts, and a Temporal test server with time skipping. The framework gives:

- `Environment` - starts and stops the test server and RoadRunner
- `WorkflowTestCase` / `TimeSkippingWorkflowTestCase` - PHPUnit base classes with a client and mocks
- `ActivityMocker` and `WorkflowMocker` - mock Activities, child Workflows, `getVersion()` and `sideEffect()`
- `WorkflowInteractions` - assertions about the Activities, timers, children and Signals of a run
- `WorkflowReplayer` - replay tests

## Test Environment Setup

**tests/bootstrap.php** - starts the test server and the test worker once per PHPUnit run:

```php
<?php

declare(strict_types=1);

use Temporal\Testing\Environment;

require __DIR__ . '/../vendor/autoload.php';

$environment = Environment::create();
$environment->startTemporalTestServer();
$environment->startRoadRunner(['./rr', 'serve', '-c', 'tests/.rr.test.yaml'], configFile: 'tests/.rr.test.yaml');
register_shutdown_function(static fn() => $environment->stop());
```

**tests/.rr.test.yaml** - the test worker needs a `kv` storage for mocks. RoadRunner runs `server.command` in the directory of the configuration file:

```yaml
version: "3"

rpc:
  listen: tcp://127.0.0.1:6001

server:
  command: "php worker.test.php"

temporal:
  address: "127.0.0.1:7233"
  activities:
    num_workers: 2

kv:
  test:
    driver: memory
    config:
      interval: 10
```

**tests/worker.test.php** - use `Temporal\Testing\WorkerFactory`, which connects the mocks:

```php
<?php

declare(strict_types=1);

use App\Activity\GreetingActivity;
use App\Workflow\GreetingWorkflow;
use Temporal\Testing\WorkerFactory;

require __DIR__ . '/../vendor/autoload.php';

$factory = WorkerFactory::create();
$worker = $factory->newWorker('test-queue');
$worker->registerWorkflowTypes(GreetingWorkflow::class);
$worker->registerActivity(GreetingActivity::class);
$factory->run();
```

Set `TEMPORAL_ADDRESS=127.0.0.1:7233` and `bootstrap="tests/bootstrap.php"` in `phpunit.xml`. `Environment` expects the `rr` and `temporal-test-server` binaries in the project root. Download `temporal-test-server` from the [temporalio/sdk-java releases](https://github.com/temporalio/sdk-java/releases) and add it to `.gitignore`.

## Workflow Test Case

```php
<?php

declare(strict_types=1);

use App\Workflow\GreetingWorkflowInterface;
use Temporal\Client\WorkflowOptions;
use Temporal\Testing\WorkflowTestCase;

final class GreetingWorkflowTest extends WorkflowTestCase
{
    public function testReturnsGreeting(): void
    {
        $workflow = $this->workflowClient->newWorkflowStub(
            GreetingWorkflowInterface::class,
            WorkflowOptions::new()->withTaskQueue('test-queue'),
        );

        $run = $this->workflowClient->start($workflow, 'World');

        self::assertSame('Hello, World!', $run->getResult('string', 10));
    }
}
```

`WorkflowTestCase` creates `$workflowClient`, `$testingService`, `$activityMocks`, `$workflowMocks` and `$delayedCallbacks`, and clears the mocks in `tearDown()`.

## Mocking Activities

Mock an Activity by its full Activity Type (interface `prefix` + method name):

```php
public function testUsesMockedActivity(): void
{
    $this->activityMocks->expectCompletion('Greeting.greet', 'Hello, mock!');

    $workflow = $this->workflowClient->newWorkflowStub(
        GreetingWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $this->workflowClient->start($workflow, 'World');

    self::assertSame('Hello, mock!', $run->getResult('string', 10));

    $this->interactions($run)
        ->activity('Greeting.greet')
        ->withInput('World')
        ->assertCalledOnce();
}
```

Other expectations:

```php
$this->activityMocks->expectFailure('Payment.charge', new \RuntimeException('Card declined'));
$this->activityMocks->expectConsecutiveCompletions('Inventory.check', [false, false, true]);
$this->activityMocks->expectCompletionWhen('Fx.rate', ['EUR', 'USD'], 1.08);
```

## Mocking Child Workflows, Versions and Side Effects

```php
$this->workflowMocks->expectCompletion('ProcessOrder', 'processed');
$this->workflowMocks->expectFailure('ProcessOrder', new \RuntimeException('failed'));
$this->workflowMocks->expectVersion('notification-channel', 2);
$this->workflowMocks->expectSideEffect(42);

// After the run
$this->workflowMocks->assertInvoked('ProcessOrder');
```

## Asserting Interactions

`$this->interactions($run)` reads the history of a run:

```php
$interactions = $this->interactions($run);
$interactions->activity('Payment.charge')->assertCalledTimes(1);
$interactions->localActivity('Lookup.quick')->assertNeverCalled();
$interactions->childWorkflow('ProcessOrder')->assertStartedOnce();
$interactions->timer()->assertStarted('1 hour');
$interactions->signal('approve')->assertSentOnce();
$interactions->assertNoOtherActivities();
```

## Time Skipping

The test server skips time when no Activity is running: a one-month timer fires immediately. `TimeSkippingWorkflowTestCase` locks time skipping during client calls, so that a test can interact with a Workflow before its timers fire.

Send a Signal after a simulated delay:

```php
public function testApprovalArrivesAfterThirtyMinutes(): void
{
    $stub = $this->workflowClient->newUntypedWorkflowStub(
        'Approval',
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );

    $this->delayedCallbacks->signalAfter(1800, 'approve')->start($stub);

    self::assertSame('approved', $stub->getResult('string', 10));
}
```

Control the server time directly with `$this->testingService`:

```php
$this->testingService->lockTimeSkipping();
try {
    $this->testingService->unlockTimeSkippingWithSleep(3600);
} finally {
    $this->testingService->unlockTimeSkipping();
}
```

Time-skipping locks are a counter. Balance each `lockTimeSkipping()` with an `unlockTimeSkipping()`. `WorkflowTestCase` fails a test that leaves the counter unbalanced. The normal dev server (`temporal server start-dev`) does not skip time.

## Testing Signals and Queries

```php
public function testSignalAndQuery(): void
{
    $workflow = $this->workflowClient->newWorkflowStub(
        OrderWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $this->workflowClient->start($workflow);

    $workflow->addItem('book');
    self::assertSame(1, $workflow->getItemCount());

    $workflow->approve();
    self::assertSame('Processed 1 items', $run->getResult('string', 10));
}
```

## Testing Failure Cases

```php
use Temporal\Exception\Client\WorkflowFailedException;
use Temporal\Exception\Failure\ActivityFailure;
use Temporal\Exception\Failure\ApplicationFailure;

public function testFailsWhenPaymentDeclined(): void
{
    $this->activityMocks->expectFailure(
        'Payment.charge',
        new ApplicationFailure('Declined', 'PaymentDeclined', true),
    );

    $workflow = $this->workflowClient->newWorkflowStub(
        OrderWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $this->workflowClient->start($workflow, 'order-1');

    try {
        $run->getResult(timeout: 10);
        self::fail('The workflow did not fail');
    } catch (WorkflowFailedException $e) {
        self::assertInstanceOf(ActivityFailure::class, $e->getPrevious());
    }
}
```

## Workflow Replay Testing

`WorkflowReplayer` sends a history to the running test worker, which replays it against the current code:

```php
use PHPUnit\Framework\TestCase;
use Temporal\Testing\Replay\WorkflowReplayer;
use Temporal\Workflow\WorkflowExecution;

final class OrderReplayTest extends TestCase
{
    public function testReplayFromFile(): void
    {
        (new WorkflowReplayer())->replayFromJSON('Order', __DIR__ . '/histories/order.json');
        $this->addToAssertionCount(1);
    }

    public function testReplayFromServer(): void
    {
        (new WorkflowReplayer())->replayFromServer(
            'Order',
            new WorkflowExecution('order-123', 'run-id'),
        );
        $this->addToAssertionCount(1);
    }
}
```

The replayer throws `NonDeterministicWorkflowException` on a mismatch. Export a history with `temporal workflow show --workflow-id order-123 --output json > tests/histories/order.json`. `replayFromServer()` requires the Run ID.

The running test worker must register the Workflow on the **same Task Queue** as in the history. Otherwise the replay fails with a non-determinism error, also for unchanged code. Add a worker for the production Task Queue to `worker.test.php`:

```php
$factory->newWorker('orders')->registerWorkflowTypes(OrderWorkflow::class);
```

The JSON file must be readable by the RoadRunner process.

## Activity Testing

An Activity implementation is a PHP class. Test it with plain PHPUnit and mocked dependencies:

```php
public function testGreet(): void
{
    self::assertSame('Hello, World!', (new GreetingActivity())->greet('World'));
}
```

Code that calls `Activity::heartbeat()` or `Activity::getInfo()` needs the worker. Test it through a Workflow test.

## Best Practices

1. Use an isolated Task Queue for tests, so no application worker takes the tasks.
2. Clear mocks between tests (`WorkflowTestCase` does it).
3. Use the same data converter in the client, the test worker and the mocks.
4. Test failure paths and cancellation, not only the happy path.
5. Keep replay histories for each released Workflow version and run them in CI.
