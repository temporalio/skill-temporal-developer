# Standalone Activities

A Standalone Activity is a top-level Activity Execution started directly by a Client, without a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:50-52 --> Standalone Activities are Temporal's job-queue primitive: the simplest way to run a single durable, retryable task, with priority, fairness, deduplication, and visibility built in. <!-- docs/encyclopedia/activities/standalone-activity.mdx:34-35, docs/evaluate/development-production-features/job-queue.mdx:25-31 -->

Use a Standalone Activity when you only need to execute a single Activity (sending an email, processing a webhook, syncing data, running one function reliably). Use a Workflow when you need to orchestrate multiple Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:31-32, 73-75 --> Running one Activity standalone results in fewer Billable Actions in Temporal Cloud than wrapping it in a Workflow, and short-lived Activities also see lower latency due to fewer Worker round-trips. <!-- docs/encyclopedia/activities/standalone-activity.mdx:52-54 -->

## Key features

- Execute any Temporal Activity as a top-level primitive without the overhead of a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:78 -->
- Native async job model: schedule -> dispatch -> process -> result. <!-- docs/encyclopedia/activities/standalone-activity.mdx:79 -->
- No head-of-line blocking; a slow job doesn't block dispatch of other Tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:80 -->
- Arbitrary-length jobs with heartbeats for liveness and progress checkpointing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:81 -->
- At-least-once execution by default with retry policy and timeouts; at-most-once when retry max attempts is 1. <!-- docs/encyclopedia/activities/standalone-activity.mdx:82-83 -->
- Addressable by Activity ID / Run ID for fetching results, cancellation, and termination. <!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
- Deduplication via conflict policy (`USE_EXISTING`, ...) and reuse policy (`REJECT_DUPLICATES`, ...). <!-- docs/encyclopedia/activities/standalone-activity.mdx:85 -->
- Separate ID space from Workflows. <!-- docs/encyclopedia/activities/standalone-activity.mdx:86 -->
- Priority and fairness, including weighted priority tiers and safeguards against starvation of lower-weight tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:87 -->
- Visibility: list Activity Executions and view status, retry count, and last error. <!-- docs/encyclopedia/activities/standalone-activity.mdx:88 -->
- Manual completion by ID or task token. <!-- docs/encyclopedia/activities/standalone-activity.mdx:89 -->
- Activity metrics including counts for success, failure, timeout, and cancel. <!-- docs/encyclopedia/activities/standalone-activity.mdx:90 -->
- Dual-use: an Activity Function runs unchanged whether invoked standalone or from a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:56-57, 91 -->

## Public Preview status and limitations

Standalone Activities are a Public Preview feature in Temporal Cloud and require Temporal CLI v1.7.0 or higher with Temporal Server v1.31.0 or higher. <!-- docs/encyclopedia/activities/standalone-activity.mdx:23, 115 --> The Temporal Dev Server has Standalone Activities enabled by default for local testing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:139 -->

Known limitations in Public Preview:

- Pause, reset, and update options are not supported (planned for GA). <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are not supported yet. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->
- Activity Operations (Pause, Unpause, Reset, Update Options) do not apply to Standalone Activities. <!-- docs/encyclopedia/activities/activity-operations.mdx:31 -->

## Separate ID space and dedup policies

Standalone Activities have a separate ID space from Workflows and other Temporal primitives. Conflict policy (`USE_EXISTING`, ...) and reuse policy (`REJECT_DUPLICATES`, ...) only observe the Standalone Activity ID space. <!-- docs/encyclopedia/activities/activity-execution.mdx:117-118 -->

The CLI accepts the following enum values when starting a Standalone Activity:

| Flag | Accepted values |
|---|---|
| `--id-conflict-policy` | `Fail`, `UseExisting` <!-- docs/cli/activity.mdx:140, 341 --> |
| `--id-reuse-policy` | `AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate` <!-- docs/cli/activity.mdx:141, 342 --> |

`TerminateExisting` (conflict policy) and `TerminateIfRunning` (reuse policy) are not currently accepted for Standalone Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->

## Lifecycle and execution model

A Standalone Activity Execution is the full chain of Activity Task Executions for one top-level Activity. <!-- docs/encyclopedia/activities/activity-execution.mdx:30 --> If the Activity fails (retries exhausted, non-retryable error, or canceled), the error is returned to the Client when it attempts to fetch the result. <!-- docs/encyclopedia/activities/activity-execution.mdx:48-51 -->

You write Activity Functions the same way for both invocation styles. The same Activity Function can be executed as a Standalone Activity or as a Workflow Activity with no code changes. <!-- docs/encyclopedia/activities/standalone-activity.mdx:56-57 --> Deploy your Activities to an Activity Worker once, and invoke them either standalone or from within a Workflow. <!-- docs/evaluate/development-production-features/job-queue.mdx:41 -->

Jobs are durably persisted, scheduled with priority and fairness, and dispatched without head-of-line blocking. Workers poll task queues, and Temporal enforces retries, timeouts, and exponential backoff. <!-- docs/evaluate/development-production-features/job-queue.mdx:45-49 --> Under the hood, Standalone Activities use Task Queues for dispatching work to Workers. <!-- docs/evaluate/development-production-features/job-queue.mdx:29 -->

