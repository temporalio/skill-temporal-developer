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

After all pre-patch Workflow Executions have left retention, remove the old branch and set `minSupported` to `1`:

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

In a later deployment, after all executions with older versions have left retention, you may remove the first `getVersion` call entirely. Once removed, permanently retire that change ID; a future change at the same location must use a new ID starting from `Workflow.DEFAULT_VERSION`:

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

Java `getVersion` records a history marker, but `TemporalChangeVersion` visibility requires either the Java SDK 1.30+ `enableUpsertVersionSearchAttributes` option or a manual upsert. The following example uses a manual upsert:

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

        // Pre-patch histories return DEFAULT_VERSION and have no version marker.
        if (version != Workflow.DEFAULT_VERSION) {
            Workflow.upsertTypedSearchAttributes(
                TEMPORAL_CHANGE_VERSION.valueSet(
                    List.of("add-fraud-check-" + version)));
        }

        if (version >= 1) {
            activities.checkFraud(order);
        }
        return activities.processPayment(order);
    }
}
```

When retiring a recorded integer version, query its exact `changeID-version` value across open and closed executions still in retention:

```bash
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND TemporalChangeVersion = "add-fraud-check-1"'
```

`Workflow.DEFAULT_VERSION` is marker absence, not version `0`. If this is the only version marker, find the simple pre-marker population with `TemporalChangeVersion IS NULL`. For multiple or optional version sites, inspect all retained executions of the Workflow Type and classify the exact marker set and Event History. A zero running count identifies no immediate live blocker, but it does not prove that older histories have left retention. Replay selected histories to test compatibility; sampled replay does not prove the retained population is empty.

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

## Upgrading on Continue-as-New

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

For long-running Pinned Workflows that use Continue-as-New, detect a new Target Worker Deployment Version on `Workflow.getInfo()` and continue-as-new with `InitialVersioningBehavior.AUTO_UPGRADE` so the new run starts on the Target Version. See `references/core/versioning.md` for the conceptual model.

### Detecting the Target Version change

`Workflow.getInfo().isTargetWorkerDeploymentVersionChanged()` returns `true` when a new Current or Ramping Version is available for this Workflow's Worker Deployment.  The flag is refreshed after each Workflow Task completes.

Check the flag from code that runs as part of a Workflow Task — for example, before accepting an Update, starting an Activity, or starting a child Workflow.

### Continue-as-new with upgrade

When the flag is set, call `Workflow.continueAsNew` with a `ContinueAsNewOptions` whose `InitialVersioningBehavior` is `AUTO_UPGRADE` so the new run starts on the Target Version of its Worker Deployment.

```java
import io.temporal.common.InitialVersioningBehavior;
import io.temporal.workflow.ContinueAsNewOptions;
import io.temporal.workflow.Workflow;

// At a natural Workflow Task boundary, e.g. before accepting Updates,
// starting Activities, starting child Workflows, etc.:
if (Workflow.getInfo().isTargetWorkerDeploymentVersionChanged()) {
  Workflow.continueAsNew(
      ContinueAsNewOptions.newBuilder()
          .setInitialVersioningBehavior(InitialVersioningBehavior.AUTO_UPGRADE)
          .build(),
      nextInput);
}
```

> [!IMPORTANT]
> Don't busy-poll the flag on a timer. Check it at a natural Workflow Task boundary — before accepting Updates, starting Activities, starting child Workflows, etc. For idle Workflows, send a Signal to wake them so they can check it (see Limitations).

### Limitations

- **Lazy moving only — idle Workflows do not upgrade.** Send a Signal to wake an idle Workflow so it can check `isTargetWorkerDeploymentVersionChanged`.
- **Workflow input must remain compatible across versions.** The new version's Workflow definition must accept the previous version's input; otherwise the new run may fail on its first Workflow Task.
- **Pinned Workflow Types only.** Auto-Upgrade Workflows move at Workflow Task boundaries already; the upgrade-on-CaN pattern adds nothing for them.

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive change IDs** that explain the change (e.g., `"add-fraud-check"` not `"patch-1"`)
3. **Deploy patches incrementally**: patch, remove old path, remove `getVersion`
4. **Enable automatic `TemporalChangeVersion` upserts on Java 1.30+** when query filtering is needed; otherwise upsert the returned non-default version manually
5. **Use PINNED for short workflows** to simplify version management
6. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
7. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
