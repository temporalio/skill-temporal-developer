# Java SDK Versioning

For conceptual overview and guidance on choosing an approach, see `references/core/versioning.md`.

## Patching API

### Workflow.getVersion()

`Workflow.getVersion(String changeId, int minSupported, int maxSupported)` returns the version to use for a given change:

```java
import io.temporal.workflow.Workflow;

@WorkflowInterface
public interface ShippingWorkflow {
    @WorkflowMethod
    void run();
}

public class ShippingWorkflowImpl implements ShippingWorkflow {
    @Override
    public void run() {
        int version = Workflow.getVersion(
            "send-email-instead-of-fax",
            Workflow.DEFAULT_VERSION,  // minSupported (no change)
            1                          // maxSupported (current version)
        );

        if (version == 1) {
            // New code path
            Workflow.newActivityStub(MyActivities.class, options).sendEmail();
        } else {
            // Old code path (for replay of existing workflows)
            Workflow.newActivityStub(MyActivities.class, options).sendFax();
        }
    }
}
```

**How it works:**

- For new executions: returns `maxSupported` and records a marker in history
- For replay with the marker: returns the recorded version
- For replay without the marker: returns `DEFAULT_VERSION` (-1)

### Three-Step Patching Process

**Step 1: Patch in New Code**

Add the version check with both old and new code paths:

```java
public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        int version = Workflow.getVersion(
            "add-fraud-check",
            Workflow.DEFAULT_VERSION,
            1);

        if (version >= 1) {
            activities.checkFraud(order);
        }

        return activities.processPayment(order);
    }
}
```

**Step 2: Remove Old Code Path**

Once all pre-patch Workflow Executions have completed, remove the old branch and set `minSupported` to `1`:

```java
public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        Workflow.getVersion("add-fraud-check", 1, 1);

        activities.checkFraud(order);
        return activities.processPayment(order);
    }
}
```

**Step 3: Remove the Patch**

After all workflows with the patch marker have completed, remove the `getVersion` call entirely:

```java
public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        activities.checkFraud(order);
        return activities.processPayment(order);
    }
}
```

### Recording TemporalChangeVersion Search Attribute

Unlike the Python and TypeScript SDKs, the Java SDK does **not** automatically record the `TemporalChangeVersion` search attribute. You must manually upsert it:

```java
import io.temporal.workflow.Workflow;
import io.temporal.common.SearchAttributeKey;
import java.util.List;

public class OrderWorkflowImpl implements OrderWorkflow {
    private static final SearchAttributeKey<List<String>> TEMPORAL_CHANGE_VERSION =
        SearchAttributeKey.forKeywordList("TemporalChangeVersion");

    @Override
    public String run(Order order) {
        int version = Workflow.getVersion("add-fraud-check", Workflow.DEFAULT_VERSION, 1);

        // Manually record for query filtering
        Workflow.upsertTypedSearchAttributes(
            TEMPORAL_CHANGE_VERSION.valueSet(List.of("add-fraud-check-1")));

        if (version >= 1) {
            activities.checkFraud(order);
        }
        return activities.processPayment(order);
    }
}
```

Query with:

```bash
temporal workflow list --query \
  'TemporalChangeVersion = "add-fraud-check-1" AND ExecutionStatus = "Running"'
```

## Workflow Type Versioning

For incompatible changes, create a new Workflow Type:

```java
@WorkflowInterface
public interface PizzaWorkflow {
    @WorkflowMethod
    String run(PizzaOrder order);
}

// Original implementation
public class PizzaWorkflowImpl implements PizzaWorkflow {
    @Override
    public String run(PizzaOrder order) {
        return processOrderV1(order);
    }
}

// New workflow type for incompatible changes
@WorkflowInterface
public interface PizzaWorkflowV2 {
    @WorkflowMethod
    String run(PizzaOrder order);
}

public class PizzaWorkflowV2Impl implements PizzaWorkflowV2 {
    @Override
    public String run(PizzaOrder order) {
        return processOrderV2(order);
    }
}
```

Register both with the Worker:

