# Temporal PHP SDK Reference

## Overview

The Temporal PHP SDK (`temporal/sdk`) uses RoadRunner as the application server to run workflows and activities. PHP 8.1+ required. Workflows and activities are defined as classes using PHP attributes (`#[WorkflowInterface]`, `#[ActivityInterface]`, etc.). Async operations use generators with `yield` instead of `await`. There is no sandbox — the SDK relies on runtime determinism checks to detect non-deterministic code.

## Quick Demo of Temporal

**Add Dependency on Temporal:** Install the SDK via Composer:

```bash
composer require temporal/sdk
```

**src/Activity/GreetingActivityInterface.php** - Activity interface:
```php
<?php

declare(strict_types=1);

namespace App\Activity;

use Temporal\Activity\ActivityInterface;
use Temporal\Activity\ActivityMethod;

#[ActivityInterface]
interface GreetingActivityInterface
{
    #[ActivityMethod]
    public function greet(string $name): string;
}
```

**src/Activity/GreetingActivity.php** - Activity implementation:
```php
<?php

declare(strict_types=1);

namespace App\Activity;

class GreetingActivity implements GreetingActivityInterface
{
    public function greet(string $name): string
    {
        return "Hello, {$name}!";
    }
}
```

**src/Workflow/GreetingWorkflowInterface.php** - Workflow interface:
```php
<?php

declare(strict_types=1);

namespace App\Workflow;

use Temporal\Workflow\WorkflowInterface;
use Temporal\Workflow\WorkflowMethod;

#[WorkflowInterface]
interface GreetingWorkflowInterface
{
    #[WorkflowMethod]
    public function greet(string $name): \Generator;
}
```

**src/Workflow/GreetingWorkflow.php** - Workflow implementation:
```php
<?php

declare(strict_types=1);

namespace App\Workflow;

use App\Activity\GreetingActivityInterface;
use Temporal\Activity\ActivityOptions;
use Temporal\Workflow;

class GreetingWorkflow implements GreetingWorkflowInterface
{
    private GreetingActivityInterface $activity;

    public function __construct()
    {
        $this->activity = Workflow::newActivityStub(
            GreetingActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout(30)
        );
    }

    public function greet(string $name): \Generator
    {
        return yield $this->activity->greet($name);
    }
}
```

**worker.php** - Worker setup (runs via RoadRunner, processes tasks indefinitely):
```php
<?php

declare(strict_types=1);

use App\Activity\GreetingActivity;
use App\Workflow\GreetingWorkflow;
use Temporal\WorkerFactory;

require __DIR__ . '/vendor/autoload.php';

// Create the worker factory (connects via RoadRunner)
$factory = WorkerFactory::create();

// Create a worker bound to a task queue
$worker = $factory->newWorker('my-task-queue');

// Register workflow and activity implementations
$worker->registerWorkflowTypes(GreetingWorkflow::class);
$worker->registerActivity(GreetingActivity::class);

// Start processing tasks (blocks until stopped)
$factory->run();
```

**Start the dev server:** Start `temporal server start-dev` in the background.

**Start the worker:** Start `php worker.php` in the background (RoadRunner must be available; alternatively use `./rr serve` with an `.rr.yaml` config).

**starter.php** - Start a workflow execution:
```php
<?php

declare(strict_types=1);

use App\Workflow\GreetingWorkflowInterface;
use Temporal\Client\WorkflowClient;
use Temporal\Client\WorkflowOptions;
use Temporal\Client\GRPC\ServiceClient;

require __DIR__ . '/vendor/autoload.php';

$client = WorkflowClient::create(ServiceClient::create('localhost:7233'));

$workflow = $client->newWorkflowStub(
    GreetingWorkflowInterface::class,
    WorkflowOptions::new()->withTaskQueue('my-task-queue')
);

$result = $workflow->greet('World');

echo "Result: {$result}" . PHP_EOL;
```

**Run the workflow:** Run `php starter.php`. Should output: `Result: Hello, World!`.


## Key Concepts

### Workflow Definition
- Use `#[WorkflowInterface]` attribute on the interface
- Use `#[WorkflowMethod]` on the entry point method
- Workflow method must return `\Generator` (use `yield` for async calls)
- Use `#[SignalMethod]`, `#[QueryMethod]`, `#[UpdateMethod]` attributes for handlers
- Implementation class does not need any attributes — attributes go on the interface

