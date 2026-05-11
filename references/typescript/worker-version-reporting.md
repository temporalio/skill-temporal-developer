# Worker Version Reporting (TypeScript SDK)

This file documents a narrow but easy-to-miss configuration mode on the TypeScript SDK's `Worker.create` options: passing a `workerDeploymentOptions.version` while leaving `useWorkerVersioning: false`. In that mode, the Worker reports its Deployment Version to the Temporal Server but does **not** enable versioned task routing or Workflow pinning.

For the full Worker Versioning feature (routing, pinning, ramping), see `references/typescript/versioning.md` and the conceptual overview in `references/core/versioning.md`.

## What "reporting" means

When a Worker starts polling Task Queues, it tells the Server which Deployment Version it belongs to. <!-- docs/encyclopedia/workers/worker-versioning.mdx:40 -->

A Deployment Version is identified by a deployment name plus a Build ID. <!-- docs/encyclopedia/workers/worker-versioning.mdx:36-40 -->

Reporting alone makes the Worker's build visible to the Server (it can show up in `temporal worker deployment describe` and the UI) but does not change how Workflow Tasks are routed, does not pin Workflows to a version, and does not enable ramping.

## The `WorkerDeploymentOptions` shape

In the TypeScript SDK, `Worker.create` accepts a `workerDeploymentOptions` field of type `WorkerDeploymentOptions`. The type is a discriminated union on `useWorkerVersioning`: <!-- sdk-typescript:packages/worker/src/worker-options.ts WorkerDeploymentOptions -->

```ts
type WorkerDeploymentOptions = {
  version: WorkerDeploymentVersion;
  useWorkerVersioning: boolean;
  defaultVersioningBehavior?: VersioningBehavior | undefined;
} & (
  | { useWorkerVersioning: true;  defaultVersioningBehavior: VersioningBehavior }
  | { useWorkerVersioning: false; defaultVersioningBehavior?: never }
);
```

Consequences:

- `version` is **always required**. Both union branches inherit `version: WorkerDeploymentVersion` from the base. <!-- sdk-typescript:packages/worker/src/worker-options.ts WorkerDeploymentOptions -->
- When `useWorkerVersioning: true`, you **must** supply `defaultVersioningBehavior`.
- When `useWorkerVersioning: false`, `defaultVersioningBehavior` **must be omitted** (`never` in the type).

`WorkerDeploymentVersion` is a two-field object: <!-- typescript.temporal.io/api/interfaces/common.WorkerDeploymentVersion -->

```ts
interface WorkerDeploymentVersion {
  readonly buildId: string;
  readonly deploymentName: string;
}
```

`VersioningBehavior` is the string union `'PINNED' | 'AUTO_UPGRADE'`. <!-- typescript.temporal.io/api/namespaces/common -->

## Reporting-only configuration

To report a Build ID without enabling Worker Versioning, set `useWorkerVersioning: false`, supply a `version`, and omit `defaultVersioningBehavior`:

```ts
import { Worker } from '@temporalio/worker';

const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue: 'my-queue',
  workerDeploymentOptions: {
    useWorkerVersioning: false,
    version: {
      deploymentName: 'order-service',
      buildId: process.env.BUILD_ID ?? 'dev',
    },
    // defaultVersioningBehavior intentionally omitted; the type forbids it here.
  },
});
```

In this mode, Workflow Tasks continue to be dispatched as on an unversioned Task Queue.

## Full Worker Versioning configuration (for contrast)

When you do want versioned routing and pinning, set `useWorkerVersioning: true` and supply a `defaultVersioningBehavior`: <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:207-221 -->

```ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue,
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: { buildId: '1.0', deploymentName: 'llm_srv' },
    defaultVersioningBehavior: 'PINNED',
  },
  connection: nativeConnection,
});
```

The Temporal docs' published example omits `defaultVersioningBehavior` from this branch; the SDK type requires it. <!-- VERIFY: docs example at docs/production-deployment/worker-deployments/worker-versioning.mdx:213-216 differs from sdk-typescript:packages/worker/src/worker-options.ts; the type definition is the binding source. -->

## When to use reporting-only

- You want server-side visibility of which build is polling (in `temporal worker deployment describe` output or the UI) before committing to versioned routing.
- You are wiring up the configuration plumbing — environment variables, deployment-name conventions — in advance of turning Worker Versioning on.
- You are debugging a Worker fleet and want each Worker to label itself with a build identifier independent of any versioning behavior.

Reporting-only does not deliver any of the Worker Versioning routing benefits (Current Version, Ramping Version, Pinning, drainage tracking). To get those, flip `useWorkerVersioning` to `true` and add a `defaultVersioningBehavior` — or annotate every Workflow with a `versioningBehavior` and leave the default unset on the Worker.

## Relationship to the deprecated `buildId` / `useVersioning` options

The TypeScript SDK previously exposed top-level `buildId: string` and `useVersioning: boolean` fields on `Worker.create` for the legacy Worker Versioning API. <!-- docs/develop/typescript/worker-versioning-legacy.mdx:35-44 -->

That API is deprecated. <!-- docs/develop/typescript/worker-versioning-legacy.mdx:15-23 -->

For new code, use `workerDeploymentOptions` instead. The TS SDK marks `workerDeploymentOptions` as exclusive with the legacy `buildId` / `useVersioning` fields. <!-- sdk-typescript:packages/worker/src/worker-options.ts (workerOptions.workerDeploymentOptions docstring) -->

## Minimum SDK version

The new `workerDeploymentOptions` API requires TypeScript SDK v1.12 or later. <!-- docs/production-deployment/worker-deployments/worker-versioning.mdx:69 -->

## Common mistakes

- Setting `useWorkerVersioning: false` and `defaultVersioningBehavior: 'PINNED'` together. The discriminated union forbids this; TypeScript will reject it at compile time. <!-- sdk-typescript:packages/worker/src/worker-options.ts WorkerDeploymentOptions -->
- Omitting `version` and assuming the Worker still reports something. `version` is required on the base type; omitting it is a type error.
- Expecting reporting-only Workers to participate in `set-current-version` / `set-ramping-version` routing. They do not; that requires `useWorkerVersioning: true`.
- Conflating the legacy top-level `buildId` field with `workerDeploymentOptions.version.buildId`. They belong to two different (and mutually exclusive) APIs.
- Assuming a `VersioningBehavior.UNSPECIFIED` value exists in TypeScript. Other SDKs have it; the TS `VersioningBehavior` type is `'PINNED' | 'AUTO_UPGRADE'` only. <!-- typescript.temporal.io/api/namespaces/common -->
