# Standalone Activities

Standalone Activities are a top-level [Activity Execution](/activity-execution) started directly by a Temporal Client, **without a Workflow**. They are Temporal's job-queue primitive — the simplest way to run a durable, retryable task on Temporal.

If you need to orchestrate multiple Activities, use a Workflow. If you just need to execute a single Activity, use a Standalone Activity.

The same Activity Function can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.

## Release stage (Public Preview)

Standalone Activities are available as a **Public Preview** feature in Temporal Cloud and in the Temporal CLI v1.7.0 or higher with Temporal Server v1.31.0 or higher.

SDK support stability differs by language — check the per-language reference:

- **.NET** SDK — Public Preview
- **Python** SDK — Public Preview
- **Java** SDK — Pre-release
- **TypeScript** SDK — Pre-release

## When to use Standalone Activities vs. a Workflow

| Use case | Choose |
|---|---|
| Run a single function reliably with retries and timeouts (send email, process webhook, sync data)  | Standalone Activity |
| Orchestrate multiple Activities, branching, child workflows, signals/queries/updates  | Workflow |
| Need lower per-execution Billable Actions in Temporal Cloud for a single Activity Execution  | Standalone Activity |
| Need lower latency for short-lived single-Activity executions (fewer Worker round-trips)  | Standalone Activity |

## Key features

Transcribed from the encyclopedia page:

- Execute any Temporal Activity as a top-level primitive without the overhead of a Workflow.
- Native async job-processing model: schedule → dispatch → process → result.
- No head-of-line blocking — a slow job doesn't block dispatch of other Tasks.
- Arbitrary-length jobs with heartbeats for liveness and checkpointing progress.
- At-least-once execution by default with native retry policy and timeouts.
- At-most-once execution if retry max attempts is 1.
- Addressable — get an Activity ID / Run ID and get the result, cancel, or terminate.
- Deduplication — conflict policy `USE_EXISTING`, reuse policy `REJECT_DUPLICATES`.
- Separate ID space from Workflows — Standalone Activities are a different kind of top-level execution.
- Priority and fairness — multi-tenant fairness, weighted priority tiers, safeguards against starvation of lower-weighted tasks. See `references/core/priority-fairness.md`.
- Visibility — list Activity Executions and view status, retry count, and last error.
- Manual completion by ID (or token) — ignore the Activity return and wait for external completion.
- Activity metrics — including counts for success, failure, timeout, and cancel.
- Dual use — the same Activity runs inside a Workflow or standalone with no Worker code changes.

## Public Preview limitations

- **Pause, reset, and update options are not supported in Public Preview** but scheduled for GA.
- **`TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet.**

If you rely on any of these, do not migrate the workload to Standalone Activities yet.

## Prerequisites

- **Temporal CLI v1.7.0 or higher** and **Temporal Server v1.31.0 or higher**.
- The Temporal Dev Server (`temporal server start-dev`) has Standalone Activities enabled by default for local testing.

Install with Homebrew or follow your platform's instructions in `references/core/install_cli.md`:

```bash
brew install temporal
```

Verify:

```bash
temporal --version
```

The output should be v1.7.0 or higher (e.g. `temporal version 1.7.0 (Server 1.31.0, UI 2.49.1)`).

## Temporal CLI subcommands

The `temporal activity` subcommand supports Standalone Activities with these commands:

| Command | Purpose |
|---|---|
| `temporal activity start` | Durably enqueue a Standalone Activity without waiting for the result. |
| `temporal activity execute` | Start a Standalone Activity and block until it returns. |
| `temporal activity result` | Wait for and print a Standalone Activity result by Activity ID. |
| `temporal activity list` | List Standalone Activity Executions matching a List Filter. |
| `temporal activity count` | Count Standalone Activity Executions matching a List Filter. |
| `temporal activity describe` | Describe a single Standalone Activity Execution. |
| `temporal activity cancel` | Cancel a running Standalone Activity. |
| `temporal activity terminate` | Terminate a Standalone Activity. |

Do **not** assume `temporal activity pause`, `reset`, or `update` exist — they are explicitly listed as **not supported in Public Preview**.

### Common CLI flags

The four key flags on `temporal activity start` / `execute` are `--type`, `--activity-id`, `--task-queue`, and one of `--start-to-close-timeout` / `--schedule-to-close-timeout`. Inputs are passed via `--input` (JSON-encoded). Example:

```bash
temporal activity execute \
  --type compose_greeting \
  --activity-id my-standalone-activity-id \
  --task-queue my-standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '{"greeting": "Hello", "name": "World"}'
```

To wait for a result by Activity ID after using `start`:

```bash
temporal activity result --activity-id my-standalone-activity-id
```

## Observability

All existing [Activity metrics](/cloud/metrics/openmetrics/metrics-reference#activity-metrics) apply to Standalone Activities — counts for scheduled, started, completed, failed, timed out, and canceled.

Use [List Filters](/list-filter) to query Standalone Activity Executions by type, status, task queue, and other attributes — either via the SDK or via `temporal activity list`.

`CountActivities` returns the total number of Standalone Activity Executions matching a filter, analogous to counting Workflow Executions. This is the **total count of executions** (running, completed, failed, etc.) — **not** the number of queued tasks.

The list/count APIs return only Standalone Activity Executions — Activities running inside Workflows are **not** included.

The Temporal Web UI exposes Standalone Activities through a dedicated nav-bar item at the top left of the page.

## Temporal Cloud support

Standalone Activities in Temporal Cloud is available as a Public Preview feature.

The per-language samples use that SDK's environment-config loader (`ClientConfig.load_client_connect_config()` for Python, `loadClientConnectConfig()` for TypeScript, `ClientEnvConfig.LoadClientConnectOptions()` for .NET, `ClientConfigProfile.load()` for Java) so the same Worker and starter code runs against a local dev server or against Temporal Cloud with no code changes.

Connection environment variables (mTLS):

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

Or API key:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

## Activity code is the same as a Workflow-driven Activity

Across all four SDKs the docs are explicit: you write the Activity function the same way and register it with the Worker the same way. The Worker doesn't need to know whether an Activity will be invoked from a Workflow or as a Standalone Activity.

`StartActivityOptions` (or its SDK equivalent) requires at minimum an **Activity ID**, a **Task Queue**, and at least one of **Start-To-Close Timeout** or **Schedule-To-Close Timeout**.

## Language-specific references

- **.NET** — `references/dotnet/standalone-activities.md`
- **Python** — `references/python/standalone-activities.md`
- **Java** — `references/java/standalone-activities.md`
- **TypeScript** — `references/typescript/standalone-activities.md`

## Related

- `references/core/priority-fairness.md` — Priority keys, fairness keys and weights, rate limiting. Standalone Activities participate in the same priority/fairness machinery.
- `references/core/install_cli.md` — Temporal CLI install instructions per platform.
- `references/core/error-reference.md` — Activity timeouts and retry semantics.
