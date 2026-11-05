# PHP SDK Patterns

Examples omit imports that are the same in every file: `Temporal\Workflow`, `Temporal\Promise`, `Temporal\Activity\ActivityOptions`, `Temporal\Workflow\WorkflowInterface` and `Temporal\Workflow\WorkflowMethod`.

## Signals

```php
use Temporal\Workflow\SignalMethod;

#[WorkflowInterface]
class OrderWorkflow
{
    private bool $approved = false;
    private array $items = [];

    #[SignalMethod]
    public function approve(): void
    {
        $this->approved = true;
    }

    #[SignalMethod]
    public function addItem(string $item): void
    {
        $this->items[] = $item;
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::await(fn() => $this->approved);
        return sprintf('Processed %d items', count($this->items));
    }
}
```

### Dynamic Signal Handlers

For handling signals with names not known at compile time. Use cases for this pattern are rare — most workflows should use statically defined signal handlers.

```php
use Temporal\DataConverter\ValuesInterface;

#[WorkflowInterface]
class DynamicSignalWorkflow
{
    private array $signals = [];

    public function __construct()
    {
        Workflow::registerDynamicSignal(function (string $name, ValuesInterface $arguments): void {
            $this->signals[$name][] = $arguments->getValue(0);
        });
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::await(fn() => isset($this->signals['done']));
        return $this->signals;
    }
}
```

## Queries

**Important:** Queries must NOT modify workflow state or have side effects. Since SDK 2.20, a command (Activity, timer, etc.) from a Query handler throws.

```php
use Temporal\Workflow\QueryMethod;

#[WorkflowInterface]
class StatusWorkflow
{
    private string $status = 'pending';
    private int $progress = 0;

    #[QueryMethod]
    public function getStatus(): string
    {
        return $this->status;
    }

    #[QueryMethod]
    public function getProgress(): int
    {
        return $this->progress;
    }

    #[WorkflowMethod]
    public function run(array $itemIds): \Generator
    {
        $activities = Workflow::newActivityStub(
            ItemActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout(60),
        );

        $this->status = 'running';
        foreach ($itemIds as $i => $itemId) {
            $this->progress = $i;
            yield $activities->processItem($itemId);
        }
        $this->status = 'completed';
        return 'done';
    }
}
```

### Dynamic Query Handlers

For handling queries with names not known at compile time. Use cases for this pattern are rare — most workflows should use statically defined query handlers.

```php
use Temporal\DataConverter\ValuesInterface;

#[WorkflowInterface]
class DynamicQueryWorkflow
{
    private array $state = ['status' => 'running', 'progress' => 0];

    public function __construct()
    {
        Workflow::registerDynamicQuery(function (string $name, ValuesInterface $arguments): mixed {
            return $this->state[$name] ?? null;
        });
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::timer(1);
    }
}
```

## Updates

```php
use Temporal\Workflow\UpdateMethod;
use Temporal\Workflow\UpdateValidatorMethod;

#[WorkflowInterface]
class CartWorkflow
{
    private array $items = [];

    #[UpdateMethod]
    public function addItem(string $item): int
    {
        $this->items[] = $item;
        return count($this->items);
    }

    #[UpdateValidatorMethod(forUpdate: 'addItem')]
    public function validateAddItem(string $item): void
    {
        if ($item === '') {
            throw new \InvalidArgumentException('Item cannot be empty');
        }
        if (count($this->items) >= 100) {
            throw new \OverflowException('Cart is full');
        }
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::await(fn() => count($this->items) > 0);
        return sprintf('Cart with %d items', count($this->items));
    }
}
```

An Update handler can be a generator and `yield` Activities. A validator must be read-only.

From a client, start an Update. `startUpdate()` returns after the Update is accepted. `getResult()` waits until it is completed:

```php
use Temporal\Client\Update\LifecycleStage;
use Temporal\Client\Update\UpdateOptions;

$stub = $client->newUntypedRunningWorkflowStub('cart-123');
$handle = $stub->startUpdate(
    UpdateOptions::new('addItem', LifecycleStage::StageAccepted)->withUpdateId($requestId),
    'book',
);
$count = $handle->getResult();
```

