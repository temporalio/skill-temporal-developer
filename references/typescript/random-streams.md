# TypeScript — Workflow Random Streams

## Context

In the TypeScript SDK, the workflow sandbox replaces Math.random() with a deterministic implementation and provides uuid4() from @temporalio/workflow. This lets you rely on randomness during replay. For isolation, create deterministic named streams rather than using the shared Math.random().

## Helper: FNV-1a hash and mulberry32 PRNG

~~~ts
// Minimal FNV-1a 32-bit hash for strings
export function fnv1a32(input: string): number {
  let h = 0x811c9dc5 >>> 0;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

// Mulberry32 PRNG: returns a closure with .next() in [0,1)
export function mulberry32(seed: number): () => number {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6D2B79F5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

export type RNG = {
  rand: () => number;              // [0,1)
  int: (min: number, max: number) => number; // inclusive min..max
  shuffle: <T>(a: T[]) => T[];
};

export function makeNamedRng(seedStr: string): RNG {
  const seed = fnv1a32(seedStr);
  const next = mulberry32(seed);
  const int = (min: number, max: number) => {
    const lo = Math.ceil(min);
    const hi = Math.floor(max);
    return Math.floor(next() * (hi - lo + 1)) + lo;
  };
  const shuffle = <T>(a: T[]) => {
    const out = a.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(next() * (i + 1));
      [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
  };
  return { rand: next, int, shuffle };
}
~~~

## Derive a deterministic seed string

Use only deterministic inputs available in workflows. For example, combine a stream name with workflow identity:

~~~ts
import { workflowInfo } from '@temporalio/workflow';

export function streamKey(name: string, scope: 'workflow'|'run' = 'workflow'): string {
  const info = workflowInfo();
  const base = ;
  return scope === 'run' ?  : ;
}
~~~

## Usage

~~~ts
import { makeNamedRng, streamKey } from './rng';

export async function MyWorkflow(): Promise<void> {
  // App-local stream: stable for this Workflow ID across retries
  const appRng = makeNamedRng(streamKey('app-default', 'workflow'));

  // Library stream: isolate a plugin
  const pluginRng = makeNamedRng(streamKey('plugin:ranker', 'run'));

  const choice = appRng.int(1, 10);
  const shuffled = pluginRng.shuffle(['a','b','c','d']);
  // ...
}
~~~

Notes
- No Node modules are used; code runs in the sandbox.
- Changing fnv1a32 or mulberry32 changes sequences; version such changes deliberately.

## Related

- Concept: references/core/random-streams.md
# TypeScript — Workflow Random Streams

## Context

In the TypeScript SDK, the workflow sandbox replaces `Math.random()` with a deterministic implementation and provides `uuid4()` from `@temporalio/workflow`. This lets you rely on randomness during replay. For isolation, create deterministic named streams rather than using the shared `Math.random()`.

## Helper: FNV-1a hash and mulberry32 PRNG

```ts
// Minimal FNV-1a 32-bit hash for strings
export function fnv1a32(input: string): number {
  let h = 0x811c9dc5 >>> 0;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

// Mulberry32 PRNG: returns a closure with .next() in [0,1)
export function mulberry32(seed: number): () => number {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6D2B79F5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

export type RNG = {
  rand: () => number;              // [0,1)
  int: (min: number, max: number) => number; // inclusive min..max
  shuffle: <T>(a: T[]) => T[];
};

export function makeNamedRng(seedStr: string): RNG {
  const seed = fnv1a32(seedStr);
  const next = mulberry32(seed);
  const int = (min: number, max: number) => {
    const lo = Math.ceil(min);
    const hi = Math.floor(max);
    return Math.floor(next() * (hi - lo + 1)) + lo;
  };
  const shuffle = <T>(a: T[]) => {
    const out = a.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(next() * (i + 1));
      [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
  };
  return { rand: next, int, shuffle };
}
```

## Derive a deterministic seed string

Use only deterministic inputs available in workflows. For example, combine a stream name with workflow identity:

```ts
import { workflowInfo } from '@temporalio/workflow';

export function streamKey(name: string, scope: 'workflow'|'run' = 'workflow'): string {
  const info = workflowInfo();
  const base = `${info.workflowId}`;
  return scope === 'run' ? `${base}/${info.runId}/${name}` : `${base}/${name}`;
}
```

## Usage

```ts
import { makeNamedRng, streamKey } from './rng';

export async function MyWorkflow(): Promise<void> {
  // App-local stream: stable for this Workflow ID across retries
  const appRng = makeNamedRng(streamKey('app-default', 'workflow'));

  // Library stream: isolate a plugin
  const pluginRng = makeNamedRng(streamKey('plugin:ranker', 'run'));

  const choice = appRng.int(1, 10);
  const shuffled = pluginRng.shuffle(['a','b','c','d']);
  // ...
}
```

Notes
- No Node modules are used; code runs in the sandbox.
- Changing `fnv1a32` or `mulberry32` changes sequences; version such changes deliberately.

## Related

- Concept: references/core/random-streams.md
- Determinism basics: ../documentation/docs/develop/typescript/workflows/basics.mdx
- Determinism basics: ../documentation/docs/develop/typescript/workflows/basics.mdx
