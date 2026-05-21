# Skill Validation Plan — `{{SKILL_NAME}}`

**Reader:** you are an AI agent. The user has told you to validate a Temporal skill using this template. Your job has two phases:

1. **Phase 1 — Fill this plan.** Examine the authored skill files, identify the docs paths and token classes, fill every `{{PLACEHOLDER}}`, and present the filled plan to the user for approval.
2. **Phase 2 — Execute the filled plan.** Run the four-check protocol and produce a go/no-go report.

**Critical constraint:** you must be a *different session* than the one that authored the skill. Do not read the authoring plan, the `AUTHORING_LOG.md`, or any prior conversation about the authoring. You validate from the authored files and the docs alone.

Do not start Phase 2 until the user approves the filled plan.

---

## How to fill the placeholders (Phase 1 instructions)

### Step A: Identify what you're validating

The user will point you at a skill directory. Record the path as `{{SKILL_ROOT}}`. Read `SKILL.md` to understand the topic and scope. List all reference files under `references/`. Record the topic as `{{SKILL_NAME}}`.

### Step B: Discover docs paths for §2

From the authored files, extract the docs paths cited in `<!-- docs/… -->` comments. Confirm these files exist under `../documentation/docs/`. Fill the path entries in §2.

If the skill cites non-docs sources (`<!-- go: … -->`, `<!-- grpc: … -->`, `<!-- man: … -->`), note those as secondary sources in §2.

### Step C: Build token-extraction patterns for Check 2

Scan the authored files and categorize which classes of factual tokens appear. Fill the patterns in Check 2. Typical classes:

- Flag names: `--[a-z][a-z0-9-]+`
- Command invocations: `^\s*(temporal|tcld) ` inside code fences
- Env vars: `TEMPORAL_[A-Z_]+`
- Enum values quoted in tables
- Error strings (for triage-style skills)
- API fields / types (topic-dependent)

### Step D: Build the regression table for Check 3

Start with the universal regression patterns already in Check 3 below. Then check whether the skill directory contains an `AUTHORING_PLAN.md` with a §8 regression table. If it does, add those entries. If no topic-specific regressions exist, the universal patterns still apply.

If the skill covers ecosystem claims, uncomment the optional ecosystem-regression subsection.

---

<!-- ═══════════════════════════════════════════════════════
     PLAN BODY — everything below is what the executing
     agent follows in Phase 2 (after placeholders are filled)
     ═══════════════════════════════════════════════════════ -->

**Purpose:** independent verification that the skill is accurate, grounded, and free of fabrication patterns. Produce a go/no-go.

**Non-purpose:** editing the skill. If validation finds problems, report them — do *not* fix them. Fixing belongs to another authoring pass.

---

## 1. Independence requirement

Validation must be performed by a different session than authoring. Do *not* reuse the orchestrator that ran the authoring subagents — it carries authoring's mental model and will miss fabrications it introduced.

The validator agents read the *authored* files and the *docs clone*; they do **not** read the authoring plan, the `AUTHORING_LOG.md`, or any prior conversation.

---

## 2. Source of truth

- Primary: `../documentation/docs/`, with topic-relevant subtrees:
  - `docs/{{PATH_1}}`
  - `docs/{{PATH_2}}`
  - `docs/{{PATH_3}}`
- Secondary: {{LIST IF APPLICABLE, e.g. Go stdlib, gRPC spec. Omit if not applicable.}}

Do not trust citations in the authored files as proof — follow them and confirm the cited text supports the claim. Citations can be wrong in three ways: wrong file, wrong line, or correct line with a claim subtly different from what the line actually says. All three must be caught.

---

## 3. Four-check validation protocol

Run all four checks. The skill passes only if all four pass.

### Check 1: citation audit

Mechanical. For every inline citation comment in the authored files:

1. Confirm the cited file exists under `../documentation/docs/` (or the secondary-source location, for ecosystem tags).
2. Read the cited line range.
3. Confirm the authored claim is substantively supported by the cited text — not merely adjacent to it.

