# TypeScript `preloadModules` Bundler Option

## What it is

`preloadModules` is a bundler option (on `bundleWorkflowCode` and on `Worker.create`'s `bundlerOptions`) <!-- VERIFY: typescript.temporal.io/api/interfaces/worker.BundleOptions for the exact location of `preloadModules` --> that names modules to be imported into the reusable V8 Workflow context once, at Worker startup, rather than on first use in each Workflow Execution.

It is a complement to the reusable-V8-context execution mode, which the SDK references as `reuseV8Context`. <!-- docs/develop/worker-tuning-reference.mdx:74,93 --> When `reuseV8Context` is in effect, all Workflow Executions on a Worker share a single V8 context; preloading shifts the one-time cost of importing a module from "first Workflow Task that touches it" to "Worker startup", so first-task latency for those modules is paid once per Worker rather than per Workflow. <!-- VERIFY: typescript.temporal.io/api/ for the precise startup semantics of preloadModules vs. lazy import -->

`preloadModules` is **not** an escape hatch from the V8 Workflow sandbox. The sandbox still blocks Node.js / DOM APIs, automatically replaces non-deterministic functions like `Math.random()`, `Date`, and `setTimeout()`, and removes `FinalizationRegistry` / `WeakRef`. <!-- docs/develop/typescript/workflows/basics.mdx:121-128 --> <!-- references/typescript/determinism-protection.md:32-55 --> A module that wouldn't survive the sandbox on lazy import won't survive it preloaded either. See `references/typescript/determinism-protection.md`.

## How it relates to other bundler options

| Option | Purpose | Where it lives |
|---|---|---|
| `workflowsPath` | Path to the workflow module the Worker bundles at runtime (dev). | `Worker.create` and `bundleWorkflowCode` <!-- docs/develop/typescript/workers/run-process.mdx:184-200 --> |
| `workflowBundle: { codePath }` | Pre-built bundle produced by `bundleWorkflowCode`; used in production instead of `workflowsPath`. | `Worker.create` <!-- docs/develop/typescript/workers/run-process.mdx:228-249 --> |
| `bundlerOptions.ignoreModules` | List of modules to **exclude** from the bundle. Excluded modules are unavailable at Workflow runtime; any call into them throws. | `Worker.create` and `bundleWorkflowCode` <!-- docs/develop/typescript/workflows/basics.mdx:121-128 referencing worker.BundleOptions#ignoremodules --> <!-- references/typescript/determinism-protection.md:8-30 --> |
| `bundlerOptions.preloadModules` | List of modules to pre-import into the reusable V8 Workflow context at Worker startup. Opposite intent of `ignoreModules`. | `Worker.create` and `bundleWorkflowCode` <!-- VERIFY: typescript.temporal.io/api/interfaces/worker.BundleOptions --> |
| `reuseV8Context` | Reuse a single V8 context across Workflows. `preloadModules` is meaningful in this mode. | `WorkerOptions` (TypeScript) <!-- docs/develop/worker-tuning-reference.mdx:74,93 --> |

`ignoreModules` and `preloadModules` are not opposites of each other in implementation, but they pull in opposite directions: `ignoreModules` *removes* a module from the bundle, while `preloadModules` *imports* it eagerly into the shared context. Listing the same module in both would be self-contradictory. <!-- VERIFY: typescript.temporal.io/api/ for whether the SDK rejects this combination at bundle time or silently picks one. -->

## When to use it

Consider `preloadModules` when:

- Your Worker uses `reuseV8Context` (which, per the SDK defaults table, is the mode the TypeScript SDK ships with `MaxWorkflowThreadCount = 1`). <!-- docs/develop/worker-tuning-reference.mdx:74 -->
- A measurable share of first-Workflow-Task latency comes from importing large or initialization-heavy modules (e.g., a serializer, a schema validator, a generated protobuf module). <!-- VERIFY: typescript.temporal.io/api/ for whether preloadModules accepts CommonJS, ESM, or both. -->
- The module is already safe to import inside the Workflow sandbox — it does not reach for `fs`, `http`, or DOM APIs at import time. <!-- docs/develop/typescript/workflows/basics.mdx:121-128 -->

Do **not** use `preloadModules` to:

- Make a Node.js-dependent module usable inside Workflows. It cannot. Use Activities for I/O, as documented. <!-- docs/develop/typescript/workflows/basics.mdx:132-135 -->
- Substitute for `workflowBundle`. Preloading is a per-context optimization; the production startup win still comes from pre-building the bundle ahead of time. <!-- docs/develop/typescript/workers/run-process.mdx:204-249 -->

## How to set it

`preloadModules` is a `bundlerOptions` field, so it is configured wherever bundler options are passed — either inline on `Worker.create` (development) or on the build-time call to `bundleWorkflowCode` (production). <!-- VERIFY: typescript.temporal.io/api/interfaces/worker.BundleOptions for the exact field shape (string[] vs. richer object). -->

**Development (bundling at Worker startup):**

```ts
import { Worker } from '@temporalio/worker';
import * as activities from './activities';

const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities,
  taskQueue: 'my-task-queue',
  bundlerOptions: {
    // VERIFY shape: the topic description says this is a bundler option
    // that accepts module names; cross-check on
    // typescript.temporal.io/api/interfaces/worker.BundleOptions.
    preloadModules: ['my-large-validator', './internal/codecs'],
  },
});
```

<!-- docs/develop/typescript/workers/run-process.mdx:184-200 for the surrounding Worker.create shape; preloadModules itself: VERIFY -->

**Production (pre-built bundle):**

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';
import path from 'path';

async function bundle() {
  const { code } = await bundleWorkflowCode({
    workflowsPath: require.resolve('../workflows'),
    // VERIFY: typescript.temporal.io/api/ for whether preloadModules sits
    // at the top level of BundleOptions or nested under bundlerOptions
    // when called via bundleWorkflowCode (vs. via Worker.create).
    preloadModules: ['my-large-validator', './internal/codecs'],
  });
  const codePath = path.join(__dirname, '../../workflow-bundle.js');
  await writeFile(codePath, code);
}
```

<!-- docs/develop/typescript/workers/run-process.mdx:209-223 for the surrounding bundleWorkflowCode shape; preloadModules itself: VERIFY -->

The Worker then loads that pre-built bundle in production exactly as it does without preloading:

```ts
const worker = await Worker.create({
  workflowBundle: { codePath: require.resolve('../workflow-bundle.js') },
  activities,
  taskQueue: 'production-sample',
});
```

<!-- docs/develop/typescript/workers/run-process.mdx:228-249 -->

`bundleWorkflowCode` uses Temporal's Webpack settings to produce the bundle, so any module listed in `preloadModules` must be Webpack-resolvable from the workflow entrypoint. <!-- docs/develop/typescript/best-practices/debugging.mdx:90-91 --> Modules that resolve at runtime but not at bundle time (for example, `node:`-prefixed builtins, which already need extra Webpack config to handle) <!-- references/typescript/determinism-protection.md:28 --> will surface as Webpack errors rather than runtime errors.

## Interaction with plugins

`bundleWorkflowCode` also takes a `plugins:` array used by Workflow interceptors and plugin authors. <!-- docs/develop/plugins-guide.mdx:875-890 --> A plugin and a preloaded module both end up in the same workflow bundle; if a plugin re-exports or already imports the modules you would otherwise list in `preloadModules`, listing them again is redundant but not contradictory. <!-- VERIFY: typescript.temporal.io/api/ -->

## What it does not change

- **Sandbox rules.** Preloaded modules still execute under the V8 sandbox. Node and DOM API access is still blocked, deterministic replacements (`Math.random`, `Date`, `setTimeout`) still apply, and `FinalizationRegistry` / `WeakRef` are still removed. <!-- docs/develop/typescript/workflows/basics.mdx:121-128 --> <!-- references/typescript/determinism-protection.md:32-55 -->
- **Replay determinism.** Workflows must still be deterministic; preloading does not change history replay semantics. See `references/core/determinism.md`.
- **Cache size and slot counts.** `maxCachedWorkflows`, `maxConcurrentWorkflowTaskExecutions`, and the other tuning knobs documented at `docs/develop/worker-tuning-reference.mdx` are independent of preloading. <!-- docs/develop/worker-tuning-reference.mdx:60-77,96-103 -->
- **`workflowBundle` requirement for production.** You still want a pre-built bundle in production for fast Worker startup; preloading is layered on top of that, not a replacement for it. <!-- docs/develop/typescript/workers/run-process.mdx:202-249 -->

## Gotchas

1. **Don't list a module in both `preloadModules` and `ignoreModules`.** The intents conflict and the resulting Worker behavior is unspecified by the local docs. <!-- VERIFY: typescript.temporal.io/api/ -->
2. **Don't preload modules with import-time side effects that touch Node/DOM APIs.** They will fail under the sandbox just as they would on lazy import. <!-- docs/develop/typescript/workflows/basics.mdx:121-128 -->
3. **Don't expect a default.** The local docs do not state a default value for `preloadModules`. If your Worker config relies on "no preloads when unset", confirm against the API reference. <!-- VERIFY: typescript.temporal.io/api/interfaces/worker.BundleOptions -->
4. **Don't preload as a fix for slow first task.** Profile first. The slow first task may be Workflow code, an Activity round-trip, or sandbox compilation — none of which preloading addresses.

## See also

- `references/typescript/determinism-protection.md` — V8 sandbox rules, `ignoreModules`, function replacements.
- `references/typescript/advanced-features.md` — Worker tuning (`maxConcurrentWorkflowTaskExecutions`, `maxCachedWorkflows`).
- `docs/develop/typescript/workers/run-process.mdx` — full `bundleWorkflowCode` / `workflowBundle` flow.
- `docs/develop/worker-tuning-reference.mdx` — `reuseV8Context` and other TypeScript-SDK defaults.
- `typescript.temporal.io/api/interfaces/worker.BundleOptions` — canonical `BundleOptions` field list (eventual ground truth for `preloadModules`).
