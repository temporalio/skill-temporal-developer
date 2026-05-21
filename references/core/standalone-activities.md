# Standalone Activities

A **Standalone Activity** is a top-level [Activity Execution](../../../documentation/docs/encyclopedia/activities/activity-execution.mdx) started directly by a Temporal Client, without a Workflow wrapping it. <!-- docs/encyclopedia/activities/standalone-activity.mdx:50 -->

This reference covers the concept. For language-specific code, see the per-SDK references listed at the bottom. For the `temporal activity` CLI, see `references/core/standalone-activities-cli.md`.

## Status and dependencies

Standalone Activities are a **Public Preview** feature. <!-- docs/encyclopedia/activities/standalone-activity.mdx:21-25 --> They require:

- **Temporal CLI v1.7.0 or higher** <!-- docs/encyclopedia/activities/standalone-activity.mdx:114 -->
- **Temporal Server v1.31.0 or higher** <!-- docs/encyclopedia/activities/standalone-activity.mdx:114 -->

The Temporal Dev Server has Standalone Activities enabled by default for local testing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:138 -->

## When to use a Standalone Activity vs. a Workflow

- If you need to **orchestrate multiple Activities**, use a [Workflow](../../../documentation/docs/encyclopedia/activities/activities.mdx). <!-- docs/encyclopedia/activities/standalone-activity.mdx:31-32 -->
- If you just need to **execute a single Activity**, use a Standalone Activity. <!-- docs/encyclopedia/activities/standalone-activity.mdx:31-32 -->

Standalone Activities are framed as Temporal's [job queue](../../../documentation/docs/evaluate/development-production-features/job-queue.mdx) — the simplest way to run durable, retryable tasks on Temporal. <!-- docs/encyclopedia/activities/standalone-activity.mdx:34-35 -->

Typical use cases include sending an email, processing a webhook, syncing data, or executing a single function reliably with built-in retries and timeouts. <!-- docs/encyclopedia/activities/standalone-activity.mdx:72-74 -->

## Dual use: same Activity Function, two execution modes

You write your Activity Functions the same way for both. **The same Activity Function can be executed as a Standalone Activity and as a Workflow Activity with no code changes.** <!-- docs/encyclopedia/activities/standalone-activity.mdx:56-57 --> No Worker code changes are required to switch between the two modes. <!-- docs/encyclopedia/activities/standalone-activity.mdx:90 -->

## Key features

- **Top-level execution** — execute any Temporal Activity as a top-level primitive without the overhead of a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:77 -->
- **Async job processing model** — schedule → dispatch → process → result. <!-- docs/encyclopedia/activities/standalone-activity.mdx:78 -->
- **No head-of-line blocking** — a slow job doesn't block dispatch of other Tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:79 -->
- **Arbitrary-length jobs** — heartbeats provide liveness and progress checkpointing. <!-- docs/encyclopedia/activities/standalone-activity.mdx:80 -->
- **At-least-once execution by default** with a native retry policy and timeouts. <!-- docs/encyclopedia/activities/standalone-activity.mdx:81 -->
- **At-most-once execution** if retry max attempts is `1`. <!-- docs/encyclopedia/activities/standalone-activity.mdx:82 -->
- **Addressable** — get an Activity ID / Run ID and use it to fetch the result, cancel, or terminate the execution. <!-- docs/encyclopedia/activities/standalone-activity.mdx:83 -->
- **Deduplication** — controlled via conflict and reuse policies (see below). <!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
- **Separate ID space from Workflows** — Standalone Activities are a different kind of top-level execution; their IDs do not collide with, and are not addressable as, Workflow IDs. <!-- docs/encyclopedia/activities/standalone-activity.mdx:85 -->
- **Priority and fairness** — multi-tenant fairness, weighted priority tiers, and safeguards against starvation of lower-weighted tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:86 -->
- **Visibility** — list Activity Executions and view status, retry count, and last error. <!-- docs/encyclopedia/activities/standalone-activity.mdx:87 -->
- **Manual completion by ID (or token)** — ignore the Activity return value and wait for external completion. <!-- docs/encyclopedia/activities/standalone-activity.mdx:88 -->
- **Activity metrics** — including counts for success, failure, timeout, and cancel. <!-- docs/encyclopedia/activities/standalone-activity.mdx:89 -->

### Conflict and reuse policies (Public Preview)

Only the values below appear in the upstream documentation for Public Preview:

- Conflict policy: `USE_EXISTING` <!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
- Reuse policy: `REJECT_DUPLICATES` <!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->

The following are **not** supported in Public Preview:

- `TerminateExisting` conflict policy <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- `TerminateIfRunning` reuse policy <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

Do not assume any other enum values exist for Standalone Activities until they are documented upstream.

## Public Preview limitations

The Public Preview has the following known limitations: <!-- docs/encyclopedia/activities/standalone-activity.mdx:105-110 -->

- **Pause, reset, and update options are not supported in Public Preview but are scheduled for GA.** <!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->
- **`TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet.** <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

## Observability

All existing [Activity metrics](../../../documentation/docs/cloud/metrics/openmetrics/metrics-reference.mdx) apply to Standalone Activities. This includes counts for scheduled, started, completed, failed, timed out, and canceled activities. <!-- docs/encyclopedia/activities/standalone-activity.mdx:94-96 --> No new Standalone-specific metric names are introduced; query the same Activity metric series you already use for Workflow Activities. <!-- docs/cloud/metrics/openmetrics/metrics-reference.mdx:315 -->

You can query Standalone Activity Executions using [List Filters](../../../documentation/docs/encyclopedia/visibility.mdx) by type, status, task queue, and other attributes — either through an SDK or via the `temporal activity list` CLI command. <!-- docs/encyclopedia/activities/standalone-activity.mdx:98-99 -->

`CountActivities` returns the total number of Standalone Activity Executions matching a filter, analogous to counting Workflow Executions. This is the total count of executions (running, completed, failed, etc.) — **not** the number of queued tasks. <!-- docs/encyclopedia/activities/standalone-activity.mdx:101-103 -->

## Temporal Cloud support

Standalone Activities in Temporal Cloud are available as a **Public Preview** feature. <!-- docs/encyclopedia/activities/standalone-activity.mdx:140-142 -->

## Billing framing (Temporal Cloud)

Running an Activity as a Standalone Activity results in **fewer Billable Actions** than running the same single Activity inside a Workflow. <!-- docs/encyclopedia/activities/standalone-activity.mdx:52-54 --> If your Activity Execution is short-lived, you may also see lower latency due to fewer Worker round-trips. <!-- docs/encyclopedia/activities/standalone-activity.mdx:52-54 --> Refer to the Temporal Cloud Actions Usage documentation for the authoritative count semantics; do not extrapolate specific numeric ratios.

## Where to go next

Per-language references in this skill:

- `references/python/standalone-activities.md`
- `references/go/standalone-activities.md`
- `references/java/standalone-activities.md`
- `references/dotnet/standalone-activities.md`

CLI reference in this skill:

- `references/core/standalone-activities-cli.md`

> **TypeScript SDK note:** Upstream documentation does not currently include a TypeScript Standalone Activities quickstart or reference. Coverage is upstream-pending; do not assume parity with Python/Go/Java/.NET until the docs land. <!-- docs/encyclopedia/activities/standalone-activity.mdx:63-66 -->
