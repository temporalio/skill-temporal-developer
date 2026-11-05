# PHP SDK Versioning

For conceptual overview, see [Temporal versioning guide](../core/versioning.md).

## Patching API

### The getVersion() Method

PHP uses `Workflow::getVersion()`, like the Go SDK. There is no `patched()` method. `getVersion()` returns a promise:

```php
$version = yield Workflow::getVersion('change-id', Workflow::DEFAULT_VERSION, 1);

if ($version === Workflow::DEFAULT_VERSION) {
    // Old code path (for replay of existing workflows)
    yield $this->activities->prePatchActivity();
} else {
    // New code path
    yield $this->activities->postPatchActivity();
}
```

**How it works:**

- For new executions: `getVersion()` returns `maxSupported` and records a marker in the Workflow history
- For replay with the marker: `getVersion()` returns the version recorded in the marker
- For replay without the marker: `getVersion()` returns `Workflow::DEFAULT_VERSION` (`-1`)
- A recorded version outside `[minSupported, maxSupported]` fails the Workflow Task

### Three-Step Patching Process

**Warning:** Failing to follow this process correctly will result in non-determinism errors for in-flight workflows.

**Step 1: Patch in New Code**

Add the version check with both old and new code paths:

```php
#[WorkflowMethod(name: 'Order')]
public function run(Order $order): \Generator
{
    $version = yield Workflow::getVersion('add-fraud-check', Workflow::DEFAULT_VERSION, 1);

    if ($version === 1) {
        // New: Run fraud check before payment
        yield $this->activities->checkFraud($order);
    }

    // Original payment logic runs for both paths
    return yield $this->activities->processPayment($order);
}
```

**Step 2: Deprecate the Old Path**

Once all pre-patch Workflow Executions have completed, remove the old code. Keep the `getVersion()` call and raise `minSupported`, so that a pre-patch history fails clearly instead of running incorrect code:

```php
#[WorkflowMethod(name: 'Order')]
public function run(Order $order): \Generator
{
    yield Workflow::getVersion('add-fraud-check', 1, 1);

    yield $this->activities->checkFraud($order);

    return yield $this->activities->processPayment($order);
}
```

**Step 3: Remove the Version Check**

After all workflows with the `add-fraud-check` marker have completed, remove the `getVersion()` call:

```php
#[WorkflowMethod(name: 'Order')]
public function run(Order $order): \Generator
{
    yield $this->activities->checkFraud($order);

    return yield $this->activities->processPayment($order);
}
```

### Adding More Versions

To change the same code again, raise `maxSupported` and keep the existing branches:

```php
$version = yield Workflow::getVersion('notification-channel', Workflow::DEFAULT_VERSION, 2);

match ($version) {
    Workflow::DEFAULT_VERSION => null,
    1 => yield $this->activities->sendSms($orderId),
    2 => yield $this->activities->sendPush($orderId),
};
```

### Query Filters for Finding Workflows by Version

`getVersion()` adds `<changeId>-<version>` to the `TemporalChangeVersion` Search Attribute:

```bash
# Find running workflows with a specific version
temporal workflow list --query \
  'WorkflowType = "Order" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "add-fraud-check-1"'

# Find running workflows without any version marker (pre-patch versions)
temporal workflow list --query \
  'WorkflowType = "Order" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL'
```

## Workflow Type Versioning

For incompatible changes, create a new Workflow Type with a new name:

```php
#[WorkflowInterface]
interface OrderWorkflowInterface
{
    #[WorkflowMethod(name: 'Order')]
    public function run(Order $order): \Generator;
}

#[WorkflowInterface]
interface OrderWorkflowV2Interface
{
    #[WorkflowMethod(name: 'OrderV2')]
    public function run(Order $order): \Generator;
}
```

Register both with the Worker:

```php
$worker->registerWorkflowTypes(OrderWorkflow::class, OrderWorkflowV2::class);
```

Update client code to start new workflows with the new type:

```php
// Old workflows continue on Order
// New workflows use OrderV2
$workflow = $client->newWorkflowStub(
    OrderWorkflowV2Interface::class,
    WorkflowOptions::new()->withTaskQueue('orders'),
);
$client->start($workflow, $order);
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "Order" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "order-processor"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., deployment "order-processor" with Build ID "v1.0" or "abc123").

### Configuring Workers for Versioning

Deployment options are part of `WorkerOptions`. The deployment name must not contain a `.`:

```php
use Temporal\Common\Versioning\WorkerDeploymentVersion;
use Temporal\Worker\WorkerDeploymentOptions;
use Temporal\Worker\WorkerOptions;

$worker = $factory->newWorker(
    'my-task-queue',
    WorkerOptions::new()->withDeploymentOptions(
        WorkerDeploymentOptions::new()
            ->withUseVersioning(true)
            ->withVersion(WorkerDeploymentVersion::new('my-service', 'v1.0.0')),
    ),
);
```

With `withUseVersioning(true)`, every registered Workflow needs a versioning behavior: either `#[WorkflowVersioningBehavior]` on its method, or `withDefaultVersioningBehavior()` on the worker. Otherwise the worker does not start.

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED Behavior**

Workflows stay locked to their original Worker version. Set it on the Workflow method:

```php
use Temporal\Common\Versioning\VersioningBehavior;
use Temporal\Workflow\WorkflowVersioningBehavior;

#[WorkflowInterface]
interface StableWorkflowInterface
{
    #[WorkflowMethod]
    #[WorkflowVersioningBehavior(VersioningBehavior::Pinned)]
    public function run(): \Generator;
}
```

**When to use PINNED:**

- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions:

```php
#[WorkflowMethod]
#[WorkflowVersioningBehavior(VersioningBehavior::AutoUpgrade)]
public function run(): \Generator;
```

**When to use AUTO_UPGRADE:**

- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using `getVersion()` for version transitions

**Important:** AUTO_UPGRADE workflows still need `getVersion()` to handle version transitions safely since they can move between Worker versions.

### Worker Configuration with Default Behavior

```php
$worker = $factory->newWorker(
    'orders',
    WorkerOptions::new()->withDeploymentOptions(
        WorkerDeploymentOptions::new()
            ->withUseVersioning(true)
            ->withVersion(WorkerDeploymentVersion::new(
                'order-service',
                getenv('BUILD_ID') ?: throw new \RuntimeException('BUILD_ID is not set'),
            ))
            ->withDefaultVersioningBehavior(VersioningBehavior::Pinned),
    ),
);
```

### Deployment Strategies

**Blue-Green Deployments**

Maintain two environments and switch traffic between them:

1. Deploy new code to idle environment
2. Run tests and validation
3. Switch traffic to new environment
4. Keep old environment for instant rollback

**Rainbow Deployments**

Multiple versions run simultaneously:

- New workflows use latest version
- Existing workflows complete on their original version
- Add new versions alongside existing ones
- Gradually sunset old versions as workflows complete

This works well with Kubernetes where you manage multiple ReplicaSets running different Worker versions.

A new version receives new Workflows only after you set it as current. Run `temporal worker deployment set-current-version` with the deployment name and Build ID.

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Upgrading on Continue-as-New

The PHP SDK 2.20 has no option to upgrade a Workflow to a new deployment version on Continue-As-New: `ContinueAsNewOptions` has no versioning setting.

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., "add-fraud-check" not "patch-1")
3. **Deploy versions incrementally**: add `getVersion()`, raise `minSupported`, remove
4. **Use PINNED for short workflows** to simplify version management
5. **Use AUTO_UPGRADE with `getVersion()`** for long-running workflows that need updates
6. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
