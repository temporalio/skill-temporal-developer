> [!NOTE]
> Standalone Activities are in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

# Job Queues in Temporal

> [!IMPORTANT]
> **"Job queue" maps to Standalone Activities.** When someone asks to build a job queue, run background jobs, process a work queue, or asks whether Temporal can replace Celery, Sidekiq, BullMQ, Resque, RQ, Hangfire, Faktory, Delayed::Job, Google Cloud Tasks, or SQS-plus-worker-processes, the answer is **Standalone Activities** — an Activity started directly from a Temporal Client, with no Workflow involved.
>
> Temporal **Task Queues** are the transport that routes Tasks to Workers; they are not the thing a producer enqueues jobs into. Answering a job queue question by describing Task Queues produces a confused design.

This file is the translation layer between job-queue vocabulary and Temporal. For the feature itself — its full capability list, the CLI, and Public Preview limitations — read `references/core/standalone-activities.md`. For API syntax, read `references/{your_language}/standalone-activities.md`.

## Why Standalone Activities are a job queue

A job is a single, discrete unit of work run asynchronously in the background — sending an email, processing a webhook, syncing data, running one function reliably. A job queue is the system that accepts that work, dispatches it to workers, retries it on failure, and shows what is running and what failed. Standalone Activities do all of this.

What is different from a conventional broker-plus-worker stack, in job-queue terms:

- **Durable job state, not just a durable message.** The Server persists the execution, its attempts, its last error, and its result. There is no separate result backend to run.
- **No dead-letter queue to operate.** A job that exhausts its Retry Policy ends as a failed execution, retained in visibility with its last error and findable with a List Filter.
- **Retries, timeouts, and backoff are enforced by the platform**, not by a decorator argument the handler can ignore.
- **The same code graduates into orchestration.** One Activity Function runs as a background job today and as a step inside a multi-step Workflow tomorrow, with no code change and no Worker change. That upgrade path is the reason to pick Temporal over a job queue you would outgrow.
- **Cheaper than the usual workaround.** Wrapping a single Activity in a Workflow costs an extra billable Action in Temporal Cloud and extra Worker round-trips; a Standalone Activity avoids both.

See `references/core/standalone-activities.md` for the rest of the feature list (execution semantics, deduplication, addressability, visibility, metrics).

## Vocabulary mapping

| Job queue concept | Temporal equivalent |
|---|---|
| A job / a task | A Standalone Activity Execution |
| Job handler (`@app.task`, `perform`, a processor function) | An ordinary Activity Definition — nothing job-specific about it |
| Enqueue a job | Client `start` (returns a handle) or `execute` (start and await the result) |
| Broker (Redis, RabbitMQ, SQS, Postgres table) | Temporal Server — durable persistence plus dispatch |
| Worker process consuming the queue | Temporal Worker polling a Task Queue |
| Queue name / routing key | Task Queue name |
| Job ID | Activity ID — you choose it; use a business identifier |
| Result backend (a database or store you provide) | The Activity's result, stored by the Server in the authoritative Activity record and retrieved from the handle or `temporal activity result` |
| `max_retries` + backoff config | Retry Policy: maximum attempts, backoff coefficient, non-retryable error types. Note it counts *total attempts*, not retries — a framework's `retry: 5` is `maximum_attempts: 6` |
| "Run this at most once" | Retry Policy with maximum attempts = 1 |
| Unique-job / idempotency key | Activity ID, plus an ID conflict policy (`Fail`, `UseExisting`) for an ID currently running **and** an ID reuse policy (`AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`) for an ID that has already completed. A unique-job gem generally wants both set; `AllowDuplicateFailedOnly` is the closest match to "re-run only if the last attempt failed" |
| Job timeout | Start-To-Close and/or Schedule-To-Close timeout (at least one is required) |
| Long job keepalive / progress reporting | Activity Heartbeats, with heartbeat details for checkpointing |
| Cancel a job | `cancel` (cooperative, surfaced on the next heartbeat) or `terminate` (forceful) |
| Priority queues | Priority keys — free, Public Preview. See `references/core/priority-fairness.md` |
| Per-tenant fairness / avoiding noisy neighbors (usually not supported) | Fairness keys and weights — Public Preview, and a paid feature in Temporal Cloud. See `references/core/priority-fairness.md` |
| Delayed job (`countdown`, `enqueue_in`, `perform_in`) | A start delay on the Standalone Activity itself — no Workflow needed. Any duration, at any scale |
| Dashboard (Flower, Sidekiq Web, Bull Board) | Temporal Web UI, `temporal activity list` (with Search Attribute support) / `describe`, and the list/count client APIs |
| Job metrics | Standard Activity metrics: scheduled, started, completed, failed, timed out, canceled |
| Manual/external job completion | Manual completion by Activity ID or task token |

