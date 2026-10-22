# Laravel Temporal (keepsuit)

Use when the application already uses Laravel or the user asks for this integration. It is a community package, not a prerequisite for PHP Temporal. Reviewed source: [0173907](https://github.com/keepsuit/laravel-temporal/tree/0173907640765f13f4e8e9ad2a970f5db4f4b1fd). That snapshot requires PHP ^8.2, Laravel components ^11/^12/^13 and SDK **~2.17.0**. The course instead locks integration **2.2.1**, Laravel **12.51.0**, SDK **2.16.0**. Do not force SDK 2.18 into a package whose constraint excludes it.

## Bootstrapping and discovery

```bash
composer require keepsuit/laravel-temporal
php artisan temporal:install
php artisan vendor:publish --tag=temporal-config
php artisan temporal:make:workflow Order
php artisan temporal:make:activity Payment
php artisan temporal:work orders
```

Inspect existing project conventions before generating files. The integration discovers definitions under `app`; external paths can be registered using `TemporalRegistry` and discovery helpers. Bind interfaces/implementations according to the package's discovery and container rules. Verify the actual registered Workflow/Activity Type names and queue, not just PHP file names.

Client code can use the bound `WorkflowClientInterface` or `Keepsuit\LaravelTemporal\Facade\Temporal` builders. Distinguish the **Laravel facade** from the SDK's `Temporal\Workflow` facade. Framework DI, DB, HTTP, config and request helpers belong in client/Activity code, not arbitrary workflow decisions.

`Temporal::buildWorkerOptionsUsing(fn(string $queue) => WorkerOptions::new()...)` customizes logical worker options. RoadRunner process limits are separate. `temporal:work` owns a RoadRunner worker process lifecycle; the course's shared Octane/Temporal `.rr.yaml` is an alternative deployment arrangement, not a requirement. Verify graceful shutdown support/options in the installed version and test SIGTERM with active Activities.

## Serialization and application lifetime

The package supports `TemporalSerializable`, Eloquent conversion via `TemporalEloquentSerialize`, and Spatie Laravel Data integration. `TemporalSerializableCastAndTransformer` can handle nested serializable values when configured. Test both ends with `DataConverterInterface` resolved from the same integration; mixing a native default client converter with a Laravel worker can break nested objects.

Prefer small explicit DTO snapshots and IDs for long-running workflows. Serialized Eloquent state does not track subsequent DB changes; lazy loading is workflow I/O. Decide whether the workflow or database projection owns each status, and update projections through Activities. Creating a DB row then starting a workflow is not one atomic transaction: use a stable business Workflow ID with reconciliation or an outbox when that gap matters.

The package's [ApplicationSandboxInterceptor](https://github.com/keepsuit/laravel-temporal/blob/0173907640765f13f4e8e9ad2a970f5db4f4b1fd/src/Interceptors/ApplicationSandboxInterceptor.php) creates a scoped application, flushes it and resets `CurrentApplication` in `finally`. This isolates container state; it is not a determinism/security sandbox. Custom static caches, native resources and process-wide listeners still need bounded lifetimes. Do not install another reset mechanism without checking the existing lifecycle. Test tenant context across successful and failed invocations in one process.

## Testing

- `Temporal::fake()` with `mockWorkflow(...)->andReturn(...)` or `mockActivity([Interface::class, 'method'])->andReturn(...)` supports dispatch/input/queue assertions. It is not a replay test.
- `Keepsuit\LaravelTemporal\Testing\WithTemporal` owns a test server and worker. `TEMPORAL_TESTING_SERVER=false` uses an external server while starting a worker.
- `WithTemporalWorker` is for a server started separately, such as via `temporal:server`.
- `TEMPORAL_TESTING_SERVER_TIME_SKIPPING=true` or the server command's `--enable-time-skipping` selects the special time-skipping server. A normal dev server does not skip time.
- `WithoutTimeSkipping` plus `TemporalTestTime::sleep()` controls time in interaction tests.

Use one lifecycle owner. Isolate test server/namespace/queue/RPC ports from application workers, and share the right converter and mock cache. A DB transaction confined to PHPUnit's process is not automatically visible to a separate Activity worker. Test real messages/cancellation and [history replay](../testing.md) in addition to dispatch fakes.

## Interceptors and analysis

Register compatible interceptors in `config/temporal.php`. Use headers and scoped tracing propagation across client → workflow → Activity → child calls; reset context at invocation boundaries. The package provides a PHPStan extension (`extension.neon`) for proxy typing. Neither that extension nor `VirtualPromise` proves deterministic execution.

Sources: [package README](https://github.com/keepsuit/laravel-temporal/blob/0173907640765f13f4e8e9ad2a970f5db4f4b1fd/README.md), [integration tests](https://github.com/keepsuit/laravel-temporal/tree/0173907640765f13f4e8e9ad2a970f5db4f4b1fd/tests/Integrations/Temporal), [course findings](../sources.md).
