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

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "order-service"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., "order-service:v1.0.0" or "order-service:abc123").

### Configuring Workers for Versioning

> **Note:** Worker Versioning is currently in Public Preview. The legacy Worker Versioning API (before 2025) will be removed from Temporal Server in March 2026.

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

**Configuration parameters:**
- `withUseWorkerVersioning`: Enables Worker Versioning
- `withDeploymentName`: Logical name for your service (consistent across versions)
- `withBuildId`: Unique identifier for this build (git hash, semver, etc.)

### PINNED vs AUTO_UPGRADE Behaviors

**When to use PINNED:**
- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**When to use AUTO_UPGRADE:**
- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using patching APIs for version transitions

**Important:** AUTO_UPGRADE workflows still need patching to handle version transitions safely since they can move between Worker versions.

Use the Temporal CLI to set the current version:

```bash
temporal worker deployment set-current-version \
  --deployment-name order-service \
  --build-id v1.0.0
```

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "order-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., `add-fraud-check` not `patch-1`)
3. **Deploy incrementally**: patch in, deprecate (remove old branch), remove version call
4. **Use `yield` on `getVersion()`** — it is a coroutine and must be awaited
5. **Use List Filters** to verify no running Workflows before removing version support
