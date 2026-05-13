# TypeScript Workflow V8 Sandboxing

## Overview

The TypeScript SDK runs workflows in a V8 sandbox that provides automatic protection against non-deterministic operations, and replaces common non-deterministic function calls with deterministic variants.

## Import Blocking

The sandbox blocks imports of `fs`, `https` modules, and any Node/DOM APIs. Otherwise, workflow code can import any package as long as it does not reference Node.js or DOM APIs.

**Note**: If you must use a library that references a Node.js or DOM API and you are certain that those APIs are not used at runtime, add that module to the `ignoreModules` list:

```ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'), // bundlerOptions only apply with workflowsPath
  activities: require('./activities'),
  taskQueue: 'my-task-queue',
  bundlerOptions: {
    // These modules may be imported (directly or transitively),
    // but will be excluded from the Workflow bundle.
    ignoreModules: ['fs', 'http', 'crypto'],
  },
});
```

**Important**: Excluded modules are completely unavailable at runtime. Any attempt to call functions from these modules will throw an error. Only exclude modules when you are certain the code paths using them will never execute during workflow execution.

**Note**: Modules with the `node:` prefix (e.g., `node:fs`) require additional webpack configuration to ignore. You may need to configure the bundler's `externals` or use webpack `resolve.alias` to handle these imports.

Use this with *extreme caution*.

## Preloading Modules into Reusable V8 Contexts

The bundler accepts a `preloadModules?: string[]` option that loads selected modules **once** during reusable V8 context bootstrap, so their module scope (top-level code, exported state) is shared across every workflow that runs in that context. <!-- sdk: packages/worker/src/workflow/bundler.ts BundleOptions.preloadModules -->

**Only beneficial when `reuseV8Context` is enabled** (which is the default `true`). <!-- sdk: packages/worker/src/worker-options.ts WorkerOptions.bundlerOptions.preloadModules JSDoc; reuseV8Context default --> Without context reuse, each workflow gets a fresh VM and there is nothing to share into.

### Why preload

Without `preloadModules`, every workflow that imports a module re-evaluates that module's top-level scope inside its own per-workflow context. For heavy modules (large constant tables, expensive schema construction, big lookup maps), this multiplies cost across workflows. Preloading evaluates the module **once** and reuses the result. <!-- sdk: packages/worker/src/workflow/bundler.ts BundleOptions.preloadModules JSDoc -->

### Where to set it

`preloadModules` is on the **bundler**, not on `Worker.create` directly. There are two call sites:

**Path A — pre-built bundle (production):** pass it to `bundleWorkflowCode`, which accepts `BundleOptions`. <!-- sdk: packages/worker/src/workflow/bundler.ts bundleWorkflowCode signature -->

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  preloadModules: ['./workflows/shared-lookup-table'],
});
await writeFile('./workflow-bundle.js', code);
```

Then pass the bundle to `Worker.create` via `workflowBundle.codePath` as usual. <!-- docs/develop/typescript/workers/run-process.mdx -->

**Path B — runtime bundling (development):** use `workflowsPath` and pass `preloadModules` through `bundlerOptions`. <!-- sdk: packages/worker/src/worker-options.ts WorkerOptions.bundlerOptions -->

```ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  taskQueue: 'my-task-queue',
  activities,
  bundlerOptions: {
    preloadModules: ['./workflows/shared-lookup-table'],
  },
});
```

**`bundlerOptions` is ignored when `workflowBundle` is supplied** — for a pre-built bundle, `preloadModules` must be specified at `bundleWorkflowCode` time, not at `Worker.create` time. <!-- sdk: packages/worker/src/worker-options.ts JSDoc on workflowBundle / bundlerOptions -->

### Safe to preload vs. unsafe to preload

The module's top-level code runs **before a workflow activator exists**, so the module cannot reference any workflow-scoped API at load time. <!-- sdk: packages/worker/src/workflow/bundler.ts BundleOptions.preloadModules JSDoc -->

**Safe** (stateless, pure):

- Constant tables, lookup maps, frozen objects.
- Pure utility functions that don't close over mutable state.
- Schema definitions (e.g., a stateless validator instance constructed at module load).

**Unsafe** (will cause workflow state leakage):

- Any module that mutates module-level variables during workflow execution. The mutations persist into the next workflow that runs in the same V8 context.
- Modules that cache per-workflow data (e.g., a memoization cache keyed by anything other than the workflow's own arguments).
- Modules that hold connections, timers, or other side-effecting handles.

The JSDoc warning is explicit: "Preloading modules that internally stores some form of per-workflow state will very likely cause workflow context leak, which may result in non-deterministic behavior and/or cause other unexpected behaviors." <!-- sdk: packages/worker/src/workflow/bundler.ts BundleOptions.preloadModules JSDoc -->

A minimal demonstration of the leak: if you preload a module containing `let counter = 0; export function next() { counter += 1; return counter; }` and two workflows each call `next()` once, they get `1` and `2` (shared state), not `1` and `1` (isolated state). <!-- sdk: packages/test/src/test-bundler.ts 'Workflow bundle can preload modules into the reusable V8 context' and 'Workflow bundle keeps module state isolated without preloadModules' --> That difference is exactly the kind of leak you must avoid.

### Constraints and errors

- **Module specifiers are strings**, the same form you would pass to `require()` (a package name, a bare module name, or a path resolvable from the workflow bundle's entrypoint). <!-- sdk: packages/worker/src/workflow/bundler.ts genEntrypoint emits `require(/* webpackMode: "eager" */ '<module>')` -->
- **`preloadModules` and `ignoreModules` are mutually exclusive.** If any preloaded module overlaps with any ignored module (by exact match OR by prefix-with-slash — `lodash` matches `lodash/map`), the bundler throws at construction time: `Cannot preload modules that are also ignored: '<module>'`. <!-- sdk: packages/worker/src/workflow/bundler.ts WorkflowCodeBundler constructor validation; moduleMatches -->
- **`preloadModules` has no documented default value.** It is optional; omitting it (or passing `[]`) is a no-op. <!-- sdk: packages/test/src/test-bundler.ts 'Workflow bundle treats an empty preloadModules list as a no-op' -->
- **Use sparingly.** Like `ignoreModules`, this is an advanced option. The JSDoc labels it: "an advanced option that should be used with care." <!-- sdk: packages/worker/src/workflow/bundler.ts BundleOptions.preloadModules JSDoc -->

## Function Replacement

Functions like `Math.random()`, `Date`, and `setTimeout()` are replaced by deterministic versions.

Date-related functions return the timestamp at which the current workflow task was initially executed. That timestamp remains the same when the workflow task is replayed, and only advances when a durable operation occurs (like `sleep()`). For example:

```ts
import { sleep } from '@temporalio/workflow';

// this prints the *exact* same timestamp repeatedly
for (let x = 0; x < 10; ++x) {
  console.log(Date.now());
}

// this prints timestamps increasing roughly 1s each iteration
for (let x = 0; x < 10; ++x) {
  await sleep('1 second');
  console.log(Date.now());
}
```

Generally, this is the behavior you want.

Additionally, `FinalizationRegistry` and `WeakRef` are removed because v8's garbage collector is not deterministic.
