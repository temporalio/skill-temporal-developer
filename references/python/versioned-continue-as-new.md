# Versioned Continue-as-New (Python)

Python SDK usage notes for the upgrade-on-Continue-as-New option that lets Pinned long-running Workflows opt into a new Worker Deployment Version at a Continue-as-New boundary. For the cross-SDK concept, semantics, and the canonical (Go) code pattern, see `references/core/versioned-continue-as-new.md` and `references/go/versioned-continue-as-new.md`.

## Status

This feature is in Public Preview as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

## Minimum SDK version

Worker Versioning (the umbrella feature that includes upgrade-on-Continue-as-New) requires Python SDK [v1.11](https://github.com/temporalio/sdk-python/releases/tag/1.11.0) at minimum. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:67 -->

<!-- VERIFY: Did upgrade-on-Continue-as-New ship in Python SDK v1.11 or in a later 1.x point release? Confirm against the Python SDK release notes. -->

## What the docs cover in Python

The local docs clone does **not** contain a Python code example for the upgrade-on-Continue-as-New option. The only in-docs example for this feature is Go. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 -->

<!-- VERIFY: Is there an official Python sample for upgrade-on-Continue-as-New (for example in temporalio/samples-python)? -->

For the canonical pattern, see `references/go/versioned-continue-as-new.md`. The behavior described in `references/core/versioned-continue-as-new.md` applies to Python as well; only the API surface differs.

## Concept recap

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-550 --> With the upgrade option enabled:

1. Each Workflow run remains pinned to its version (no patching needed during a run). <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:552 -->
2. The Temporal Server tells the Workflow when a new Target Version becomes available. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553 -->
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554 -->

The new run uses Auto-Upgrade versioning behavior and the Target Version of its Worker Deployment — it is not Pinned to a fixed version by virtue of using this option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587-590 -->

## Python API surface

### Declaring versioning behavior at registration

A Workflow declares its versioning behavior on the `@workflow.defn` decorator:

```python
@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class HelloWorld:
    @workflow.run
    async def run(self):
        return "hello world!"
```

<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:396-406 -->

### Invoking Continue-as-New

Python Workflows call `workflow.continue_as_new(...)` to stop the current run and start a new one with the same Workflow Id. <!-- docs/develop/python/workflows/continue-as-new.mdx:58-74 -->

```python
workflow.continue_as_new(
    ClusterManagerInput(
        state=self.state,
        test_continue_as_new=input.test_continue_as_new,
    )
)
```

<!-- docs/develop/python/workflows/continue-as-new.mdx:67-74 -->

### Detecting a new Target Version

The Go example reads `info.GetTargetWorkerDeploymentVersionChanged()` to learn when a new Target Version is available. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:570-583 --> The Python docs in this clone do not name a Python equivalent.

<!-- VERIFY: What is the Python SDK API name for checking that a new Target Worker Deployment Version is available? Likely an attribute or method on workflow.info() in temporalio.workflow — confirm against the Python SDK 1.11+ release notes or temporalio.workflow module. -->

### Passing the Auto-Upgrade option to Continue-as-New

The Go example uses `workflow.NewContinueAsNewErrorWithOptions` with `ContinueAsNewErrorOptions{ InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade }` to make the new run start with Auto-Upgrade behavior on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:584-594 --> Do **not** translate those Go identifiers literally into Python — the Python SDK exposes its own equivalent.

<!-- VERIFY: What is the Python SDK API for passing InitialVersioningBehavior=AutoUpgrade through workflow.continue_as_new(...)? Check whether this is a keyword argument on workflow.continue_as_new (e.g. versioning_behavior=...) or a separate options object in temporalio.workflow / temporalio.common for the Python SDK 1.11+ release. -->

## The handshake (prose)

The runtime pattern, regardless of SDK, is:

1. Register the Workflow with Pinned versioning behavior so each run stays on a fixed Worker Deployment Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549, 396-406 -->
2. From inside the Workflow, periodically check whether the Server has reported a new Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:553, 570-583 -->
3. When a new Target Version is observed, call Continue-as-New, passing the Auto-Upgrade initial versioning behavior so the next run picks up the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:554, 584-594 -->

For working code, follow the Go example structure in `references/go/versioned-continue-as-new.md` and translate it to the Python API names once those are verified.

## Limitations

- **Lazy moving only.** Workflows must be invoked by executing a step to receive the Target-Version-Changed information. Sleeping Workflows are not proactively notified — wake them with a Signal if you want them to check. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->
- **Interface compatibility.** When continuing as new to a different version, ensure the input the previous version produces is compatible with the new version's Workflow definition. If incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

## See also

- `references/core/versioned-continue-as-new.md` — cross-SDK concept and semantics.
- `references/go/versioned-continue-as-new.md` — canonical (Go) code example.
- `references/python/versioning.md` — general Python versioning (patching, Worker Versioning).