On head-of-line blocking: a slow job occupies one Worker slot rather than stalling a single-threaded consumer, so one slow job does not block dispatch of the rest. Backlog-level starvation across tenants is a separate problem — by default Tasks dispatch FIFO, so a tenant enqueueing 100k jobs does put a small tenant behind the whole backlog. Fairness is what fixes that, and few job queues offer fairness keys that can be used to enforce multi-tenant fairness or other fine-grained fairness schemes.

## Job-queue features that need a different Temporal primitive

Not every "job queue" request is a single job. Route these away from Standalone Activities:

| Ask | Use instead |
|---|---|
| Chained jobs, DAGs, Celery canvas / chords, "when job A finishes run B and C" | A **Workflow**. That is orchestration, which is what Workflows are for. |
| Fan-out with a join, or a batch with a completion callback | A **Workflow** that starts the Activities in parallel and awaits them. |
| Compensation / rollback when a later step fails | A **Workflow** using the saga pattern — see `references/core/patterns.md`. |
| Recurring or periodic jobs (Celery beat, `sidekiq-cron`, a crontab) | A **Temporal Schedule**, which starts a thin Workflow that calls the one Activity. Scheduled Standalone Activities are coming in a future release. |
| A job that waits for human approval or an external event | A **Workflow** with a Signal or Update handler. |
| Long-lived per-entity state (a per-user or per-order actor) | The **entity Workflow** pattern — see `references/core/patterns.md`. |

A one-shot delayed job ("run this in 10 minutes") uses a start delay on the Standalone Activity itself — `start_delay` on the start request, or `--start-delay` on `temporal activity start`. Temporal accepts any duration at any scale, where job frameworks like Celery limit both.

Rule of thumb: **one unit of work → Standalone Activity, delayed or not; more than one step, or waiting on an external event → Workflow.**

## Migrating from an existing job queue

The shape of the port is the same regardless of source system:

1. **Handler → Activity Definition.** The body of the job handler becomes the body of an Activity. Drop the framework decorator and use the SDK's Activity decorator/annotation. Keep the handler's own retry/idempotency logic only where it is genuinely business logic; delete hand-rolled retry loops.
2. **Worker process → Temporal Worker.** One Worker process registers the Activities and polls a Task Queue. Concurrency knobs move from the framework's worker flags to Worker options — see `references/{your_language}/advanced-features.md`, and the `temporal-workertuning` skill for sizing.
3. **`delay()` / `perform_async` / `queue.add()` → Client `start` or `execute`.** This is the only real call-site change. It happens in producer code, which must be non-Workflow application code.
4. **Retry/timeout config → Retry Policy and Activity timeouts** on the start options, not on the handler. Remember the attempts-vs-retries off-by-one.
5. **Job ID → Activity ID.** Reuse whatever idempotency key already exists. If there was none, derive one from the business entity.
6. **Monitoring → built-in visibility and metrics.** Replace Flower/Sidekiq Web/Bull Board polling of a Redis key with `list`/`count`/`describe` and the Web UI.

Framework-specific notes worth stating when they come up:

