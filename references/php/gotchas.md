# PHP Gotchas

PHP-specific mistakes and anti-patterns. See also [Common Gotchas](../core/gotchas.md) for language-agnostic concepts.

## Worker Startup

### Running the Worker Without RoadRunner

```bash
# BAD - No RoadRunner transport, the worker cannot receive tasks
php worker.php

# GOOD - RoadRunner starts worker.php and supplies the transport
./rr serve -c .rr.yaml
```

### Writing to STDOUT

RoadRunner uses the STDOUT stream of the worker process for its protocol. A direct write to this stream corrupts it. The output of `echo` and `var_dump()` goes to the RoadRunner log, without levels or context.

```php
// BAD - Breaks the RoadRunner protocol, the Activity fails and the worker is lost
fwrite(\STDOUT, "Processing order {$orderId}\n");

// BAD - A log record without level or context
echo "Processing order {$orderId}\n";

// GOOD - Workflow code: replay-aware logger
Workflow::getLogger()->info('Processing order', ['orderId' => $orderId]);

// GOOD - Activity code: a PSR-3 logger that writes to STDERR
$this->logger->info('Processing order', ['orderId' => $orderId]);
```

### Changed Code Is Not Loaded

RoadRunner keeps the PHP worker processes alive. After a code change, the old code runs until the processes restart:

```bash
# Restart the PHP worker processes
./rr reset -c .rr.yaml
```

## Generators and Promises

### Forgetting `yield`

```php
// BAD - $result is a promise, not the Activity result. The Error retries the Workflow Task
public function run(string $orderId): \Generator
{
    $result = $this->activities->charge($orderId);
    $uuid = Workflow::uuid();
    yield Workflow::timer(10);
    return 'Charged: ' . $result;
}

// GOOD - Wait for each promise
public function run(string $orderId): \Generator
{
    $result = yield $this->activities->charge($orderId);
    $uuid = yield Workflow::uuid();
    yield Workflow::timer(10);
    return 'Charged: ' . $result;
}
```

### Incorrect Return Type on a Generator Method

```php
// BAD - Fatal error: a generator cannot declare string
#[WorkflowMethod]
public function run(string $name): string
{
    return yield $this->activities->greet($name);
}

// GOOD - Declare \Generator, describe the result with #[ReturnType]
#[WorkflowMethod]
#[ReturnType('string')]
public function run(string $name): \Generator
{
    return yield $this->activities->greet($name);
}
```

### Unbounded Fan-Out

```php
use Temporal\Promise;

// BAD - 100,000 concurrent Activities in one Workflow run
$promises = [];
foreach ($allItemIds as $id) {
    $promises[] = $this->activities->process($id);
}
yield Promise::all($promises);
```

