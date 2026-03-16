# PHP SDK Determinism

## Overview

The PHP SDK does NOT have a sandbox like Python or TypeScript. There is no automatic enforcement of determinism — the developer must be disciplined. The SDK provides runtime command-ordering checks only.

## Why Determinism Matters: History Replay

Temporal provides durable execution through **History Replay**. When a Worker needs to restore workflow state (after a crash, cache eviction, or to continue after a long timer), it re-executes the workflow code from the beginning, which requires the workflow code to be **deterministic**.

See `references/core/determinism.md` for the full explanation.

## SDK Protection / Runtime Checking

The PHP SDK performs runtime checks that detect adding, removing, or reordering calls to:

- `ExecuteActivity()`
- `ExecuteChildWorkflow()`
- `NewTimer()`
- `RequestCancelWorkflow()`
- `SideEffect()`
- `SignalExternalWorkflow()`
- `Sleep()`

**This is NOT a thorough check** — it does not verify arguments or timer durations. Non-determinism that doesn't reorder commands will go undetected. Use replay testing to catch subtler issues.

## Forbidden Operations

These must NOT be used in workflow code:

- No direct I/O: `fopen()`, `file_get_contents()`, `curl_*`, PDO, etc.
- No `sleep()` — use `yield Workflow::timer(new \DateInterval('PT10S'))`
- No `time()`, `date()`, `microtime()` — use `Workflow::now()`
- No `rand()`, `random_int()`, `uniqid()` — use `yield Workflow::sideEffect()`
- No blocking SPL functions
- No mutable global state

## Testing Replay Compatibility

Use the `WorkflowReplayer` class to verify your code changes are compatible with existing histories. See the Workflow Replay Testing section of `references/php/testing.md`.

## Best Practices

1. Use `Workflow::now()` for all time and date operations
2. Use `yield Workflow::sideEffect()` for any non-deterministic values
3. Delegate all I/O to activities
4. Test with `WorkflowReplayer` to catch non-determinism
5. Use `Workflow::getLogger()` instead of `error_log()` for replay-safe logging
