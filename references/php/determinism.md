# PHP SDK Determinism

PHP has no workflow determinism sandbox. Replay reconstructs state by matching commands against recorded history; it cannot prove that every PHP computation is pure. See [core replay concepts](../core/determinism.md).

| In workflow code | Use instead |
| --- | --- |
| DB/ORM, HTTP, files, external services | Activities |
| `sleep()` / `usleep()` | `yield Workflow::timer(...)` |
| Wall-clock `time()`, `microtime()`, `Carbon::now()` | `Workflow::now()` |
| Random UUID generation | `yield Workflow::uuid()` (check newer UUID APIs against the SDK) |
| Small random/computed external value | `yield Workflow::sideEffect(fn() => random_int(...))` |
| Mutable globals, environment-dependent branching | Explicit input or Activity-provided recorded data |

`sideEffect()` records a returned value. Do not put a payment, notification, arbitrary DB write or a change to workflow fields in its callback; replay skips that callback. Use its yielded result. `Workflow::now()` is synchronous, while UUID, timer, sideEffect, getVersion and Continue-As-New APIs return promises. Predicates passed to `Workflow::await()`/`awaitWithTimeout()` must re-evaluate state, not capture a boolean already evaluated once.

A method containing `yield` must return a generator-compatible PHP type, regardless of the final serialized result. Waiting on an Activity does not block a PHP thread for its entire duration, but a blocking call inside workflow code stalls the worker's event loop and can exceed Workflow Task timeouts.

Changes to command sequence require [versioning](versioning.md). Replay checks do not compare every ordinary variable, Activity input or timer duration; replay testing is compatibility evidence for the supplied histories, not a universal side-effect detector. Pair [recorded-history replay](testing.md) with code review and outcome tests. Use `Workflow::getLogger()` for replay-aware logging.

Source: [PHP Workflow facade](https://github.com/temporalio/sdk-php/blob/v2.18/src/Workflow.php).
