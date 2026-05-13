# Standalone Activities

## What is a Standalone Activity?

A **Standalone Activity** is a top-level [Activity Execution](https://docs.temporal.io/activity-execution) started directly by a Client, without using a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:50-51 -->

Use a Standalone Activity when you need to execute a single Activity reliably; use a [Workflow](https://docs.temporal.io/workflows) when you need to orchestrate multiple Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:31-32 -->

You write the Activity Function the same way for both. The same Activity Function can be executed as a Standalone Activity and as a Workflow Activity with no code changes. <!-- docs/encyclopedia/activities/standalone-activity.mdx:56-57 -->

If an Activity Execution fails for a Standalone Activity, the error is returned to the Client when it attempts to fetch the result. <!-- docs/encyclopedia/activities/activity-execution.mdx:50-51 -->

## Support and version requirements

Standalone Activities are a Public Preview feature in Temporal Cloud and require: <!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->

- **Temporal CLI** v1.7.0 or higher.
- **Temporal Server** v1.31.0 or higher.

The Temporal Dev Server has Standalone Activities enabled by default for local testing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:139 -->

The Web UI surfaces Standalone Activities from a nav bar item near the top left of the page. <!-- docs/encyclopedia/activities/standalone-activity.mdx:114-116 -->

### SDK support stages and minimums

| SDK | Stage | Minimum SDK version |
|-----|-------|---------------------|
| Python | Public Preview <!-- docs/develop/python/activities/standalone-activities.mdx:22-26 --> | 1.23.0 <!-- docs/develop/python/activities/standalone-activities.mdx:69 --> |
| TypeScript | Pre-release <!-- docs/develop/typescript/activities/standalone-activities.mdx:22-26 --> | 1.17.0 <!-- docs/develop/typescript/activities/standalone-activities.mdx:62 --> |
| .NET | Public Preview <!-- docs/develop/dotnet/activities/standalone-activities.mdx:22-26 --> | 1.12.0 <!-- docs/develop/dotnet/activities/standalone-activities.mdx:62 --> |
| Java | Pre-release <!-- docs/develop/java/activities/standalone-activities.mdx:22-26 --> | 1.35.0 <!-- docs/develop/java/activities/standalone-activities.mdx:64 --> |

## Key features

Per the encyclopedia listing: <!-- docs/encyclopedia/activities/standalone-activity.mdx:77-91 -->

- Execute any Activity as a top-level primitive without the overhead of a Workflow.
- Native async job processing model: schedule → dispatch → process → result.
- No head-of-line blocking — a slow job doesn't block the dispatch of other Tasks.
- Arbitrary length jobs with heartbeats for liveness and checkpointing progress.
- At-least-once execution by default with native retry policy and timeouts.
- At-most-once execution when retry max attempts is 1.
- Addressable: get an Activity ID / Run ID and get the result, cancel, or terminate.
- Deduplication via conflict policy (`USE_EXISTING`) and reuse policy (`REJECT_DUPLICATES`).
- Separate ID space from Workflows — Standalone Activities are a different kind of top-level execution.
- Priority and Fairness — see `references/core/priority-fairness.md`.
- Visibility — list Activity Executions and view status, retry count, and last error.
- Manual completion by ID or token: ignore the Activity return and wait for external completion.
- Activity metrics including counts for success, failure, timeout, and cancel.
- Dual use — execute an Activity within a Workflow or standalone with no Worker code changes.

## Public Preview limitations

- **Pause, Reset, and Update Options** are not supported in Public Preview; scheduled for GA. <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- **`TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy** are not supported yet. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->

Activity Operations (Pause, Unpause, Reset, Update Options) do not apply to Standalone Activities. <!-- docs/encyclopedia/activities/activity-operations.mdx:31 -->

The corresponding `temporal activity` CLI subcommands explicitly state "Not supported for Standalone Activities": `pause` <!-- docs/cli/activity.mdx:200-202 -->, `reset` <!-- docs/cli/activity.mdx:234-236 -->, `unpause` <!-- docs/cli/activity.mdx:381-384 -->, `update-options` <!-- docs/cli/activity.mdx:432-436 -->.

## Activity Info and serialization context

A Standalone Activity Execution is not tied to a parent Workflow Execution, so any Activity Info or serialization context fields that reference the invoking Workflow (Workflow ID, Workflow Run ID, Workflow Type, etc.) are absent when the Activity runs standalone.

<!-- VERIFY: The `documentation/` clone does not specify, per-SDK, exactly which Activity Info / serialization context fields become null/None/unset under a standalone activation. Treat any field-level claim about this with care and consult the per-SDK source until the planned `0010-serialization-context` content lands. -->

## CLI: `temporal activity` subcommands

The `temporal activity` group supports Standalone Activities via these subcommands: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:136-137 -->

The CLI page is auto-generated from `commands.yml`. <!-- docs/cli/activity.mdx:32-33 -->

### `start` — Start a Standalone Activity, return Activity ID and Run ID

<!-- docs/cli/activity.mdx:318-359 -->

```bash
temporal activity start \
    --activity-id YourActivityId \
    --type YourActivity \
    --task-queue YourTaskQueue \
    --start-to-close-timeout 5m \
    --input '{"some-key": "some-value"}'
```

Required flags: `--activity-id`, `--type`, `--task-queue`. Required additionally: either `--start-to-close-timeout` or `--schedule-to-close-timeout`. <!-- docs/cli/activity.mdx:151-154 -->

Notable optional flags: `--id-conflict-policy` (`Fail`, `UseExisting`) <!-- docs/cli/activity.mdx:341 -->, `--id-reuse-policy` (`AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`) <!-- docs/cli/activity.mdx:342 -->, `--priority-key` (1–5, default 3) <!-- docs/cli/activity.mdx:347 -->, `--fairness-key`, `--fairness-weight` (0.001–1000) <!-- docs/cli/activity.mdx:337-338 -->, `--retry-maximum-attempts` (1 disables retries; 0 means unlimited) <!-- docs/cli/activity.mdx:349 -->, `--search-attribute` <!-- docs/cli/activity.mdx:354 -->, `--heartbeat-timeout` <!-- docs/cli/activity.mdx:340 -->.

### `execute` — Start and block until the Activity completes

<!-- docs/cli/activity.mdx:117-159 -->

```bash
temporal activity execute \
    --activity-id YourActivityId \
    --type YourActivity \
    --task-queue YourTaskQueue \
    --start-to-close-timeout 30s \
    --input '{"some-key": "some-value"}'
```

The flag set is the same as `start`. The result is output to stdout. <!-- docs/cli/activity.mdx:119-120 -->

### `result` — Wait for an existing Standalone Activity's result

<!-- docs/cli/activity.mdx:301-316 -->

```bash
temporal activity result \
    --activity-id YourActivityId
```

Flags: `--activity-id` (required), `--run-id` (optional, latest run if not set).

### `list` — List Standalone Activities matching a query

<!-- docs/cli/activity.mdx:180-198 -->

```bash
temporal activity list \
    --query 'ActivityType="YourActivity"'
```

Flags: `--query` / `-q`, `--limit`, `--page-size`. Uses [List Filter](https://docs.temporal.io/list-filter) syntax.

### `count` — Count Standalone Activities matching a query

<!-- docs/cli/activity.mdx:81-98 -->

```bash
temporal activity count \
    --query 'ActivityType="YourActivity"'
```

Returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:103-104 -->

### `describe` — Show information about a Standalone Activity

<!-- docs/cli/activity.mdx:100-115 -->

```bash
temporal activity describe \
    --activity-id YourActivityId
```

Flags: `--activity-id` (required), `--run-id` (optional), `--raw` (optional bool).

### `cancel` — Request cancellation of a Standalone Activity

<!-- docs/cli/activity.mdx:37-58 -->

```bash
temporal activity cancel \
    --activity-id YourActivityId
```

Cancellation transitions the Activity's run state to `CancelRequested`. If the Activity is heartbeating, a cancellation error is raised when the next heartbeat response is received; if the Activity allows that error to propagate, the Activity transitions to canceled status. Flags: `--activity-id` (required), `--reason`, `--run-id`.

### `terminate` — Terminate a Standalone Activity

<!-- docs/cli/activity.mdx:361-379 -->

```bash
temporal activity terminate \
    --activity-id YourActivityId \
    --reason YourReason
```

Activity code cannot see or respond to terminations. <!-- docs/cli/activity.mdx:371 -->

### `complete` / `fail` — manual completion or failure

These two subcommands accept either a Workflow Activity or a Standalone Activity:

- For a **Standalone Activity**, omit `--workflow-id`; `--run-id` is the Activity Run ID. <!-- docs/cli/activity.mdx:78-79, 177-178 -->
- For a **Workflow Activity**, supply `--workflow-id`; `--run-id` is the Workflow Run ID. <!-- docs/cli/activity.mdx:78-79, 177-178 -->

`complete` example: <!-- docs/cli/activity.mdx:60-79 -->

```bash
temporal activity complete \
    --activity-id YourActivityId \
    --result '{"YourResultKey": "YourResultVal"}'
```

`fail` example: <!-- docs/cli/activity.mdx:160-178 -->

```bash
temporal activity fail \
    --activity-id YourActivityId \
    --reason "downstream returned 500"
```

## Use cases

Standalone Activities are Temporal's [job queue](https://docs.temporal.io/evaluate/development-production-features/job-queue) primitive — sending an email, processing a webhook, syncing data, or executing a single function reliably with built-in retries and timeouts. <!-- docs/encyclopedia/activities/standalone-activity.mdx:73-75 -->

## Visibility

- `temporal activity list` and `temporal activity count` (or the SDK equivalents) take [List Filter](https://docs.temporal.io/list-filter) queries by type, status, task queue, etc. <!-- docs/encyclopedia/activities/standalone-activity.mdx:99-100 -->
- These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included. <!-- docs/develop/python/activities/standalone-activities.mdx:346, docs/develop/typescript/activities/standalone-activities.mdx:344, docs/develop/dotnet/activities/standalone-activities.mdx:356, docs/develop/java/activities/standalone-activities.mdx:350-351 -->
- All existing [Activity metrics](https://docs.temporal.io/cloud/metrics/openmetrics/metrics-reference#activity-metrics) apply to Standalone Activities, including counts for scheduled, started, completed, failed, timed out, and canceled. <!-- docs/encyclopedia/activities/standalone-activity.mdx:95-97 -->

## Priority and Fairness

`--priority-key`, `--fairness-key`, and `--fairness-weight` are accepted on `temporal activity start` and `temporal activity execute`. <!-- docs/cli/activity.mdx:337-338, 347 --> See `references/core/priority-fairness.md` for the conceptual model.

## SDK references

- Python — `references/python/standalone-activities.md`
- TypeScript — `references/typescript/standalone-activities.md`
- .NET — `references/dotnet/standalone-activities.md`
- Java — `references/java/standalone-activities.md`
