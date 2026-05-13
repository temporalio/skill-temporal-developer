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

## Versioned Continue-as-New (Upgrade-on-CaN)

> **Public Preview.** Experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

A Pinned Workflow that uses Continue-as-New can opt to upgrade onto a newer Worker Deployment Version at the Continue-as-New boundary, without patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-533 --> See `references/core/versioning.md` §"Versioned Continue-as-New" for the cross-language concept.

This is a **Pinned-Workflow** pattern. Without the upgrade option, a Pinned Workflow's version is inherited across the entire Continue-as-New chain. <!-- docs/encyclopedia/workers/worker-versioning.mdx:129-132 --> Auto-Upgrade Workflows already follow the Target Worker Deployment Version on every Workflow Task; they do not use this mechanism.

### How the SDK exposes the feature

The local Temporal documentation only shows a Go example for this Public-Preview feature. The Java SDK exposes equivalent capabilities, but the specific token names are not described in the docs clone — confirm them in the upstream SDK before writing production code.

The conceptual surface (verified in the docs) is <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:556-605 -->:

1. A per-Workflow-Info flag named in docs prose as `target_worker_deployment_version_changed`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 --> It becomes `true` when a new Target Worker Deployment Version is available, and it is refreshed only when a Workflow Task completes. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:571 -->
2. A Continue-as-New variant that accepts options, with an option to set the *new* run's initial versioning behavior. The Go example sets the new run to Auto-Upgrade so it lands on the Target Worker Deployment Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584-591 -->

Java-side concrete names (not in the local docs):

- The accessor for the target-version-changed flag on `WorkflowInfo` (or equivalent): <!-- VERIFY: exact method on io.temporal.workflow.WorkflowInfo (or equivalent on Workflow) that reports target Worker Deployment Version changes; check upstream temporalio/sdk-java release notes (Public Preview) -->
- The Continue-as-New variant that accepts an initial versioning behavior, and the spelling of the AUTO_UPGRADE constant: <!-- VERIFY: which `Workflow.continueAsNew(...)` overload (or `ContinueAsNewOptions` builder) accepts an initial versioning behavior, and the enum constant name, in upstream temporalio/sdk-java -->

Until those are verified against the upstream SDK, treat the *check* as conceptual rather than tied to a specific Java token:

```java
// Pseudocode — token names are SDK-version-specific and not in the docs clone.
// Verify against upstream temporalio/sdk-java before using in production.
@WorkflowInterface
public interface LongRunningEntity {
    @WorkflowMethod
    void run(State state);
}

public static class LongRunningEntityImpl implements LongRunningEntity {
    @Override
    @WorkflowVersioningBehavior(VersioningBehavior.PINNED)
    public void run(State state) {
        while (!state.isDone()) {
            doUnitOfWork(state);

            // Check after each meaningful Workflow Task — the flag refreshes
            // only across Workflow Task boundaries.
            if (/* <!-- VERIFY: WorkflowInfo accessor for target-version-changed --> */) {
                // Continue-as-New with an initial versioning behavior so the
                // new run starts with AutoUpgrade behavior and lands on its
                // Worker Deployment's Target Version.
                // <!-- VERIFY: Continue-as-New variant + AUTO_UPGRADE constant in upstream temporalio/sdk-java -->
                Workflow.continueAsNew(state);
            }
        }
    }
}
```

When in doubt, link the user to the docs Go example (`references/go/versioning.md` §Versioned Continue-as-New) as the canonical documented form.

### Where to check the flag

The docs name these as good check points <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:576-577 -->:

- Before accepting Updates.
- Before starting Activities.
- Before starting Child Workflows.

The flag is **not** a real-time signal — it refreshes only when the SDK completes a Workflow Task.

### Limitations

From the Public Preview caution <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:607-618 -->:

- **Lazy moving only.** Idle / sleeping Workflows are not proactively notified of a Target-Version change. Send a Signal to wake them so they can re-check the flag.
- **Interface compatibility.** The new version's Workflow definition must accept the previous run's Continue-as-New input. If it doesn't, the new run may fail on its first Workflow Task.

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., `"add-fraud-check"` not `"patch-1"`)
3. **Deploy patches incrementally**: patch, remove old path, remove `getVersion`
4. **Manually upsert `TemporalChangeVersion`** search attribute when using `getVersion` if you need query filtering
5. **Use PINNED for short workflows** to simplify version management
6. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
7. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
