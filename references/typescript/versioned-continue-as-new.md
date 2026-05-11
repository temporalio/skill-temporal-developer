# Versioned Continue-as-New (TypeScript)

This file covers the TypeScript SDK surface for the Upgrade-on-Continue-as-New feature of Worker Versioning. For the full concept model (Pinned vs. Auto-Upgrade, Target Version, lazy moving, handshake sequence), see `references/core/versioned-continue-as-new.md`. For a working code example, see `references/go/versioned-continue-as-new.md` — the in-docs example for this feature is Go-only.

## Status

:::note Public Preview

This feature is in Public Preview as an experimental SDK-level option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 541-545 -->

:::

The local docs clone does not contain a TypeScript code example for the upgrade-on-Continue-as-New option. The only example in `worker-versioning.mdx` is written in Go. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 561-605 --> <!-- VERIFY: does the TypeScript SDK v1.12+ expose an upgrade-on-CaN option on continueAsNew? Check @temporalio/workflow release notes and the typescript.temporal.io API reference for 1.12+. -->

## Minimum SDK version

Worker Versioning requires TypeScript SDK **v1.12** or later. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx line 69 -->

## What the feature does

Long-running Workflows that use [Continue-as-New](/workflow-execution/continue-as-new) can upgrade to newer Worker Deployment Versions at Continue-as-New boundaries without requiring patching. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 530-533 -->

By default, Pinned Workflows stay on their original Worker Deployment Version even when they Continue-as-New. With the upgrade option enabled, each run remains pinned for its own duration, the Server tells the Workflow when a new Target Version is available, and the *new* run started by Continue-as-New begins on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 547-554 -->

Note: this is opt-in. The new run is started with **Auto-Upgrade** behavior so that it picks up the Target Version of its Worker Deployment — it is not pinned to the new version automatically. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 587-590 -->

## Declaring versioning behavior on a Workflow (TypeScript)

The TypeScript SDK declares per-Workflow versioning behavior via `setWorkflowOptions`:

```ts
setWorkflowOptions({ versioningBehavior: 'PINNED' }, helloWorld);
export async function helloWorld(): Promise<string> {
  return 'hello world!';
}
```

<!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 409-414 -->

## Continue-as-New in TypeScript (general)

Inside a Workflow, call `continueAsNew()` from `@temporalio/workflow` with the same type as the current Workflow. This stops the current run and starts a new one with a fresh Event History under the same Workflow Id chain. <!-- docs/develop/typescript/workflows/continue-as-new.mdx lines 32, 56-57 -->

```typescript
return await wf.continueAsNew<typeof clusterManagerWorkflow>({
  state: manager.getState(),
  testContinueAsNew: input.testContinueAsNew,
});
```

<!-- docs/develop/typescript/workflows/continue-as-new.mdx lines 65-70 -->

You can use `wf.workflowInfo().continueAsNewSuggested` to check whether the Server is suggesting you Continue-as-New based on Event History size. <!-- docs/develop/typescript/workflows/continue-as-new.mdx lines 82-83, 100-112 -->

If your Workflow uses Updates or Signals, do not call Continue-as-New from inside handlers; wait for handlers to finish before continuing as new. <!-- docs/develop/typescript/workflows/continue-as-new.mdx lines 72-76 -->

## The upgrade-on-Continue-as-New handshake

Conceptually (see the core reference for the full handshake):

1. The current run is Pinned and keeps running on its original Worker Deployment Version.
2. The Server signals the Workflow that a new Target Worker Deployment Version is available. This is delivered as a flag on Workflow info that is refreshed after each Workflow Task completes. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 552-554, 570-577 -->
3. The Workflow code observes the flag (typically at a natural decision point — e.g. before accepting an Update, starting an Activity, or starting a child Workflow) and chooses to call Continue-as-New with the upgrade option. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 574-577 -->
4. The new run starts with Auto-Upgrade behavior on the Target Version. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 587-590 -->

<!-- VERIFY: what is the TypeScript SDK API name for the "target worker deployment version changed" flag? The Go SDK exposes it as workflow.GetInfo(ctx).GetTargetWorkerDeploymentVersionChanged(). Check @temporalio/workflow workflowInfo() fields in 1.12+. -->

<!-- VERIFY: what is the TypeScript SDK API name for passing the "initial versioning behavior = auto-upgrade" option to continueAsNew? The Go SDK exposes it as workflow.ContinueAsNewErrorOptions{ InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade }. Check @temporalio/workflow continueAsNew() options in 1.12+. -->

## Limitations (Public Preview)

- **Lazy moving only.** A Workflow must execute a Workflow Task to receive the Target-Version-Changed information. Sleeping/idle Workflows are not proactively notified; if you need them to react, send them a Signal to wake them so they can check. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 611-613 -->
- **Interface compatibility.** When continuing as new to a different version, the Workflow input produced by the previous version's Workflow Definition must be compatible with the new version's Workflow Definition. If incompatible, the new run may fail on its first Workflow Task. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx lines 614-616 -->

## See also

- `references/core/versioned-continue-as-new.md` — concept-level behavior shared by all SDKs.
- `references/go/versioned-continue-as-new.md` — canonical worked example (Go is the only language with an in-docs code sample for this feature).
- `references/typescript/versioning.md` — general TypeScript versioning (Patching and Worker Versioning).