### Activity Definition
- Use `#[ActivityInterface]` attribute on the interface
- Use `#[ActivityMethod]` on each activity method
- Implementation class contains the actual logic — no Temporal attributes needed
- Activities can perform I/O, call external services, use `sleep()`, etc.

### Worker Setup
- Create `WorkerFactory::create()` — connects through RoadRunner
- Call `$factory->newWorker('task-queue')` to bind to a task queue
- Register workflow types: `$worker->registerWorkflowTypes(MyWorkflow::class)`
- Register activities: `$worker->registerActivity(MyActivity::class)` (or pass an instance)
- Call `$factory->run()` to start processing (blocks)

### Determinism

**Workflow code must be deterministic!** The PHP SDK has no sandbox. All non-deterministic operations must use Temporal-provided APIs or be delegated to activities. Read `references/core/determinism.md` and `references/php/determinism.md` for details.

## File Organization Best Practice

**Keep Workflow definitions in separate files from Activity definitions.** Use interfaces to decouple workflows from activity implementations.

```
my_temporal_app/
├── src/
│   ├── Workflow/
│   │   ├── GreetingWorkflowInterface.php   # Workflow interface only
│   │   └── GreetingWorkflow.php            # Workflow implementation
│   └── Activity/
│       ├── GreetingActivityInterface.php   # Activity interface only
│       └── GreetingActivity.php            # Activity implementation
├── worker.php                              # Worker setup, registers both
└── starter.php                             # Client code to start workflows
```

Workflows reference activities only through their interfaces. This keeps the workflow file free of activity implementation details and avoids unnecessary coupling.

## Determinism Rules

PHP has **no sandbox**. Non-deterministic code in a workflow will cause history replay failures. Do not use:

| Forbidden | Use Instead |
|-----------|-------------|
| `sleep($seconds)` | `yield Workflow::timer($seconds)` |
| `time()` / `microtime()` / `new \DateTime()` | `Workflow::now()` (returns `\DateTimeImmutable`) |
| `rand()` / `mt_rand()` / `random_int()` | `yield Workflow::sideEffect(fn() => rand())` |
| Direct I/O (`file_get_contents`, `curl_exec`, DB queries) | Execute an activity |
| Blocking SPL functions that depend on external state | Execute an activity |
| `getenv()` / `$_ENV` reads (non-constant) | Pass via workflow input or use `sideEffect` |

Always `yield` promises returned by activity stubs and `Workflow::*` async methods. Forgetting `yield` means the workflow continues without waiting for the result.

## Common Pitfalls

1. **Non-deterministic code in workflows** — Use activities for all I/O, randomness, and time-dependent logic
2. **Forgetting `yield` on promises** — `$this->activity->greet($name)` returns a promise; without `yield` the workflow gets the promise object, not the result
3. **Blocking operations in workflow code** — Never call `sleep()`, make HTTP requests, or query a database directly inside a workflow method
4. **Not heartbeating long-running activities** — Long activities must call `Activity::heartbeat()` periodically or Temporal will time them out
5. **Using `echo` or `print()` in workflows** — Use `Workflow::getLogger()->info(...)` instead for replay-safe logging
6. **Mixing workflow and activity classes in the same file** — Keep them separate for clarity and maintainability
7. **Registering the wrong class** — Register the implementation class (e.g., `GreetingWorkflow::class`), not the interface
8. **Missing `declare(strict_types=1)`** — Omitting strict types can cause subtle type coercion bugs in workflow data

## Writing Tests

See `references/php/testing.md` for info on writing tests.

## Additional Resources

### Reference Files
- **`references/php/patterns.md`** - Signals, queries, child workflows, saga pattern, etc.
- **`references/php/determinism.md`** - Forbidden operations, safe alternatives, runtime checks
- **`references/php/error-handling.md`** - ApplicationFailure, retry policies, non-retryable errors, idempotency
- **`references/php/observability.md`** - Logging, metrics, tracing, Search Attributes
- **`references/php/testing.md`** - Testing workflows and activities with the PHP SDK
- **`references/php/versioning.md`** - Patching API, workflow type versioning
- **`references/core/determinism.md`** - Core determinism concepts shared across all SDKs