```java
worker.registerWorkflowImplementationTypes(
    PizzaWorkflowImpl.class,
    PizzaWorkflowV2Impl.class);
```

Start new workflows with the new type:

```java
PizzaWorkflowV2 workflow = client.newWorkflowStub(
    PizzaWorkflowV2.class,
    WorkflowOptions.newBuilder()
        .setTaskQueue("pizza-task-queue")
        .build());
workflow.run(order);
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level. Available since Java SDK v1.29.

### Key Concepts

- **Worker Deployment**: A logical group of Workers processing the same Task Queue, identified by a deployment name (e.g., `"order-service"`).
- **Worker Deployment Version**: A specific version within a deployment, identified by the combination of deployment name and Build ID (e.g., `"order-service:v1.0.0"`). Each version corresponds to a particular code revision.

### Configuring Workers

```java
import io.temporal.worker.Worker;
import io.temporal.worker.WorkerFactory;
import io.temporal.worker.WorkerOptions;
import io.temporal.worker.WorkerDeploymentOptions;
import io.temporal.worker.WorkerDeploymentVersion;

WorkerDeploymentVersion version = WorkerDeploymentVersion.newBuilder()
    .setDeploymentName("order-service")
    .setBuildId("v1.0.0")  // or git commit hash
    .build();

WorkerDeploymentOptions deploymentOptions = WorkerDeploymentOptions.newBuilder()
    .setVersion(version)
    .setUseWorkerVersioning(true)
    .build();

WorkerFactory factory = WorkerFactory.newInstance(client);
Worker worker = factory.newWorker(
    "my-task-queue",
    WorkerOptions.newBuilder()
        .setDeploymentOptions(deploymentOptions)
        .build());

worker.registerWorkflowImplementationTypes(MyWorkflowImpl.class);
worker.registerActivitiesImplementations(new MyActivitiesImpl());
factory.start();
```

### PINNED vs AUTO_UPGRADE Behaviors

Set the versioning behavior on the workflow definition:

```java
import io.temporal.workflow.VersioningBehavior;
import io.temporal.workflow.Workflow;

public class MyWorkflowImpl implements MyWorkflow {
    @Override
    public String run(String input) {
        Workflow.setVersioningBehavior(VersioningBehavior.PINNED);
        // ... workflow logic
    }
}
```

**PINNED**: Workflow stays on the Worker version that started it. Use for short-running workflows or when consistency within a single execution is critical. New workflows start on the current version; existing ones stay put.

**AUTO_UPGRADE**: Workflow moves to the latest Worker version on the next Workflow Task. Use for long-running workflows that need bug fixes or feature updates. Combine with `Workflow.getVersion()` patching to handle version transitions safely.

### Deployment Strategies

**Blue-Green**: Run two deployment versions simultaneously. Set the new version as the current deployment. PINNED workflows finish on the old version; new workflows start on the new version. Drain the old version once all its workflows complete.

**Rainbow**: Run multiple versions concurrently for gradual rollouts. Each version handles its own workflows. Useful when you have many long-running PINNED workflows across several code revisions.

### Querying Workflows by Worker Version

```bash
# List workflows running on a specific version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "order-service:v1.0.0" AND ExecutionStatus = "Running"'

# Count workflows per version to monitor drain progress
temporal workflow count --query \
  'TemporalWorkerDeploymentVersion = "order-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., `"add-fraud-check"` not `"patch-1"`)
3. **Deploy patches incrementally**: patch, remove old path, remove `getVersion`
4. **Manually upsert `TemporalChangeVersion`** search attribute when using `getVersion` if you need query filtering
5. **Use PINNED for short workflows** to simplify version management
6. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
7. **Generate Build IDs from code** (git hash) to ensure changes produce new versions

## Upgrading on Continue-as-New

