# PHP SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## Patching API

### The getVersion() Function

PHP uses `Workflow::getVersion()` (not `patched()`) to check whether a Workflow should run new or old code:

```php
use Temporal\Workflow;

class OrderWorkflow implements OrderWorkflowInterface
{
    public function run(array $order): \Generator
    {
        $version = yield Workflow::getVersion('add-fraud-check', Workflow::DEFAULT_VERSION, 1);

        if ($version === 1) {
            // New code path
            yield $this->activity->checkFraud($order);
        }
        // else: DEFAULT_VERSION — old code path (for replay of pre-patch executions)

        return yield $this->activity->processPayment($order);
    }
}
```

**How it works:**
- `getVersion(changeId, minSupported, maxSupported)` records a marker in the Workflow history
- For new executions: returns `maxSupported` (e.g., `1`)
- For replay of pre-patch history: returns `Workflow::DEFAULT_VERSION` (value: `-1`)
- `DEFAULT_VERSION` represents executions that predate the patch

**PHP-specific:** `getVersion()` is a coroutine — always `yield` it.

### Three-Step Patching Process

Patching is a three-step process for safely deploying changes.

**Warning:** Failing to follow this process will result in non-determinism errors for in-flight Workflows.

**Step 1: Patch in New Code**

Add the version check with both old and new code paths:

```php
public function run(array $order): \Generator
{
    $version = yield Workflow::getVersion('add-fraud-check', Workflow::DEFAULT_VERSION, 1);

    if ($version === 1) {
        // New: Run fraud check before payment
        yield $this->activity->checkFraud($order);
    }
    // DEFAULT_VERSION: skip fraud check (original behavior)

    return yield $this->activity->processPayment($order);
}
```

**Step 2: Deprecate the Patch**

Once all pre-patch Workflow Executions have completed, remove the old branch. Keep the `getVersion()` call with `minSupported = maxSupported = 1`:

```php
public function run(array $order): \Generator
{
    // minSupported = 1: will throw on replay of pre-patch history (safe — those are all done)
    yield Workflow::getVersion('add-fraud-check', 1, 1);

    // Only new code remains
    yield $this->activity->checkFraud($order);

    return yield $this->activity->processPayment($order);
}
```

**Step 3: Remove the Version Call**

After all Workflows that passed through Step 2 have completed, remove the `getVersion()` call entirely:

```php
public function run(array $order): \Generator
{
    yield $this->activity->checkFraud($order);

    return yield $this->activity->processPayment($order);
}
```

### Query Filters for Finding Workflows by Version

Use List Filters to find Workflows with specific patch versions:

```bash
# Find running Workflows with a specific patch
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "add-fraud-check"'

# Find running Workflows without any patch (pre-patch versions)
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL'
```

## Workflow Type Versioning

For incompatible changes, create a new Workflow type instead of patching:

```php
// Original interface
#[WorkflowInterface]
interface PizzaWorkflowInterface
{
    #[WorkflowMethod(name: 'PizzaWorkflow')]
    public function run(array $order): \Generator;
}

// New interface for incompatible changes
#[WorkflowInterface]
interface PizzaWorkflowV2Interface
{
    #[WorkflowMethod(name: 'PizzaWorkflowV2')]
    public function run(array $order): \Generator;
}
```

Register both with the Worker:

```php
$worker = $factory->newWorker('pizza-task-queue');
$worker->registerWorkflowTypes(PizzaWorkflow::class);
$worker->registerWorkflowTypes(PizzaWorkflowV2::class);
```

Start new executions using the new type:

```php
$workflow = $client->newWorkflowStub(
    PizzaWorkflowV2Interface::class,
    WorkflowOptions::new()->withTaskQueue('pizza-task-queue')
);
$result = $workflow->run($order);
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously. PHP uses the same concepts as other SDKs: Worker Deployment name, Build ID, PINNED vs AUTO_UPGRADE behaviors.

> **Note:** Worker Versioning is currently in Public Preview. The legacy Worker Versioning API (before 2025) will be removed from Temporal Server in March 2026.

Configure a versioned Worker in the RoadRunner worker setup:

```php
$factory = WorkerFactory::create();

$worker = $factory->newWorker(
    taskQueue: 'order-service',
    deploymentOptions: WorkerDeploymentOptions::new()
        ->withDeploymentName('order-service')
        ->withBuildId('v1.0.0')  // git commit hash or semver
        ->withUseWorkerVersioning(true)
);

$worker->registerWorkflowTypes(OrderWorkflow::class);
$worker->registerActivity(OrderActivity::class);

$factory->run();
```

Use the Temporal CLI to set the current version:

```bash
temporal worker deployment set-current-version \
  --deployment-name order-service \
  --build-id v1.0.0
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., `add-fraud-check` not `patch-1`)
3. **Deploy incrementally**: patch in, deprecate (remove old branch), remove version call
4. **Use `yield` on `getVersion()`** — it is a coroutine and must be awaited
5. **Use List Filters** to verify no running Workflows before removing version support