- **Celery / RQ (Python):** `@app.task` → `@activity.defn`; `.delay()`/`.apply_async()` → `client.start_activity(...)`; `acks_late`/`task_reject_on_worker_lost` behavior is the default (at-least-once); `task_time_limit` → Start-To-Close timeout; `max_retries=3` → `maximum_attempts=4`; Celery beat → a Schedule; canvas (`chain`, `group`, `chord`) → a Workflow.
- **Sidekiq / Resque / Delayed::Job (Ruby):** the `perform` method becomes the Activity; `perform_async` becomes a Client call; `retry: 5` becomes `maximum_attempts: 6`; unique-job gems become an Activity ID plus an ID conflict policy.
- **BullMQ / Bee-Queue (Node):** `queue.add(name, data, opts)` → Client `start`; the processor function → the Activity; `opts.jobId` → Activity ID; `attempts` maps 1:1 onto maximum attempts and `backoff` onto the Retry Policy; `repeat` → a Schedule; flows/parent-child jobs → a Workflow.
- **SQS + worker, or Cloud Tasks:** the queue, the visibility-timeout tuning, and the DLQ all go away. Producers call the Temporal Client directly; the Server owns dispatch, redelivery, and retention of failures.
- **Hangfire (.NET):** `BackgroundJob.Enqueue` is fire-and-forget, so it maps to `StartActivityAsync` (use `ExecuteActivityAsync` only where the caller actually waits); `RecurringJob` → a Schedule; continuations → a Workflow.

## Anti-patterns

Anti-patterns to avoid when building a job queue on Temporal:

1. **A Workflow per job that runs exactly one Activity.** It costs an extra billable Action and extra Worker round-trips for no orchestration benefit. Prefer a Standalone Activity, including for delayed jobs, which take a start delay directly. Recurring jobs on a Schedule are the exception, since Schedules start Workflows.
2. **A long-lived "queue manager" Workflow** that accepts jobs by Signal and dispatches them. It reinvents a queue the Server already provides, grows unbounded Event History, forces continue-as-new, and reintroduces head-of-line blocking.
3. **An Activity that polls Redis/SQS/a database table for work** and then dispatches it. Once on Temporal, the producer should enqueue Standalone Activities directly. (Polling an external system you do not control is a different, legitimate pattern — see `references/core/patterns.md`.)
4. **Hand-rolled retry loops inside the Activity.** Configure a Retry Policy instead; a `for attempt in range(3)` inside an Activity hides failures from visibility and metrics.
5. **A side table tracking job status.** Status, attempt count, last error, and result are already queryable. Add a table only where job state has to be joined against business data.
6. **A random UUID as the Activity ID by default.** A business identifier such as `send-welcome-email:user-42` makes jobs addressable and deduplicated for free. A UUID is the fallback for when no meaningful identifier exists.

## Code layout

A job queue built on Standalone Activities has three pieces, and they belong in three places:

- **The Activity Definition** — plain Activity code, identical to one written for a Workflow.
- **The Worker** — registers the Activity and polls the Task Queue. It does not know or care whether the Activity will be invoked standalone or from a Workflow.
- **The producer** — application code, an HTTP handler, or a CLI entry point that calls the Client.

A Workflow that needs a job to outlive it can start a Standalone Activity from inside a regular in-Workflow Activity, using the SDK Client there. Workflow code cannot start one directly today; that is planned for a future release.

## SDK guides and runnable samples

| Language | SDK guide | Runnable sample |
|---|---|---|
| Go | https://docs.temporal.io/develop/go/activities/standalone-activities | https://github.com/temporalio/samples-go/tree/main/standalone-activity/helloworld |
| Python | https://docs.temporal.io/develop/python/activities/standalone-activities | https://github.com/temporalio/samples-python/tree/main/hello_standalone_activity |
| TypeScript | https://docs.temporal.io/develop/typescript/activities/standalone-activities | https://github.com/temporalio/samples-typescript/tree/main/standalone-activity |
| Java | https://docs.temporal.io/develop/java/activities/standalone-activities | https://github.com/temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/standaloneactivities |
| .NET | https://docs.temporal.io/develop/dotnet/activities/standalone-activities | https://github.com/temporalio/samples-dotnet/tree/main/src/StandaloneActivity |
| Ruby | https://docs.temporal.io/develop/ruby/activities/standalone-activities | https://github.com/temporalio/samples-ruby/tree/main/standalone_activity |

Conceptual references: [Job Queue](https://docs.temporal.io/evaluate/development-production-features/job-queue) and [Standalone Activity](https://docs.temporal.io/standalone-activity).

Rust is the one SDK in this skill without Standalone Activity support. For a language without support, the fallback is a Workflow that runs the single Activity, accepting the extra Action and latency until support lands.
