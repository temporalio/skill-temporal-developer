# PHP Gotchas

1. **Direct PHP worker startup:** RoadRunner must launch the entrypoint; use `rr serve` with the matching configuration. See [quickstart](php.md).
2. **Generator return declarations:** A method with `yield` cannot return `string` or `void` in PHP. `#[ReturnType]` describes the serialized workflow result separately.
3. **Forgetting a join:** Collect promises for concurrent work, then yield their join. Returning after scheduling a notification does not ensure it completes. `Workflow::uuid()` also requires `yield`.
4. **Awaiting a boolean:** Use `yield Workflow::await(fn() => Workflow::allHandlersFinished())`, not the already evaluated result of `allHandlersFinished()`.
5. **Lost Signals:** Clearing a shared buffer after yielding can erase messages received during the wait. Snapshot/reset before yielding; preserve pending data across Continue-As-New. See [patterns](patterns.md).
6. **Reusing Update ID for every change:** Use an ID per logical request; retry that request with the same ID. StageAccepted is not StageCompleted.
7. **Compensation after cancellation:** A handwritten `finally` remains in the cancelled scope. Use detached cleanup and await it. SDK `Saga::compensate()` already uses detached scopes.
8. **Heartbeat misconceptions:** Set HeartbeatTimeout for heartbeat-based failure detection; checkpoint completed work, resume from persisted details and remain idempotent. Heartbeats may be throttled and do not reset Start-To-Close. See [errors/timeouts](error-handling.md).
9. **Unbounded batches:** Limit page size, in-flight promises, retained results and history independently. More Activity workers do not bound workflow memory. See [batch processing](batch-processing.md).
10. **Long-lived services:** Shared Activity instances, static caches and ORM identity maps can retain both memory and tenant state. Reset per-invocation resources and measure RSS separately from PHP allocations. See [workers](workers.md).
11. **Fake means replay-safe:** Dispatch fakes are not recorded-history replay; real message/timer tests also require a worker and the correct server. See [testing](testing.md).
12. **Copying another SDK's APIs:** Verify namespace, method signature and locked version. Examples involving converters, completion tokens, deployment options and testing lifecycle are especially easy to mistranslate.
13. **Treating samples as production code:** Preserve the demonstrated concept while reviewing idempotency, cancellation, workflow IDs, payloads, source versions and unfinished paths. See [source assessment](sources.md).
