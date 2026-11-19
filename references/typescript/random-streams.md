# TypeScript SDK Workflow Random Streams

> [!NOTE]
> This feature is Experimental. It is acceptable to use it on behalf of a user, but inform them that the API may change.

Requires TypeScript SDK v1.18.0 or later. See `references/core/random-streams.md` for concepts.

## API

`@temporalio/workflow` exports:

- `getRandomStream(name)`: returns a named `WorkflowRandomStream`, derived from the Workflow seed without consuming the default `Math.random()` stream.
- `workflowRandom`: the default stream, the same sequence `Math.random()` uses.

A `WorkflowRandomStream` has:

| Method | Returns |
|--------|---------|
| `random()` | Next number in `[0, 1)`, like `Math.random()` |
| `uuid4()` | A deterministic UUIDv4 string |
| `fill(bytes)` | The given `Uint8Array`, filled with random bytes |
| `with(fn)` | The result of `fn`, with `Math.random()` and `uuid4()` routed through this stream while `fn` runs |

## Explicit draws

Prefer calling the stream's methods directly.

```typescript
import { getRandomStream } from '@temporalio/workflow';

const IDS_STREAM = '@example/my-plugin/ids';

export async function myWorkflow(): Promise<string> {
  const stream = getRandomStream(IDS_STREAM);
  const id = stream.uuid4();
  const jitterMs = Math.floor(stream.random() * 1000);
  const nonce = stream.fill(new Uint8Array(16));
  return id;
}
```

## Scoped override

Use `with(fn)` when existing code calls `Math.random()` or `uuid4()` and must not consume the Workflow's default stream. The override follows async continuations started by `fn`.

```typescript
import { getRandomStream } from '@temporalio/workflow';

const stream = getRandomStream('@example/my-plugin/sampling');
const sample = stream.with(() => pickRandomSubset(items)); // pickRandomSubset calls Math.random()
```

## Instead of

- `crypto.randomUUID()` or other entropy sources in Workflow code: these are non-deterministic.
- A hand-rolled PRNG seeded from `workflowInfo()`: use `getRandomStream` instead.
- Library or plugin code drawing from `Math.random()`: this shifts the application's random values. Give the library its own named stream.
