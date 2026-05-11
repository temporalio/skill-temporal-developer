# Skill Validation Plan — `standalone-activities`

**Skill root:** `.` (`/home/runner/work/skill-sync-pipeline/skill-sync-pipeline/skill-temporal-developer`)

**Authored files under validation (branch `draft/0001-standalone-activities`):**

- `SKILL.md` (modified — adds the "Standalone Activities" section, bumps version 0.3.2 → 0.3.3)
- `references/core/standalone-activities.md` (new)
- `references/python/standalone-activities.md` (new)
- `references/typescript/standalone-activities.md` (new)
- `references/java/standalone-activities.md` (new)
- `references/dotnet/standalone-activities.md` (new)

Note: no Go reference was authored; SKILL.md does not list one. Go is out of scope for this skill (consistent with Standalone Activities being a non-Go feature in the SKILL.md description).

---

**Purpose:** independent verification that the skill is accurate, grounded, and free of fabrication patterns. Produce a go/no-go.

**Non-purpose:** editing the skill. If validation finds problems, report them — do *not* fix them. Fixing belongs to another authoring pass.

---

## 1. Independence requirement

Validation is being performed by a fresh session that has not read `AUTHORING_LOG.md` and is treating the authoring plan as off-limits except for the §8 regression table (Step D narrow exception). Validation reads the authored files and the docs clone at `../documentation/`.

---

## 2. Source of truth

- Primary: `../documentation/docs/`, with topic-relevant subtrees:
  - `docs/encyclopedia/activities/` — concept docs (`standalone-activity.mdx`, `activity-execution.mdx`, `activity-operations.mdx`)
  - `docs/cli/activity.mdx` — CLI flags / subcommands
  - `docs/develop/{python,typescript,java,dotnet}/activities/standalone-activities.mdx` — per-language SDK docs
  - `docs/evaluate/development-production-features/job-queue.mdx` — job-queue framing
  - `docs/evaluate/temporal-cloud/actions.mdx` — Cloud billable Action types
  - `docs/cloud/metrics/openmetrics/metrics-reference.mdx` — Cloud metrics (workflow-type label, terminate count)
- Secondary: none — this topic has no `<!-- go: -->` / `<!-- grpc: -->` / `<!-- man: -->` ecosystem tags in the authored files.

Do not trust citations in the authored files as proof — follow them and confirm the cited text supports the claim.

---

## 3. Four-check validation protocol

Run all four checks. The skill passes only if all four pass.

### Check 1: citation audit

For every inline `<!-- docs/… -->` comment in the authored files: confirm the cited file exists; read the cited line range; confirm the authored claim is substantively supported by the cited text — not merely adjacent to it.

**Pass criterion:** ≥ 98% of citations resolve cleanly.

**How to run:** Grep the authored files for `<!-- docs/`, extract path + line, Read, verify. Delegate per-reference-file to a subagent for parallelism.

### Check 2: reverse-grep audit

Extract every factual token from the authored files, then grep the source-of-truth clone for each. Anything not found is a fabrication suspect.

Patterns to extract for `standalone-activities`:

