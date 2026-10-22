# PHP Source Map and Course Assessment

Reviewed on **2026-09-06**. Use this file when refreshing the PHP references, adapting a course lesson, or checking the provenance/limits of a recommendation. Read the task-specific guide first; this map is not required context for every PHP task.

## Evidence and compatibility

Repositories were cloned locally, including all course lesson refs/history. Course inspection covered custom workflows/Activities, DTOs/models, HTTP/console entrypoints, configuration, tests, Docker/telemetry wiring and historical code removed from `main`. This is a source-code review; the course videos were not supplied or watched. The full course stack was not run. Recency is recorded from commits, not inferred from the user's description of the course.

| Source | Reviewed revision / date | Use |
| --- | --- | --- |
| [Official PHP developer guide](https://docs.temporal.io/develop/php) | Live pages on review date: setup, worker processes, testing, messages, versioning, Activity timeouts | Concepts and supported usage; resolve ambiguous examples against SDK source |
| [temporal-course](https://github.com/agoalofalife-screencasts/temporal-course/tree/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab) | `9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab`, 2026-07-02; 24 commits reachable across fetched refs | Evolving Laravel food-delivery case study; lesson map below |
| [samples-php](https://github.com/temporalio/samples-php/tree/bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4) | `bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4`, 2026-06-04 | SDK patterns and executable project structure |
| [temporal-php/support](https://github.com/temporal-php/support/tree/b177152a2add479b0b3e83c1431517db8ce8184d) | `b177152a2add479b0b3e83c1431517db8ce8184d` | Optional factory defaults, attributes, VirtualPromise; factory tests checked |
| [keepsuit/laravel-temporal](https://github.com/keepsuit/laravel-temporal/tree/0173907640765f13f4e8e9ad2a970f5db4f4b1fd) | `0173907640765f13f4e8e9ad2a970f5db4f4b1fd`, 2026-08-07 | Laravel lifecycle, discovery, converters, fake and real-worker testing |
| [SDK PHP v2.18](https://github.com/temporalio/sdk-php/tree/v2.18) | `6e81416d87df815d1626c0ed77bf1a7875d69340`, 2026-08-17; also inspected `v2.16.0` | API/signature checks, including differences from the course |
| [Parallel batch processing](https://medium.com/@thierry.feuzeu/parallel-batch-processing-with-temporal-b10ae89e7269) | Thierry Feuzeu, 2025-04-07; article body accessible | Pattern inspiration; assessment in [batch-processing.md](batch-processing.md) |
| [Long-running PHP memory](https://butschster.medium.com/the-memory-pattern-every-php-developer-should-know-about-long-running-processes-d3a03b87271c) | Pavel Buchnev, 2025-11-19; article body accessible | Operational hypotheses; cross-checked against PHP/RoadRunner manuals |
| [Worker architecture and scaling](https://levelup.gitconnected.com/temporal-worker-architecture-and-scaling-af0c670ce6c1) | Sanil Khurana, 2025-08-07; article body accessible | Python-oriented model; port concepts only after PHP/RoadRunner verification |

The course's `composer.lock` records PHP application requirement ^8.4, Laravel **12.51.0**, `keepsuit/laravel-temporal` **2.2.1**, SDK **2.16.0**, support **1.1.0**, and `internal/promise` **3.4.1**. Its Dockerfile uses RoadRunner **2025.1.5**, and Compose uses Temporal **1.29.3**. These are reproduction facts, not recommended deployment pins. The reviewed newer Laravel integration requires SDK **~2.17.0**, so SDK `v2.18` is a separate API reference, not a tested combination with that integration.

Prefer the target application's lockfile and compatible release documentation. Community packages and examples can lag independently; “newest source” is not one coherent runtime.

## Course lesson map

Remote names are preserved verbatim, including `lessson-6.*`. Links pin the lesson snapshot so an earlier approach remains inspectable even if later lessons replace it.

| Lesson / ref | Source | Ideas to retain and where to apply them |
| --- | --- | --- |
| `lesson-0.2` (`139c1cb`) | [Hello World baseline](https://github.com/agoalofalife-screencasts/temporal-course/tree/139c1cb/app/Temporal) | Attributed concrete workflows, stub construction, a generator entrypoint, synchronous client result, Laravel/Octane HTTP versus Temporal worker roles → [quickstart](php.md), [Laravel](integrations/laravel-temporal.md) |
| `lesson-1.1` (`b98c181`) | [Order introduction](https://github.com/agoalofalife-screencasts/temporal-course/tree/b98c181/app) | Order DTO/model conversion; business Workflow IDs; asynchronous HTTP start; Activity type naming; retries, timeout budgets and cancellation choices → [data](data-handling.md), [errors](error-handling.md) |
| `lesson-1.2` (`9b18453`) | [PrepareOrderActivity](https://github.com/agoalofalife-screencasts/temporal-course/blob/9b18453/app/Temporal/Activities/PrepareOrderActivity.php) | Staged work, attempt-aware failure injection, heartbeat progress and resumption. This Activity is deleted later; preserve the checkpointing lesson → [patterns](patterns.md) |
| `lesson-2.1` (`3c5d9cf`) | [Signal-based order](https://github.com/agoalofalife-screencasts/temporal-course/tree/3c5d9cf/app) | Replace simulated preparation with an external restaurant callback; Signal mutates workflow state, main coroutine awaits it; validate/deduplicate callback inputs → [patterns](patterns.md) |
| `lesson-2.2` (`2c84d27`) | [Restaurant deadline](https://github.com/agoalofalife-screencasts/temporal-course/blob/2c84d27/app/Temporal/Workflows/OrderWorkflow.php) | Durable await-with-timeout and explicit accepted/rejected/timeout outcomes, rather than blocking HTTP or PHP sleep |
| `lesson-2.3` (`f5cce01`) | [Query endpoint](https://github.com/agoalofalife-screencasts/temporal-course/blob/f5cce01/app/Http/Controllers/OrderStatusController.php) | Read workflow state through Query; enum-to-display mapping; not-found handling; distinguish live workflow state from DB projections |
| `lesson-3.1` (`3515c7f`) | [Courier child workflow](https://github.com/agoalofalife-screencasts/temporal-course/tree/3515c7f/app/Temporal/Workflows/SearchCourier) | Child lifecycle/ID/parent-close policy; contract interface and `ReturnType`; expanding radius with bounded attempts; accept/decline Signals; structured found/not-found outcome |
| `lesson-3.2` (`703845a`) | [Parallel courier providers](https://github.com/agoalofalife-screencasts/temporal-course/blob/703845a/app/Temporal/Workflows/SearchCourier/FindCourierWorkflow.php) | Compare all-results, first-fulfilled and first-non-empty policies; deadline and provider completion tracking → [batch/branch coordination](batch-processing.md) |
| `lesson-4.1` (`8eb245a`) | [Saga and cancellation](https://github.com/agoalofalife-screencasts/temporal-course/tree/8eb245a/app/Temporal) | Restaurant/courier compensation, reverse versus parallel cleanup, detached cleanup in child cancellation, cancellation as a domain outcome |
| `lesson-4.2` (`dc81aa4`) | [Versioned notification](https://github.com/agoalofalife-screencasts/temporal-course/blob/dc81aa4/app/Temporal/Workflows/OrderWorkflow.php) | Preserve no-notification/SMS/push branches with `getVersion()`; do not change historic command ordering → [versioning](versioning.md) |
| Xdebug commits (`8ede7e2`, `d648c87`) | [Activity debug configuration](https://github.com/agoalofalife-screencasts/temporal-course/blob/8ede7e2/.rr.yaml) | Separate Activity worker command, trigger-based debugging and container-to-host IDE mappings; account for timeout effects → [workers](workers.md) |
| `lesson-4.3` (`25a6de8`) | [Promotion workflow](https://github.com/agoalofalife-screencasts/temporal-course/tree/25a6de8/app) | Entity workflow, Signal buffer, batch persistence, history growth, handler draining and Continue-As-New; bounded signal generator for exercises |
| `lesson-5.1` (`d6e2202`) | [Weekly scheduling](https://github.com/agoalofalife-screencasts/temporal-course/blob/d6e2202/app/Console/Commands/MakeWeeklyOrderWorkflowBySchedule.php) | Schedule client/converter, calendar versus interval, timezone, jitter, overlap, catchup, pause/trigger/backfill; per-occurrence payment/booking workflow → [advanced features](advanced-features.md) |
| `lesson-5.2` (`85370b7`) | [Updates and result polling](https://github.com/agoalofalife-screencasts/temporal-course/blob/85370b7/app/Http/Controllers/OrderController.php) | Synchronous Update, pure validator, async StageAccepted handle, later result retrieval and HTTP error mapping; `sideEffect()` for recorded random values |
| `lessson-6.1` (`5917908`) | [Test infrastructure](https://github.com/agoalofalife-screencasts/temporal-course/tree/5917908/tests) | Dedicated server versus time-skipping server; test RoadRunner/RPC/KV isolation; ActivityMocker; ready-state polling; timers that would otherwise take a month → [testing](testing.md) |
| `lessson-6.2` / `main` (`9218c40`) | [Telemetry deployment](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/docker-compose.yml) | Server/SDK/application metrics; Prometheus/Grafana; OpenTelemetry → collector → Zipkin; JSON stderr logs → Vector → VictoriaLogs; Search Attributes and trace correlation → [observability](observability.md) |

## Course limitations to resolve when adapting

These are source-level findings and reasoning, not claims reproduced against a running course stack. They belong in implementation reviews, not as silent changes to the upstream course.

1. **Unawaited values and side effects.** [OrderWorkflow](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Workflows/OrderWorkflow.php) assigns `Workflow::uuid()` without `yield`; it is a promise. [WeeklySubscriptionWorkflow](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Workflows/WeeklySubscriptionWorkflow.php) schedules a notification without waiting. Explicitly await results or their join before declaring completion.
2. **Signal initialization/races.** Order status is initialized after a yielded side effect, and RestaurantProcessing is set after notification. A Query/Signal can encounter uninitialized or unexpected state. Initialize handler-visible fields and define early/duplicate/late-message behavior before external callbacks can arrive.
3. **Lost promotion input.** [RestaurantPromotionWorkflow](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Workflows/RestaurantPromotionWorkflow.php) clears `pendingOffers` after yielding persistence. Offers received during that wait can be discarded. Snapshot/reset first; handle failed persistence; bound the buffer and carry pending state through Continue-As-New. Make the handoff terminal and explicit with `return yield` in the main method.
4. **Incomplete provider settlement.** [FindCourierWorkflow](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Workflows/SearchCourier/FindCourierWorkflow.php) increments completion only on success and leaves losing branches active. Rejections can prevent an all-complete condition; late results can affect later attempts. Use attempt-local state, completion in `finally`, and deliberate cancellation/draining.
5. **Courier acceptance validation.** The handler accepts any ID when none is assigned. Validate the sender/correlation at ingress and offered ID/current round in workflow state; handle duplicate/late acceptance and release losing reservations.
6. **Compensation window and outcome.** Order registers restaurant cancellation after notification succeeds; a successful side effect with a lost response has no registered compensation. Register idempotent “if applied” compensation first. SDK `Saga::compensate()` already detaches; do not misdiagnose its call as ordinary cancelled-scope cleanup. Separately, choose cancellation ordering: default `TryCancel` can start compensation before the original Activity finishes, requiring cooperative waiting and/or fencing/reconciliation of late side effects. Catching cancellation and returning a DTO/void completes normally: choose that business outcome or rethrow intentionally.
7. **Update deduplication.** The async controller uses Workflow ID as Update ID, making distinct address edits share one deduplication identity. Use a stable ID per logical request; retain the accepting Run ID for later retrieval when needed. Acceptance does not imply completion.
8. **Address projection mismatch.** [DatabaseActivity](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/app/Temporal/Activities/DatabaseActivity.php) updates `address`, while the model/DTO use `delivery_address`. Do not transplant that field name. Concurrent yielding Updates also need a coherent state/DB ordering policy.
9. **Schedule code is exploratory.** The console command fetches a hard-coded handle and executes `exit(0)` before creation; booking failure/payment compensation is unfinished. Its “interval starts at creation” comment is not the interval semantics. Extract schedule choices, not the command verbatim; backfill and whole-workflow retries can duplicate charges.
10. **Workflow versioning is local, not global.** The notification patch does not protect every later addition, such as a new early side-effect marker. Replay representative pre-patch histories before deploying any evolved course stage against existing executions.
11. **Mock names and versions.** [OrderWorkflowTest](https://github.com/agoalofalife-screencasts/temporal-course/blob/9218c4002d79f9f9ee4675784c4ce63d7ad0c1ab/tests/Feature/OrderWorkflowTest.php) mocks `NotifyRestaurant.notify`, while the attributes declare prefix `NotifyRestaurant` and method `Notify`; verify the exact registered type rather than guessing punctuation/case. Its fixed-result limitation describes the old mocker, not SDK v2.18. Reset shared mocks/time locks between tests.
12. **Observability semantics.** A metrics Activity can overcount on retry. Synchronous span export is a throughput tradeoff; configure flushing for batching instead of assuming a long-lived worker can never flush. DB listeners should not imply a zero-duration post-query span measured the actual query; handle SQL privacy and label cardinality.
13. **Demo operations and defaults.** Docker ports, container names, development credentials, unpinned extension installs, timeout values, debugger configuration and `auto-setup` are local-course choices. Preserve separate HTTP/Temporal/test lifecycles, but use the target application's deployment and isolation practices.

## Official sample ideas beyond the course

Use the [pinned sample tree](https://github.com/temporalio/samples-php/tree/bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4/app/src) as a retrieval index:

| Samples | Reusable idea / adaptation boundary |
| --- | --- |
| `SimpleActivity`, `ActivityRetry`, `Exception`, `PolymorphicActivity` | Basic contracts, retries, exception wrapping and shared interfaces; verify current registration APIs |
| `AsyncActivity`, `AsyncClosure`, `CancellationScope` | Start concurrent branches before joining; cancel explicit scopes; add bounds for large inputs |
| `Child`, `Saga`, `BookingSaga`, `MoneyTransfer` | Child lifecycle and compensating operations; test loss-of-response windows and idempotency |
| `Signal`, `Query`, `Updates`, `SafeMessageHandlers` | Message contracts, state readiness, `Workflow::runLocked()`/Mutex, handler draining, state handoff and deduplication; review continuation details against the SDK |
| `MoneyBatch` | Signal-with-start for lazy creation of an entity workflow, and aggregation before one downstream action |
| `Periodic`, `Subscription`, `Cron`, `UpdatableTimer` | Long-lived timers, cancellation and rescheduling; use managed Schedules where recurring independent starts are intended |
| `FileProcessing` | Return host/queue affinity with a file reference; host-local routing couples recovery to that host. Prefer durable shared storage when replacement workers must recover |
| `AsyncActivityCompletion`, `LocalActivity` | Deferred completion token handling and local execution tradeoffs; do not confuse Activity completion with a Signal |
| `SearchAttributes`, `Interceptors`, `MtlsHelloWorld` | Visibility, boundary hooks and secure client/worker connections; verify PHP-specific configuration |
| `InfrequentPolling` | Poll via retrying Activities; benign failure category is version-dependent, not a blanket error-suppression policy |
| `Replay`, `app/tests/Feature` | Real RoadRunner/KV mock transport and history replay; adapt bootstrap to SDK version and make replay errors fail CI |

## Article conclusions

The memory article usefully highlights large ORM/file allocations, bounded caches, streaming, scope cleanup and worker rotation. Its absolute “memory never returns”/“process dies each request” framing is too strong. PHP's manual documents `gc_mem_caches()` and distinguishes live allocations from reserved memory; PHP-FPM normally reuses processes. Diagnose retention versus real leaks with PHP counters and RSS. The [worker guide](workers.md) uses those verified distinctions.

The scaling article explains polling, execution slots, resource limits and pod autoscaling using **Python**. Its executor/tuner/PollerBehavior APIs and deprecation statements do not establish PHP support. Transfer the distinction between admission and execution capacity, metric-driven scaling and graceful scale-down; use verified RoadRunner pools and PHP WorkerOptions. The bounded batch article's specific adoption/corrections are in [batch-processing.md](batch-processing.md).

## Refresh and verification

Recheck pinned paths, package constraints and changed API signatures on refresh. Use the [behavioral scenarios](skill-scenarios.md) to detect retrieval/application regressions. PHP lint proves syntax, source signature checks prove only API shape, and a scenario review proves instruction usability; none substitutes for a live worker/server integration run. Report those levels separately.