Read bounded pages and use Continue-As-New between pages. See [bounded batches](patterns.md#bounded-batch-processing).

## Activities

### Registering an Activity Instance

```php
// BAD - registerActivity() takes a class name, not an object
$worker->registerActivity(new OrderActivity($logger));

// GOOD - Class name with a factory for constructor dependencies
$worker->registerActivity(
    OrderActivity::class,
    fn(\ReflectionClass $class) => $container->get($class->getName()),
);
```

### Shared State in Long-Lived Processes

A RoadRunner worker process runs many Activity tasks. For an Activity registered by class name, each task gets a new instance. Static variables, shared container services, and instances that a factory returns from a container keep their values between tasks.

```php
// BAD - The tenant of one task leaks into the next task
final class ReportActivity implements ReportActivityInterface
{
    private static ?string $tenant = null;

    public function build(string $tenant, string $reportId): string
    {
        self::$tenant ??= $tenant;
        return $this->repository->forTenant(self::$tenant)->build($reportId);
    }
}

// GOOD - Pass the context explicitly on each call
final class ReportActivity implements ReportActivityInterface
{
    public function build(string $tenant, string $reportId): string
    {
        return $this->repository->forTenant($tenant)->build($reportId);
    }
}
```

Reset application state after each Activity with a finalizer, for example an ORM identity map:

```php
$worker->registerActivityFinalizer(fn() => $entityManager->clear());
```

### Local Activity Without `#[LocalActivityInterface]`

```php
// BAD - With LocalActivityOptions, the stub call throws a TypeError and the Workflow Task retries
#[ActivityInterface(prefix: 'Lookup.')]
interface LookupActivityInterface
{
    #[ActivityMethod]
    public function quickLookup(string $key): string;
}

// GOOD - The interface is marked as local
#[LocalActivityInterface(prefix: 'Lookup.')]
interface LookupActivityInterface
{
    #[ActivityMethod]
    public function quickLookup(string $key): string;
}
```

## Wrong Retry Classification

Transient network errors should be retried. Validation errors should not be. See [PHP error handling guide](error-handling.md) to classify errors with `nonRetryable: true` and `RetryOptions::withNonRetryableExceptions()`.

## Heartbeating

### Forgetting to Heartbeat Long Activities

```php
// BAD - No heartbeat, a stuck Activity is found only at Start-To-Close
public function processFile(string $path): void
{
    foreach (new \SplFileObject($path) as $line) {
        $this->processLine($line);
    }
}

// GOOD - Heartbeat with progress
public function processFile(string $path): void
{
    foreach (new \SplFileObject($path) as $number => $line) {
        $this->processLine($line);
        Activity::heartbeat($number);
    }
}
```

### Heartbeat Timeout Too Short

```php
// BAD - Heartbeat timeout is shorter than the time between heartbeats
ActivityOptions::new()
    ->withStartToCloseTimeout('30 minutes')
    ->withHeartbeatTimeout(10);

// GOOD - Heartbeat timeout allows for processing variance
ActivityOptions::new()
    ->withStartToCloseTimeout('30 minutes')
    ->withHeartbeatTimeout('2 minutes');
```

## Cancellation

### Not Handling Workflow Cancellation

```php
// BAD - Cleanup runs in the cancelled scope, the Activity is cancelled immediately
public function run(string $resourceId): \Generator
{
    try {
        yield $this->activities->acquire($resourceId);
        yield $this->activities->doWork($resourceId);
    } finally {
        yield $this->activities->release($resourceId);
    }
}

// GOOD - Cleanup in a detached scope runs after cancellation
public function run(string $resourceId): \Generator
{
    try {
        yield $this->activities->acquire($resourceId);
        yield $this->activities->doWork($resourceId);
    } finally {
        yield Workflow::asyncDetached(fn() => yield $this->activities->release($resourceId));
    }
}
```

### Not Handling Activity Cancellation

Cancellation is delivered to an Activity only through a heartbeat. See [heartbeat details](patterns.md#activity-heartbeat-details) for the exceptions.

```php
// BAD - The Activity ignores cancellation
public function sync(array $ids): void
{
    foreach ($ids as $id) {
        $this->syncOne($id);
    }
}

// GOOD - Heartbeat and handle cancellation
public function sync(array $ids): void
{
    try {
        foreach ($ids as $id) {
            Activity::heartbeat($id);
            $this->syncOne($id);
        }
    } catch (ActivityCompletionException $e) {
        $this->rollback();
        throw $e;
    }
}
```

## Message Handlers

### Awaiting an Evaluated Boolean

```php
// BAD - TypeError: await() takes a callable, a promise or a Mutex, not a bool
yield Workflow::await(Workflow::allHandlersFinished());

// GOOD - A callable is evaluated again after each change
yield Workflow::await(fn() => Workflow::allHandlersFinished());
```

### Losing Signals in a Buffer

```php
// BAD - Signals received while persistOffers() runs are erased
yield $this->activities->persistOffers($this->pendingOffers);
$this->pendingOffers = [];

// GOOD - Take the batch before the yield
$batch = $this->pendingOffers;
$this->pendingOffers = [];
yield $this->activities->persistOffers($batch);
```

Before Continue-As-New, wait for all handlers and pass the remaining buffer to the next run.

## Testing

### Not Testing Failures

Make sure Workflows work as expected under failure paths, not just happy paths. See [PHP testing guide](testing.md) for more info.

### Not Testing Replay

Replay tests find non-determinism in Workflow code before a deployment. See [PHP testing guide](testing.md#workflow-replay-testing).

## Timers and Sleep

### Using sleep()

```php
// BAD - sleep() blocks the worker event loop and is not durable
public function run(): \Generator
{
    sleep(60);
    yield $this->activities->sendReminder();
}

// GOOD - A durable timer in the Event History
public function run(): \Generator
{
    yield Workflow::timer(60);
    yield $this->activities->sendReminder();
}
```

## Copying APIs From Other SDKs

PHP names and signatures differ from other SDKs. For example: `Workflow::getVersion()`, not `patched()`. `registerActivity()`, not `activities: [...]`. A `DataConverter` with payload converters, not `withCodec()`. Make sure the API exists in the installed `temporal/sdk` version.
