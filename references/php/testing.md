# PHP SDK Testing

Read the installed SDK and framework versions before copying a test bootstrap. Testing helpers ship under `Temporal\Testing` in `temporal/sdk`; they are not an in-process replacement for RoadRunner. Sources: [official testing guide](https://docs.temporal.io/develop/php/best-practices/testing-suite), [SDK testing code at v2.18](https://github.com/temporalio/sdk-php/tree/v2.18/testing/src), [sample feature tests](https://github.com/temporalio/samples-php/tree/bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4/app/tests/Feature).

## Choose the test boundary

| Test | Establishes | Does not establish |
| --- | --- | --- |
| Plain PHPUnit Activity unit test | Domain logic, I/O adapter behavior, idempotency | Worker transport or workflow replay |
| Laravel `Temporal::fake()` | Dispatch/input/queue assertions and controlled fakes | Real timers, cancellation delivery or replay compatibility |
| Real worker + mocked Activities | Orchestration, messages, failure handling | Real external side effects |
| Real worker + real test dependencies | Serialization, registration and integration | Compatibility with all historical executions |
| Replay of recorded histories | Compatibility of commands with those histories | Correctness of new external Activity behavior |

## Real worker with Activity mocks

Run a dedicated test worker process. Its entrypoint is the normal worker registration code with `Temporal\Testing\WorkerFactory` instead of `Temporal\WorkerFactory`, ending in `$factory->run()`. Do not call `$factory->start()`, `$factory->stop()` or treat `$factory->getClient()` as a workflow client: those are not the testing lifecycle shown by the SDK.

Configure the test worker and shared mock transport:

```yaml
version: "3"
rpc:
  listen: tcp://127.0.0.1:6002
server:
  command: "php worker.test.php"
  relay: pipes
temporal:
  address: "127.0.0.1:7235"
  activities:
    num_workers: 2
kv:
  test:
    driver: memory
    config:
      interval: 10
logs:
  level: info
```

This is `tests/.rr.test.yaml`, with commands resolved from the project root. Use the same test Temporal endpoint and namespace in the client, server and worker, and an isolated test Task Queue. Export `TEMPORAL_ADDRESS=127.0.0.1:7235` and `RR_RPC=tcp://127.0.0.1:6002` for the test runner. A mock written to a different RoadRunner RPC/KV instance will never reach the worker. An ordinary application worker polling the test queue can steal tasks and execute real Activities.

Environment API changed between the course's SDK and `v2.18`:

```php
use Temporal\Testing\Environment;

$environment = Environment::create();
// SDK v2.18: explicit server + worker lifecycle.
$environment->startTemporalTestServer();
$environment->startRoadRunner(
    ['./rr', 'serve', '-c', 'tests/.rr.test.yaml'],
    configFile: 'tests/.rr.test.yaml',
);
register_shutdown_function(static fn() => $environment->stop());
```

Provision the compatible RoadRunner and Temporal test-server binaries first; v2.18 does not perform the old automatic test-server download here. `configFile` is also used for the readiness check; `-c` in the command selects the actual serving configuration.

For SDK **v2.16.0**, the course-compatible equivalent is `$environment->start('./rr serve -c tests/.rr.test.yaml')`. Against an already running dedicated server, start only the worker through an external process supervisor or the framework lifecycle. In v2.16, `Environment::startRoadRunner()` can run alone with a command string. In v2.18 it checks Environment server state first; do not copy the course's worker-only bootstrap unchanged. Do not combine these bootstraps with a framework trait that already owns the server/worker lifecycle.

A test body can use an explicit cache connection, especially with custom DTO converters:

```php
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\WorkflowClient;
use Temporal\Client\WorkflowOptions;
use Temporal\Testing\ActivityMocker;
use Temporal\Worker\ActivityInvocationCache\RoadRunnerActivityInvocationCache;

$client = WorkflowClient::create(ServiceClient::create('127.0.0.1:7235'));
$mocks = new ActivityMocker(
    new RoadRunnerActivityInvocationCache('tcp://127.0.0.1:6002', 'test'),
);
try {
    // Must match the registered Activity Type, including prefix and case.
    // Assumes #[ActivityInterface(prefix: 'Greeting.')] and method name 'greet'.
    $mocks->expectCompletion('Greeting.greet', 'Hello, test!');
    $workflow = $client->newWorkflowStub(
        GreetingWorkflowInterface::class,
        WorkflowOptions::new()->withTaskQueue('test-queue'),
    );
    $run = $client->start($workflow, 'test');
    self::assertSame('Hello, test!', $run->getResult(timeout: 10));
} finally {
    $mocks->clear();
}
```

`expectFailure($activityType, $throwable)` configures failure. SDK v2.16's mocker supplies fixed results; v2.18 also has `expectConsecutiveCompletions()` and `expectCompletionWhen()`. Verify capabilities rather than carrying forward the course comment that consecutive results are impossible. For DTOs, use the same converter in the client, test worker and invocation cache. Clear mocks between tests and isolate concurrently running tests; global cache clearing can interfere with another test.

## Time and messages

The normal dev server does **not** support time skipping. The special test server does. `Environment::startTemporalTestServer()` and `TestService` support that server; do not call test-service APIs against a normal server. Lock/unlock time skipping deliberately around interaction tests and restore it in teardown. A real Activity still needs real execution time; time skipping is not a faster PHP clock.

Create the helper with `Temporal\Testing\TestService::create('127.0.0.1:7235')`. Time-skipping locks are a **counter**, not a boolean: `lockTimeSkipping()` increments it and `unlockTimeSkipping()` decrements it. Balance each acquired lock in `finally`; do not unlock locks owned by framework lifecycle code. On an exclusively owned test server with exactly one lock, `unlockTimeSkippingWithSleep(3600)` temporarily releases and restores that lock to advance one hour. Additional locks prevent that fast-forward; an already-zero counter makes the call unbalanced. In SDK v2.18, `lockDelta()` helps detect an imbalance introduced through that helper instance.

Start asynchronously with `$client->start($stub, ...$input)`. For a Signal, observe an initialized ready state through a bounded Query before sending when the protocol requires it; after sending, wait for the expected state or result. Signal acknowledgement is not a business-result acknowledgement. Initialize state visible to early queries; do not swallow arbitrary query errors until a test happens to pass.

Test Query read-only behavior, duplicate and late Signals, timeout versus Signal races, Update validator rejection, successful Update result, and accepted-but-not-completed async Updates. Give each logical Update a distinct stable request ID; retry the same request with the same ID. Before workflow completion/Continue-As-New, drain handlers with `yield Workflow::await(fn() => Workflow::allHandlersFinished())` and preserve pending inputs. Verify same Workflow ID/new Run ID across Continue-As-New and test a Signal arriving while a batch Activity is pending.

See [Laravel testing helpers](integrations/laravel-temporal.md) for `WithTemporal`, `WithTemporalWorker`, `WithoutTimeSkipping` and `TemporalTestTime`.

## Replay testing

Use the actual namespace and signatures:

```php
use Temporal\Testing\Replay\WorkflowReplayer;
use Temporal\Workflow\WorkflowExecution;

$replayer = new WorkflowReplayer();
$replayer->replayFromServer(
    workflowType: 'Order', // Registered Workflow Type, not necessarily a PHP FQCN.
    execution: new WorkflowExecution('order-123', 'recorded-run-id'),
);
$replayer->replayFromJSON('Order', __DIR__ . '/histories/order.json');
// Given a Temporal\Api\History\V1\History object:
// $replayer->replayHistory($history);
```

A compatible RoadRunner instance must be running with the workflow implementation registered and replay RPC support (introduced in RoadRunner 2023.3). `RR_RPC` must reach it. Server replay requires both Workflow ID and Run ID. JSON replay paths must exist where RoadRunner reads them, including across containers. `replayHistory()` takes only the History object; it derives the type from the first event.

Keep fixtures for pre/post-patch executions and meaningful message/timer/child/failure branches. Fail the test/CI command on `ReplayerException`, especially `NonDeterministicWorkflowException`. The samples' replay command prints failures but returns success, so do not reuse its exit behavior as a CI gate. A replay pass only covers supplied histories.
