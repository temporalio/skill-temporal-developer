# Versioned Continue-as-New

A SDK-level option that lets a Pinned Workflow detect when a new Target Worker Deployment Version is available and, at its next Continue-as-New boundary, start the new run on that Target Version with Auto-Upgrade behavior — no patching required <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:530-554 -->.

## Public Preview

:::note Public Preview

This feature is in Public Preview as an experimental SDK-level option <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:543 -->.

:::

## When this feature applies

Long-running Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) can upgrade to newer Worker Deployment Versions at Continue-as-New boundaries without requiring patching <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:532-533 -->.

This pattern is ideal for <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:535-539 -->:

- **Entity Workflows** that run for months or years
- **Batch processing** Workflows that checkpoint with Continue-as-New
- **AI agent Workflows** with long sleeps waiting for user input

### Decision-guide row

The Worker Versioning decision guide recommends this combination for long-running Workflows that use Continue-as-New <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:261-265 -->:

| Workflow Duration         | Uses Continue-as-New? | Recommended Behavior        | Patching Required? |
| ------------------------- | --------------------- | --------------------------- | ------------------ |
| **Long** (weeks to years) | Yes                   | `PINNED` + upgrade on CaN   | Never              |

## Vocabulary

This feature involves three distinct names that should not be conflated:

- **Target Worker Deployment Version** — the concept. The version your Workflow will upgrade to next; can be the Deployment's Current Version or the Ramping Version, with Workflow ID determining which group an Auto-Upgrade Workflow falls into when a ramp is active <!-- docs/encyclopedia/workers/worker-versioning.mdx:79 -->.
- **`target_worker_deployment_version_changed`** — the prose field name used in the docs to refer to the flag set by Server when a new Target Version becomes available <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:559 -->.
- **`GetTargetWorkerDeploymentVersionChanged`** — the Go SDK accessor on the Workflow info (other SDKs spell this differently; see language-specific references) <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:583 -->.

## How it works

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549 -->. With the upgrade option enabled, the mechanism is three steps <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:551-554 -->:

1. Each Workflow run remains pinned to its version (no patching needed during a run).
2. The Temporal Server tells the Workflow when a new Target Version becomes available.
3. When the Workflow performs Continue-as-New with the upgrade option, the new run starts on the Target Version.

### Detecting a new Target Version

When a new Worker Deployment Version becomes Current or Ramping, active Workflows can detect this through `target_worker_deployment_version_changed` <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:558-559 -->.

The flag is refreshed after each Workflow Task (WFT) completes <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:571 -->. In a Workflow that regularly performs non-sleep Workflow Tasks, the flag will naturally update; you can choose to check the field periodically, or before accepting updates, starting activities, or starting child workflows <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:575-577 -->.

SDK API names are documented per language — see `references/{lang}/versioned-continue-as-new.md` for code examples.

### Behavior of the new run after upgrade-on-CaN

When the Workflow performs Continue-as-New with the upgrade option, the new run starts with Auto-Upgrade behavior and uses the Target Version of its Worker Deployment <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:587-590 -->. The new run is **not** Pinned to the new version.

## Inheritance semantics across Continue-as-New (and related boundaries)

The encyclopedia distinguishes several cases that govern whether and how a new run inherits its parent's version. Versioned Continue-as-New is the SDK-level escape hatch for the first case below — opting a Pinned Workflow out of pinned-version inheritance at the Continue-as-New boundary so the new run starts on the Target Version with Auto-Upgrade behavior.

### Pinned Workflow, Continue-as-New (same Worker Deployment)

The Pinned version is inherited across the Continue-As-New chain <!-- docs/encyclopedia/workers/worker-versioning.mdx:129-131 -->. Versioned Continue-as-New is the opt-in mechanism that overrides this default at a Continue-as-New boundary <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:549-554 -->.

### Auto-Upgrade Workflow, Continue-as-New

When the Original Workflow is Auto-upgrade, no version inheritance occurs <!-- docs/encyclopedia/workers/worker-versioning.mdx:134-136 -->. Auto-upgrade Workflows never inherit versions <!-- docs/encyclopedia/workers/worker-versioning.mdx:105 -->.

### Pinned Workflow, Continue-as-New to a different Worker Deployment

If the new run's Task Queue is not in the same Worker Deployment as the original Workflow, no inheritance occurs and the new run starts on the Current Version of its task queue <!-- docs/encyclopedia/workers/worker-versioning.mdx:132 -->.

### Cron jobs

Cron jobs **never inherit** versioning behavior or version <!-- docs/encyclopedia/workers/worker-versioning.mdx:150-152 -->.

## Limitations

:::caution Current Limitations <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:609 -->

- **Lazy moving only:** Workflows must be invoked by executing a step to receive the Target-Version-Changed information. Sleeping Workflows won't proactively get the Target-Version-Changed information. If you have idle Workflows that you want to wake up so they can check the flag, you can send them a Signal <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->.
- **Interface compatibility:** When continuing as new to a different version, ensure your Workflow input provided by the previous version's workflow definition is compatible with the new version's workflow definition. If incompatible, the new run may fail on its first Workflow Task <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->.

:::

## Minimum SDK and Server versions

The docs list these as minimums for Worker Versioning generally <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:64-77 -->. The upgrade-on-CaN option is a further experimental option layered on top of Worker Versioning <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:543 -->.

| Component                | Minimum version |
| ------------------------ | --------------- |
| Go SDK                   | v1.35.0         |
| Python SDK               | v1.11           |
| Java SDK                 | v1.29           |
| TypeScript SDK           | v1.12           |
| .NET SDK                 | v1.7.0          |
| Ruby SDK                 | v0.5.0          |
| Temporal CLI (self-host) | v1.4.1          |
| Temporal Server          | v1.29.1         |
| Temporal UI              | v2.38.0         |

<!-- VERIFY: The docs list minimum SDK versions for Worker Versioning generally (lines 64-71) but do not state a separate minimum SDK version for the Public-Preview upgrade-on-CaN option specifically. Question: are these same minimums sufficient for the upgrade-on-CaN option, or does each SDK gate the option behind a higher version? -->

## Related references

- `references/core/versioning.md` — general Worker Versioning context, Pinned vs. Auto-Upgrade behaviors, Current and Ramping Versions.
- `references/{lang}/versioned-continue-as-new.md` — language-specific API names and code examples for each SDK.