## CLI surface

The `temporal activity` subcommand supports Standalone Activities with: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:136-137 -->

| Subcommand | Applies to | Notes |
|---|---|---|
| `start` | Standalone Activity | Starts a new Standalone Activity; outputs Activity ID and Run ID. <!-- docs/cli/activity.mdx:318-321 --> |
| `execute` | Standalone Activity | Starts and blocks until completion; result is written to stdout. <!-- docs/cli/activity.mdx:117-120 --> |
| `result` | Standalone Activity | Waits for a Standalone Activity to complete and outputs the result. <!-- docs/cli/activity.mdx:301-304 --> |
| `list` | Standalone Activity | Lists Standalone Activities; supports `--query`. <!-- docs/cli/activity.mdx:180-183 --> |
| `count` | Standalone Activity | Counts Standalone Activities matching `--query`. <!-- docs/cli/activity.mdx:81-84 --> |
| `describe` | Standalone Activity | Displays information about a Standalone Activity. <!-- docs/cli/activity.mdx:100-103 --> |
| `cancel` | Standalone Activity | Requests cancellation; transitions run state to `CancelRequested`. <!-- docs/cli/activity.mdx:38-50 --> |
| `terminate` | Standalone Activity | Terminates a Standalone Activity; Activity code cannot see or respond to terminations. <!-- docs/cli/activity.mdx:361-371 --> |
| `complete` | Either (workflow Activity if `--workflow-id` is set; Standalone Activity if omitted) | <!-- docs/cli/activity.mdx:76, 79 --> |
| `fail` | Either (workflow Activity if `--workflow-id` is set; Standalone Activity if omitted) | <!-- docs/cli/activity.mdx:174, 178 --> |
| `pause` | Workflow Activity only | Not supported for Standalone Activities. <!-- docs/cli/activity.mdx:202 --> |
| `unpause` | Workflow Activity only | Not supported for Standalone Activities. <!-- docs/cli/activity.mdx:383-384 --> |
| `reset` | Workflow Activity only | Not supported for Standalone Activities. <!-- docs/cli/activity.mdx:236 --> |
| `update-options` | Workflow Activity only | Not supported for Standalone Activities. <!-- docs/cli/activity.mdx:436 --> |

### Required flags for `start` and `execute`

Both `start` and `execute` require: <!-- docs/cli/activity.mdx:133-159, 332-359 -->

- `--activity-id, -a` (string) — Activity ID.
- `--type` (string) — Activity Type name.
- `--task-queue, -t` (string) — Activity task queue.
- Either `--start-to-close-timeout` or `--schedule-to-close-timeout` (duration).

Common optional flags include `--input` / `--input-file`, `--heartbeat-timeout`, `--schedule-to-start-timeout`, retry-policy flags (`--retry-initial-interval`, `--retry-maximum-interval`, `--retry-backoff-coefficient`, `--retry-maximum-attempts`), `--priority-key` (1-5, lower = higher; default 3), `--fairness-key` / `--fairness-weight`, `--search-attribute`, `--headers`, `--id-conflict-policy`, and `--id-reuse-policy`. <!-- docs/cli/activity.mdx:133-159, 332-359 -->

## Observability

All existing Activity metrics apply to Standalone Activities, covering counts for scheduled, started, completed, failed, timed out, and canceled. <!-- docs/encyclopedia/activities/standalone-activity.mdx:95-97 -->

For Activity metrics that include the `temporal_workflow_type` label, Standalone Activities use the placeholder value `"__standalone_activity"`. The label is present but set to that placeholder rather than a real Workflow Type. <!-- docs/cloud/metrics/openmetrics/metrics-reference.mdx:313-315 -->

`temporal_cloud_v1_activity_terminate_count` applies only to Standalone Activities; Activities running within a Workflow cannot be terminated independently. <!-- docs/cloud/metrics/openmetrics/metrics-reference.mdx:394-396 -->

`CountActivities` returns the total number of Standalone Activity Executions matching a filter, analogous to counting Workflow Executions. This is the total count of executions (running, completed, failed, etc.), not the number of queued tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:102-104 -->

Use List Filters to query Standalone Activity Executions by type, status, task queue, and other attributes via the SDK or `temporal activity list`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:99-100 -->

## Temporal Cloud Actions

Temporal Cloud bills four Standalone-Activity Action types: <!-- docs/evaluate/temporal-cloud/actions.mdx:120-123 -->

| Usage Name | Metric Name |
|---|---|
| Start Standalone Activity | `start_standalone_activity` |
| Retry Standalone Activity | `retry_standalone_activity` |
| Record Standalone Activity Heartbeat | `record_standalone_activity_heartbeat` |
| Record Standalone Activity Heartbeat By ID | `record_standalone_activity_heartbeat_by_id` |

## Pointers to language-specific guides

For SDK usage (client APIs, worker registration, type-safe handles, result fetching, list/count, cancel/terminate), see the per-language reference files:

- `references/python/standalone-activities.md`
- `references/typescript/standalone-activities.md`
- `references/java/standalone-activities.md`
- `references/dotnet/standalone-activities.md`
