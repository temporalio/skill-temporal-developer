# PHP SDK Testing

## Overview

You test Temporal PHP Workflows using PHPUnit with the Temporal testing package. The PHP SDK provides `WorkerFactory` from `Temporal\Testing` and a RoadRunner test server for running workflows in an isolated environment.

## Test Environment Setup

Set up a `bootstrap.php` to initialize the test environment:

```php
use Temporal\Testing\Environment;

$environment = Environment::create();
$environment->start();

register_shutdown_function(function () use ($environment): void {
    $environment->stop();
});
```

Configure `phpunit.xml` to use the bootstrap:

```xml
<phpunit bootstrap="bootstrap.php">
    <testsuites>
        <testsuite name="Temporal">
            <directory>tests</directory>
        </testsuite>
    </testsuites>
</phpunit>
```

A test case uses `WorkerFactory` from the Testing namespace and registers workflows and activities:

```php
use PHPUnit\Framework\TestCase;
use Temporal\Testing\WorkerFactory;

class MyWorkflowTest extends TestCase
{
    private WorkerFactory $factory;

    protected function setUp(): void
    {
        $this->factory = WorkerFactory::create();
        $worker = $this->factory->newWorker();
        $worker->registerWorkflowTypes(MyWorkflow::class);
        $worker->registerActivity(MyActivity::class);
        $this->factory->start();
    }

    protected function tearDown(): void
    {
        $this->factory->stop();
    }
}
```

## Activity Mocking

Use `ActivityMocker` to mock activities without executing their real implementation:

```php
use PHPUnit\Framework\TestCase;
use Temporal\Testing\ActivityMocker;
use Temporal\Testing\WorkerFactory;

class MyWorkflowTest extends TestCase
{
    private WorkerFactory $factory;
    private ActivityMocker $activityMocks;

    protected function setUp(): void
    {
        $this->factory = WorkerFactory::create();
        $worker = $this->factory->newWorker();
        $worker->registerWorkflowTypes(MyWorkflow::class);
        $this->factory->start();

        $this->activityMocks = new ActivityMocker();
    }

    protected function tearDown(): void
    {
        $this->activityMocks->clear();
        $this->factory->stop();
    }

    public function testWorkflowWithMock(): void
    {
        $this->activityMocks->expectCompletion(
            MyActivity::class . '::doSomething',
            'mocked result'
        );

        $workflow = $this->factory->getClient()->newWorkflowStub(MyWorkflow::class);
        $result = $workflow->run('input');

        $this->assertEquals('expected output', $result);
    }
}
```

`expectCompletion(string $name, mixed $result)` — mock a successful activity result.

## Testing Signals and Queries

Start a workflow asynchronously, send a signal via the client, then query state:

```php
public function testSignalAndQuery(): void
{
    $workflow = $this->factory->getClient()->newWorkflowStub(MyWorkflow::class);

    // Start workflow asynchronously
    $run = $this->factory->getClient()->startWorkflow($workflow, 'input');

    // Send signal
    $workflow->mySignal('signal data');

    // Query state
    $status = $workflow->getStatus();
    $this->assertEquals('expected', $status);

    // Wait for completion
    $result = $run->getResult();
    $this->assertEquals('done', $result);
}
```

## Testing Failure Cases

Mock activity failures with `expectFailure()`:

```php
public function testActivityFailureHandling(): void
{
    $this->activityMocks->expectFailure(
        MyActivity::class . '::doSomething',
        new \RuntimeException('Simulated failure')
    );

    $workflow = $this->factory->getClient()->newWorkflowStub(MyWorkflow::class);

    $this->expectException(\Temporal\Exception\Failure\ApplicationFailure::class);
    $workflow->run('input');
}
```

## Replay Testing

Use `WorkflowReplayer` to verify workflow determinism against recorded histories:

```php
use Temporal\Testing\WorkflowReplayer;

// Replay from server
$replayer = new WorkflowReplayer();
$replayer->replayFromServer(
    workflowType: MyWorkflow::class,
    workflowId: 'workflow-id-to-replay',
);

// Replay from JSON file
$replayer->replayFromJSON(
    workflowType: MyWorkflow::class,
    path: __DIR__ . '/history.json',
);

// Replay from a WorkflowHistory object
$replayer->replayHistory(
    workflowType: MyWorkflow::class,
    history: $history,
);
```

## Activity Testing

Test activities directly without a workflow:

```php
use PHPUnit\Framework\TestCase;

class MyActivityTest extends TestCase
{
    private MyActivity $activity;

    protected function setUp(): void
    {
        $this->activity = new MyActivity();
    }

    public function testActivity(): void
    {
        $result = $this->activity->doSomething('arg1');
        $this->assertEquals('expected', $result);
    }
}
```

Activities are plain PHP classes — test them directly by instantiating and calling methods.

## Best Practices

1. Use the test environment (`Temporal\Testing\Environment`) for all workflow tests
2. Mock external dependencies using `ActivityMocker` rather than calling real services
3. Test replay compatibility when changing workflow code to catch determinism violations
4. Use unique workflow IDs per test to avoid conflicts
5. Call `$this->activityMocks->clear()` in `tearDown()` to reset mocks between tests
6. Test signal and query handlers explicitly with async workflow start
