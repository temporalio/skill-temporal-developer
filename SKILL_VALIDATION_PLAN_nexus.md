# Skill Validation Plan — `nexus`

**Reader:** you are an AI agent. The user has told you to validate a Temporal skill using this template. Your job has two phases:

1. **Phase 1 — Fill this plan.** Examine the authored skill files, identify the docs paths and token classes, fill every `{{PLACEHOLDER}}`, and present the filled plan to the user for approval.
2. **Phase 2 — Execute the filled plan.** Run the four-check protocol and produce a go/no-go report.

**Critical constraint:** you must be a *different session* than the one that authored the skill. Do not read the authoring plan, the `AUTHORING_LOG.md`, or any prior conversation about the authoring. You validate from the authored files and the docs alone.

(In this CI run, approval is automatic and Phase 2 follows immediately in the same session.)

---

**Subject under validation**

- `{{SKILL_NAME}}` = **nexus**
- `{{SKILL_ROOT}}` = `.` (the repository root: `/home/runner/work/skill-sync-pipeline/skill-sync-pipeline/skill-temporal-developer/`)
- Files authored on `draft/0034-nexus`:
  - `SKILL.md` — modified (added Nexus section)
  - `references/core/nexus.md` (561 lines, ~144 citations)
  - `references/dotnet/nexus.md` (261 lines, ~43 citations)
  - `references/go/nexus.md` (332 lines, ~43 citations)
  - `references/java/nexus.md` (288 lines, ~43 citations)
  - `references/python/nexus.md` (259 lines, ~41 citations)
  - `references/typescript/nexus.md` (232 lines, ~43 citations)

---

## 1. Independence requirement

Validation must be performed by a different session than authoring. Do *not* reuse the orchestrator that ran the authoring subagents — it carries authoring's mental model and will miss fabrications it introduced.

The validator agents read the *authored* files and the *docs clone*; they do **not** read the authoring plan, the `AUTHORING_LOG.md`, or any prior conversation.

---

## 2. Source of truth

- Primary: `../documentation/docs/`, with topic-relevant subtrees:
  - `docs/encyclopedia/nexus/` — `nexus.mdx`, `nexus-services.mdx`, `nexus-operations.mdx`, `nexus-endpoints.mdx`, `nexus-registry.mdx`, `nexus-patterns.mdx`, `nexus-security.mdx`, `nexus-error-handling.mdx`, `nexus-execution-debugging.mdx`, `nexus-metrics.mdx`
  - `docs/develop/{python,typescript,go,java,dotnet}/nexus/` — `feature-guide.mdx`, `quickstart.mdx`
  - `docs/cli/operator.mdx` (the `temporal operator nexus endpoint` CLI surface)
  - `docs/cloud/tcld/nexus.mdx` (the `tcld nexus endpoint` Cloud CLI surface)
  - `docs/cloud/nexus/limits.mdx`, `docs/cloud/nexus/index.mdx` (Temporal Cloud limits and Cloud extras)
  - `docs/references/failures.mdx` (Nexus error tables; Application Failure mapping)
- Secondary: not applicable. The Nexus skill should be wholly grounded in the docs tree. Untagged ecosystem claims (e.g., `gRPC`, `x509`, `tls`) are not expected and would be findings.

Do not trust citations in the authored files as proof — follow them and confirm the cited text supports the claim. Citations can be wrong in three ways: wrong file, wrong line, or correct line with a claim subtly different from what the line actually says. All three must be caught.

---

## 3. Four-check validation protocol

Run all four checks. The skill passes only if all four pass.

### Check 1: citation audit

Mechanical. For every inline citation comment in the authored files:

1. Confirm the cited file exists under `../documentation/docs/`.
2. Read the cited line range.
3. Confirm the authored claim is substantively supported by the cited text — not merely adjacent to it.

**Pass criterion:** ≥ 98% of citations resolve cleanly. Any unresolved citation is a finding.

**How to run:** Grep the authored files for `<!-- docs/`, extract path + line, Read, verify. Delegate per-reference-file to a subagent for parallelism.

There are six reference files with ~357 citations total. Delegate one subagent per file. Sampling is acceptable for very high-volume files (e.g., spot-check at least 25 of 144 in `core/nexus.md`); other files (≤ 43 citations) should be audited exhaustively.

### Check 2: reverse-grep audit

Extract every factual token from the authored files, then grep the source-of-truth clone for each. Anything not found is a fabrication suspect.

Patterns to extract for `nexus`:

- **CLI flag names**: regex `--[a-z][a-z0-9-]+` inside code fences and tables. For each, confirm the flag is documented for the surrounding command in `docs/cli/operator.mdx`, `docs/cloud/tcld/nexus.mdx`, or the relevant SDK feature guide.
- **CLI command invocations**: lines matching `^\s*(temporal|tcld) ` inside code fences. For each, confirm the verb/subcommand chain exists (e.g., `temporal operator nexus endpoint create`, `tcld nexus endpoint allowed-namespace add`).
- **Workflow / Nexus event names**: tokens matching `\bNexusOperation[A-Z][A-Za-z]*` and the bare strings `ScheduleNexusOperation`, `Completed`, `Failed`, `Canceled`, `NexusOperationTimedOut`, `Standby`, `BackingOff`, `Blocked`. Confirm each appears in the encyclopedia or feature-guide pages.
- **SDK API surface tokens** (language-specific, per-file):
  - .NET: `NexusService`, `NexusOperation`, `NexusServiceHandler`, `NexusOperationHandler`, `OperationHandler.Sync`, `IOperationHandler`, `WorkflowRunOperationHandler.FromHandleFactory`, `WorkflowRunOperationContext`, `NexusOperationExecutionContext.Current.TemporalClient`, `AddNexusService`, `CreateNexusWorkflowClient`, `ExecuteNexusOperationAsync`, `NexusWorkflowOperationOptions`, the four cancellation enum names (`Abandon`, `TryCancel`, `WaitCancellationRequested`, `WaitCancellationCompleted`).
  - Go: `nexus.NewSyncOperation`, `temporalnexus.NewWorkflowRunOperation`, `NewWorkflowRunOperationWithOptions`, `MustNewWorkflowRunOperationWithOptions`, `temporalnexus.WorkflowRunOperationOptions`, `temporalnexus.WorkflowHandle`, `temporalnexus.ExecuteUntypedWorkflow`, `temporalnexus.GetClient`, `nexus.NewService`, `service.Register`, `w.RegisterNexusService`, `workflow.NewNexusClient`, `c.ExecuteOperation`, `workflow.NexusOperationOptions`, `workflow.NexusOperationExecution`, `fut.GetNexusOperationExecution`, `workflow.WithCancel`.
  - Java: `@Service`, `@Operation`, `@ServiceImpl`, `@OperationImpl`, `OperationHandler`, `OperationHandler.sync`, `WorkflowRunOperation.fromWorkflowMethod`, `WorkflowRunOperation.fromWorkflowHandle`, `WorkflowHandle.fromWorkflowMethod`, `Nexus.getOperationContext().getWorkflowClient()`, `worker.registerNexusServiceImplementation`, `Workflow.newNexusServiceStub`, `Workflow.startNexusOperation`, `NexusOperationHandle`, `NexusServiceOptions`, `NexusOperationOptions`, `WorkflowImplementationOptions.setNexusServiceOptions`, and the four cancellation enum names (`ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`).
  - Python: `@nexusrpc.service`, `nexusrpc.Operation`, `@nexusrpc.handler.sync_operation`, `@nexusrpc.handler.service_handler`, `nexusrpc.handler.StartOperationContext`, `@nexus.workflow_run_operation`, `nexus.WorkflowRunOperationContext`, `nexus.WorkflowHandle`, `nexus.client()`, `nexus.info()`, `workflow.create_nexus_client`, `nexus_client.execute_operation`, `nexus_client.start_operation`, `nexusrpc.OperationError`, `nexusrpc.HandlerError`, `temporalio.exceptions.NexusOperationError`, `nexusrpc.HandlerErrorType`, `cancellation_type`, and the four cancellation enum names.
  - TypeScript: `nexus.service`, `nexus.operation`, `nexus.serviceHandler`, `WorkflowRunOperationHandler`, `temporalNexus.startWorkflow`, `temporalNexus.getClient`, `wf.createNexusServiceClient`, `nexusClient.executeOperation`, `OperationError`, `HandlerError`, `NexusOperationFailure`, `ctx.abortSignal`, `ctx.requestDeadline`, `ctx.requestId`, the `nexusServices` Worker option, and `OpenTelemetryPlugin`.