- **CLI flag names**: regex `--[a-z][a-z0-9-]+` inside code fences and inline backticks. (e.g. `--activity-id`, `--task-queue`, `--start-to-close-timeout`, `--id-conflict-policy`, `--id-reuse-policy`, `--query`, `--input`, `--priority-key`, `--fairness-key`, `--fairness-weight`, `--workflow-id`.)
- **CLI command invocations**: lines matching `^\s*(\./)?temporal ` inside code fences. (e.g. `temporal activity execute`, `temporal activity start`, `temporal activity result`, `temporal activity list`, `temporal activity count`, `temporal server start-dev`.)
- **CLI subcommands** named in tables: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, `terminate`, `complete`, `fail`, `pause`, `unpause`, `reset`, `update-options`.
- **Env vars**: regex `TEMPORAL_[A-Z_]+`. (e.g. `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, `TEMPORAL_API_KEY`.) *Note:* the universal Check-3 regression table lists `TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH` as the **wrong** form — verify against the actual current docs, since the authored files use the long form.
- **Enum values quoted in tables**: `Fail`, `UseExisting`, `AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`, `TerminateExisting`, `TerminateIfRunning`, `USE_EXISTING`, `REJECT_DUPLICATES`. Confirm each value appears next to the relevant flag in `docs/cli/activity.mdx` or the encyclopedia page.
- **Cloud metric / Action names** quoted in tables: `start_standalone_activity`, `retry_standalone_activity`, `record_standalone_activity_heartbeat`, `record_standalone_activity_heartbeat_by_id`, `temporal_workflow_type`, `__standalone_activity`, `temporal_cloud_v1_activity_terminate_count`, `CountActivities`, `CancelRequested`.
- **SDK symbol tokens** (per-language reference files):
  - Python: `temporalio`, `@activity.defn`, `Client.connect`, `Worker`, `client.execute_activity`, `client.start_activity`, `client.get_activity_handle`, `activity_handle.result`, `client.list_activities`, `client.count_activities`, `ClientConfig.load_client_connect_config`.
  - TypeScript: `@temporalio/activity`, `@temporalio/worker`, `@temporalio/client`, `@temporalio/envconfig`, `NativeConnection`, `Worker.create`, `loadClientConnectConfig`, `client.activity.typed`, `client.activity.execute`, `client.activity.start`, `client.activity.getHandle`, `client.activity.list`, `client.activity.count`, `ApplicationFailure`, `ActivityExecutionInfo`.
  - Java: `@ActivityInterface`, `@ActivityMethod`, `ClientConfigProfile.load`, `WorkflowServiceStubs`, `WorkflowClient`, `WorkerFactory`, `ActivityClient`, `ActivityClient.newInstance`, `ActivityClientOptions`, `StartActivityOptions`, `ActivityHandle`, `client.execute`, `client.start`, `client.getHandle`, `handle.getResult`, `handle.getResultAsync`, `client.listExecutions`, `client.countExecutions`, `ActivityExecutionMetadata`, `ActivityExecutionCount`.
  - .NET: `[Activity]`, `Temporalio.Activities`, `Temporalio.Worker`, `Temporalio.Client`, `Temporalio.Common.EnvConfig`, `TemporalClient.ConnectAsync`, `ClientEnvConfig.LoadClientConnectOptions`, `TemporalWorker`, `TemporalWorkerOptions`, `client.ExecuteActivityAsync`, `client.StartActivityAsync`, `client.GetActivityHandle`, `handle.GetResultAsync`, `client.ListActivitiesAsync`, `client.CountActivitiesAsync`, `ScheduleToCloseTimeout`, `StartToCloseTimeout`, `StartActivityOptions`.
- **Version numbers**: each SDK floor (Python `1.23.0`, TypeScript `1.17.0`, Java `1.35.0`, .NET `1.12.0`), CLI `v1.7.0`, Server `v1.31.0`.

For each extracted token, run Grep against the relevant docs subtree. Absence means:

- Fabricated — finding.
- Real but undocumented — acceptable only if explicitly marked `<!-- undocumented: source = … -->`. (No such marks appear in the authored files at time of writing.)
- Ecosystem token — acceptable only if tagged with `<!-- go: -->` / `<!-- grpc: -->` / `<!-- man: -->`. (Not applicable here.)

**Pass criterion:** zero unexplained grep-misses.

### Check 3: regression on known bugs

Any of these patterns appearing in the authored files is a failure.

**Universal patterns (apply to every Temporal skill):**

| Wrong pattern | Should be |
|---|---|
| `--profile` as a flag in `temporal` command | `--env` |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | `TEMPORAL_TLS_CERT` |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | `TEMPORAL_TLS_KEY` |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | `TEMPORAL_TLS_CA` |
| `tcld service-account` (entire command group) | does not exist — should be absent |
| `--output text` / `--output jsonl` | `table, json, card` only |
| `saas-api.tmprl.cloud:7233` | port 443 |

**Topic-specific patterns** (from authoring plan §8, the input to this check):

| Wrong pattern | Should be | Source |
|---|---|---|
| Claim that Standalone Activities support `pause` / `unpause` / `reset` / `update-options` | Not supported for Standalone Activities | `docs/encyclopedia/activities/activity-operations.mdx:31`, `docs/cli/activity.mdx:202,236,384,436` |
| Conflict/reuse policy includes `TerminateExisting` / `TerminateIfRunning` as supported | Explicitly **not supported** in Public Preview; CLI accepts only `Fail, UseExisting` for `--id-conflict-policy` and `AllowDuplicate, AllowDuplicateFailedOnly, RejectDuplicate` for `--id-reuse-policy` | `docs/encyclopedia/activities/standalone-activity.mdx:85,111`, `docs/cli/activity.mdx:140-141` |
| Standalone Activity IDs share the same ID space as Workflow IDs | Separate ID space from Workflows | `docs/encyclopedia/activities/standalone-activity.mdx:86`, `docs/encyclopedia/activities/activity-execution.mdx:117-118` |
| Standalone Activities require a different Worker than Workflow Activities | Same Worker; no code changes | `docs/encyclopedia/activities/standalone-activity.mdx:91`, per-language SDK pages |
| Standalone Activity errors are returned to a parent Workflow | No Workflow; error returned to Client when fetching result | `docs/encyclopedia/activities/activity-execution.mdx:49-51` |
| `temporal_workflow_type` label is omitted for Standalone Activities | Label is present with placeholder value `__standalone_activity` | `docs/cloud/metrics/openmetrics/metrics-reference.mdx:315` |
| Generic Activity timeout flags apply only to Workflow Activities | Apply to `temporal activity start` / `execute` Standalone Activity calls; one of `start-to-close` or `schedule-to-close` required | `docs/cli/activity.mdx:151-154,352-355` |
| `temporal activity describe` / `cancel` / `terminate` work on workflow-Activity executions | These operate on Standalone Activities | `docs/cli/activity.mdx:39,102,363` |
| `client.list_activities()` (and per-language equivalents) returns both Workflow and Standalone Activities | Returns **only** Standalone Activity Executions | per-language SDK pages |

**Pass criterion:** zero hits against any regression pattern.

### Check 4: independent re-verification (sampling)

For each reference file (5 files × ~10 claims = ~50 claims total):

1. Pick 10 citations at random (seeded by hash of file path + index, or every Nth).
2. Read *only* the claim in the authored file — not the citation.
3. Open the cited doc *independently* and read the section fresh.
4. Write down what the correct claim should be, given only the docs.
5. Compare your version to the authored version.

"Substantively different" = a reader following one would do something different than a reader following the other.

**Pass criterion:** ≥ 95% of sampled claims match.

---

## 4. Execution shape

Single validator orchestrator (this session):

1. Read this plan.
2. Read the authored files in `.`.
3. Run Check 1 — delegate to per-reference-file subagents for parallelism.
4. Run Check 2 — delegate per reference file.
5. Run Check 3 — single Grep pass across all six files.
6. Run Check 4 — delegate per reference file; each subagent reads only the docs, not the rest of the skill.
7. Produce the report per §5.

---

## 5. Deliverables

- **`VALIDATION_REPORT.md`** at `.` with sections:
  - **Go/no-go** — one-line verdict per check, overall verdict.
  - **Check 1 findings** — unresolved citations, with file:line and the cited-vs-actual difference.
  - **Check 2 findings** — tokens not found in docs, grouped by reference file.
  - **Check 3 findings** — any regression-pattern hits, file:line, the wrong text.
  - **Check 4 findings** — sampled claims that diverged from docs, with both versions.
  - **Statistics** — citation count, grep-miss count, sample size, match rate.

---

## 6. Stop conditions

Abort and escalate if: authoring artifacts missing; docs clone missing; > 30% of citations fail Check 1; files added outside expected skill layout.

---

End of plan.
