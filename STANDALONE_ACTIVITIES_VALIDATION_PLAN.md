# Skill Validation Plan — `Standalone Activities`

**Reader:** you are an AI agent. The user has told you to validate the Standalone Activities additions to the Temporal Developer skill using this template. Your job has two phases:

1. **Phase 1 — Fill this plan.** *(Done — this document is already filled.)*
2. **Phase 2 — Execute the filled plan.** Run the four-check protocol and produce a go/no-go report.

**Critical constraint:** you must be a *different session* than the one that authored the skill. Do not read `STANDALONE_ACTIVITIES_AUTHORING_PLAN.md`, `AUTHORING_LOG.md`, or any prior conversation about the authoring. You validate from the authored files and the docs alone.

Do not start Phase 2 until the user approves the filled plan.

---

<!-- ═══════════════════════════════════════════════════════
     PLAN BODY
     ═══════════════════════════════════════════════════════ -->

**Purpose:** independent verification that the Standalone Activities reference set added in commit `b0f3d87` is accurate, grounded, and free of fabrication patterns. Produce a go/no-go.

**Non-purpose:** editing the skill. If validation finds problems, report them — do *not* fix them.

**Scope (files added/changed by this PR):**

- `references/core/standalone-activities.md`
- `references/core/standalone-activities-cli.md`
- `references/python/standalone-activities.md`
- `references/go/standalone-activities.md`
- `references/java/standalone-activities.md`
- `references/dotnet/standalone-activities.md`
- (For context only, not the validation target itself: the new "Standalone Activities" section in `SKILL.md`.)

`{{SKILL_ROOT}}` = `/Users/don/work/skills/skill-temporal-developer`

---

## 1. Independence requirement

Validation must be performed by a different session than authoring. Do *not* reuse the orchestrator that ran the authoring subagents.

The validator agents read the *authored* files above and the *docs clone* at `/Users/don/work/skills/documentation/`; they do **not** read `STANDALONE_ACTIVITIES_AUTHORING_PLAN.md` or `AUTHORING_LOG.md`.

---

## 2. Source of truth

- Primary: `/Users/don/work/skills/documentation/docs/`. Topic-relevant subtrees:
  - `docs/encyclopedia/activities/standalone-activity.mdx` (concept, status, policies, limitations, Cloud)
  - `docs/cli/activity.mdx` (CLI subcommand reference — every flag table)
  - `docs/develop/python/activities/standalone-activities.mdx`
  - `docs/develop/go/activities/standalone-activities.mdx`
  - `docs/develop/java/activities/standalone-activities.mdx`
  - `docs/develop/dotnet/activities/standalone-activities.mdx`
  - `docs/cloud/metrics/openmetrics/metrics-reference.mdx` (metric coverage cross-reference)
- Secondary: none. The skill does not cite SDK source code, gRPC specs, or man pages for the Standalone Activities scope.

All seven cited paths above were confirmed to exist under `documentation/docs/` during plan filling.

Do not trust citations in the authored files as proof — follow them and confirm the cited text supports the claim. Citations can be wrong in three ways: wrong file, wrong line, or correct line with a claim subtly different from what the line actually says.

---

## 3. Four-check validation protocol

Run all four checks. The skill passes only if all four pass.

### Check 1: citation audit

For every inline `<!-- docs/… -->` comment in the six authored files:

1. Confirm the cited file exists under `/Users/don/work/skills/documentation/docs/`.
2. Read the cited line range.
3. Confirm the authored claim is substantively supported by the cited text.

`<!-- VERIFY: … -->` markers (4 known to exist, mostly around per-language conflict/reuse-policy parameter wiring) are **not** citations — they're authored-side caveats. Note them in the report but do not count them as citation failures.

**Pass criterion:** ≥ 98% of `<!-- docs/… -->` citations resolve cleanly.

**How to run:** `grep -nE '<!-- docs/' references/{core,python,go,java,dotnet}/standalone-activities*.md` to enumerate. Delegate per-reference-file to a subagent for parallelism (6 files → 6 subagents).

### Check 2: reverse-grep audit

Extract every factual token from the six authored files, then grep the docs subtree for each. Anything not found is a fabrication suspect.

Token classes for this skill:

