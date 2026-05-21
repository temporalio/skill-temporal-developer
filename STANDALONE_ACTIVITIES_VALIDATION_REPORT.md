# Standalone Activities — Validation Report

**Plan:** `STANDALONE_ACTIVITIES_VALIDATION_PLAN.md`
**Scope:** the six reference files added in commit `b0f3d87` ("Add Standalone Activities feature reference").
**Method:** four-check protocol per the plan, with one validator subagent per reference file (Checks 1, 2, 4) and a single regression grep pass for Check 3.

---

## Go/no-go

| Check | Verdict | Threshold | Result |
|---|---|---|---|
| Check 1 — citation audit | **PASS** | ≥ 98% resolve cleanly | 247/247 = 100% |
| Check 2 — reverse-grep / token audit | **PASS** | zero unexplained misses | 0 unexplained misses |
| Check 3 — known-bug regression | **PASS (with one INFO)** | zero hits | 0 fabrication hits; 1 universal-rule tension faithfully transcribed from upstream — see §Check 3 |
| Check 4 — independent re-verification (sampling) | **PASS** | ≥ 95% match | 60/60 = 100% sampled match |

**Overall verdict: GO.**

The PR is grounded, accurate, and free of fabrication. One issue surfaced by Check 3 (TLS env-var names) reflects upstream documentation rather than a skill defect — call out separately, do not block the PR.

---

## Check 1 findings (citation audit)

Zero unresolved citations across all six files. Every `<!-- docs/... -->` citation comment points to an existing line range in the docs clone and substantively supports the immediately preceding authored claim.

Per-file breakdown:

| File | Citations | Resolved |
|---|---:|---:|
| `references/core/standalone-activities.md` | 35 | 35 |
| `references/core/standalone-activities-cli.md` | 52 | 52 |
| `references/python/standalone-activities.md` | 36 | 36 |
| `references/go/standalone-activities.md` | 43 | 43 |
| `references/java/standalone-activities.md` | 43 | 43 |
| `references/dotnet/standalone-activities.md` | 38 | 38 |
| **Total** | **247** | **247** |

Two minor non-failure observations worth recording (kept as observations, not findings):

- `references/core/standalone-activities.md:68` cites `docs/cloud/metrics/openmetrics/metrics-reference.mdx:315`. The cited line confirms metric-series reuse but uses a slightly different framing (it mentions a `__standalone_activity` placeholder label value that the authored prose abstracts away). Substantively supported; framing is the author's, not invented.
- `references/go/standalone-activities.md:48-54` says "Temporal Dev Server has Standalone Activities enabled by default" with a citation only to `docs/develop/go/activities/standalone-activities.mdx:81` (which says "Start the Temporal development server"). The "enabled by default" half of that claim is more directly supported by `docs/encyclopedia/activities/standalone-activity.mdx:138`. Adding the encyclopedia citation would be cleaner. Not blocking.

---

## Check 2 findings (reverse-grep / token audit)

Zero unexplained grep-misses across all six files.

- **CLI flags / subcommands** (`core/standalone-activities-cli.md`): all 14 subcommand headers and ~115 flag rows (cancel 3, complete 4, count 1, describe 3, execute 25, fail 5, list 3, pause 5, reset 15, result 2, start 25, terminate 3, unpause 13, update-options 20) match `docs/cli/activity.mdx`. Shorthands (`-a`, `-r`, `-w`, `-q`, `-t`) and Required/No columns are correct, including the case where `--task-queue` carries `-t` shorthand on `start`/`execute` but **no shorthand** on `update-options` — correctly transcribed.
- **Policy enums** (`core/standalone-activities.md` and four SDK files): `USE_EXISTING`, `REJECT_DUPLICATES` resolve to `docs/encyclopedia/activities/standalone-activity.mdx:84`; `TerminateExisting`, `TerminateIfRunning` resolve to line 110 (negative-availability claim). No other policy enum values were claimed. Where a per-language doc does not surface SDK parameter names for the policies (Python, Java, .NET — and Go for the field name on `StartActivityOptions`), the authored file inserts a `<!-- VERIFY: ... -->` caveat rather than fabricating a signature. Acceptable.
- **Version strings**: `v1.7.0` (CLI), `v1.31.0` (Server), and per-SDK floors (`v1.23.0` Python, `v1.41.0` Go, `v1.35.0` Java, `v1.12.0` .NET) all confirmed against the cited docs. The Python file's server-version claim is properly flagged with VERIFY because the upstream Python SDK doc itself doesn't restate the server requirement; encyclopedia carries it.
- **SDK API symbols**: every Python kwarg, Go field, Java method, and .NET property/method named in the authored files is grep-resolvable in the corresponding `docs/develop/<lang>/activities/standalone-activities.mdx` page. No fabricated APIs.
- **Run-state strings**: only `CancelRequested` (cli ref); confirmed at `docs/cli/activity.mdx:47`.
- **Metric names**: no Standalone-specific metric names invented; the core file explicitly states no new metric names are introduced and reuses general Activity metric series.
- **Imports/namespaces**: Python `temporalio.client` / `temporalio.envconfig` / `temporalio.worker`; Go `go.temporal.io/sdk/{activity,client,worker,contrib/envconfig}`; Java `io.temporal.client`; .NET `Temporalio.{Client,Activities,Worker,Common.EnvConfig}` — all present in the cited per-language docs.

