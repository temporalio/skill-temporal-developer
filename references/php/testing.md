# PHP SDK Testing

## Overview

The `temporal/sdk` package contains a PHPUnit testing framework in the `Temporal\Testing` namespace. Tests run against a real worker that RoadRunner starts, and a Temporal test server with time skipping. The framework gives:

- `Environment` - starts and stops the test server and RoadRunner
- `WorkflowTestCase` / `TimeSkippingWorkflowTestCase` - PHPUnit base classes with a client and mocks
- `ActivityMocker`, `WorkflowMocker` and `SearchAttributeMocker` - mock Activities, child Workflows, `getVersion()`, `sideEffect()` and typed Search Attribute upserts
- `WorkflowInteractions` - assertions about the Activities, timers, children and external Signals of a run
- `WorkflowReplayer` - replay tests

## Choose the Test Boundary

| Test | Shows | Does not show |
| -- | -- | -- |
| Plain PHPUnit test of an Activity class | Domain logic, I/O adapters, idempotency | Worker transport, replay |
| Real worker + mocked Activities | Orchestration, messages, failure handling | Real external side effects |
| Real worker + real Activities | Serialization, registration, integration | Compatibility with old histories |
| Replay of recorded histories | Compatibility of the code with those histories | Correctness of new behavior |

## Test Environment Setup

Use ports that differ from a local dev server and an application RoadRunner. Set them in `phpunit.xml`:

```xml
<phpunit bootstrap="tests/bootstrap.php">
    <php>
        <env name="TEMPORAL_ADDRESS" value="127.0.0.1:7235"/>
        <env name="RR_RPC" value="tcp://127.0.0.1:6002"/>
    </php>
</phpunit>
```

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

**tests/.rr.test.yaml** - the test worker needs a `kv` storage named `test` for mocks. RoadRunner runs `server.command` in the directory of the configuration file:

```yaml
version: "3"

rpc:
  listen: tcp://127.0.0.1:6002

server:
  command: "php worker.test.php"

temporal:
  address: "127.0.0.1:7235"
  activities:
    num_workers: 2

kv:
  test:
    driver: memory
    config:
      interval: 10
```

**tests/worker.test.php** - `Temporal\Testing\WorkerFactory` connects the Activity mocks. Child Workflow, `getVersion()`, `sideEffect()` and Search Attribute mocks need the interceptors:

```php
<?php

declare(strict_types=1);

use App\Activity\GreetingActivity;
use App\Workflow\GreetingWorkflow;
use Temporal\Interceptor\SimplePipelineProvider;
use Temporal\Testing\MockChildWorkflowInterceptor;
use Temporal\Testing\MockSearchAttributeInterceptor;
use Temporal\Testing\MockSideEffectInterceptor;
use Temporal\Testing\WorkerFactory;

require __DIR__ . '/../vendor/autoload.php';

$factory = WorkerFactory::create();
$worker = $factory->newWorker(
    'test-queue',
    interceptorProvider: new SimplePipelineProvider([
        new MockChildWorkflowInterceptor(),
        new MockSideEffectInterceptor(),
        new MockSearchAttributeInterceptor(),
    ]),
);
$worker->registerWorkflowTypes(GreetingWorkflow::class);
$worker->registerActivity(GreetingActivity::class);

// Replay needs the Workflow on the Task Queue of the recorded histories
$factory->newWorker('my-task-queue')->registerWorkflowTypes(GreetingWorkflow::class);

$factory->run();
```

`MockSearchAttributeInterceptor` is also necessary for a Workflow that upserts typed Search Attributes: the time-skipping test server does not support that call.

