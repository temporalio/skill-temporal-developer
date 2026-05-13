# Python SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## Patching API

### The patched() Function

The `patched()` function checks whether a Workflow should run new or old code:

```python
from temporalio import workflow

@workflow.defn
class ShippingWorkflow:
    @workflow.run
    async def run(self) -> None:
        if workflow.patched("send-email-instead-of-fax"):
            # New code path
            await workflow.execute_activity(
                send_email,
                start_to_close_timeout=timedelta(minutes=5),
            )
        else:
            # Old code path (for replay of existing workflows)
            await workflow.execute_activity(
                send_fax,
                start_to_close_timeout=timedelta(minutes=5),
            )
```

**How it works:**

- For new executions: `patched()` returns `True` and records a marker in the Workflow history
- For replay with the marker: `patched()` returns `True` (history includes this patch)
- For replay without the marker: `patched()` returns `False` (history predates this patch)

**Python-specific behavior:** The `patched()` return value is memoized on first call. This means you cannot reliably use `patched()` in loops—it will return the same value every iteration. Workaround: append a sequence number to the patch ID for each iteration (e.g., `f"my-change-{i}"`).

### Three-Step Patching Process

Patching is a three-step process for safely deploying changes.

**Warning:** Failing to follow this process correctly will result in non-determinism errors for in-flight workflows.

**Step 1: Patch in New Code**

Add the patch with both old and new code paths:

```python
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        if workflow.patched("add-fraud-check"):
            # New: Run fraud check before payment
            await workflow.execute_activity(
                check_fraud,
                order,
                start_to_close_timeout=timedelta(minutes=2),
            )

        # Original payment logic runs for both paths
        return await workflow.execute_activity(
            process_payment,
            order,
            start_to_close_timeout=timedelta(minutes=5),
        )
```

**Step 2: Deprecate the Patch**

Once all pre-patch Workflow Executions have completed, remove the old code and use `deprecate_patch()`:

```python
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        workflow.deprecate_patch("add-fraud-check")

        # Only new code remains
        await workflow.execute_activity(
            check_fraud,
            order,
            start_to_close_timeout=timedelta(minutes=2),
        )

        return await workflow.execute_activity(
            process_payment,
            order,
            start_to_close_timeout=timedelta(minutes=5),
        )
```

**Step 3: Remove the Patch**

After all workflows with the deprecated patch marker have completed, remove the `deprecate_patch()` call entirely:

```python
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        await workflow.execute_activity(
            check_fraud,
            order,
            start_to_close_timeout=timedelta(minutes=2),
        )

        return await workflow.execute_activity(
            process_payment,
            order,
            start_to_close_timeout=timedelta(minutes=5),
        )
```

### Query Filters for Finding Workflows by Version

Use List Filters to find workflows with specific patch versions:

```bash
# Find running workflows with a specific patch
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "add-fraud-check"'

# Find running workflows without any patch (pre-patch versions)
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL'
```

## Workflow Type Versioning

For incompatible changes, create a new Workflow Type instead of using patches:

```python
@workflow.defn(name="PizzaWorkflow")
class PizzaWorkflow:
    @workflow.run
    async def run(self, order: PizzaOrder) -> str:
        # Original implementation
        return await self._process_order_v1(order)

@workflow.defn(name="PizzaWorkflowV2")
class PizzaWorkflowV2:
    @workflow.run
    async def run(self, order: PizzaOrder) -> str:
        # New implementation with incompatible changes
        return await self._process_order_v2(order)
```

Register both with the Worker:

```python
worker = Worker(
    client,
    task_queue="pizza-task-queue",
    workflows=[PizzaWorkflow, PizzaWorkflowV2],
    activities=[make_pizza, deliver_pizza],
)
```

Update client code to start new workflows with the new type:

```python
# Old workflows continue on PizzaWorkflow
# New workflows use PizzaWorkflowV2
handle = await client.start_workflow(
    PizzaWorkflowV2.run,
    order,
    id=f"pizza-{order.id}",
    task_queue="pizza-task-queue",
)
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "loan-processor"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., "loan-processor:v1.0" or "loan-processor:abc123").

### Configuring Workers for Versioning

```python
from temporalio.worker import Worker
from temporalio.worker.deployment_config import (
    WorkerDeploymentConfig,
    WorkerDeploymentVersion,
)

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    deployment_config=WorkerDeploymentConfig(
        version=WorkerDeploymentVersion(
            deployment_name="my-service",
            build_id="v1.0.0",  # or git commit hash
        ),
        use_worker_versioning=True,
    ),
)
```

**Configuration parameters:**

- `use_worker_versioning`: Enables Worker Versioning
- `version`: Identifies the Worker Deployment Version (deployment name + build ID)
- Build ID: Typically a git commit hash, version number, or timestamp

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED Behavior**

Workflows stay locked to their original Worker version:

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior

@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class StableWorkflow:
    @workflow.run
    async def run(self) -> str:
        return await workflow.execute_activity(
            process_order,
            start_to_close_timeout=timedelta(minutes=5),
        )
```

