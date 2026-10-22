# PHP SDK Patterns

Sources: [SDK workflow APIs](https://github.com/temporalio/sdk-php/blob/v2.18/src/Workflow.php), [official samples](https://github.com/temporalio/samples-php/tree/bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4/app/src), and [reviewed course lessons](sources.md). Examples are independent fragments; supply imports and application contracts from the surrounding project.

## Signals

```php
use Temporal\Workflow;
use Temporal\Workflow\WorkflowInterface;
use Temporal\Workflow\WorkflowMethod;
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
        // Wait for approval
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

**Important:** Queries must NOT modify workflow state or have side effects.

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
    public function run(): \Generator
    {
        $this->status = 'running';
        for ($i = 0; $i < 100; $i++) {
            $this->progress = $i;
            yield Workflow::newActivityStub(
                MyActivities::class,
                ActivityOptions::new()->withStartToCloseTimeout(CarbonInterval::minutes(1))
            )->processItem($i);
        }
        $this->status = 'completed';
        return 'done';
    }
}
```

### Dynamic Query Handlers

For handling queries with names not known at compile time. Use cases for this pattern are rare — most workflows should use statically defined query handlers.

```php
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
        // ... workflow logic
        yield Workflow::timer(CarbonInterval::seconds(1));
    }
}
```

## Updates

```php
use Temporal\Workflow\UpdateMethod;
use Temporal\Workflow\UpdateValidatorMethod;

#[WorkflowInterface]
class OrderWorkflow
{
    private array $items = [];

    #[UpdateMethod]
    public function addItem(string $item): int
    {
        $this->items[] = $item;
        return count($this->items);  // Returns new count to caller
    }

    #[UpdateValidatorMethod(forUpdate: 'addItem')]
    public function validateAddItem(string $item): void
    {
        if (empty($item)) {
            throw new \InvalidArgumentException('Item cannot be empty');
        }
        if (count($this->items) >= 100) {
            throw new \OverflowException('Order is full');
        }
    }

    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::await(fn() => count($this->items) > 0);
        return sprintf('Order with %d items', count($this->items));
    }
}
```

## Child Workflows

```php
#[WorkflowInterface]
class ParentWorkflow
{
    #[WorkflowMethod]
    public function run(array $orders): \Generator
    {
        $results = [];
        foreach ($orders as $order) {
            $result = yield Workflow::newChildWorkflowStub(
                ProcessOrderWorkflow::class,
                ChildWorkflowOptions::new()
                    ->withWorkflowId('order-' . $order->id)
                    ->withParentClosePolicy(\Temporal\Workflow\ParentClosePolicy::Abandon)
            )->run($order);
            $results[] = $result;
        }
        return $results;
    }
}
```

Alternatively, use `Workflow::executeChildWorkflow()` for a one-shot call:

```php
$result = yield Workflow::executeChildWorkflow(
    'ProcessOrderWorkflow',
    [$order],
    ChildWorkflowOptions::new()->withWorkflowId('order-' . $order->id)
);
```

## Handles to External Workflows

```php
#[WorkflowInterface]
class CoordinatorWorkflow
{
    #[WorkflowMethod]
    public function run(string $targetWorkflowId): \Generator
    {
        // Get stub for external workflow
        $handle = Workflow::newExternalWorkflowStub(
            TargetWorkflow::class,
            new \Temporal\Workflow\WorkflowExecution($targetWorkflowId)
        );

        // Signal the external workflow
        yield $handle->dataReady($dataPayload);

        // Or cancel it
        yield Workflow::newUntypedExternalWorkflowStub(new \Temporal\Workflow\WorkflowExecution($targetWorkflowId))->cancel();
    }
}
```

## Parallel Execution

Use this only for a small, already bounded input. For many items or independent multi-step chains, read [bounded batch processing](batch-processing.md). `Workflow::async()` gives cooperative workflow concurrency; RoadRunner Activity processes provide execution capacity. Awaiting already-started promises in submission order does not serialize the Activities, but it delays publication of later results.

```php
use Temporal\Workflow;

#[WorkflowInterface]
class ParallelWorkflow
{
    #[WorkflowMethod]
    public function run(array $items): \Generator
    {
        $activities = Workflow::newActivityStub(
            MyActivities::class,
            ActivityOptions::new()->withStartToCloseTimeout(CarbonInterval::minutes(5))
        );

        // Launch all activities in parallel using Workflow::async()
        $promises = [];
        foreach ($items as $item) {
            $promises[] = Workflow::async(fn() => yield $activities->processItem($item));
        }

        // Wait for all to complete
        $results = [];
        foreach ($promises as $promise) {
            $results[] = yield $promise;
        }
        return $results;
    }
}
```

## Continue-as-New

```php
use Temporal\Workflow;

#[WorkflowInterface]
class LongRunningWorkflow
{
    #[WorkflowMethod]
    public function run(WorkflowState $state): \Generator
    {
        while (true) {
            $state = yield $this->processNextBatch($state);

            if ($state->isComplete) {
                return 'done';
            }

            // Continue with fresh history before hitting limits
            if (Workflow::getInfo()->shouldContinueAsNew) {
                yield Workflow::await(fn() => Workflow::allHandlersFinished());
                // Include pending messages and the cursor in $state.
                return yield Workflow::continueAsNew(
                    'LongRunningWorkflow',
                    [$state]
                );
            }
        }
    }
}
```

## Saga Pattern (Compensations)

`Temporal\Workflow\Saga` keeps compensation callbacks and defaults to reverse registration order. `setParallelCompensation(true)` is suitable only for independent compensations. `setContinueWithError(true)` attempts later sequential compensations after a failure and reports collected failures. These are business choices, not universal defaults.

Choose Activity cancellation semantics before using the example. The default `TryCancel` returns cancellation to the workflow immediately, so compensation may race the still-running operation. For operations that cooperate through heartbeats, a configured stub can wait for cancellation completion:

```php
use Temporal\Activity\ActivityCancellationType;
use Temporal\Activity\ActivityOptions;

$options = ActivityOptions::new()
    ->withStartToCloseTimeout(60)
    ->withScheduleToCloseTimeout(300)
    ->withHeartbeatTimeout(10)
    ->withCancellationType(ActivityCancellationType::WaitCancellationCompleted);
```

Pass these options to the Activity stub. Waiting can be slow if the Activity ignores cancellation; bound external I/O and heartbeat regularly. A timeout or acknowledgement does not prove an external payment cannot settle later. Use a stable operation ID plus cancellation intent/fencing or reconciliation at the side-effect boundary. In particular, `refundIfCharged()` must not treat “no charge yet” as proof that no future charge is possible. See [SDK cancellation modes](https://github.com/temporalio/sdk-php/blob/v2.18/src/Activity/ActivityCancellationType.php).

```php
use Temporal\Workflow\Saga;

// Inside a generator workflow; $activities is a configured Activity stub.
$saga = new Saga();
try {
    // Register first: reserve may succeed even if its response is lost.
    // releaseIfReserved must tolerate both absence and repeated compensation.
    $saga->addCompensation(fn() => yield $activities->releaseIfReserved($orderId));
    yield $activities->reserve($orderId);

    $saga->addCompensation(fn() => yield $activities->refundIfCharged($orderId));
    yield $activities->charge($orderId);
} catch (\Throwable $failure) {
    yield $saga->compensate();
    throw $failure;
}
```

The SDK's `Saga::compensate()` creates detached cancellation scopes internally, so the call above is usable after cancellation. If compensation fails, decide how to retain/report both the original and cleanup failures. Returning a cancellation DTO or swallowing `CanceledFailure` completes the workflow normally; rethrow when the workflow must remain Cancelled.

For handwritten cleanup, a plain `finally` does not make its scope immune to cancellation:

```php
try {
    yield $activities->doWork($resourceId);
} finally {
    yield Workflow::asyncDetached(function () use ($activities, $resourceId) {
        yield $activities->releaseIfAcquired($resourceId);
    });
}
```

Detached means independent of parent cancellation, not an independently durable process. Await cleanup before completing. Termination and execution timeouts do not provide the same cleanup opportunity as cooperative cancellation.

## Wait Condition with Timeout

```php
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
        // Wait for approval with 24-hour timeout
        $approved = yield Workflow::awaitWithTimeout(
            CarbonInterval::hours(24),
            fn() => $this->approved
        );

        if ($approved) {
            return 'approved';
        }
        return 'auto-rejected due to timeout';
    }
}
```

## Waiting for All Handlers to Finish

Signal and Update handlers may yield Activities; validators and Queries must not. Async handlers interleave at yield points, so guard shared state and use a workflow-safe lock when a state transition must stay atomic. Initialize handler-visible state before it can be read. Do not finish the main workflow while a handler is still running.

Use a shared `Temporal\Workflow\Mutex` instance per workflow and `yield Workflow::runLocked($this->mutex, function () { /* yielding state transition */ })` for handlers that must serialize. Create the mutex before handlers can run; a new mutex per call cannot coordinate them. `runLocked()` releases it in `finally`. Do not use blocking OS/DB locks in workflow code or hold the mutex while waiting for a handler that needs that same mutex.

When async handlers are necessary, use `Workflow::await(fn() => Workflow::allHandlersFinished())` at the end of your workflow (or before continue-as-new) to prevent completion until all pending handlers complete.

```php
#[WorkflowInterface]
class HandlerAwareWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        // ... main workflow logic ...

        // Before exiting, wait for all handlers to finish
        yield Workflow::await(fn() => Workflow::allHandlersFinished());
        return 'done';
    }
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
use Temporal\Activity\ActivityInterface;
use Temporal\Activity\ActivityMethod;
use Temporal\Exception\Client\ActivityCanceledException;

#[ActivityInterface]
class FileProcessingActivities
{
    #[ActivityMethod]
    public function processLargeFile(string $filePath): string
    {
        // Get heartbeat details from previous attempt (if any)
        $startLine = Activity::hasHeartbeatDetails()
            ? Activity::getHeartbeatDetails('int')
            : 0;

        // Stream inside the Activity; do not materialize the entire file.
        $lines = new \SplFileObject($filePath);
        $lines->seek($startLine);

        try {
            while (!$lines->eof()) {
                $i = $lines->key();
                $line = $lines->fgets();
                if ($line === '') {
                    break;
                }
                $this->processLine($line);

                // Heartbeat with progress
                // If cancelled, heartbeat() throws ActivityCanceledException
                Activity::heartbeat($i + 1);
            }
            return 'completed';
        } catch (ActivityCanceledException $e) {
            // Perform cleanup on cancellation
            $this->cleanup();
            throw $e;
        }
    }
}
```

## Timers

```php
#[WorkflowInterface]
class TimerWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        yield Workflow::timer(CarbonInterval::hours(1));
        return 'Timer fired';
    }
}
```

## Local Activities

**Purpose**: Reduce scheduling latency for short operations executed by the workflow worker infrastructure without a server Activity Task Queue round trip. Completed results are recorded in history, but a local Activity may be re-executed before that record is persisted. Use idempotency; local Activities lack normal heartbeat/routing semantics and can delay Workflow Tasks. Prefer normal Activities unless measured latency justifies the tradeoff.

```php
#[WorkflowInterface]
class LocalActivityWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        $activities = Workflow::newActivityStub(
            LookupActivities::class,
            LocalActivityOptions::new()->withStartToCloseTimeout(CarbonInterval::seconds(5))
        );

        $result = yield $activities->quickLookup('key');
        return $result;
    }
}
```

## Safe signal buffering

Snapshot and remove only the batch being processed **before** yielding. Clearing the whole shared buffer after an Activity can discard Signals received during the wait:

```php
$batch = $this->pendingOffers;
$this->pendingOffers = [];
yield $activities->persistOffers($batch);
// New signals are now in pendingOffers and remain available for the next batch.
```

On terminal persistence failure, explicitly fail or requeue that batch; do not silently discard it. Bound the buffer and define an overload/admission policy. Before Continue-As-New, wait for handlers, preserve all pending state in the next input, and `return yield Workflow::continueAsNew(...)` from the main method. `allHandlersFinished()` does not mean the application buffer is empty. Start the next run with the same Workflow ID and new Run ID; caller protocols must tolerate the transition.

## Client-side Updates

A typed running stub can call an attributed Update and wait for its result. For accepted-but-not-completed processing:

```php
use Temporal\Client\Update\LifecycleStage;
use Temporal\Client\Update\UpdateOptions;

$stub = $client->newUntypedRunningWorkflowStub($workflowId);
$handle = $stub->startUpdate(
    UpdateOptions::new('updateAddress', LifecycleStage::StageAccepted)
        ->withUpdateId($requestId)
        ->withResultType(OrderResult::class),
    $newAddress,
);
// Persist handle identity if another request/process will fetch the result.
$result = $handle->getResult(timeout: 5);
```

The request ID identifies one logical mutation. Reuse it for retries of that mutation; use another ID for another address change. Store Workflow ID, Run ID and Update ID when later retrieval must target the accepting run. Acceptance follows validation; it does not mean the Activity or state change finished. A client result timeout does not cancel the Update. Test validator rejection (`WorkflowUpdateException`), completion and handler-draining behavior.