Use one Update ID per logical request. Retry the same request with the same ID. A client timeout in `getResult()` does not cancel the Update.

## Child Workflows

```php
use Temporal\Workflow\ChildWorkflowOptions;
use Temporal\Workflow\ParentClosePolicy;

#[WorkflowInterface]
class ParentWorkflow
{
    #[WorkflowMethod]
    public function run(array $orderIds): \Generator
    {
        $results = [];
        foreach ($orderIds as $orderId) {
            $child = Workflow::newChildWorkflowStub(
                ProcessOrderWorkflowInterface::class,
                ChildWorkflowOptions::new()
                    ->withWorkflowId('order-' . $orderId)
                    ->withParentClosePolicy(ParentClosePolicy::Abandon),
            );
            $results[] = yield $child->run($orderId);
        }
        return $results;
    }
}
```

By default, the PHP SDK also cancels `Abandon` children when the parent is cancelled. For real abandon semantics, set `FeatureFlags::$cancelAbandonedChildWorkflows = false` in the worker. See [feature flags](advanced-features.md#feature-flags).

Use `Workflow::executeChildWorkflow()` for an untyped call:

```php
$result = yield Workflow::executeChildWorkflow(
    'ProcessOrder',
    [$orderId],
    ChildWorkflowOptions::new()->withWorkflowId('order-' . $orderId),
);
```

## Handles to External Workflows

```php
use Temporal\Workflow\WorkflowExecution;

#[WorkflowInterface]
class CoordinatorWorkflow
{
    #[WorkflowMethod]
    public function run(string $targetWorkflowId, array $data): \Generator
    {
        $target = Workflow::newExternalWorkflowStub(
            TargetWorkflowInterface::class,
            new WorkflowExecution($targetWorkflowId),
        );

        yield $target->dataReady($data);

        yield Workflow::newUntypedExternalWorkflowStub(new WorkflowExecution($targetWorkflowId))->cancel();
    }
}
```

## Parallel Execution

```php
#[WorkflowInterface]
class ParallelWorkflow
{
    #[WorkflowMethod]
    public function run(array $items): \Generator
    {
        $activities = Workflow::newActivityStub(
            ItemActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout('5 minutes'),
        );

        $promises = [];
        foreach ($items as $item) {
            $promises[] = $activities->processItem($item);
        }

        return yield Promise::all($promises);
    }
}
```

Use `Workflow::async()` to run a sequence of steps as one concurrent branch:

```php
$branches = [];
foreach ($orderIds as $orderId) {
    $branches[] = Workflow::async(function () use ($activities, $orderId) {
        $reservation = yield $activities->reserve($orderId);
        return yield $activities->ship($orderId, $reservation);
    });
}
$results = yield Promise::all($branches);
```

`Promise::all()` rejects on the first rejection. It does not cancel the other branches. `Promise::any()` waits for the first fulfilled promise. `Promise::race()` waits for the first settled promise.

### Bounded Batch Processing

Do not start one Activity per item for a large input. Read a bounded page, process it, and use Continue-As-New between pages:

```php
#[WorkflowInterface]
class BatchWorkflow
{
    #[WorkflowMethod(name: 'Batch')]
    public function run(string $batchId, ?string $cursor = null, int $processed = 0): \Generator
    {
        $activities = Workflow::newActivityStub(
            BatchActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout(60),
        );

        $page = yield $activities->readPage($batchId, $cursor, 100);

        yield Promise::all(array_map(
            fn(string $itemId) => $activities->processItem($batchId, $itemId),
            $page->itemIds,
        ));
        $processed += count($page->itemIds);

        if ($page->nextCursor === null) {
            return $processed;
        }

        return yield Workflow::continueAsNew('Batch', [$batchId, $page->nextCursor, $processed]);
    }
}
```

Keep only counters and cursors in Workflow state. Store large results outside Temporal and pass references.

To continue the batch when one item fails, turn the terminal failure of an item into an outcome. Let cancellation propagate:

```php
use Temporal\Exception\Failure\ActivityFailure;
use Temporal\Exception\Failure\CanceledFailure;

$outcomes = yield Promise::all(array_map(
    fn(string $itemId) => Workflow::async(function () use ($activities, $batchId, $itemId) {
        try {
            yield $activities->processItem($batchId, $itemId);
            return true;
        } catch (ActivityFailure $e) {
            if ($e->getPrevious() instanceof CanceledFailure) {
                throw $e;
            }
            yield $activities->markFailed($batchId, $itemId, $e->getMessage());
            return false;
        }
    }),
    $page->itemIds,
));
```

## Continue-as-New

```php
#[WorkflowInterface]
class LongRunningWorkflow
{
    #[WorkflowMethod(name: 'LongRunning')]
    public function run(WorkflowState $state): \Generator
    {
        while (true) {
            $state = yield $this->processNextBatch($state);

            if ($state->isComplete) {
                return 'done';
            }

            if (Workflow::getInfo()->shouldContinueAsNew) {
                yield Workflow::await(fn() => Workflow::allHandlersFinished());
                return yield Workflow::continueAsNew('LongRunning', [$state]);
            }
        }
    }
}
```

## Saga Pattern (Compensations)

`Temporal\Workflow\Saga` stores compensations and runs them in reverse order. `compensate()` runs them in a detached cancellation scope, so it also works after the Workflow is cancelled.

```php
use Temporal\Workflow\Saga;

#[WorkflowInterface]
class BookingWorkflow
{
    #[WorkflowMethod]
    public function run(string $tripId): \Generator
    {
        $activities = Workflow::newActivityStub(
            BookingActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout(30),
        );

        $saga = new Saga();
        $saga->setParallelCompensation(false);

        try {
            // Add the compensation BEFORE the action: the action can succeed and its response can be lost.
            $saga->addCompensation(fn() => yield $activities->cancelHotel($tripId));
            yield $activities->bookHotel($tripId);

            $saga->addCompensation(fn() => yield $activities->cancelFlight($tripId));
            yield $activities->bookFlight($tripId);

            return 'booked';
        } catch (\Throwable $e) {
            yield $saga->compensate();
            throw $e;
        }
    }
}
```

Compensation Activities must be idempotent: they can run when the action did not happen, or more than once. `setContinueWithError(true)` continues with the next compensations when one fails.

## Cancellation Scopes

`Workflow::async()` creates a cancellation scope. Cancel it to cancel all its Activities, timers and children:

```php
use Temporal\Exception\Failure\CanceledFailure;

$scope = Workflow::async(fn() => yield $activities->longRunning());

yield Workflow::timer(30);
$scope->cancel();

try {
    yield $scope;
} catch (CanceledFailure) {
    Workflow::getLogger()->info('Long running activity was cancelled');
}
```

`Workflow::asyncDetached()` creates a scope that is not cancelled with its parent. Use it for [cleanup after Workflow cancellation](gotchas.md#not-handling-workflow-cancellation).

## Wait Condition with Timeout

```php
use Temporal\Workflow\SignalMethod;

#[WorkflowInterface]
class ApprovalWorkflow
{
    private bool $approved = false;

    #[SignalMethod]
    public function approve(): void
    {
        $this->approved = true;
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        $approved = yield Workflow::awaitWithTimeout('24 hours', fn() => $this->approved);

        return $approved ? 'approved' : 'auto-rejected due to timeout';
    }
}
```

`awaitWithTimeout()` returns `true` when a condition is met and `false` on timeout. Since SDK 2.20, give `AwaitOptions` to add a summary to the timer, so that concurrent waits are distinguishable in the UI:

```php
use Temporal\Workflow\AwaitOptions;
use Temporal\Workflow\TimerOptions;

yield Workflow::awaitWithTimeout(
    AwaitOptions::new('24 hours')->withTimerOptions(TimerOptions::new()->withSummary('wait-for-approval')),
    fn() => $this->approved,
);
```

Conditions can be callables, promises or a `Workflow\Mutex`. By default, a rejected promise in a multi-condition await is ignored until the timeout. Since SDK 2.19, set `FeatureFlags::$settleAwaitOnFirstSettledCondition = true` on the worker to unblock on the first settled condition and propagate the rejection. This flag changes the emitted commands: enable it only for new Workflows or with [versioning](versioning.md).

## Waiting for All Handlers to Finish

Signal and Update handlers can `yield`. They interleave with the main method at each `yield`. Use `Workflow::await(fn() => Workflow::allHandlersFinished())` before completion or Continue-As-New:

```php
#[WorkflowInterface]
class HandlerAwareWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        // ... main workflow logic ...

        yield Workflow::await(fn() => Workflow::allHandlersFinished());
        return 'done';
    }
}
```

To serialize handlers that change shared state across a `yield`, use one `Temporal\Workflow\Mutex` per Workflow instance:

```php
use Temporal\Workflow\Mutex;
use Temporal\Workflow\UpdateMethod;

private Mutex $lock;

public function __construct()
{
    $this->lock = new Mutex();
}

#[UpdateMethod]
public function reserve(string $sku): \Generator
{
    return yield Workflow::runLocked($this->lock, function () use ($sku) {
        $this->reservations[] = yield $this->activities->reserve($sku);
        return count($this->reservations);
    });
}
```

## Activity Heartbeat Details

### WHY:

- **Support activity cancellation** — Cancellations are delivered via heartbeat; activities that don't heartbeat won't know they've been cancelled
- **Resume progress after worker failure** — Heartbeat details persist across retries

### WHEN:

- **Cancellable activities** — Any activity that should respond to cancellation
- **Long-running activities** — Track progress for resumability
- **Checkpointing** — Save progress periodically

```php
use Temporal\Activity;
use Temporal\Exception\Client\ActivityCompletionException;

final class FileProcessingActivity implements FileProcessingActivityInterface
{
    public function processLargeFile(string $path): string
    {
        $startLine = Activity::hasHeartbeatDetails() ? Activity::getHeartbeatDetails('int') : 0;

        $file = new \SplFileObject($path);
        $file->seek($startLine);

        try {
            while (!$file->eof()) {
                $line = $file->current();
                if ($line !== '') {
                    $this->processLine($line);
                }
                $file->next();
                Activity::heartbeat($file->key());
            }
            return 'completed';
        } catch (ActivityCompletionException $e) {
            $this->cleanup();
            throw $e;
        }
    }
}
```

`Activity::heartbeat()` throws an `ActivityCompletionException` when the Activity is cancelled (`ActivityCanceledException`) or paused (`ActivityPausedException`). Always rethrow it. `Activity::getCancellationDetails()` tells the reason. Do not use the exception class to tell a reset from a cancellation: with RoadRunner 3.0.1 and Server 1.32, a reset of a running Activity arrives as `ActivityCanceledException` with `cancelRequested` set.

## Timers

```php
use Temporal\Workflow\TimerOptions;

#[WorkflowInterface]
class TimerWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::timer('1 hour', TimerOptions::new()->withSummary('cool-down'));
        return 'Timer fired';
    }
}
```

## Local Activities

**Purpose**: Reduce latency for short, lightweight operations by skipping the task queue. ONLY use these when necessary for performance. Do NOT use these by default, as they are not durable and distributed.

A local Activity interface must have `#[LocalActivityInterface]`. See [gotchas](gotchas.md#local-activity-without-localactivityinterface). A `#[LocalActivityInterface]` stub without `LocalActivityOptions` throws a `RuntimeException`.

```php
use Temporal\Activity\ActivityMethod;
use Temporal\Activity\LocalActivityInterface;
use Temporal\Activity\LocalActivityOptions;

#[LocalActivityInterface(prefix: 'Lookup.')]
interface LookupActivityInterface
{
    #[ActivityMethod]
    public function quickLookup(string $key): string;
}

#[WorkflowInterface]
class LocalActivityWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        $activities = Workflow::newActivityStub(
            LookupActivityInterface::class,
            LocalActivityOptions::new()->withStartToCloseTimeout(5),
        );

        return yield $activities->quickLookup('key');
    }
}
```
