# TypeScript Workflow Bundler — `preloadModules`

## Overview

`preloadModules` is a TypeScript workflow bundler option. Modules listed in it are loaded **once** during reusable V8 context bootstrap, and their module-scope side effects are shared across every workflow that runs in that same V8 context. <!-- sdk-typescript: packages/worker/src/workflow/bundler.ts -->

The option is only beneficial when `reuseV8Context` is enabled — which is the default for the TypeScript SDK. <!-- sdk-typescript: packages/worker/src/worker-options.ts (reuseV8Context default true) -->

Use it for heavy, stateless modules whose initialization cost you don't want to pay on every workflow instance.

## How to pass it

There are two surfaces that accept `preloadModules`:

### 1. To `bundleWorkflowCode` (pre-bundled, production path)

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';
import path from 'path';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('../workflows'),
  preloadModules: ['./shared/schema-registry', './shared/protobuf-types'],
});

await writeFile(path.join(__dirname, '../../workflow-bundle.js'), code);
```

The bundle that `bundleWorkflowCode` produces exposes the preloaded modules through a generated `preloadModules` entry that the worker invokes during V8 context bootstrap. <!-- sdk-typescript: packages/worker/src/workflow/bundler.ts (exports.preloadModules) -->

### 2. To `Worker.create` via `bundlerOptions` (runtime bundling path)

```ts
const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities,
  taskQueue: 'my-task-queue',
  bundlerOptions: {
    preloadModules: ['./shared/schema-registry'],
  },
});
```

`bundlerOptions` only takes effect when the worker bundles at runtime — i.e. when you pass `workflowsPath`. It is **ignored** when you pass a pre-built `workflowBundle`; in that case preload the modules at build time by passing `preloadModules` to `bundleWorkflowCode` instead. (See `references/typescript/determinism-protection.md` for the same caveat applied to `ignoreModules`.)

## Validation: mutually exclusive with `ignoreModules`

A module cannot appear in both `preloadModules` and `ignoreModules`. The bundler throws at build time:

```
Cannot preload modules that are also ignored: '<module-name>'
```

<!-- sdk-typescript: packages/worker/src/workflow/bundler.ts (bundler constructor validation) -->

## When to use it

Preload modules whose module-scope work is **deterministic, expensive, and shareable**:

- Schema registries / protobuf-type loaders that parse `.proto` files at import time.
- JSON-schema or zod compilers that pre-compile validators on module load.
- Lookup tables or computed constants that take measurable time to build.

The win: that work happens once per V8 context instead of once per cached workflow.

## When **not** to use it

Per the SDK source's own warning: "Preloading modules that internally store some form of per-workflow state will very likely cause workflow context leak, which may result in non-deterministic behavior and/or cause other unexpected behaviors." <!-- sdk-typescript: packages/worker/src/workflow/bundler.ts (preloadModules JSDoc) -->

Specifically, do **not** preload:

- Modules that capture or memoize anything keyed on a particular workflow.
- Modules whose top-level code reads `workflowInfo()`, `proxyActivities`, sinks, or anything else that requires a workflow activator — those APIs don't exist at bootstrap time.
- Modules that mutate shared singletons during normal operation.

State written into a preloaded module is visible to every workflow sharing the V8 context. That is exactly the kind of cross-workflow leak that produces non-determinism on replay.

## Relationship to `reuseV8Context`

`reuseV8Context` defaults to `true`. <!-- sdk-typescript: packages/worker/src/worker-options.ts (@default true) --> If you have explicitly turned it off, `preloadModules` is a no-op — there is no shared context to preload into. The SDK source recommends leaving `reuseV8Context` on; it cites roughly 2/3 memory reduction and 1/3–1/2 CPU reduction from internal stress tests. <!-- sdk-typescript: packages/worker/src/worker-options.ts (reuseV8Context JSDoc) -->

## Quick checklist

- [ ] The module's top-level code is pure (no I/O, no state mutation tied to a workflow).
- [ ] The module does not import `@temporalio/workflow` APIs that require an activator.
- [ ] The module appears in neither your `ignoreModules` list nor your workflow's runtime import graph in a way that depends on it being absent.
- [ ] If you ship a pre-built bundle, you passed `preloadModules` to `bundleWorkflowCode`, not to `Worker.create`'s `bundlerOptions`.
