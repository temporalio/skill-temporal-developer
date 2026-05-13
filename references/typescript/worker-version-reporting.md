# TypeScript Worker Version Reporting

How a Temporal TypeScript Worker reports a Build ID and Deployment Version to the Temporal Service, and how the `workerDeploymentOptions` fields interact.

For the broader versioning workflow (patching, deprecating patches, deployment lifecycle), see `references/typescript/versioning.md`. For cross-SDK concepts, see `references/core/versioning.md`.

## The reporting model

When a Worker starts polling Task Queues, it reports its Deployment Version to the Temporal Server.

A Deployment Version is identified by two strings: a `deploymentName` that groups related Workers across versions, and a `buildId` that identifies a specific release of your Worker code.

In the TypeScript SDK you supply both values through the `workerDeploymentOptions.version` object on `Worker.create`.

## The `workerDeploymentOptions` shape

Three parameters are documented for Worker Versioning configuration, and the TypeScript SDK exposes them under `workerDeploymentOptions`. The first two are required; the third is optional.

```ts
const myWorker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue,
  workerDeploymentOptions: {
    useWorkerVersioning: true,
    version: { buildId: '1.0', deploymentName: 'llm_srv' },
  },
  connection: nativeConnection,
});
```

Field reference:

- `useWorkerVersioning` — boolean. Enables the Versioning functionality for this Worker.
- `version.buildId` — string. The Build ID portion of the Deployment Version.
- `version.deploymentName` — string. The deployment name portion of the Deployment Version.
- `defaultVersioningBehavior` — optional string. When unset, every Workflow Type must declare its own versioning behavior; setting it provides a default of `'PINNED'` or `'AUTO_UPGRADE'` for unannotated Workflows.

## Why `defaultVersioningBehavior` is absent from the canonical snippet

The TypeScript example on the Worker Versioning page does not include `defaultVersioningBehavior` — the field is optional, so the canonical snippet shows the minimum reporting shape.

The documentation states that if no `DefaultVersioningBehavior` is supplied, every Workflow Type must declare its own versioning behavior at registration time.

When the field is omitted, the Worker still reports its Deployment Version on every poll (that part is governed by `useWorkerVersioning` + `version`, not by `defaultVersioningBehavior`). The omission only affects the default applied to unannotated Workflows; it does not silence reporting.

Recommended posture from the docs:

> Otherwise, if your Worker and Workflows are new, we suggest not providing a `DefaultVersioningBehavior`.

Once every Workflow Type is annotated, you can remove the field.

## `defaultVersioningBehavior` value casing

In TypeScript, `defaultVersioningBehavior` uses string-literal values, not a constant enum like Go or Java. The multi-language serverless page shows the assignment using the `'PINNED'` string literal directly:

```ts
config.workerOptions.workerDeploymentOptions!.defaultVersioningBehavior = 'PINNED';
```

The two documented behaviors are `'PINNED'` and `'AUTO_UPGRADE'`.

## Lambda Workers report unconditionally

The `@temporalio/lambda-worker` package behaves differently from the standard `@temporalio/worker`: Worker Deployment Versioning is always enabled on Lambda, and the deployment version is required at the call site of `runWorker`.

The default versioning behavior on Lambda is `'PINNED'`. To change it, set `workerDeploymentOptions.defaultVersioningBehavior` inside the configure callback.

```ts
export const handler = runWorker(
  { deploymentName: 'sdk-demo', buildId: 'v1' },
  (config) => {
    config.workerOptions.taskQueue = TASK_QUEUE;
    config.workerOptions.workflowBundle = {
      codePath: require.resolve('./workflow-bundle.js'),
    };
    config.workerOptions.activities = activities;
  },
);
```

The two contrasts with the standard Worker are:

1. There is no `useWorkerVersioning: true` flag at the call site — Lambda always opts in.
2. There is a documented default behavior (`'PINNED'`), so the field can be left unset to accept that default. The non-Lambda Worker has no documented default, which is why the standard-Worker recommendation is to either annotate every Workflow Type or set the field explicitly.

## Do not confuse with the legacy top-level `buildId` API

A separate, deprecated form sets `buildId` and `useVersioning` directly on the top-level Worker options, not under `workerDeploymentOptions`:

```ts
// Deprecated — do not use for new code.
const worker = await Worker.create({
  taskQueue: 'your_task_queue_name',
  buildId: buildId,
  useVersioning: true,
});
```

Server support for the pre-2025 Worker Versioning API will be removed in March 2026.

Differences to watch for when reading older code or examples:

- Legacy: `buildId` is a top-level string on `Worker.create({...})`. Current: `buildId` is nested under `workerDeploymentOptions.version`.
- Legacy: the opt-in flag is named `useVersioning`. Current: it is named `useWorkerVersioning`, and lives inside `workerDeploymentOptions`.
- Legacy: there is no `deploymentName` — Build IDs were registered as version sets against a Task Queue. Current: every Build ID is paired with a `deploymentName` to form a Deployment Version.

## SDK minimum version

Worker Versioning requires `@temporalio/*` v1.12 or later.

## Self-checks before deploying

- The Build ID is unique per release. The docs suggest a Git SHA combined with a human-readable timestamp as one option.
- The `deploymentName` is stable across releases of the same logical service.
- After deploying, the new Deployment Version becomes visible to `temporal worker deployment describe`.