`Environment` expects the `rr` and `temporal-test-server` binaries in the project root. Download `temporal-test-server` from the [temporalio/sdk-java releases](https://github.com/temporalio/sdk-java/releases) and add it to `.gitignore`.

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

`WorkflowTestCase` creates `$workflowClient`, `$testingService`, `$activityMocks`, `$workflowMocks`, `$searchAttributeMocks` and `$delayedCallbacks`. It clears the mocks in `tearDown()`.

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
$this->activityMocks->expectFailure('Payment.charge', new ApplicationFailure('Declined', 'PaymentDeclined', true));
$this->activityMocks->expectConsecutiveCompletions('Inventory.check', [false, false, true]);
$this->activityMocks->expectCompletionWhen('Fx.rate', ['EUR', 'USD'], 1.08);
```

A mocked failure answers every retry attempt. With the default retry policy, a retryable failure repeats until a timeout stops it. Use a non-retryable failure, or limit `maximumAttempts` in the Activity options.

With a custom data converter, give the same converter to the mock cache:

```php
use Temporal\Testing\ActivityMocker;
use Temporal\Worker\ActivityInvocationCache\RoadRunnerActivityInvocationCache;

$mocks = new ActivityMocker(new RoadRunnerActivityInvocationCache('tcp://127.0.0.1:6002', 'test', $converter));
```

## Mocking Child Workflows, Versions and Side Effects

These mocks need the interceptors in `worker.test.php`:

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
$interactions->assertNoOtherActivities();
```

`signal()` counts Signals that the Workflow sends to other Workflows, not Signals that it receives:

```php
$interactions->signal('dataReady')->assertSentOnce();
```

## Time Skipping

The test server skips time when no Activity is running: a one-month timer fires immediately. The normal dev server (`temporal server start-dev`) does not skip time.

Send a Signal after a simulated delay. Use `$this->delayedCallbacks` in a test that extends the plain `WorkflowTestCase`:

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

By default, the scheduler waits until the Workflow starts its first timer. For a Workflow without a timer, give a condition with `readyWhen()`.

`TimeSkippingWorkflowTestCase` locks time skipping for the whole test and unlocks it only while `getResult()` waits. Signals and Queries that the test sends before `getResult()` arrive before the timers fire. Inside this class, `$this->delayedCallbacks` throws `LogicException`.

Control the server time directly in a plain `WorkflowTestCase`:

```php
$this->testingService->lockTimeSkipping();
try {
    $this->testingService->unlockTimeSkippingWithSleep(3600);
} finally {
    $this->testingService->unlockTimeSkipping();
}
```

Time-skipping locks are a counter. Balance each `lockTimeSkipping()` with an `unlockTimeSkipping()`. `WorkflowTestCase` fails a test that leaves the counter unbalanced. `unlockTimeSkippingWithSleep()` skips time only when the counter is 1. With more locks it waits in real time.

## Testing Signals, Queries and Updates

This example assumes a Workflow with the Signals `addItem()` and `approve()` and the Query `getItemCount()`:

```php
public function testSignalAndQuery(): void
{
    $workflow = $this->workflowClient->newWorkflowStub(
        CartWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $this->workflowClient->start($workflow);

    $workflow->addItem('book');
    self::assertSame(1, $workflow->getItemCount());

    $workflow->approve();
    self::assertSame('Processed 1 items', $run->getResult('string', 10));
}
```

The SDK tests Updates on the test server with time skipping locked. Use `TimeSkippingWorkflowTestCase`, or add the `Temporal\Testing\WithoutTimeSkipping` trait to the test class.

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
        PaymentWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $this->workflowClient->start($workflow, 'order-1');

    try {
        $run->getResult(timeout: 10);
        self::fail('The workflow did not fail');
    } catch (WorkflowFailedException $e) {
        // Assumes the Workflow does not catch the ActivityFailure
        self::assertInstanceOf(ActivityFailure::class, $e->getPrevious());
    }
}
```

The client receives `WorkflowFailedException`. Its previous exception is the failure that the Workflow threw: an `ActivityFailure` that is not caught, or the `ApplicationFailure` that the Workflow throws itself.

## Workflow Replay Testing

`WorkflowReplayer` sends a history to the running test worker, which replays it against the current code:

```php
use PHPUnit\Framework\TestCase;
use Temporal\Testing\Replay\WorkflowReplayer;
use Temporal\Workflow\WorkflowExecution;

final class GreetingReplayTest extends TestCase
{
    public function testReplayFromFile(): void
    {
        (new WorkflowReplayer())->replayFromJSON('Greeting', __DIR__ . '/histories/greeting.json');
        $this->addToAssertionCount(1);
    }

    public function testReplayFromServer(): void
    {
        (new WorkflowReplayer())->replayFromServer(
            'Greeting',
            new WorkflowExecution('greeting-world', 'run-id'),
        );
        $this->addToAssertionCount(1);
    }
}
```

- The replayer throws `NonDeterministicWorkflowException` (a `ReplayerException`) on a mismatch. Let it fail the test and the CI job.
- `replayFromServer()` requires the Run ID.
- `replayFromJSON()` takes an optional `$lastEventId` to replay only a part of the history.
- `replayHistory(History $history)` replays a `Temporal\Api\History\V1\History` object. `downloadHistory()` saves a history from the server to a file.
- The replayer connects to the RoadRunner RPC from `RR_RPC`.

Export a history with `temporal workflow show --workflow-id greeting-world --output json > tests/histories/greeting.json`.

The running test worker must register the Workflow on the **same Task Queue** as in the history. Otherwise the replay fails with a non-determinism error, also for unchanged code. The `worker.test.php` above adds a worker for the production Task Queue. The JSON file must be readable by the RoadRunner process.

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