- **CLI flag names:** regex `--[a-z][a-z0-9-]+`. Run against `docs/cli/activity.mdx`. Every flag must appear in that file's flag tables for the same subcommand it's claimed under.
- **CLI subcommand invocations:** lines matching `^\s*temporal activity ` inside ```` ```bash / ```sh ```` code fences in `references/core/standalone-activities-cli.md` and any other authored file. The subcommand keyword (`start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, `terminate`, `complete`, `fail`, `pause`, `reset`, `update-options`) must appear as a documented subcommand in `docs/cli/activity.mdx`.
- **Conflict/reuse policy enum values quoted in tables or prose:** `USE_EXISTING`, `REJECT_DUPLICATES`, `TerminateExisting`, `TerminateIfRunning`, plus any other ALL_CAPS or PascalCase token that appears next to "conflict policy" or "reuse policy". For each, confirm the value appears next to the corresponding field in `docs/encyclopedia/activities/standalone-activity.mdx`. Any other policy enum value found in the authored files is a fabrication suspect.
- **SDK API surface tokens** (per language file):
  - Python: `client.start_activity`, `start_activity`, `result()`, `cancel()`, `terminate()`, `describe()`, any `id_conflict_policy` / `id_reuse_policy` kwargs. Grep `docs/develop/python/activities/standalone-activities.mdx`.
  - Go: `client.ExecuteActivity`, `StartActivityOptions`, option field names, handle methods (`Get`, `Cancel`, `Terminate`). Grep `docs/develop/go/activities/standalone-activities.mdx`.
  - Java: `WorkflowClient.startActivity` / `executeActivity` (or whatever the authored file claims), `StartActivityOptions` builder methods. Grep `docs/develop/java/activities/standalone-activities.mdx`.
  - .NET: `ITemporalClient.StartActivityAsync` / `ExecuteActivityAsync` (or whatever the authored file claims), `StartActivityOptions` properties. Grep `docs/develop/dotnet/activities/standalone-activities.mdx`.
- **Version strings:** `v1\.[0-9]+\.[0-9]+`. Specifically `v1.7.0` (CLI) and `v1.31.0` (Server) must be the only versions claimed for Standalone Activities prerequisites — confirm against `docs/encyclopedia/activities/standalone-activity.mdx` lines 110–115.
- **Run-state / status strings:** any quoted/back-ticked status like `CancelRequested`, `Running`, `Completed`. Grep `docs/cli/activity.mdx`.
- **Metric names:** any `temporal_*` or `activity_*` metric name in `references/core/standalone-activities.md`. Grep `docs/cloud/metrics/openmetrics/metrics-reference.mdx`.

For each extracted token, run Grep against the relevant docs subtree. Absence means one of:

- The token is fabricated — **finding**.
- The token is real but undocumented — acceptable only if the authored file explicitly marks it with `<!-- undocumented: source = … -->` or a `<!-- VERIFY: … -->` caveat that explains why the token is included without an upstream citation.
- The token is an ecosystem token (none expected for this skill) — would need a source-category tag.

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

**Topic-specific patterns (Standalone Activities Public Preview):**

| Wrong pattern | Should be | Source |
|---|---|---|
| `pause` / `reset` / `update-options` listed as supported for Standalone Activities | Listed as **not supported in Public Preview** | docs/encyclopedia/activities/standalone-activity.mdx:109 |
| `TerminateExisting` conflict policy presented as usable today | Listed as not supported in Public Preview | docs/encyclopedia/activities/standalone-activity.mdx:110 |
| `TerminateIfRunning` reuse policy presented as usable today | Listed as not supported in Public Preview | docs/encyclopedia/activities/standalone-activity.mdx:110 |
| Conflict/reuse policy enum values *other than* `USE_EXISTING` and `REJECT_DUPLICATES` claimed as currently available | Only those two values appear in PP docs | docs/encyclopedia/activities/standalone-activity.mdx:84 |
| `--workflow-id` marked as **required** for `temporal activity complete` / `fail` when targeting a Standalone Activity | Required for Workflow Activities only; **omit** for Standalone Activities | docs/cli/activity.mdx:80-81, 179-180 |
| CLI prerequisite stated as anything other than v1.7.0+ | `Temporal CLI v1.7.0 or higher` | docs/encyclopedia/activities/standalone-activity.mdx:114 |
| Server prerequisite stated as anything other than v1.31.0+ | `Temporal Server v1.31.0 or higher` | docs/encyclopedia/activities/standalone-activity.mdx:114 |
| Standalone Activity ID claimed to share namespace with Workflow ID | Separate ID space; not addressable as Workflow IDs | docs/encyclopedia/activities/standalone-activity.mdx:85 |
| TypeScript SDK quickstart presented as available | Coverage is upstream-pending; must be flagged as such | docs/encyclopedia/activities/standalone-activity.mdx:63-66 |
| Standalone Activities described as **GA** / **Generally Available** | **Public Preview** | docs/encyclopedia/activities/standalone-activity.mdx:21-25 |
| Claim that a Workflow is required to invoke an Activity at all | Standalone Activity is top-level, no Workflow needed | docs/encyclopedia/activities/standalone-activity.mdx:50 |
| `CountActivities` described as returning queue depth / pending tasks | Returns total count of executions matching filter — not queued tasks | docs/encyclopedia/activities/standalone-activity.mdx:101-103 |
| Claim that switching an Activity Function between Workflow-invoked and Standalone modes requires Worker code changes | No Worker code changes required | docs/encyclopedia/activities/standalone-activity.mdx:90 |
| New "Standalone-specific" metric names invented (e.g. `temporal_standalone_activity_*`) | No new metric names — reuse existing Activity metrics | docs/encyclopedia/activities/standalone-activity.mdx:94-96 |

**Pass criterion:** zero hits against any regression pattern.

### Check 4: independent re-verification (sampling)

Catches *subtle-wrong*: a citation points at a real line, but the author's interpretation is off by a nuance.

Pick **10 claims at random** per reference file (6 files × 10 = ~60 sampled claims). For each:

1. Read *only* the claim in the authored file — not the citation.
2. Open the cited doc *independently* and read the section fresh.
3. Write down what you think the correct claim should be, given only the docs.
4. Compare your version to the authored version.

For the CLI reference file specifically (`standalone-activities-cli.md`), bias the sample toward flag tables — the highest-density area for off-by-one cell errors (wrong "Required" status, wrong shorthand, wrong description for an adjacent flag).

For the `core/standalone-activities.md` file, bias the sample toward the Public Preview limitations section and the conflict/reuse policy section — these are the easiest places to lose a "not" or swap an enum value.

"Substantively different" = a reader following one would do something different than a reader following the other. Typographical / stylistic differences don't count.

**Pass criterion:** ≥ 95% of sampled claims match. Below 95% = flag for second authoring pass.

**How to randomize:** number all `<!-- docs/… -->` citations in each file from top to bottom; pick every Nth (where N = floor(total/10)) starting from a fixed offset of 1. Record the picked indices in the report.

---

## 4. Execution shape

One validator orchestrator agent. The agent:

1. Reads this plan.
2. Reads the six authored files in `{{SKILL_ROOT}}/references/{core,python,go,java,dotnet}/` (not the authoring plan, not the `AUTHORING_LOG.md`).
3. Runs Check 1 — delegate to a per-reference-file subagent for parallelism (6 subagents).
4. Runs Check 2 — delegate per reference file (6 subagents).
5. Runs Check 3 — single pass with Grep across all six files.
6. Runs Check 4 — delegate per reference file (6 subagents); each subagent reads only the docs, not the rest of the skill.
7. Produces the report per §5.

---

## 5. Deliverables

- **`STANDALONE_ACTIVITIES_VALIDATION_REPORT.md`** at `{{SKILL_ROOT}}` with sections:
  - **Go/no-go** — one-line verdict per check, overall verdict.
  - **Check 1 findings** — unresolved citations, with file:line and the cited-vs-actual difference.
  - **Check 2 findings** — tokens not found in docs, grouped by reference file.
  - **Check 3 findings** — any regression-pattern hits, file:line, the wrong text.
  - **Check 4 findings** — sampled claims that diverged from docs, with both versions.
  - **Statistics** — citation count, grep-miss count, sample size, match rate.
  - **VERIFY-marker inventory** — list of `<!-- VERIFY: … -->` caveats with the validator's judgment of whether each is acceptable as-is or should be resolved before GA.
- Do *not* edit the authored files. Reports go in a separate file.

Overall verdict rubric:

- **GO** — all four checks pass their thresholds.
- **RE-RUN AUTHORING** — Check 3 has any hit, or Check 4 < 95%, or Check 1 < 98%.
- **MINOR FIXES** — Check 2 has ≤ 5 unexplained misses that look like typos or missing citation comments.

---

## 6. Stop conditions

Abort validation and escalate if:

- Any of the six authored files is missing — nothing to validate.
- The docs clone at `/Users/don/work/skills/documentation/` is absent or empty — no source of truth.
- More than 30% of citations fail Check 1 — authoring wasn't grounded; full re-authoring needed.
- The PR added files outside `references/{core,python,go,java,dotnet}/` and `SKILL.md` (e.g. new top-level docs, tutorials) — flag as scope violation.

---

## 7. What this plan does *not* do

- **No live testing.** Running `temporal activity start` against a real server is the highest-confidence check but outside this plan's remit.
- **No prose quality grading.** Validation checks factual correctness only.
- **No scope auditing.** Whether a Standalone Activities claim belongs in `core/` vs. a per-language file is a design question answered during authoring.
- **No TypeScript coverage review.** The skill explicitly defers TS to upstream; absence of a TS file is intentional, not a finding.

End of plan.