Long-running Workflows that use [Continue-as-New](https://docs.temporal.io/workflow-execution/continue-as-new) and run under `PINNED` versioning behavior can land on the latest Target Worker Deployment Version at each Continue-as-New (CaN) boundary without using the patching API. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532-533 -->

This feature is currently in **Public Preview** as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

### When to use it

- **Entity Workflows** that run for months or years <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:537 -->
- **Batch processing** Workflows that checkpoint with Continue-as-New <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:538 -->
- **AI agent Workflows** with long sleeps waiting for user input <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:539 -->

### Decision logic

The Decision guide in the canonical docs splits long-running Workflows by whether they use Continue-as-New: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:261-266 -->

- **Long-running + uses Continue-as-New** → `PINNED` + upgrade on Continue-as-New. Patching is **never required**. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 -->
- **Long-running + no Continue-as-New** → `AUTO_UPGRADE` + patching with `Workflow.getVersion()`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:266 -->

So if your Java Workflow is already structured around Continue-as-New (e.g., the `ClusterManagerWorkflow` shape with `Workflow.getInfo().isContinueAsNewSuggested()` checks), prefer `PINNED` plus upgrade-on-CaN over `AUTO_UPGRADE` plus patching.

### How it works (language-neutral)

By default, `PINNED` Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the upgrade-on-CaN option enabled: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 -->

1. Each individual Workflow run stays pinned to its starting Version, so no patching is needed mid-run. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:552 -->
2. The Temporal Server notifies the Workflow when a new Target Worker Deployment Version becomes available (Current or Ramping). <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553, 558-559 -->
3. When the Workflow performs Continue-as-New with the upgrade option, the **new run** starts on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 -->

The new run can be started under `AUTO_UPGRADE` behavior so it picks up the Target Version of its Worker Deployment, but practically your code chooses to Continue-as-New at the next safe checkpoint and the new run boots on the new Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587-590 -->

### Detection is lazy

The "Target Version changed" signal is refreshed only as the Workflow runs Workflow Tasks. Sleeping or idle Workflows do **not** proactively learn that a new Target Version is available. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

The documented escape hatch is to send the Workflow a **Signal** to wake it up so it can check the Target-Version-Changed flag and decide whether to Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:612-613 -->

In practice, check the flag in the natural places where a long-running Workflow already does Workflow Tasks: before accepting Updates, before starting Activities, before launching Child Workflows, or at regular timer boundaries.

### Input compatibility caveat

When you Continue-as-New across a Version change, the **previous Version writes the input** that the **new Version reads**. If the new Workflow definition's input shape is not compatible with what the old Version produced, the new run can fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

Plan Continue-as-New input objects (e.g., the `ClusterManagerInput` style class) with the same care you give Activity input/output: additive, optional fields; no removed or renamed required fields between Versions.

### Continue-as-New inheritance reminder

By default, Continue-as-New on a `PINNED` Workflow inherits the parent's pinned Version across the chain — that is the behavior the upgrade-on-CaN option is designed to override at a chosen boundary. <!-- docs/encyclopedia/workers/worker-versioning.mdx:129-132 -->

If the new run's Task Queue is **not** in the same Worker Deployment as the original Workflow, no inheritance occurs and the new run starts on the Current Version of its Task Queue instead. <!-- docs/encyclopedia/workers/worker-versioning.mdx:131-132 -->

Auto-upgrade Workflows never inherit versions across Continue-as-New. <!-- docs/encyclopedia/workers/worker-versioning.mdx:134-136 -->

### Java SDK API status

The canonical Temporal documentation worked example for upgrade-on-Continue-as-New is currently provided **only in Go**, using `workflow.GetInfo(...).GetTargetWorkerDeploymentVersionChanged()` and `workflow.NewContinueAsNewErrorWithOptions(..., InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade, ...)`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 -->

As of 2026-05, the docs clone does **not** document the equivalent Java SDK token names for this Public Preview feature, so this section deliberately omits a Java code snippet to avoid inventing symbol names. For the worked code example, see:

- `references/go/versioning.md` § Upgrading on Continue-as-New
- The canonical page: `docs/production-deployment/worker-deployments/worker-versioning.mdx` § Upgrading on Continue-as-New

<!-- VERIFY: Java SDK token names for upgrade-on-CaN — docs only document Go as of 2026-05; consult Java SDK source or release notes -->
