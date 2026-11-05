# PHP SDK Determinism

## Overview

The PHP SDK has **no sandbox**. Nothing stops Workflow code from calling `time()`, `rand()`, `file_get_contents()` or a database. Determinism is the responsibility of the developer. The SDK gives deterministic replacements, a guard against commands from read-only callbacks, and the `WorkflowReplayer` for replay tests.

## Why Determinism Matters: History Replay

Temporal re-executes Workflow code on recovery and matches its commands against the recorded history. See [Temporal determinism rules](../core/determinism.md) for a deep explanation.

## SDK Protection

The SDK does not detect forbidden PHP functions. A non-deterministic call is found only when replay produces a different command. See [determinism protection](determinism-protection.md) for the read-only callback guard and the panic policy.

## Forbidden Operations in Workflows

- `sleep()`, `usleep()` - block the worker event loop
- `time()`, `microtime()`, `new \DateTime()`, `Carbon::now()` - wall-clock time
- `rand()`, `mt_rand()`, `random_int()`, `uniqid()` - non-deterministic values
- File, network and database I/O, including ORM lazy loading
- `getenv()`, `$_ENV`, mutable static state - values can change between runs
- `echo`, `print`, `var_dump()` - the output repeats on replay

## Safe Builtin Alternatives to Common Non Deterministic Things

| Forbidden | Safe Alternative |
| -- | -- |
| `sleep($n)` | `yield Workflow::timer($n)` |
| `time()` / `new \DateTime()` | `Workflow::now()` (returns `\DateTimeInterface`) |
| `random_int(1, 100)` | `yield Workflow::sideEffect(fn() => random_int(1, 100))` |
| `Uuid::uuid4()` | `yield Workflow::uuid()` / `yield Workflow::uuid4()` |
| `Uuid::uuid7()` | `yield Workflow::uuid7()` |
| `$logger->info()` / `echo` | `Workflow::getLogger()->info(...)` |
| DB query / HTTP call | An Activity |

`Workflow::now()`, `allHandlersFinished()` and the Search Attribute and Memo upserts are synchronous: do not `yield` them. `timer()`, `sideEffect()`, `uuid()`, `uuid4()`, `uuid7()`, `getVersion()` and `continueAsNew()` return promises: use `yield`.

Replay does not run the `sideEffect()` callback: it uses the recorded value. Do not do I/O, payments, or changes to Workflow properties in the callback. Use only its yielded result.

## Testing Replay Compatibility

Use `Temporal\Testing\Replay\WorkflowReplayer` to replay recorded histories against the current code. See the [testing guide](testing.md#workflow-replay-testing) for details.

```php
use Temporal\Testing\Replay\WorkflowReplayer;

(new WorkflowReplayer())->replayFromJSON('Order', __DIR__ . '/histories/order.json');
```

## Best Practices

- Use `Workflow::now()`, `timer()`, `sideEffect()`, `uuid()` and `getLogger()` instead of the PHP equivalents.
- Delegate all I/O, network calls, and side effects to Activities.
- Do not branch on environment variables or configuration that can change. Pass them as Workflow input.
- Run replay tests against saved histories before you deploy Workflow changes.
