# Temporal PHP SDK Reference

## Overview

The Temporal PHP SDK (`temporal/sdk`) runs Workflows and Activities inside PHP worker processes that [RoadRunner](https://roadrunner.dev) starts and supervises. RoadRunner embeds the Temporal Go SDK, polls the server, and forwards tasks to PHP. SDK 2.20+ requires PHP 8.2+ and recommends RoadRunner v3. Workflow code is a coroutine: asynchronous operations return promises, and the Workflow waits for them with `yield`. The SDK has no determinism sandbox.

## Quick Demo of Temporal

**Add Dependency on Temporal:** Install the SDK and download the RoadRunner binary:

```bash
composer require temporal/sdk
./vendor/bin/rr get-binary
```

Configure Composer PSR-4 autoloading (`"App\\": "src/"`). The SDK requires the `curl` and `json` PHP extensions. The client needs the `grpc` extension. The `protobuf` extension is optional and makes serialization faster.

**src/Activity/GreetingActivityInterface.php** - Activity interface:

```php
<?php

declare(strict_types=1);

namespace App\Activity;

use Temporal\Activity\ActivityInterface;
use Temporal\Activity\ActivityMethod;

#[ActivityInterface(prefix: 'Greeting.')]
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

final class GreetingActivity implements GreetingActivityInterface
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

use Temporal\Workflow\ReturnType;
use Temporal\Workflow\WorkflowInterface;
use Temporal\Workflow\WorkflowMethod;

#[WorkflowInterface]
interface GreetingWorkflowInterface
{
    #[WorkflowMethod(name: 'Greeting')]
    #[ReturnType('string')]
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
use Temporal\Internal\Workflow\ActivityProxy;
use Temporal\Workflow;

final class GreetingWorkflow implements GreetingWorkflowInterface
{
    private ActivityProxy|GreetingActivityInterface $activity;

    public function __construct()
    {
        $this->activity = Workflow::newActivityStub(
            GreetingActivityInterface::class,
            ActivityOptions::new()->withStartToCloseTimeout(30),
        );
    }

    public function greet(string $name): \Generator
    {
        return yield $this->activity->greet($name);
    }
}
```

**worker.php** - Worker setup (RoadRunner starts this file; it processes tasks until stopped):

```php
<?php

declare(strict_types=1);

use App\Activity\GreetingActivity;
use App\Workflow\GreetingWorkflow;
use Temporal\WorkerFactory;

require __DIR__ . '/vendor/autoload.php';

$factory = WorkerFactory::create();

$worker = $factory->newWorker('my-task-queue');
$worker->registerWorkflowTypes(GreetingWorkflow::class);
$worker->registerActivity(GreetingActivity::class);

$factory->run();
```

**.rr.yaml** - RoadRunner configuration:

```yaml
version: "3"

rpc:
  listen: tcp://127.0.0.1:6001

server:
  command: "php worker.php"

temporal:
  address: "127.0.0.1:7233"
  activities:
    num_workers: 4

logs:
  level: info
```

**Start the dev server:** Start `temporal server start-dev` in the background.

**Start the worker:** Start `./rr serve -c .rr.yaml` in the background. Do not run `php worker.php` directly: the worker needs the RoadRunner transport.

**starter.php** - Start a workflow execution:

```php
<?php

declare(strict_types=1);

use App\Workflow\GreetingWorkflowInterface;
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\WorkflowClient;
use Temporal\Client\WorkflowOptions;

require __DIR__ . '/vendor/autoload.php';

$client = WorkflowClient::create(ServiceClient::create('127.0.0.1:7233'));

$workflow = $client->newWorkflowStub(
    GreetingWorkflowInterface::class,
    WorkflowOptions::new()
        ->withWorkflowId('greeting-world')
        ->withTaskQueue('my-task-queue'),
);

$result = $workflow->greet('World');

echo "Result: {$result}" . PHP_EOL;
```

**Run the workflow:** Run `php starter.php`. Should output: `Result: Hello, World!`.

## Key Concepts

### Workflow Definition

- Put `#[WorkflowInterface]` on the interface (or directly on the class) and `#[WorkflowMethod]` on the entry method.
- A method that contains `yield` is a generator. Declare its return type as `\Generator` (or omit it). Use `#[ReturnType(...)]` to describe the serialized result.
- Use `#[SignalMethod]`, `#[QueryMethod]`, `#[UpdateMethod]` and `#[UpdateValidatorMethod]` for message handlers.
- Use `#[WorkflowInit]` on the constructor to receive the Workflow input before any handler runs. See [advanced features](advanced-features.md#workflow-init-attribute).

### Activity Definition

- Put `#[ActivityInterface]` on the interface and `#[ActivityMethod]` on each method.
- The registered Activity Type is `prefix` + method name, for example `Greeting.greet`.
- The implementation is ordinary PHP code. It can do I/O, call services, and block.

### Evolving Inputs and Results

The JSON converter creates DTOs without their constructor. Add a new field as a property with a property default (`public ?string $couponCode = null;`), not as a constructor parameter. See [data handling](data-handling.md#typed-inputs-and-results).

### Worker Setup

- `WorkerFactory::create()` connects to RoadRunner, not directly to the server. The server address is in `.rr.yaml`.
- `$factory->newWorker('task-queue', $options)` creates a logical worker for one Task Queue.
- Register Workflow classes with `registerWorkflowTypes()`.
- Register Activities with `registerActivity(Class::class)`. For constructor dependencies, give a factory: `registerActivity(MyActivity::class, fn(\ReflectionClass $class) => $container->get($class->getName()))`.
- `$factory->run()` starts processing and blocks.

### Determinism

**Workflow code must be deterministic!** The PHP SDK has no sandbox. Use `Workflow::now()`, `Workflow::timer()`, `Workflow::sideEffect()` and `Workflow::uuid()` instead of their PHP equivalents. Put all I/O in Activities. Read [Temporal determinism rules](../core/determinism.md) and [PHP determinism rules](determinism.md) to understand more.

## File Organization Best Practice

**Keep Workflow definitions in separate files from Activity definitions.** A Workflow refers to an Activity only through its interface.

```text
my_temporal_app/
├── src/
│   ├── Workflow/
│   │   ├── GreetingWorkflowInterface.php
│   │   └── GreetingWorkflow.php
│   └── Activity/
│       ├── GreetingActivityInterface.php
│       └── GreetingActivity.php
├── .rr.yaml          # RoadRunner configuration
├── worker.php        # Worker entrypoint, started by RoadRunner
└── starter.php       # Client code that starts workflows
```

## Unsupported Features

SDK 2.20 has no Standalone Activities and no Nexus Operations API. For a job queue, use the fallback in the [Temporal job queue guide](../core/job-queue.md).

## Common Pitfalls

1. **Running `php worker.php` directly** - RoadRunner must start the worker. Use `rr serve`.
2. **Forgetting `yield`** - An Activity stub call returns a promise. Without `yield`, the Workflow gets the promise, not the result.
3. **Declaring `string` or `void` on a generator method** - PHP rejects it. Use `\Generator` and `#[ReturnType]`.
4. **Non-deterministic code in workflows** - No sandbox catches `time()`, `rand()`, `sleep()` or a DB query. See [determinism](determinism.md).
5. **Registering an Activity instance** - `registerActivity()` takes a class name and an optional factory, not an object.
6. **Incorrect Activity Type names** - The type includes the interface `prefix`. Mocks and untyped stubs must use the full name.
7. **Using `echo` or `var_dump()` in a worker** - The output goes to the RoadRunner log without levels or context. A direct write to the `STDOUT` stream corrupts the RoadRunner protocol. Use `Workflow::getLogger()` or a PSR-3 logger that writes to STDERR.
8. **Typing a stub property with the interface only** - `Workflow::newActivityStub()` returns an `ActivityProxy`. Declare the property as `ActivityProxy|MyActivityInterface`, or a `TypeError` blocks the Workflow.
9. **Shared state in a worker process** - A worker process runs many Activity tasks. Static variables and shared container services keep their values between tasks. Do not keep request or tenant state there.

## Writing Tests

See [PHP testing guide](testing.md) for info on writing tests.

## Additional Resources

### Reference Files

- **[PHP workflow patterns](patterns.md)** - Signals, queries, updates, child workflows, saga, batches
- **[PHP determinism rules](determinism.md)** - Forbidden operations and safe alternatives
- **[PHP determinism protection](determinism-protection.md)** - Runtime guards, panic policy, replay checks
- **[PHP gotchas](gotchas.md)** - PHP-specific mistakes, with examples
- **[PHP error handling](error-handling.md)** - ApplicationFailure, retry policies, timeouts
- **[PHP data handling](data-handling.md)** - Data converters, serialization context, encryption, payload limits
- **[PHP observability](observability.md)** - Logging, metrics, tracing, Search Attributes
- **[PHP testing guide](testing.md)** - Test framework, mocks, time skipping, replay
- **[PHP versioning](versioning.md)** - `getVersion()`, Workflow Type versioning, Worker Versioning
- **[PHP advanced features](advanced-features.md)** - Schedules, async completion, worker tuning, Cloud Operations API
- **[PHP priority and fairness](priority-fairness.md)** - Task Queue Priority and Fairness

### PHP Integrations

For PHP-specific third-party integrations (Laravel, etc.), see [integrations catalog](../integrations.md) and filter for PHP. Reference files live under `references/php/integrations/`.
