# PHP SDK Patterns

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
#[WorkflowInterface]
class DynamicSignalWorkflow
{
    private array $signals = [];

    public function __construct()
    {
        Workflow::registerDynamicSignal(function (string $name, array $args): void {
            $this->signals[$name][] = $args[0] ?? null;
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
        Workflow::registerDynamicQuery(function (string $name, array $args): mixed {
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
                    ->withParentClosePolicy(ParentClosePolicy::POLICY_ABANDON)
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
            $targetWorkflowId
        );

        // Signal the external workflow
        yield $handle->dataReady($dataPayload);

        // Or cancel it
        yield $handle->cancel();
    }
}
```

## Parallel Execution

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
                return Workflow::continueAsNew($state);
            }
        }
    }
}
```

## Saga Pattern (Compensations)

**Important:** Compensation activities should be idempotent — they may be retried (as with ALL activities).

```php
#[WorkflowInterface]
class OrderSagaWorkflow
{
    #[WorkflowMethod]
    public function run(Order $order): \Generator
    {
        $compensations = [];
        $activities = Workflow::newActivityStub(
            OrderActivities::class,
            ActivityOptions::new()->withStartToCloseTimeout(CarbonInterval::minutes(5))
        );

        try {
            // Note: save the compensation BEFORE running the activity,
            // because the activity could succeed but fail to report (timeout, crash, etc.).
            // The compensation must handle both reserved and unreserved states.
            $compensations[] = fn() => yield $activities->releaseInventoryIfReserved($order);
            yield $activities->reserveInventory($order);

            $compensations[] = fn() => yield $activities->refundPaymentIfCharged($order);
            yield $activities->chargePayment($order);

            yield $activities->shipOrder($order);

            return 'Order completed';
        } catch (\Throwable $e) {
            Workflow::getLogger()->error('Order failed, running compensations', ['error' => $e->getMessage()]);
            foreach (array_reverse($compensations) as $compensate) {
                try {
                    yield $compensate();
                } catch (\Throwable $compErr) {
                    Workflow::getLogger()->error('Compensation failed', ['error' => $compErr->getMessage()]);
                }
            }
            throw $e;
        }
    }
}
```

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

Signal and update handlers should generally be non-async (avoid running activities from them). Otherwise, the workflow may complete before handlers finish their execution. However, making handlers non-async sometimes requires workarounds that add complexity.

When async handlers are necessary, use `Workflow::await(Workflow::allHandlersFinished())` at the end of your workflow (or before continue-as-new) to prevent completion until all pending handlers complete.

```php
#[WorkflowInterface]
class HandlerAwareWorkflow
{
    #[WorkflowMethod]
    public function run(): \Generator
    {
        // ... main workflow logic ...

        // Before exiting, wait for all handlers to finish
        yield Workflow::await(Workflow::allHandlersFinished());
        return 'done';
    }
}
```

## Activity Heartbeating

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
use Temporal\Exception\Failure\CanceledFailure;

#[ActivityInterface]
class FileProcessingActivities
{
    #[ActivityMethod]
    public function processLargeFile(string $filePath): string
    {
        // Get heartbeat details from previous attempt (if any)
        $heartbeatDetails = Activity::getHeartbeatDetails();
        $startLine = $heartbeatDetails[0] ?? 0;

        $lines = file($filePath);

        try {
            for ($i = $startLine; $i < count($lines); $i++) {
                $this->processLine($lines[$i]);

                // Heartbeat with progress
                // If cancelled, heartbeat() throws CanceledFailure
                Activity::heartbeat($i + 1);
            }
            return 'completed';
        } catch (CanceledFailure $e) {
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

**Purpose**: Reduce latency for short, lightweight operations by skipping the task queue. ONLY use these when necessary for performance. Do NOT use these by default, as they are not durable and distributed.

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
