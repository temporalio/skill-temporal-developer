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

## Upgrading on Continue-as-New

Long-running Workflows that use [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) can upgrade to newer Worker Deployment Versions at Continue-as-New boundaries without requiring patching.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532 -->
The feature is currently in Public Preview as an experimental SDK-level option, so the API surface may evolve before GA.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541 -->
It is intended for Workflows that stay `PINNED` for the duration of each run but want each new run, started via Continue-as-New, to land on the latest Target Worker Deployment Version.

### When to use it

This pattern is ideal for:
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:535 -->

- **Entity Workflows** that run for months or years.
- **Batch processing** Workflows that checkpoint with Continue-as-New.
- **AI agent Workflows** with long sleeps waiting for user input.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:537-539 -->

### Choosing between upgrade-on-CaN and Auto-Upgrade

The Decision Guide in the worker-versioning docs separates long-running Workflows by whether they use Continue-as-New. A **long** Workflow that uses Continue-as-New should pick `PINNED` together with upgrade-on-Continue-as-New, and never needs patching. A **long** Workflow that does not use Continue-as-New should pick `AUTO_UPGRADE` and accept that patching is required to safely cross version boundaries within a single run. Upgrade-on-Continue-as-New is therefore *not* a drop-in substitute for `AUTO_UPGRADE`; it is the recommended pairing specifically for the Pinned + CaN shape.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:261-266 -->

### How it works (mechanics)

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the upgrade option enabled:
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 -->

1. Each Workflow run remains pinned to its version, so no patching is needed *within* a single run.
   <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:552 -->
2. The Temporal Server tells the Workflow when a new Target Version becomes available.
   <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553 -->
3. When the Workflow then performs Continue-as-New with the upgrade option, the new run starts on the Target Version.
   <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 -->

### Detection is lazy

A Workflow only learns that the Target Version has changed when it executes a Workflow Task — sleeping or idle Workflows will not be proactively notified. If you have idle Workflows that you want to wake up so they can check for a Target-Version change, send them a Signal to trigger a Workflow Task.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

### Input compatibility caveat

When continuing as new across versions, ensure that the input produced by the previous version's Workflow definition is compatible with the new version's Workflow definition. If the input shape is incompatible, the new run may fail on its first Workflow Task.
<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

### Continue-as-New inheritance reminder

Continue-as-New version inheritance follows the same rules whether or not the upgrade option is used. When the original run is Pinned, the Pinned version is inherited across the Continue-as-New chain, unless the new run's Task Queue is in a different Worker Deployment — in which case no inheritance occurs and the new run starts on the Current Version of its Task Queue. Auto-Upgrade Workflows never inherit a version on Continue-as-New, and Cron Jobs never inherit versioning behavior or version at all.
<!-- docs/encyclopedia/workers/worker-versioning.mdx:128-152 -->

### Python API status

As of 2026-05, the documentation clone consulted for this reference documents the worked code example for upgrade-on-Continue-as-New **only in Go**. The Python SDK's specific symbol names for this feature — the per-call option that selects the upgrade behavior on `workflow.continue_as_new(...)`, and the Workflow-info accessor that signals a Target Version change — are not transcribed here because they are not present in these docs.

For a runnable code example demonstrating the Target-Version-Changed check and the Continue-as-New call with the upgrade option, see the Go reference at `references/go/versioning.md` ("Upgrading on Continue-as-New" section). The canonical product documentation lives at `docs/production-deployment/worker-deployments/worker-versioning.mdx` under the `#upgrade-on-continue-as-new` anchor.

When wiring this up in Python, keep using the documented baseline call shape `workflow.continue_as_new(...)` and the documented signal `workflow.info().is_continue_as_new_suggested()` to decide *when* to continue as new; consult the Python SDK source or release notes for the exact option name that selects the upgrade-on-CaN behavior.

<!-- VERIFY: Python SDK token names for upgrade-on-CaN — docs only document Go as of 2026-05; consult Python SDK source or release notes -->
