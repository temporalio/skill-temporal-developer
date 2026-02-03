# Python SDK Versioning

## Overview

Workflow versioning allows you to safely deploy changes to Workflow code without causing non-deterministic errors in running Workflow Executions. The Python SDK provides multiple approaches: the Patching API for code-level version management, Workflow Type versioning for incompatible changes, and Worker Versioning for deployment-level control.

## Why Versioning is Needed

When Workers restart after a deployment, they resume open Workflow Executions through History Replay. If the updated Workflow Definition produces a different sequence of Commands than the original code, it causes a non-deterministic error. Versioning ensures backward compatibility by preserving the original execution path for existing workflows while allowing new workflows to use updated code.

## Workflow Versioning with Patching API

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
                schedule_to_close_timeout=timedelta(minutes=5),
            )
        else:
            # Old code path (for replay of existing workflows)
            await workflow.execute_activity(
                send_fax,
                schedule_to_close_timeout=timedelta(minutes=5),
            )
```

**How it works:**
- For new executions: `patched()` returns `True` and records a marker in the Workflow history
- For replay with the marker: `patched()` returns `True` (history includes this patch)
- For replay without the marker: `patched()` returns `False` (history predates this patch)

### Three-Step Patching Process

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
                schedule_to_close_timeout=timedelta(minutes=2),
            )

        # Original payment logic runs for both paths
        return await workflow.execute_activity(
            process_payment,
            order,
            schedule_to_close_timeout=timedelta(minutes=5),
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
            schedule_to_close_timeout=timedelta(minutes=2),
        )

        return await workflow.execute_activity(
            process_payment,
            order,
            schedule_to_close_timeout=timedelta(minutes=5),
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
            schedule_to_close_timeout=timedelta(minutes=2),
        )

        return await workflow.execute_activity(
            process_payment,
            order,
            schedule_to_close_timeout=timedelta(minutes=5),
        )
```

### Branching with Multiple Patches

A Workflow can have multiple patches, each representing a modification deployed at a specific time:

```python
@workflow.defn
class NotificationWorkflow:
    @workflow.run
    async def run(self) -> None:
        if workflow.patched("use-sms"):
            # Latest: SMS notifications
            await workflow.execute_activity(
                send_sms,
                schedule_to_close_timeout=timedelta(minutes=5),
            )
        elif workflow.patched("use-email"):
            # Intermediate: Email notifications
            await workflow.execute_activity(
                send_email,
                schedule_to_close_timeout=timedelta(minutes=5),
            )
        else:
            # Original: Fax notifications
            await workflow.execute_activity(
                send_fax,
                schedule_to_close_timeout=timedelta(minutes=5),
            )
```

You can use a single patch ID for multiple changes deployed together:

```python
if workflow.patched("v2-updates"):
    # All v2 changes together
    await workflow.execute_activity(validate_v2, ...)
    await workflow.execute_activity(process_v2, ...)
else:
    await workflow.execute_activity(validate_v1, ...)
    await workflow.execute_activity(process_v1, ...)
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
from temporalio.workflow import VersioningBehavior

@workflow.defn
class StableWorkflow:
    @workflow.run
    async def run(self) -> str:
        # This workflow will always run on its assigned version
        return await workflow.execute_activity(
            process_order,
            schedule_to_close_timeout=timedelta(minutes=5),
        )
```

**When to use PINNED:**
- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- You want to eliminate version compatibility complexity
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions:

**When to use AUTO_UPGRADE:**
- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments
- You are already using patching APIs for version transitions

**Important:** AUTO_UPGRADE workflows still need patching to handle version transitions safely since they can move between Worker versions.

### Worker Configuration with Default Behavior

```python
# For short-running workflows, prefer PINNED
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
        # default_versioning_behavior=VersioningBehavior.PINNED,
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