- **Handler error enum values**: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`, `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`. Each must appear in `docs/develop/python/nexus/feature-guide.mdx` or `docs/develop/typescript/nexus/feature-guide.mdx` or `docs/references/failures.mdx`.
- **Timeout-type token strings**: `TIMEOUT_TYPE_SCHEDULE_TO_START`, `TIMEOUT_TYPE_START_TO_CLOSE`. Confirm in `docs/encyclopedia/nexus/nexus-operations.mdx`.
- **Server / SDK version strings**: every `v1.x.y` mentioned in prerequisites — `temporal` CLI v1.3.0, Go v1.33.0, Java v1.28.0, Python v1.14.1, TypeScript v1.12.3, .NET v1.9.0, Server v1.31.0. Confirm against the relevant feature-guide line.
- **Numeric limits** (Cloud limits + sync deadline + circuit-breaker constants): 10 seconds (sync handler deadline), 60 days (Schedule-to-Close cap), 5 consecutive retryable errors (trip threshold), 60 seconds (half-open delay), 100 Endpoints, 30 in-flight Operations, 2000 callbacks. Each must appear in `docs/cloud/nexus/limits.mdx`, `docs/encyclopedia/nexus/nexus-operations.mdx`, or the encyclopedia overview pages.
- **SDK metric names**: `nexus_poll_no_task`, `nexus_task_schedule_to_start_latency`, `nexus_task_execution_failed`, `nexus_task_execution_latency`, `nexus_task_endtoend_latency`. Confirm in `docs/encyclopedia/nexus/nexus-metrics.mdx`.
- **Cloud metric names**: `RespondWorkflowTaskCompleted`, `PollNexusTaskQueue`, `RespondNexusTaskCompleted`, `RespondNexusTaskFailed`. Confirm in `docs/encyclopedia/nexus/nexus-metrics.mdx`.
- **CLI `Pending Nexus Operations` example fields**: the `Endpoint`, `Service`, `Operation`, `OperationToken`, `State`, `Attempt`, `ScheduleToCloseTimeout`, `NextAttemptScheduleTime`, `LastAttemptCompleteTime`, `LastAttemptFailure`, the `BackingOff` state label, and the verbatim error JSON in the code fence. Confirm in `docs/encyclopedia/nexus/nexus-execution-debugging.mdx`.
- **Enum / option values in tables** (Cloud `tcld` flag aliases like `tns`, `ttq`, `ans`, `ep`, `nxs`, `an`, `d`, `df`, `n`, `r`, `v`). Confirm each alias appears next to its flag in `docs/cloud/tcld/nexus.mdx`.

For each extracted token, run Grep against the relevant docs subtree. Absence means one of:

- The token is fabricated — **finding**.
- The token is real but undocumented — acceptable only if the authored file explicitly marks it with `<!-- undocumented: source = … -->`.
- The token is an ecosystem token — acceptable only if tagged with its source category (e.g., `<!-- go: … -->`).

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

**Topic-specific patterns (Nexus):**

| Wrong pattern | Should be | Source |
|---|---|---|
| `temporal nexus endpoint …` (verb directly under `temporal`) | `temporal operator nexus endpoint …` | docs/cli/operator.mdx:338 |
| `temporal operator nexus endpoint create` without **both** `--target-namespace` and `--target-task-queue` when describing the Worker-target form | both required together | docs/cli/operator.mdx:343 |
| `tcld nexus endpoint create --target-url` | flag does not exist for tcld (Cloud only supports Worker targets) | docs/cloud/tcld/nexus.mdx:149-156 |
| Circuit breaker trips after some number other than **5** consecutive retryable errors | 5 consecutive retryable errors | docs/encyclopedia/nexus/nexus.mdx:106 / nexus-operations.mdx:232 |
| Sync handler deadline of any value other than **10 seconds** | 10 seconds | docs/encyclopedia/nexus/nexus.mdx:62, nexus-operations.mdx:75 |
| Max Schedule-to-Close other than **60 days** (Cloud) | 60 days | docs/cloud/nexus/limits.mdx:34, nexus-operations.mdx:110 |
| Half-open delay other than **60 seconds** | 60 seconds | docs/encyclopedia/nexus/nexus-operations.mdx:236-242 |
| `NexusOperationStarted` reported for synchronous Operations | only for async; sync skips Started | docs/develop/*/nexus/feature-guide.mdx (per-SDK) |
| RESOURCE_EXHAUSTED listed only as non-retryable (without acknowledging doc conflict) | should be flagged as ambiguous per the `<!-- VERIFY: … -->` block at core/nexus.md:257 | core/nexus.md:257 |
| `temporal nexus operation …` CLI verb | does not exist; the CLI surface is `temporal operator nexus endpoint` only | docs/cli/operator.mdx |
| Endpoint count cap other than **100** (Cloud default) | 100 per Account | docs/cloud/nexus/limits.mdx:31 |
| In-flight Operations per Workflow other than **30** | 30 | docs/cloud/nexus/limits.mdx:32 |
| Callbacks per Workflow other than **2000** | 2000 | docs/cloud/nexus/limits.mdx:35 |
| Server version requirement for Schedule-to-Start / Start-to-Close other than **1.31.0+** | 1.31.0+ | docs/encyclopedia/nexus/nexus-operations.mdx:210, 226 |

**Pass criterion:** zero hits against any regression pattern. Strict — these are bugs already identified and should not survive a grounded authoring pass.

### Check 4: independent re-verification (sampling)

The first three checks catch fabrication and drift. This one catches *subtle-wrong*: a citation points at a real line, but the author's interpretation of that line is off by a nuance.

Pick **10 claims at random** per reference file (60 claims total across 6 files). For each:

1. Read *only* the claim in the authored file — not the citation.
2. Open the cited doc *independently* and read the section fresh.
3. Write down what you think the correct claim should be, given only the docs.
4. Compare your version to the authored version.

"Substantively different" = a reader following one would do something different than a reader following the other. Typographical / stylistic differences don't count.

**Pass criterion:** ≥ 95% of sampled claims match. Below 95% = flag for second authoring pass.

**How to randomize:** number all citations in a file; pick every Nth so the sample is spread across the file. Record which citation line-numbers were sampled in the report.

Areas to weight when picking samples (commonly the source of subtle-wrong):

- Cancellation type semantics (Abandon / TryCancel / WaitCancellationRequested / WaitCancellationCompleted) and their default.
- Circuit-breaker state transitions (open → half-open → closed) and what counts as a "retryable error".
- Timeout semantics (Schedule-to-Close vs. Schedule-to-Start vs. Start-to-Close) and which apply to sync vs. async.
- The Handler error type retryability table (especially `RESOURCE_EXHAUSTED` and `NOT_IMPLEMENTED` — the authored file already calls out a `<!-- VERIFY: … -->` conflict).
- The collocated vs. router-queue pattern descriptions.
- CLI flag presence (e.g., the `--target-url` flag is documented in operator CLI as Experimental — confirm the authored framing).

---

## 4. Execution shape

One validator orchestrator agent (this session). The agent:

1. Reads this plan.
2. Reads the authored files in `.` (not the authoring plan, not any `AUTHORING_LOG.md`).
3. Runs Check 1 — delegate to a per-reference-file subagent for parallelism (six subagents).
4. Runs Check 2 — delegate per reference file (can be combined with Check 1's per-file pass for efficiency).
5. Runs Check 3 — single pass across all six files.
6. Runs Check 4 — delegate per reference file; each subagent reads only the docs, not the rest of the skill.
7. Produces the report per §5.

---

## 5. Deliverables

- **`VALIDATION_REPORT.md`** at the skill root with sections:
  - **Go/no-go** — one-line verdict per check, overall verdict.
  - **Check 1 findings** — unresolved citations, with file:line and the cited-vs-actual difference.
  - **Check 2 findings** — tokens not found in docs, grouped by reference file.
  - **Check 3 findings** — any regression-pattern hits, file:line, the wrong text.
  - **Check 4 findings** — sampled claims that diverged from docs, with both versions.
  - **Statistics** — citation count, grep-miss count, sample size, match rate.
- Do *not* edit the authored files. Reports go in a separate file.

Overall verdict rubric:

- **GO** — all four checks pass their thresholds.
- **RE-RUN AUTHORING** — Check 3 has any hit, or Check 4 < 95%, or Check 1 < 98%. Don't patch; send affected files back through authoring.
- **MINOR FIXES** — Check 2 has ≤ 5 unexplained misses that look like typos or missing citation comments. Flag for spot-fix, no full re-authoring.

---

## 6. Stop conditions

Abort validation and escalate if:

- The authoring output artifacts are missing (no commits, no `AUTHORING_LOG.md`) — nothing to validate.
- The docs clone at `../documentation/` is absent or empty — no source of truth.
- More than 30% of citations fail Check 1 — authoring wasn't grounded; full re-authoring needed.
- The authoring added files outside the expected skill layout (new `docs/` subdirs, tutorials, meta-docs) — flag as scope violation.

---

## 7. What this plan does *not* do

- **No live testing.** Running commands against real Temporal systems is the highest-confidence check but outside this plan's remit.
- **No prose quality grading.** Validation checks factual correctness only.
- **No scope auditing.** Whether a claim belongs in this skill vs. a sibling is a design question answered during authoring.

End of plan.