**When to use PINNED:**

- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions:

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior

@workflow.defn(versioning_behavior=VersioningBehavior.AUTO_UPGRADE)
class UpgradableWorkflow:
    @workflow.run
    async def run(self) -> str:
        return await workflow.execute_activity(
            process_order,
            start_to_close_timeout=timedelta(minutes=5),
        )
```

**When to use AUTO_UPGRADE:**

- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using patching APIs for version transitions

**Important:** AUTO_UPGRADE workflows still need patching to handle version transitions safely since they can move between Worker versions.

### Worker Configuration with Default Behavior

```python
worker = Worker(
    client,
    task_queue="orders-task-queue",
    workflows=[OrderWorkflow],
    activities=[process_order],
    deployment_config=WorkerDeploymentConfig(
        version=WorkerDeploymentVersion(
            deployment_name="order-service",
            build_id=os.environ["BUILD_ID"],
        ),
        use_worker_versioning=True,
        default_versioning_behavior=VersioningBehavior.PINNED,
    ),
)
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

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive patch IDs** that explain the change (e.g., "add-fraud-check" not "patch-1")
3. **Deploy patches incrementally**: patch, deprecate, remove
4. **Use PINNED for short workflows** to simplify version management
5. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
6. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
7. **Avoid rolling deployments** for high-availability services with long-running workflows

## Upgrade on Continue-as-New (Python)

Long-running PINNED Workflows that already use [Continue-as-New](/workflow-execution/continue-as-new) can opt in to upgrade to a newer Worker Deployment Version at the Continue-as-New boundary, without using the patching APIs.

This feature is in **Public Preview** as an experimental SDK-level option.  The canonical, language-neutral description lives in `documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx` under `## Upgrading on Continue-as-New`.

### When to use it

The decision table recommends `PINNED` + upgrade-on-CaN for **long (weeks-to-years) Workflows that use Continue-as-New**.  Common shapes: **Customer entity** Workflows (months-years) and **AI agent / Chatbot** Workflows with long sleeps.

Do not enable this for Workflows that don't already perform Continue-as-New — the upgrade only happens at a CaN boundary triggered by the workflow itself.

### How it works

By default, a PINNED Workflow stays on its original Worker Deployment Version across Continue-as-New.  With the upgrade option enabled:

1. Each Workflow run remains pinned to its version (no patching needed within a single run).
2. The Temporal Server tells the Workflow when a new [Target Version](/worker-versioning#versioning-definitions) becomes available.
3. When the Workflow performs Continue-as-New with the upgrade option, the **new run** starts on the Target Version.

The opt-in is **per Continue-as-New call**, not a Worker-level toggle — there is no Worker setting that flips this on globally.

### Detecting that a new Target Version is available

When a new Worker Deployment Version becomes Current or Ramping, an active Workflow can detect this through a conceptual flag the canonical docs name `target_worker_deployment_version_changed`.

The flag is **refreshed after each Workflow Task completes** — it is not a sticky boolean and is not pushed in real time into the middle of a long sleep. If your Workflow spends most of its time idle, you need to give it an opportunity to take a Workflow Task (for example, after a timer fires, before accepting an Update, or before starting an Activity or Child Workflow) so the refreshed flag value can be observed.

When the flag is true, the Workflow can perform Continue-as-New with the upgrade option set so the next run starts on the Target Version.

### A note on the SDK identifiers

The canonical docs only show a **Go** worked example for this feature — there is no Python code sample in the docs for Continue-as-New with the upgrade option, and the docs do not name the Python equivalents of `GetTargetWorkerDeploymentVersionChanged`, `NewContinueAsNewErrorWithOptions`, `ContinueAsNewErrorOptions`, `InitialVersioningBehavior`, or `ContinueAsNewVersioningBehaviorAutoUpgrade`.

For the exact Python identifiers, consult the Python SDK release notes for the version that introduced upgrade-on-Continue-as-New support, or read the typed bindings in your installed `temporalio` package. The canonical worked example, in Go, is reproduced in `references/go/versioning.md` and shows the shape (poll the flag periodically; on true, raise a Continue-as-New error carrying an "initial versioning behavior = auto-upgrade" option so the next run lands on the Target Version).

### Limitations

- **Lazy moving only.** Sleeping Workflows are not proactively notified that the Target Version changed. If you have idle Workflows that you want to wake up so they can check the flag, send them a Signal to force a Workflow Task.
- **Input compatibility.** When continuing as new across versions, the input produced by the previous version's Workflow definition must be compatible with the new version's Workflow definition. If it is not, the new run may fail on its first Workflow Task.
- **Public Preview / experimental.** Expect the SDK surface to evolve; do not treat the API as generally available.

### See also

Conceptual treatment in `references/core/versioning.md` §Upgrade on Continue-as-New. Canonical worked example (Go) in `references/go/versioning.md`.