**Pass criterion:** ≥ 98% of citations resolve cleanly. Any unresolved citation is a finding.

**How to run:** Grep the authored files for `<!-- docs/` (and any other source-category tags), extract path + line, Read, verify. Delegate per-reference-file to a subagent for parallelism.

### Check 2: reverse-grep audit

Extract every factual token from the authored files, then grep the source-of-truth clone for each. Anything not found is a fabrication suspect.

Patterns to extract for `{{SKILL_NAME}}`:

- {{TOKEN_CLASS_1}}: regex `{{REGEX}}`.
- {{TOKEN_CLASS_2}}: lines matching `{{PATTERN}}` inside code fences.
- {{TOKEN_CLASS_3}}: {{SHAPE}}.
- {{TOKEN_CLASS_4}}: enum values quoted in tables — for each, confirm the value appears next to the field in the relevant docs file.

For each extracted token, run Grep against the relevant docs subtree. Absence means one of:

- The token is fabricated — **finding**.
- The token is real but undocumented — acceptable only if the authored file explicitly marks it with `<!-- undocumented: source = … -->`.
- The token is an ecosystem token — acceptable only if tagged with its source category.

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

**Topic-specific patterns:**

| Wrong pattern | Should be | Source |
|---|---|---|
| {{WRONG_PATTERN_1}} | {{CORRECT_FORM}} | docs/{{PATH}}:{{LINE}} |
| {{WRONG_PATTERN_2}} | {{CORRECT_FORM}} | docs/{{PATH}}:{{LINE}} |

<!-- OPTIONAL ecosystem-regression subsection — keep only if skill covers ecosystem claims.
Additional rules:
- Invented gRPC status codes (outside the canonical 17: OK, CANCELLED, UNKNOWN, INVALID_ARGUMENT, DEADLINE_EXCEEDED, NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED, RESOURCE_EXHAUSTED, FAILED_PRECONDITION, ABORTED, OUT_OF_RANGE, UNIMPLEMENTED, INTERNAL, UNAVAILABLE, DATA_LOSS, UNAUTHENTICATED).
- Uncited quoted error strings.
- Untagged ecosystem claims (every `x509:` / `tls:` / `openssl` / `nc` claim must carry a `<!-- go: … -->`, `<!-- grpc: … -->`, or `<!-- man: … -->` tag).
end optional -->

**Pass criterion:** zero hits against any regression pattern. Strict — these are bugs already identified and should not survive a grounded authoring pass.

### Check 4: independent re-verification (sampling)

The first three checks catch fabrication and drift. This one catches *subtle-wrong*: a citation points at a real line, but the author's interpretation of that line is off by a nuance.

Pick **10 claims at random** per reference file (typically 20–120 per skill total). For each:

1. Read *only* the claim in the authored file — not the citation.
2. Open the cited doc *independently* and read the section fresh.
3. Write down what you think the correct claim should be, given only the docs.
4. Compare your version to the authored version.

"Substantively different" = a reader following one would do something different than a reader following the other. Typographical / stylistic differences don't count.

**Pass criterion:** ≥ 95% of sampled claims match. Below 95% = flag for second authoring pass.

**How to randomize:** number all citations in a file; use a seeded approach (every Nth citation, or shuffle-by-hash) to pick. Record which citations were sampled in the report.

---

## 4. Execution shape

One validator orchestrator agent. The agent:

1. Reads this plan.
2. Reads the authored files in `{{SKILL_ROOT}}` (not the authoring plan, not the `AUTHORING_LOG.md`).
3. Runs Check 1 — delegate to a per-reference-file subagent for parallelism.
4. Runs Check 2 — delegate per reference file.
5. Runs Check 3 — single pass across all files.
6. Runs Check 4 — delegate per reference file; each subagent reads only the docs, not the rest of the skill.
7. Produces the report per §5.

---

## 5. Deliverables

- **`VALIDATION_REPORT.md`** at `{{SKILL_ROOT}}` with sections:
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
