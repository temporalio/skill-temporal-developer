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

## Upgrade on Continue-as-New (Java)

This is a Public Preview, experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 --> See the canonical docs at `documentation/docs/production-deployment/worker-deployments/worker-versioning.mdx` §Upgrading on Continue-as-New for the authoritative description.

### When to use it

Use this pattern when a Workflow Type is `PINNED` and uses Continue-as-New to manage history size or run for long durations (weeks to years). It is the recommended fit on the decision table for long Workflows that use Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:265 --> Typical examples are Customer entity Workflows and AI agent / Chatbot Workflows. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:275-276 -->

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New; opting into the upgrade option is what allows the next run to land on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 -->

### How it works

The mechanic is a three-step interaction between the Server, the running Workflow, and Continue-as-New: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:551-554 -->

1. Each Workflow run remains pinned to its version, so no patching is needed inside a run.
2. The Temporal Server tells the Workflow when a new Target Worker Deployment Version becomes available.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

There is no Worker-level toggle for this behavior. The opt-in lives on the Continue-as-New call itself, so each Continue-as-New decides whether the next run should adopt the Target Version.

### Detecting the change

When a new Worker Deployment Version becomes Current or Ramping, active Workflows can detect this through the conceptual flag `target_worker_deployment_version_changed`. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 -->

This flag is refreshed after each Workflow Task completes, so it reflects the most recent server state rather than being a sticky one-time signal. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570-571 --> A Workflow that wants to react can read the flag at natural decision points (for example, before accepting an Update, starting an Activity, or starting a Child Workflow) on each Workflow Task.

### Java SDK identifiers

The per-Continue-as-New opt-in concept exists across SDKs, but the canonical docs section currently provides a code example only for Go. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 --> The exact Java identifier names for the change-detection accessor, the Continue-as-New-with-options shape, and the "initial versioning behavior = auto-upgrade" hint are not enumerated in the docs file, so this skill does not name them.

Java readers should:

- Consult the Java SDK release notes and Javadoc that correspond to their SDK version for the exact identifier names.
- Treat the Go example in `references/go/versioning.md` as the canonical shape — the same three pieces (read the change flag, build a Continue-as-New-with-options call, set the new run's initial versioning behavior to Auto-Upgrade so it picks up the Target Version) are what the Java equivalents must compose.

### Limitations

- **Lazy moving only.** Workflows must be invoked by executing a step to receive the Target-Version-Changed information; sleeping Workflows are not proactively notified. If you have idle Workflows that you want to wake up so that they can check the change flag, send them a Signal. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->
- **Input compatibility.** When continuing as new to a different version, ensure the Workflow input produced by the previous version's Workflow definition is compatible with the new version's Workflow definition. If incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

### See also

Conceptual treatment in `references/core/versioning.md` §Upgrade on Continue-as-New. Canonical worked example (Go) in `references/go/versioning.md`.