---

## Check 3 findings (known-bug regression)

**Universal patterns:**

| Pattern | Hits |
|---|---|
| `--profile` flag | 0 |
| `tcld service-account` | 0 |
| `--output text` / `--output jsonl` | 0 |
| `saas-api.tmprl.cloud:7233` | 0 |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH` | **8 hits across 4 files** — see INFO below |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | 0 |

**Topic-specific patterns (all from §3 of the plan):** zero hits. Specifically:

- `pause` / `reset` / `update-options` are mentioned only as **not supported in Public Preview** with citations to `docs/encyclopedia/activities/standalone-activity.mdx:109` and the corresponding `docs/cli/activity.mdx` "Not supported for Standalone Activities" lines. Never presented as currently usable for Standalone Activities.
- `TerminateExisting` / `TerminateIfRunning` appear only in negative-availability statements. Never presented as currently usable.
- No conflict/reuse policy enum values other than `USE_EXISTING` / `REJECT_DUPLICATES` (positive) and `TerminateExisting` / `TerminateIfRunning` (negative) are claimed.
- `--workflow-id` is correctly described as **omitted** for Standalone Activities on `complete`/`fail` (cli ref lines 52, 122) — not required.
- Versions `v1.7.0` (CLI) and `v1.31.0` (Server) used everywhere; no off-version drift.
- "Public Preview" appears 28 times across the six files; "Generally Available" / "currently GA" / "is GA" never appears (the only `GA` reference is the cli-ref's "Support is scheduled for GA", which is a negative — `pause`/`reset`/`update-options` are not yet GA).
- TypeScript SDK is referenced exactly once (in `core/standalone-activities.md:95`) and correctly framed as upstream-pending, not as available.
- Standalone Activity ID space is correctly described as separate from Workflow IDs.
- `CountActivities` is correctly described as a count of executions matching a filter, not as queue depth.

### INFO: TLS env-var name conflict between universal-regression rule and upstream docs

The universal-regression table in the plan says `TEMPORAL_TLS_CLIENT_CERT_PATH` should be `TEMPORAL_TLS_CERT` (and the `_KEY_PATH` form should be `TEMPORAL_TLS_KEY`). All four SDK reference files use the long form:

| File | Lines |
|---|---|
| `references/python/standalone-activities.md` | 306–307 |
| `references/go/standalone-activities.md` | 362–363 |
| `references/java/standalone-activities.md` | 250–251 |
| `references/dotnet/standalone-activities.md` | 268–269 |

This is **not a fabrication**. Each upstream Standalone-Activities SDK doc uses the same long form verbatim:

| Upstream doc | Lines |
|---|---|
| `docs/develop/python/activities/standalone-activities.mdx` | 456–457 |
| `docs/develop/go/activities/standalone-activities.mdx` | 426–427 |
| `docs/develop/java/activities/standalone-activities.mdx` | 428–429 |
| `docs/develop/dotnet/activities/standalone-activities.mdx` | 443–444 |

Interpretation: the SDK envconfig variable names (`TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH`) are distinct from the CLI-level env vars (`TEMPORAL_TLS_CERT` / `TEMPORAL_TLS_KEY`). The universal-regression rule was likely written against the CLI-level form and does not account for the SDK envconfig form.

**Recommendation (out of scope for this validation):** reconcile this in the universal-regression table — either narrow the rule to the CLI context or add the envconfig forms as accepted variants. The PR itself faithfully reflects upstream and should not be sent back through authoring on this point. **Not a blocker.**

---

## Check 4 findings (independent re-verification — sampling)

10 evenly spaced citations sampled per file (60 total). All 60 sampled claims independently re-derived from the cited docs matched the authored claims substantively. Zero divergences.

Per-file sample sizes / match rates:

| File | Sampled | Matched |
|---|---:|---:|
| `core/standalone-activities.md` | 10 | 10 |
| `core/standalone-activities-cli.md` | 10 | 10 |
| `python/standalone-activities.md` | 10 | 10 |
| `go/standalone-activities.md` | 10 | 10 |
| `java/standalone-activities.md` | 10 | 10 |
| `dotnet/standalone-activities.md` | 10 | 10 |

CLI-flag-table cells (the highest off-by-one risk) were specifically sampled and matched correctly: `--reason` on `cancel`, `--raw` on `describe`, `--detail` on `fail`, `--workflow-id` required on `pause`, `--activity-id` / `--run-id` on `result`, `--reason` on `terminate`, and `--task-queue` (no shorthand) on `update-options`.

---

## VERIFY-marker inventory

Four `<!-- VERIFY: ... -->` markers exist across the six files. All four flag the same upstream gap — per-SDK conflict/reuse-policy parameter names are not surfaced in the SDK docs, only in the encyclopedia at the conceptual level — and correctly chose to omit the parameter signature rather than fabricate one. Each marker is judged **acceptable as-is** for the Public Preview state of the docs:

| File | Line | Subject | Judgment |
|---|---|---|---|
| `python/standalone-activities.md` | 21 | Server v1.31.0 not stated in Python doc; sourced from encyclopedia | Acceptable |
| `python/standalone-activities.md` | 178 | `id_conflict_policy` / `id_reuse_policy` kwargs not in Python doc | Acceptable; encyclopedia covers values |
| `go/standalone-activities.md` | 214–217 | Go `StartActivityOptions` field name for conflict/reuse policy not in Go doc | Acceptable; defers to godoc |
| `java/standalone-activities.md` | 163 | Java `StartActivityOptions` builder methods for conflict/reuse policy not in Java doc | Acceptable |
| `dotnet/standalone-activities.md` | 181 | .NET `StartActivityOptions` properties for conflict/reuse policy not in .NET doc | Acceptable |

(Note: the table lists 5 entries; the per-file scans found 4 distinct policy-related markers plus 1 server-version marker in the Python file. All justified.)

**No `<!-- undocumented: source = ... -->` markers exist in any file.** That tag wasn't needed because every fabrication-suspect token resolved to upstream.

When per-SDK conflict/reuse-policy wiring lands upstream, these VERIFY markers should be revisited. They are appropriate caveats today.

---

## Statistics

- **Files validated:** 6
- **Total lines of authored content:** 1,673
- **Citations:** 247 (all to docs clone; no secondary sources used)
- **Citation pass rate:** 247/247 = 100%
- **Token classes checked:** CLI flags, CLI subcommands, policy enums, version strings, SDK API symbols, run-state strings, metric names, imports/namespaces (~250+ distinct tokens)
- **Unexplained grep-misses:** 0
- **Regression-pattern hits:** 0 fabrications; 1 universal-rule tension (TLS env vars) traceable to upstream and out of skill scope to resolve
- **Check 4 sample size:** 60 (10/file)
- **Check 4 match rate:** 60/60 = 100%
- **VERIFY markers:** 5 (all justified by upstream gaps)
- **`<!-- undocumented: ... -->` markers:** 0

---

## Recommendation

**GO.** The PR meets all four-check thresholds. Merge.

Two follow-ups, neither blocking:

1. Consider adding `docs/encyclopedia/activities/standalone-activity.mdx:138` as a secondary citation alongside the existing dev-server citation in `references/go/standalone-activities.md:48-54` (and parallel spots in the other SDK files where the "enabled by default" claim appears) for the cleanest sourcing of the "enabled by default" half of that claim.
2. Reconcile the universal-regression rule on `TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH` vs. the SDK envconfig env-var names. This is a docs/regression-table problem, not a skill problem.

Revisit the five VERIFY markers when upstream surfaces per-SDK conflict/reuse-policy parameters.
