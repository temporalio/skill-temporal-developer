# Authoring Log

## Standalone Activities feature (added per `STANDALONE_ACTIVITIES_AUTHORING_PLAN.md`)

Six new reference files plus a surgical `SKILL.md` edit. Each reference file was authored by an isolated subagent that read only the docs paths assigned to it (no cross-reading of sibling reference files).

### `references/core/standalone-activities.md`
- **Docs consulted:** `docs/encyclopedia/activities/standalone-activity.mdx` (primary), `docs/cloud/metrics/openmetrics/metrics-reference.mdx` (line 315, for the no-new-metric-names claim). Supporting files (`activities.mdx`, `activity-execution.mdx`, `job-queue.mdx`) referenced by link only.
- **Citations:** 26 inline.
- **VERIFY markers:** 0.
- Self-checks passed: `TerminateExisting` / `TerminateIfRunning` listed only as unsupported; pause/reset/update-options listed only as unsupported; CLI v1.7.0+ / Server v1.31.0+ stated verbatim; separate ID space; dual-use claim preserved verbatim; no invented metric names; no TypeScript link.

### `references/core/standalone-activities-cli.md`
- **Docs consulted:** `docs/cli/activity.mdx` (full file), `docs/encyclopedia/activities/standalone-activity.mdx` (lines 23, 109–114, 135–138).
- **Citations:** 50 inline. 323 lines.
- **VERIFY markers:** 0.
- All 14 `temporal activity` subcommands have their own H3 headings. Public Preview gaps (`pause`, `reset`, `update-options`) flagged at top and at each subcommand. `unpause` annotated since it only operates on paused Activities, which Standalone Activities cannot enter in Public Preview. Global Flags referenced by line range, not transcribed.

### `references/python/standalone-activities.md`
- **Docs consulted:** `docs/develop/python/activities/standalone-activities.mdx` only.
- **Citations:** 30 inline.
- **VERIFY markers:** 2.
  1. Server v1.31.0+ requirement is not stated in the Python doc (only CLI v1.7.0+ and Python SDK v1.23.0+ are stated there). The encyclopedia is the source for the server-version pairing.
  2. The Python doc does not show conflict-policy / reuse-policy kwargs on `start_activity` (`USE_EXISTING`, `REJECT_DUPLICATES`, etc.). Per methodology, no kwargs were invented; policy semantics deferred to `references/core/standalone-activities.md`.
- Methods/kwargs used: `client.execute_activity`, `client.start_activity`, `client.get_activity_handle`, `activity_handle.result`, `client.list_activities`, `client.count_activities`, `ClientConfig.load_client_connect_config`. Cloud auth limited to mTLS + API key (env-var modes).

### `references/go/standalone-activities.md`
- **Docs consulted:** `docs/develop/go/activities/standalone-activities.mdx` (primary), `docs/encyclopedia/activities/standalone-activity.mdx` (versions + Public Preview limitations only).
- **Citations:** 33 inline. ~270 lines.
- **VERIFY markers:** 1. The Go doc does not show the exact field name on `StartActivityOptions` for conflict policy / reuse policy, nor the Go enum constants for `USE_EXISTING` / `REJECT_DUPLICATES`. The encyclopedia lists the policy values but Go-specific binding names need confirmation against the godoc before adding a code snippet.
- APIs verbatim from the Go doc: `ExecuteActivity`, `GetActivityHandle`, `ListActivities`, `CountActivities`, `StartActivityOptions`, `GetActivityHandleOptions`, `ListActivitiesOptions`, `CountActivitiesOptions`, handle methods `Get`/`GetID`/`GetRunID`.

### `references/java/standalone-activities.md`
- **Docs consulted:** `docs/develop/java/activities/standalone-activities.mdx` (primary), `docs/encyclopedia/activities/standalone-activity.mdx` (versions + Public Preview limitations only).
- **Citations:** 33 inline (32 to the Java doc, 4 to the encyclopedia — some overlap).
- **VERIFY markers:** 1. The Java doc does not show builder methods on `StartActivityOptions` for conflict policy / reuse policy. Policy values documented as concepts; Java setter names not invented.
- Prereqs documented: Java 8+, Java SDK v1.35.0+, CLI v1.7.0+, Server v1.31.0+. Cloud auth limited to mTLS and API key.

### `references/dotnet/standalone-activities.md`
- **Docs consulted:** `docs/develop/dotnet/activities/standalone-activities.mdx` (primary), `docs/encyclopedia/activities/standalone-activity.mdx` (versions + Public Preview limitations only).
- **Citations:** 32 inline (28 to the .NET doc, 4 to the encyclopedia).
- **VERIFY markers:** 1. The .NET doc does not show a code snippet wiring `USE_EXISTING` / `REJECT_DUPLICATES` into `StartActivityOptions`; the specific .NET option property names are not present. Documented the supported policy values (from the encyclopedia) and the unsupported `TerminateExisting` / `TerminateIfRunning` limitation, without inventing .NET property names.
- APIs verbatim from the .NET doc: `ExecuteActivityAsync`, `StartActivityAsync`, `GetActivityHandle`, `GetResultAsync`, `ListActivitiesAsync`, `CountActivitiesAsync`, `StartActivityOptions`, `[Activity]`, `TemporalWorker`, `TemporalWorkerOptions`, `AddActivity`, `ClientEnvConfig.LoadClientConnectOptions`, `ActivityExecution`. Cloud auth limited to mTLS and API key.

### `SKILL.md` edit
- Added a "Standalone Activities" section just above "Task Queue Priority and Fairness", pointing at the six new reference files and noting that TypeScript SDK coverage is upstream-pending.
- No other changes to existing sections; skill version field left at `0.3.2` (no user request to bump).

### Cross-cutting VERIFY summary

The five language/CLI subagents converged on a single shared gap: **the per-language docs do not yet show conflict-policy / reuse-policy parameter wiring** (Python kwargs, Go fields, Java builders, .NET options). The encyclopedia lists the policy values (`USE_EXISTING`, `REJECT_DUPLICATES`; with `TerminateExisting` / `TerminateIfRunning` unsupported in Public Preview). Recommended follow-up: when the SDK docs add policy snippets (or when the API surface is confirmed against the per-language godoc/javadoc/etc.), revisit the four language references and resolve the VERIFY markers.

### Files NOT modified

- `references/typescript/` — intentionally untouched. No upstream Standalone Activities doc exists.
- `references/python/advanced-features.md`, `references/go/advanced-features.md`, etc. — left as-is. The plan reserved the option to add a one-line cross-link, but the SKILL.md "Standalone Activities" section already provides the discovery path; no edit was needed.
