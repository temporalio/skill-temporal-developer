# Workflow Random Streams

> [!NOTE]
> This feature is Experimental. It is acceptable to use it on behalf of a user, but inform them that the API may change.

## What this is

A Workflow random stream is a deterministic pseudorandom source that the SDK provides to Workflow code. Each stream has a caller-chosen name. The SDK seeds it for the current Workflow Execution, so replay produces the same values in the same order.

Named streams are independent of each other and of the Workflow's default random source. Drawing from one stream never shifts the values another stream returns.

## When to use it

- A plugin, interceptor, or library needs replay-safe random values without changing the random values the application Workflow code sees.
- Separate components of a Workflow need random values that must not shift when another component adds or removes draws.
- Workflow code needs many random values (shuffles, sampling, tie-breaking, IDs) and recording each one with a Side Effect would bloat Event History.

For a single random value in application code, the SDK's default deterministic random helpers are enough. See `references/{your_language}/determinism.md`.

## SDK support

| SDK | API | Minimum version |
|-----|-----|-----------------|
| Go | `workflow.GetRandomStream(ctx, name)` | v1.48.0 |
| TypeScript | `getRandomStream(name)` from `@temporalio/workflow` | v1.18.0 |

Use the SDK API. Do not build your own seeded PRNG from Workflow ID or Run ID in its place.

## Rules

- **Use a stable, unique name.** Prefix it with your package or module path, for example `example.com/myplugin/ids`. Changing a stream's name changes its values, which breaks replay of open Workflows.
- **Same name, same stream.** Calling the API again with the same name returns the same stream, positioned where earlier draws left it.
- **Draws are not recorded in history.** Each draw advances Workflow state, so replay must make the same draws in the same order. Adding, removing, or reordering draws in running Workflows needs versioning; see `references/core/versioning.md`.
- **Workflow code only.** Activities are not replayed and can use ordinary randomness.

## Language guides

- Go: `references/go/random-streams.md`
- TypeScript: `references/typescript/random-streams.md`
