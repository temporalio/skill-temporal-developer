# Temporal PHP SDK Reference

## Overview

The Temporal PHP SDK (`temporal/sdk`) uses RoadRunner to run workflows and activities. The SDK requires PHP 8.1+; framework integrations can require newer PHP. Async operations use generators and `yield`. There is no determinism sandbox: replay checks do not prevent arbitrary PHP I/O.

Before adapting examples, inspect `composer.lock`, the RoadRunner binary/configuration, PHP extensions, and the Temporal Server version. The reviewed course locks SDK 2.16.0; the SDK reference was also checked at tag `v2.18`. These are source snapshots, not an instruction to upgrade. See [sources and course lessons](sources.md) for commits, coverage, and limitations.

Read only the relevant detail: [worker lifecycle and scaling](workers.md), [bounded batches and message handling](patterns.md), [Laravel](integrations/laravel-temporal.md), [support factories and typing](integrations/support.md), or [testing and replay](testing.md).

## Quick Demo of Temporal

**Add Dependency on Temporal:** Install the SDK via Composer:

```bash
composer require temporal/sdk
```

Configure Composer PSR-4 autoloading (`"App\\": "src/"`) and run `composer dump-autoload`. For the native gRPC client shown below, install/enable `ext-grpc`; `ext-protobuf` is an optional performance improvement. Install a RoadRunner binary compatible with the locked SDK, for example through `./vendor/bin/rr get-binary`.

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

**.rr.yaml** — RoadRunner launches `worker.php` and supplies its transport:

```yaml
version: "3"
rpc:
  listen: tcp://127.0.0.1:6001
server:
  command: "php worker.php"
  relay: pipes
temporal:
  address: "127.0.0.1:7233"
  activities:
    num_workers: 2
logs:
  level: info
```

**Start the worker:** Run `./rr serve -c .rr.yaml`. Running `php worker.php` directly does not provide the RoadRunner worker transport. Keep server, worker, and starter addresses/namespace/task queue consistent.

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
- Methods containing `yield` must have a compatible return declaration such as `\Generator`, or omit it; they cannot declare `string`/`void`. A synchronous workflow can return a value directly. Use `#[ReturnType(...)]` for the serialized result of a generator workflow.
- Use `#[SignalMethod]`, `#[QueryMethod]`, `#[UpdateMethod]` attributes for handlers
- Put attributes on the interface when using a separate contract. Directly attributed concrete classes are also supported; do not invent an interface-only requirement.

### Activity Definition
- Use `#[ActivityInterface]` attribute on the interface
- Use `#[ActivityMethod]` on each activity method
- Implementation class contains the actual logic — no Temporal attributes needed
- Activities can perform I/O, call external services, use `sleep()`, etc.

### Worker Setup
- Create `WorkerFactory::create()` — connects through RoadRunner
- Call `$factory->newWorker('task-queue')` to bind to a task queue
- Register workflow types: `$worker->registerWorkflowTypes(MyWorkflow::class)`
- Register activities by class name. For constructor dependencies: `$worker->registerActivity(MyActivity::class, fn(\ReflectionClass $type) => $container->get($type->getName()))`. `registerActivity()` does not accept an instance; the older `registerActivityImplementations($instance)` API is deprecated. Keep instances stateless between invocations.
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
| `getenv()` / `$_ENV` reads for decisions | Pass configuration via workflow input; fetch changing configuration through an Activity |

Await async results with `yield`, or collect promises and yield their join for concurrency. `Workflow::uuid()`, `sideEffect()`, `getVersion()` and `continueAsNew()` return promises; `now()`, `allHandlersFinished()` and Search Attribute upserts are synchronous. Do not mechanically yield every facade method.

## Common Pitfalls

1. **Non-deterministic code in workflows** — Use activities for all I/O, randomness, and time-dependent logic
2. **Forgetting `yield` on promises** — `$this->activity->greet($name)` returns a promise; without `yield` the workflow gets the promise object, not the result
3. **Blocking operations in workflow code** — Never call `sleep()`, make HTTP requests, or query a database directly inside a workflow method
4. **Incorrect heartbeat assumptions** — Heartbeat timeout applies when configured. Heartbeat long work for failure detection, cancellation and checkpoints; it does not extend Start-To-Close or guarantee exactly-once processing.
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
- **[workers.md](workers.md)** - RoadRunner pools, memory, state isolation and scaling
- **[integrations/laravel-temporal.md](integrations/laravel-temporal.md)** - Laravel discovery, builders, data conversion and test helpers
- **[integrations/support.md](integrations/support.md)** - Optional factories, attributes and VirtualPromise
- **[sources.md](sources.md)** - Source snapshots, course lesson map and corrections to teaching examples
- **`references/core/determinism.md`** - Core determinism concepts shared across all SDKs
