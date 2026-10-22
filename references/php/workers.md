# PHP Workers: RoadRunner, State and Scaling

Read for worker startup, DI, memory growth, throughput, and deployment. See [PHP quickstart](php.md) for a minimal worker. Source snapshots are in [sources.md](sources.md).

## Execution model

RoadRunner embeds the Temporal Go SDK and bridges it to PHP processes. PHP workflow coroutines orchestrate work; Activity PHP processes perform blocking I/O or computation. Waiting on a durable timer does not reserve an Activity process for the timer's duration. A PHP `WorkerFactory::newWorker()` registers a logical Task Queue worker; it is not an operating-system process constructor.

Distinguish these controls:

| Control | What it limits |
| --- | --- |
| Workflow code's in-flight promises | Per-workflow fan-out and retained state |
| `WorkerOptions::withMaxConcurrentActivityExecutionSize()` | Concurrent Activity executions admitted by that worker |
| `withMaxConcurrentActivityTaskPollers()` / `withMaxConcurrentWorkflowTaskPollers()` | Concurrent polling, not PHP execution capacity |
| `temporal.activities.num_workers` | Size of the RoadRunner PHP Activity process pool |
| RoadRunner replicas | Aggregate capacity, subject to shared DB/API limits |
| `withTaskQueueActivitiesPerSecond()` | Server-side Activity dispatch rate for a queue |
| `withWorkerActivitiesPerSecond()` | Activity rate per worker |

More pollers cannot compensate for a saturated PHP pool. A large SDK execution limit with few PHP processes can hold tasks locally while their Start-To-Close budget runs. Do not derive a universal concurrency value from CPU count: measure work duration, memory per task, downstream connection limits and queue latency. Multi-queue workers can share a process pool, so per-queue limits are not automatically isolated capacity.

Sources: [RoadRunner worker model](https://docs.roadrunner.dev/docs/workflow-engine/worker), [SDK WorkerOptions](https://github.com/temporalio/sdk-php/blob/v2.18/src/Worker/WorkerOptions.php).

## Pool configuration

Example values must be adjusted to measured workload requirements:

```yaml
version: "3"
rpc:
  listen: tcp://127.0.0.1:6001
server:
  command: "php worker.php"
  relay: pipes
temporal:
  address: "127.0.0.1:7233"
  activities:
    num_workers: 4
    max_jobs: 1000
    supervisor:
      max_worker_memory: 256
logs:
  level: info
```

In the Temporal plugin the pool section is named `activities`, not `pool`. `supervisor.max_worker_memory` is a soft memory limit in megabytes; `temporal.activities.memory_limit: 128MB` is not the pool option. `max_jobs` recycles processes after a job count; it neither fixes leaks nor controls peak memory. Prefer the memory supervisor for memory-driven recycling. A hard `exec_ttl` can interrupt an Activity and cause a retry, so it is not interchangeable with a Temporal timeout.

HTTP/Octane processes have their own `http.pool` settings. If HTTP and Temporal share RoadRunner, explicitly route the worker bootstraps by mode or set the Temporal worker command. Changing HTTP pool limits does not configure Temporal Activity capacity.

Sources: [pool settings](https://docs.roadrunner.dev/docs/php-worker/pool), [Temporal pool naming](https://docs.roadrunner.dev/docs/php-worker/developer).

## Memory and invocation lifetime

Inspect three different measurements: `memory_get_usage(false)` for live PHP allocations, `memory_get_usage(true)` for memory reserved by PHP's allocator, and process/container RSS for the whole process. Native extension allocations may be missing from PHP's counters. A high-water plateau can be allocator retention or fragmentation; sustained growth in live allocations suggests retained objects. Neither symptom proves the cause without measurement.

Use keyset-paged DB reads and streaming file reads inside Activities. Keep ORM identity maps, query logs, listeners, caches and tracing buffers bounded. Avoid `file()` for large inputs, `Model::all()`, huge eager relation graphs, and unbounded workflow result arrays. Store large outputs externally and return references. `unset()` removes a reference; it does not guarantee lower RSS. `gc_collect_cycles()` collects cycles; `gc_mem_caches()` can reclaim allocator caches, but neither replaces fixing retained references. PHP-FPM normally resets request state while reusing its process; it does not necessarily exit after every request.

An Activity factory may resolve a shared service. Never retain the current tenant, credentials, request, transaction or tracing scope in mutable statics or shared Activity fields. Pass business context explicitly; use SDK headers/interceptors for tracing context. Restore scoped context in `finally`, including on failures. For interleaved workflow coroutines use coroutine-aware context, not one global current-tenant variable. A worker restart is not a per-invocation isolation mechanism.

`registerActivityFinalizer()` can release/reset application resources after each Activity; an Activity's own `try/finally` is useful for resources it owns. In Laravel, inspect the integration's application sandbox lifecycle and add a test that executes tenant A then tenant B in the same worker, including an exception in A. Its container isolation does not make workflow I/O deterministic.

Sources: [PHP memory counters](https://www.php.net/manual/en/function.memory-get-usage.php), [allocator cache reclamation](https://www.php.net/manual/en/function.gc-mem-caches.php), [Activity registration/finalizers](https://github.com/temporalio/sdk-php/blob/v2.18/src/Worker/WorkerInterface.php), [Laravel sandbox](integrations/laravel-temporal.md).

## Scaling and shutdown

Scale from Schedule-To-Start latency, backlog, available execution capacity, CPU/RSS, Activity duration and downstream errors. High queue latency with a full pool suggests insufficient execution capacity; high latency with idle capacity warrants checking polling, task-type registration, queue/namespace/version routing and connectivity first. Split queues and deployments when workloads need independent resource or rate limits.

For Kubernetes/KEDA, use metrics verified for the installed server/SDK and test scale-down with active long Activities. An empty server queue does not imply idle workers: tasks may already be executing. Configure termination grace periods, graceful draining, heartbeat checkpoints and idempotent retry. Test forced worker loss separately. Do not port Python `ThreadPoolExecutor`, `WorkerTuner` or `PollerBehavior` examples into PHP APIs.

For local Xdebug, the course sets an Activity-specific command through `/usr/bin/env XDEBUG_TRIGGER=PHPSTORM php ...`; reproduce it only in development, with verified worker paths and IDE mappings. A debugger pause can exceed Temporal task/Activity timeouts. Confirm recovery with replay and use [testing.md](testing.md) for an isolated stack.
