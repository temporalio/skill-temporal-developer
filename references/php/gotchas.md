# PHP Gotchas

PHP-specific mistakes and anti-patterns. See also `references/core/gotchas.md` for language-agnostic concepts.

## Wrong Retry Classification

**Example:** Transient network errors should be retried. Authentication errors should not be.
See `references/php/error-handling.md` to understand how to classify errors.

## Cancellation

### Not Handling Workflow Cancellation

```php
// BAD - Cleanup doesn't run on cancellation
#[WorkflowMethod]
public function run(): void
{
    yield $this->myActivity->acquireResource();
    yield $this->myActivity->doWork();
    yield $this->myActivity->releaseResource();  // Never runs if cancelled!
}

// GOOD - Use try/finally for cleanup
#[WorkflowMethod]
public function run(): void
{
    yield $this->myActivity->acquireResource();
    try {
        yield $this->myActivity->doWork();
    } finally {
        // Runs even on cancellation
        yield $this->myActivity->releaseResource();
    }
}
```

When a workflow is cancelled from the client, a `Temporal\Exception\Client\WorkflowFailedException` is thrown on the caller side. Inside the workflow, cancellation arrives as a `CanceledFailure` on the yielded promise.

### Not Handling Activity Cancellation

Activities detect cancellation through heartbeat. Without heartbeating, an activity runs to completion even when cancelled.

```php
// BAD - Activity ignores cancellation
#[ActivityMethod]
public function longRunningTask(): void
{
    foreach ($this->items as $item) {
        $this->process($item);  // Runs to completion even if cancelled
    }
}

// GOOD - Heartbeat and detect cancellation
#[ActivityMethod]
public function longRunningTask(): void
{
    foreach ($this->items as $i => $item) {
        Activity::heartbeat(['progress' => $i]);  // Throws on cancellation
        $this->process($item);
    }
}
```

`Activity::heartbeat()` throws `Temporal\Exception\Failure\CanceledFailure` when the activity has been cancelled. Let it propagate or catch it for cleanup.

## Heartbeating

### Forgetting to Heartbeat Long Activities

```php
// BAD - No heartbeat, can't detect stuck activities
#[ActivityMethod]
public function processLargeFile(string $path): void
{
    foreach ($this->readChunks($path) as $chunk) {
        $this->process($chunk);  // Takes hours, no heartbeat
    }
}

// GOOD - Regular heartbeats with progress
#[ActivityMethod]
public function processLargeFile(string $path): void
{
    foreach ($this->readChunks($path) as $i => $chunk) {
        Activity::heartbeat(['chunk' => $i]);
        $this->process($chunk);
    }
}
```

### Heartbeat Timeout Too Short

```php
// BAD - Heartbeat timeout shorter than processing time
$options = ActivityOptions::new()
    ->withStartToCloseTimeout(CarbonInterval::minutes(30))
    ->withHeartbeatTimeout(CarbonInterval::seconds(10));  // Too short!

// GOOD - Heartbeat timeout allows for processing variance
$options = ActivityOptions::new()
    ->withStartToCloseTimeout(CarbonInterval::minutes(30))
    ->withHeartbeatTimeout(CarbonInterval::minutes(2));
```

Set heartbeat timeout as high as acceptable for your use case — each heartbeat counts as an action.

## Testing

### Not Testing Failures

It is important to make sure workflows work as expected under failure paths in addition to happy paths. Please see `references/php/testing.md` for more info.

### Not Testing Replay

Replay tests help you test that you do not have hidden sources of non-determinism bugs in your workflow code, and should be considered in addition to standard testing. Please see `references/php/testing.md` for more info.

## Timers and Sleep

### Using sleep() in Workflows

```php
// BAD: sleep() is not deterministic during replay
#[WorkflowMethod]
public function run(): void
{
    sleep(60);  // Non-deterministic! Uses wall clock, not workflow timer
}

// GOOD: Use Workflow::timer() for deterministic timers
#[WorkflowMethod]
public function run(): \Generator
{
    yield Workflow::timer(60);
    // Or with CarbonInterval:
    yield Workflow::timer(CarbonInterval::seconds(60));
}
```

**Why this matters:** `sleep()` uses the system clock, which differs between original execution and replay. `Workflow::timer()` creates a durable timer in the event history, ensuring consistent behavior during replay.
