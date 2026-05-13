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

## Preloading Modules into the Reusable V8 Context

`bundlerOptions.preloadModules` is a list of module specifiers that the bundler eagerly `require()`s once during reusable V8 context bootstrap, before any workflow activator exists. The modules land in the shared module cache and are reused by every workflow that runs in that V8 context.

**Precondition:** preloading is only beneficial when `reuseV8Context` is enabled. `reuseV8Context` defaults to `true`, so this option is a no-op if you have explicitly disabled it.

**Where the option lives.** Same camel-case spelling, two call sites:

When using `workflowsPath` (the bundler runs at Worker startup), set it under `bundlerOptions`:

```ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities: require('./activities'),
  taskQueue: 'my-task-queue',
  bundlerOptions: {
    // Loaded once per reusable V8 context, shared across all workflows in that context
    preloadModules: ['lodash', './workflow-shared/constants'],
  },
});
```

When pre-bundling with `bundleWorkflowCode` (the recommended production path), it is a top-level option on `BundleOptions`:

```ts
import { bundleWorkflowCode } from '@temporalio/worker';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  preloadModules: ['lodash', './workflow-shared/constants'],
});
```

The Worker then runs the prebuilt bundle via `workflowBundle: { codePath: ... }`; the preload list is baked into the bundle's entrypoint, so the Worker does not need to repeat it.

### When NOT to preload

Module scope for a preloaded module runs **before any workflow activator exists**. That means anything the module captures at import time — counters, caches, singleton handles, registry maps keyed by workflow id — is shared across every workflow that subsequently runs in that V8 context.

Do not preload a module if any of the following are true:

- It allocates per-workflow state at top level (counters, request id maps, registries).
- It depends on globals that the workflow sandbox sets up per workflow (e.g. the workflow activator, `Math.random`'s seed, `Date`'s clock).
- It has import-time side effects you only want to pay per workflow.

The SDK's own warning is explicit: "Preloading modules that internally stores some form of per-workflow state will very likely cause workflow context leak, which may result in non-deterministic behavior and/or cause other unexpected behaviors."

### Overlap with `ignoreModules` is rejected

A module specifier may not appear in both `preloadModules` and `ignoreModules`; the bundler throws at construction time with `Cannot preload modules that are also ignored: '<module>'`.

```ts
// Throws: Cannot preload modules that are also ignored: 'fs'
bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  ignoreModules: ['fs'],
  preloadModules: ['fs'],
});
```

`preloadModules` is **not** related to `workflowInterceptorModules`. Interceptor modules are loaded through the interceptor registration pathway; `preloadModules` is for arbitrary user modules whose initialization you want to pay once and share.

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
