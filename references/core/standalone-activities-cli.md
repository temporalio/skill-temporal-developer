# Standalone Activities — `temporal activity` CLI Reference

This reference covers the `temporal activity` CLI surface as it pertains to **Standalone Activities** (a [Public Preview](https://docs.temporal.io/evaluate/development-production-features/release-stages#public-preview) feature). It transcribes flag tables verbatim from the auto-generated CLI docs and flags Public Preview gaps.

## Prerequisites

- **Temporal CLI v1.7.0 or higher** <!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->
- **Temporal Server v1.31.0 or higher** <!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->
- The Temporal **Dev Server has Standalone Activities enabled by default** for local testing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:138 -->

Verify the installed version with `temporal --version`; it should report v1.7.0 or higher.

## Public Preview limitations (CLI surface)

The following `temporal activity` subcommands exist as general activity-management commands but are **not supported for Standalone Activities** in Public Preview:

- `pause` — Not supported for Standalone Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->
- `reset` — Not supported for Standalone Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->
- `update-options` — Not supported for Standalone Activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->

These subcommands continue to work for Workflow-invoked Activities; only Standalone Activity targeting is gated. Support is scheduled for GA. <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->

The subcommands explicitly documented as supported for Standalone Activities are: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:135-136 --> The `complete` and `fail` commands accept Standalone Activities as well (they take a Standalone Activity ID when `--workflow-id` is omitted). <!-- docs/cli/activity.mdx:78,81 --> <!-- docs/cli/activity.mdx:176,180 -->

---

## Subcommands

For shared auth, address, namespace, codec, and TLS flags, see the **Global Flags** reference at the bottom of `/Users/don/work/skills/documentation/docs/cli/activity.mdx` (lines 507–544). <!-- docs/cli/activity.mdx:507 --> They apply to every subcommand below and are not transcribed here.

### `cancel`

Request cancellation of a Standalone Activity. <!-- docs/cli/activity.mdx:39 --> Transitions run state to `CancelRequested`; if the Activity is heartbeating, a cancellation error is delivered on the next heartbeat response. <!-- docs/cli/activity.mdx:46-50 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--reason` | No | Reason for cancellation. |
| `--run-id`, `-r` | No | Activity Run ID. If not set, targets the latest run. |

<!-- docs/cli/activity.mdx:54-58 -->

### `complete`

Mark an Activity as successfully finished and return a JSON result. <!-- docs/cli/activity.mdx:64-65 --> For a Standalone Activity, omit `--workflow-id`; `--run-id` then refers to the Activity Run ID. <!-- docs/cli/activity.mdx:80-81 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. May be a Workflow Activity or Standalone Activity ID. |
| `--result` | Yes | Result `JSON` to return. |
| `--run-id`, `-r` | No | Run ID. Workflow Run ID for workflow Activities; Activity Run ID for Standalone Activities. |
| `--workflow-id`, `-w` | No | Workflow ID. Required for workflow Activities. Omit for Standalone Activities. |

<!-- docs/cli/activity.mdx:76-81 -->

### `count`

Return a count of Standalone Activities matching a filter. <!-- docs/cli/activity.mdx:85-86 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--query`, `-q` | No | Query to filter Activity Executions to count. |

<!-- docs/cli/activity.mdx:98-100 -->

### `describe`

Display information about a Standalone Activity. <!-- docs/cli/activity.mdx:104 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--raw` | No | Print properties without changing their format. |
| `--run-id`, `-r` | No | Activity Run ID. If not set, targets the latest run. |

<!-- docs/cli/activity.mdx:113-117 -->

### `execute`

Start a new Standalone Activity and **block until it completes**, printing the result to stdout. <!-- docs/cli/activity.mdx:121-122 --> Either `--start-to-close-timeout` or `--schedule-to-close-timeout` is required. <!-- docs/cli/activity.mdx:153,156 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--fairness-key` | No | Fairness key (max 64 bytes) for proportional task dispatch. |
| `--fairness-weight` | No | Weight `[0.001-1000]` for this fairness key. |
| `--headers` | No | Temporal activity headers in `KEY=VALUE` format. May be passed multiple times. |
| `--heartbeat-timeout` | No | Maximum time between successful Worker heartbeats. |
| `--id-conflict-policy` | No | Policy when an Activity with the same ID is currently running. Accepted values: `Fail`, `UseExisting`. |
| `--id-reuse-policy` | No | Policy when an Activity with the same ID exists and has completed. Accepted values: `AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`. |
| `--input`, `-i` | No | Input value (JSON, or use `--input-meta`). Repeatable. |
| `--input-base64` | No | Assume inputs are base64-encoded. |
| `--input-file` | No | Path(s) to input file(s). Repeatable. |
| `--input-meta` | No | Input payload metadata as `KEY=VALUE`. |
| `--priority-key` | No | Priority key (1–5, lower = higher priority). Default 3. |
| `--retry-backoff-coefficient` | No | Coefficient for the next retry interval. Must be ≥1. |
| `--retry-initial-interval` | No | Interval of the first retry. |
| `--retry-maximum-attempts` | No | Maximum attempts. `1` disables retries; `0` is unlimited. |
| `--retry-maximum-interval` | No | Maximum interval between retries. |
| `--schedule-to-close-timeout` | No | Maximum total time including retries. |
| `--schedule-to-start-timeout` | No | Maximum time a task can sit in the queue. |
| `--search-attribute` | No | Search Attribute in `KEY=VALUE`. Repeatable. |
| `--start-to-close-timeout` | No | Maximum time for a single attempt. |
| `--static-details` | No | Static Activity details for UIs (Markdown). _(Experimental)_ |
| `--static-summary` | No | Static Activity summary for UIs (Markdown). _(Experimental)_ |
| `--task-queue`, `-t` | Yes | Activity task queue. |
| `--type` | Yes | Activity Type name. |

<!-- docs/cli/activity.mdx:135-160 -->

### `fail`

Fail an Activity, marking it as having encountered an error. <!-- docs/cli/activity.mdx:164 --> For Standalone Activities, omit `--workflow-id`. <!-- docs/cli/activity.mdx:179-180 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. May be a Workflow Activity or Standalone Activity ID. |
| `--detail` | No | Failure detail (JSON). Attached as the failure details payload. |
| `--reason` | No | Failure reason. Attached as the failure message. |
| `--run-id`, `-r` | No | Run ID. Workflow Run ID for workflow Activities; Activity Run ID for Standalone Activities. |
| `--workflow-id`, `-w` | No | Workflow ID. Required for workflow Activities. Omit for Standalone Activities. |

<!-- docs/cli/activity.mdx:174-180 -->

### `list`

List Standalone Activities. Use `--query` to filter results. <!-- docs/cli/activity.mdx:184 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--limit` | No | Maximum number of Activity Executions to display. |
| `--page-size` | No | Maximum number of Activity Executions to fetch per page. |
| `--query`, `-q` | No | Query to filter the Activity Executions to list. |

<!-- docs/cli/activity.mdx:196-200 -->

### `pause`

> **Not supported for Standalone Activities** in Public Preview. <!-- docs/cli/activity.mdx:204 --> <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 --> Use this only for Workflow-invoked Activities; scheduled for GA.

Pauses an Activity so that it will not run again until unpaused. <!-- docs/cli/activity.mdx:202-211 --> See `unpause` to resume, or `reset` to also restart from the beginning. <!-- docs/cli/activity.mdx:225-226 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | No | Activity ID to pause. Mutually exclusive with `--activity-type`. |
| `--activity-type` | No | All activities of this Activity Type will be paused. _(Experimental for Type-targeting.)_ |
| `--identity` | No | Identity of the user or client submitting the request. |
| `--run-id`, `-r` | No | Run ID. |
| `--workflow-id`, `-w` | Yes | Workflow ID. |

<!-- docs/cli/activity.mdx:230-236 -->

### `reset`

> **Not supported for Standalone Activities** in Public Preview. <!-- docs/cli/activity.mdx:240 --> <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 --> Use this only for Workflow-invoked Activities.

Resets an Activity as if it were first being scheduled — resetting attempts, timeout, and optionally heartbeat details. <!-- docs/cli/activity.mdx:240-244 --> Either `--activity-id`, `--activity-type`, or `--match-all` must be specified. <!-- docs/cli/activity.mdx:280 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | No | Activity ID to reset. Requires `--workflow-id`. Mutually exclusive with `--query`, `--match-all`, `--activity-type`. |
| `--activity-type` | No | Activities of this Type will be reset. _(Experimental.)_ |
| `--headers` | No | Temporal workflow headers in `KEY=VALUE`. Repeatable. |
| `--jitter` | No | Reset within a random window inside this duration. Only with `--query`. |
| `--keep-paused` | No | If the activity was paused, keep it paused. |
| `--match-all` | No | Reset every activity. _(Experimental.)_ |
| `--query`, `-q` | No | SQL-like List Filter for batch reset. _(Experimental.)_ |
| `--reason` | No | Reason for batch operation. Only with `--query`. |
| `--reset-attempts` | No | Reset the activity attempts. |
| `--reset-heartbeats` | No | Reset the Activity's heartbeats. Only works with `--reset-attempts`. |
| `--restore-original-options` | No | Restore the original options of the activity. |
| `--rps` | No | Limit batch's requests per second. Only with `--query`. |
| `--run-id`, `-r` | No | Run ID. Only with `--workflow-id`. |
| `--workflow-id`, `-w` | No | Workflow ID. Set either `--workflow-id` or `--query`. |
| `--yes`, `-y` | No | Skip confirmation. Only with `--query`. |

<!-- docs/cli/activity.mdx:292-308 -->

### `result`

Wait for a Standalone Activity to complete and output the result. <!-- docs/cli/activity.mdx:312-313 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--run-id`, `-r` | No | Activity Run ID. If not set, targets the latest run. |

<!-- docs/cli/activity.mdx:322-325 -->

### `start`

Start a new Standalone Activity. Outputs the Activity ID and Run ID and returns immediately (fire-and-forget). <!-- docs/cli/activity.mdx:329-330 --> Either `--start-to-close-timeout` or `--schedule-to-close-timeout` is required. <!-- docs/cli/activity.mdx:361,364 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--fairness-key` | No | Fairness key (max 64 bytes). |
| `--fairness-weight` | No | Weight `[0.001-1000]`. |
| `--headers` | No | Temporal activity headers in `KEY=VALUE`. Repeatable. |
| `--heartbeat-timeout` | No | Maximum time between successful Worker heartbeats. |
| `--id-conflict-policy` | No | Accepted: `Fail`, `UseExisting`. |
| `--id-reuse-policy` | No | Accepted: `AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`. |
| `--input`, `-i` | No | Input value. Repeatable. |
| `--input-base64` | No | Assume inputs are base64-encoded. |
| `--input-file` | No | Path(s) to input file(s). Repeatable. |
| `--input-meta` | No | Input payload metadata as `KEY=VALUE`. |
| `--priority-key` | No | Priority key (1–5, lower = higher priority). Default 3. |
| `--retry-backoff-coefficient` | No | Must be ≥1. |
| `--retry-initial-interval` | No | First retry interval. |
| `--retry-maximum-attempts` | No | `1` disables retries; `0` is unlimited. |
| `--retry-maximum-interval` | No | Cap between retries. |
| `--schedule-to-close-timeout` | No | Total deadline including retries. |
| `--schedule-to-start-timeout` | No | Queue waiting deadline. |
| `--search-attribute` | No | Search Attribute in `KEY=VALUE`. Repeatable. |
| `--start-to-close-timeout` | No | Single-attempt deadline. |
| `--static-details` | No | Static Activity details (Markdown). _(Experimental)_ |
| `--static-summary` | No | Static Activity summary (Markdown). _(Experimental)_ |
| `--task-queue`, `-t` | Yes | Activity task queue. |
| `--type` | Yes | Activity Type name. |

<!-- docs/cli/activity.mdx:343-368 -->

### `terminate`

Terminate a Standalone Activity. Activity code cannot see or respond to terminations. <!-- docs/cli/activity.mdx:372,380 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | Yes | Activity ID. |
| `--reason` | No | Reason for termination. Defaults to a message with the current user's name. |
| `--run-id`, `-r` | No | Activity Run ID. If not set, targets the latest run. |

<!-- docs/cli/activity.mdx:384-388 -->

### `unpause`

Re-schedule a previously-paused Activity for execution. **Not supported for Standalone Activities.** <!-- docs/cli/activity.mdx:392-393 --> <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 --> (Public Preview gap is `pause`/`reset`/`update-options`; `unpause` only ever applies to paused Activities, which on Standalone Activities cannot exist in Public Preview.)

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | No | Activity ID to unpause. Requires `--workflow-id`. Mutually exclusive with `--query`, `--match-all`, `--activity-type`. |
| `--activity-type` | No | Activities of this Type will unpause. _(Experimental.)_ |
| `--headers` | No | Temporal workflow headers in `KEY=VALUE`. Repeatable. |
| `--jitter` | No | Random start window. Only with `--query`. |
| `--match-all` | No | Unpause every paused activity. _(Experimental.)_ |
| `--query`, `-q` | No | SQL-like List Filter for batch unpause. _(Experimental.)_ |
| `--reason` | No | Reason for batch operation. Only with `--query`. |
| `--reset-attempts` | No | Reset the activity attempts. |
| `--reset-heartbeats` | No | Reset heartbeats. Only works with `--reset-attempts`. |
| `--rps` | No | Limit batch's requests per second. Only with `--query`. |
| `--run-id`, `-r` | No | Run ID. Only with `--workflow-id`. |
| `--workflow-id`, `-w` | No | Workflow ID. Set either `--workflow-id` or `--query`. |
| `--yes`, `-y` | No | Skip confirmation. Only with `--query`. |

<!-- docs/cli/activity.mdx:430-444 -->

### `update-options`

> **Not supported for Standalone Activities** in Public Preview. <!-- docs/cli/activity.mdx:450 --> <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 --> Use this only for Workflow-invoked Activities; scheduled for GA.

Update the options of a running Activity passed in from a Workflow. Updates are incremental. <!-- docs/cli/activity.mdx:448-450 --> Either `--activity-id`, `--activity-type`, or `--match-all` must be specified. <!-- docs/cli/activity.mdx:471 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--activity-id`, `-a` | No | Activity ID. Requires `--workflow-id`. |
| `--activity-type` | No | Activities of this Type will be updated. _(Experimental.)_ |
| `--headers` | No | Temporal workflow headers in `KEY=VALUE`. Repeatable. |
| `--heartbeat-timeout` | No | Maximum time between successful worker heartbeats. |
| `--match-all` | No | Update every activity. _(Experimental.)_ |
| `--query`, `-q` | No | SQL-like List Filter for batch update. _(Experimental.)_ |
| `--reason` | No | Reason for batch operation. Only with `--query`. |
| `--restore-original-options` | No | Restore the original options of the activity. |
| `--retry-backoff-coefficient` | No | Must be ≥1. |
| `--retry-initial-interval` | No | First retry interval. |
| `--retry-maximum-attempts` | No | `1` disables retries; `0` is unlimited. |
| `--retry-maximum-interval` | No | Cap between retries. |
| `--rps` | No | Limit batch's requests per second. Only with `--query`. |
| `--run-id`, `-r` | No | Run ID. Only with `--workflow-id`. |
| `--schedule-to-close-timeout` | No | Total deadline including retries. |
| `--schedule-to-start-timeout` | No | Queue waiting deadline. |
| `--start-to-close-timeout` | No | Single-attempt deadline. |
| `--task-queue` | No | Name of the task queue. |
| `--workflow-id`, `-w` | No | Workflow ID. Set either `--workflow-id` or `--query`. |
| `--yes`, `-y` | No | Skip confirmation. Only with `--query`. |

<!-- docs/cli/activity.mdx:486-505 -->

---

## Global Flags

Shared flags for `--address`, `--api-key`, `--namespace`, `--codec-endpoint`/`--codec-auth`, `--tls*`, `--grpc-meta`, `--identity`, `--output`, etc. live in the `## Global Flags` section of the docs file. See `/Users/don/work/skills/documentation/docs/cli/activity.mdx` lines 507–544. <!-- docs/cli/activity.mdx:507-544 -->

---

## Common flows

### Start-and-wait (synchronous)

Use `execute` to start a Standalone Activity and block on its result. <!-- docs/cli/activity.mdx:119-122 --> The result is printed to stdout when the Activity completes.

### Fire-and-forget, retrieve later

1. Use `start` to schedule the Activity; the command outputs the Activity ID and Run ID. <!-- docs/cli/activity.mdx:329-330 -->
2. Use `result` later (from any machine) with the same `--activity-id` to block until completion and read the output. <!-- docs/cli/activity.mdx:312-313 -->

### Listing and counting

- Use `list` with `--query` (a [List Filter](https://docs.temporal.io/list-filter)) to enumerate Standalone Activity Executions. <!-- docs/cli/activity.mdx:184 -->
- Use `count` with the same query syntax to obtain a total count without paging. <!-- docs/cli/activity.mdx:85-86 -->

### Inspect a single Activity

Use `describe` with `--activity-id` (and optionally `--run-id`) to view current state, attempts, and the latest failure. <!-- docs/cli/activity.mdx:104 -->

### Cancel vs. terminate

- `cancel` requests cooperative cancellation; the Activity sees the cancellation on its next heartbeat and may run cleanup. <!-- docs/cli/activity.mdx:39 --> <!-- docs/cli/activity.mdx:46-50 -->
- `terminate` ends the Activity unilaterally; Activity code cannot see or respond. <!-- docs/cli/activity.mdx:372 --> <!-- docs/cli/activity.mdx:380 -->

### External completion

If the Activity uses manual completion, use `complete` (with `--workflow-id` omitted) to deliver the result, or `fail` to deliver an error. <!-- docs/cli/activity.mdx:78-81 --> <!-- docs/cli/activity.mdx:176-180 -->
