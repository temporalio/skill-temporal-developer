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

### Preloading Modules

`bundlerOptions.preloadModules` is a sibling of `ignoreModules` on the same `BundleOptions` interface.   Where `ignoreModules` *excludes* a module from the workflow bundle, `preloadModules` *eagerly evaluates* one into the V8 workflow context so the load cost is paid once per Worker rather than once per workflow execution.

This is only meaningful when the Worker reuses its V8 context across workflows — i.e., when `reuseV8Context` is enabled.

Like `ignoreModules`, `preloadModules` is a **bundler-time** option: it applies when the Worker is built from `workflowsPath`, not when it consumes a pre-built `workflowBundle`. If you ship a production Worker by pre-building with `bundleWorkflowCode` and loading the bundle via `workflowBundle: { codePath }` (`docs/develop/typescript/workers/run-process.mdx:228–249`), set `preloadModules` on the `bundleWorkflowCode` call at build time — not on the Worker that loads the bundle.

```ts
// Same Worker shape as the `ignoreModules` example above. `preloadModules`
// is an additional, separately-documented field on `bundlerOptions`.
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities: require('./activities'),
  taskQueue: 'my-task-queue',
  reuseV8Context: true,
  bundlerOptions: {
    ignoreModules: ['fs'],
    // preloadModules: <see VERIFY note above — local docs/ clone does not document the value shape>
  },
});
```

`preloadModules` does **not** bypass the V8 sandbox or the determinism replacements described below — a preloaded module still cannot escape the sandbox.

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
