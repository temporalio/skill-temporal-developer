# Skill Authoring Plan — `temporal-developer: Standalone Activities feature`

**Mode:** greenfield (additive)

**Context:** The `temporal-developer` skill exists at `/Users/don/work/skills/skill-temporal-developer/` and is otherwise complete. This plan adds a new feature — **Standalone Activities** — into the existing skill. Standalone Activities are a Public Preview Temporal feature (CLI v1.7.0+, Server v1.31.0+) that let a Client run a single Activity as a top-level execution without a Workflow — Temporal's "job queue" primitive. The feature is documented in the encyclopedia, the `temporal activity` CLI reference, and four language SDK pages (Python, Go, Java, .NET). TypeScript has no Standalone Activities doc yet, so the skill must not invent TypeScript content. The job is to author new reference files that slot into the existing layout (`references/core/` and `references/{lang}/`) and to extend `SKILL.md` to point at them. Everything else in the skill stays untouched.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for Standalone Activities:

- `docs/encyclopedia/activities/standalone-activity.mdx` — concept page: definition, use cases, key features, observability, Public Preview limitations, CLI/Cloud support requirements.
- `docs/cli/activity.mdx` — `temporal activity` subcommand reference: `cancel`, `complete`, `count`, `describe`, `execute`, `fail`, `list`, `pause`, `reset`, `result`, `start`, `terminate`, `unpause`, `update-options`, plus global flags.
- `docs/develop/python/activities/standalone-activities.mdx` — Python SDK quickstart and APIs (write Activity, run Worker, execute/start/get handle/wait/list/count, Cloud connect mTLS + API key).
- `docs/develop/go/activities/standalone-activities.mdx` — Go SDK quickstart and APIs.
- `docs/develop/java/activities/standalone-activities.mdx` — Java SDK quickstart and APIs.
- `docs/develop/dotnet/activities/standalone-activities.mdx` — .NET SDK quickstart and APIs.
- `docs/encyclopedia/activities/activities.mdx`, `docs/encyclopedia/activities/activity-execution.mdx`, `docs/encyclopedia/activities/activity-operations.mdx` — Activity fundamentals that Standalone Activities inherit (timeouts, retries, heartbeats, cancellation). Cite when explaining shared mechanics rather than restating.
- `docs/evaluate/development-production-features/job-queue.mdx` — framing of Standalone Activities as Temporal's job-queue primitive.
- `docs/cloud/metrics/openmetrics/metrics-reference.mdx` — Activity metrics that apply to Standalone Activities (cite for observability claims only).

**Secondary (only if primary is silent):** SDK source/API references in sibling clones if present under `../`. Do not reach for the network unless the local clone is silent.

Prefer Read/Grep on the local clone over WebFetch.

**Never trust:** any prior sketches, slack threads, or wiki pages on Standalone Activities — treat as inputs to framing only, not as ground truth. In particular, do not invent a TypeScript SDK API surface — the docs clone has no TypeScript Standalone Activities page.

---

## 2. Preserve vs. rewrite

This feature is additive. The only existing files that get modified are `SKILL.md` (add pointers to the new references) and, if relevant, `references/{python,go,java,dotnet}/advanced-features.md` (add a one-line cross-link to the new standalone-activities reference). Do **not** rewrite existing reference content. Do **not** touch `references/typescript/` for Standalone Activities — the docs do not yet cover it; note the gap in `SKILL.md` instead.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, SDK method, conflict-policy value, or reuse-policy value, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what subcommands does `temporal activity` support for Standalone Activities?":

1. `Read ../documentation/docs/cli/activity.mdx` — scan all `## <subcommand>` headings.
2. Transcribe only the subcommands that appear there (`cancel`, `complete`, `count`, `describe`, `execute`, `fail`, `list`, `pause`, `reset`, `result`, `start`, `terminate`, `unpause`, `update-options`).
3. Record the line number where each appears.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`temporal activity start` <!-- docs/cli/activity.mdx:327 -->
```

Use one inline comment per non-trivial factual claim. Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If a `temporal activity <foo>` subcommand is not in `docs/cli/activity.mdx`, it doesn't exist.
2. **No "probably accepts" enum values.** Only list conflict-policy and reuse-policy values present in the docs. Do not pad the list.
3. **No "probably named" env vars, flags, or fields.**
4. **No inferred flag names.** Don't derive flags from prose.
5. **No conflating concept with interface.** "Standalone Activity" is a concept; the SDK methods and CLI subcommands are the interface — name each separately and cite each independently.
6. **No flattening of subcommand groups.** `temporal activity` has 14 subcommands; do not merge them into one example.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Conflict policy and reuse policy values.** The encyclopedia explicitly lists `USE_EXISTING` and `REJECT_DUPLICATES` and explicitly calls out that `TerminateExisting` / `TerminateIfRunning` are *not yet supported* in Public Preview. Do not list any policy value not present in the docs, and do not omit the unsupported-in-Preview note.
- **Public Preview limitations.** The encyclopedia calls out specific gaps (no pause/reset/update-options support in Public Preview; `TerminateExisting`/`TerminateIfRunning` unsupported). Reproduce these limitations verbatim — do not quietly drop them, and do not invent additional ones.
- **Version requirements.** Standalone Activities require Temporal CLI v1.7.0+ and Temporal Server v1.31.0+. Do not state earlier versions; do not omit the requirement.
- **TypeScript SDK.** No Standalone Activities doc exists at `docs/develop/typescript/activities/`. Do not write a TypeScript reference. In `SKILL.md`, note that TypeScript is not yet covered upstream.
- **Dual-use claim.** The encyclopedia states the *same Activity Function* can run as both Standalone and Workflow Activity with no Worker code changes. Preserve that exact framing — do not weaken it ("similar code") or strengthen it ("identical setup").
- **CLI flag surface.** `temporal activity` shares many global flags with other `temporal` commands (auth, address, namespace, codec, TLS). Cite the CLI doc's `## Global Flags` section, do not transcribe every flag — link by reference.
- **Identifier separation.** Standalone Activities live in a separate ID space from Workflows. Do not write recipes that assume a Workflow ID can address a Standalone Activity or vice versa.
- **Billing / Cloud framing.** The encyclopedia notes fewer Billable Actions than running a single-Activity Workflow. Do not extrapolate pricing numbers; cite the encyclopedia line and stop.
- **Activity metrics reuse.** Existing Activity metrics apply — do not invent Standalone-Activity-specific metric names. Cite `docs/cloud/metrics/openmetrics/metrics-reference.mdx`.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check the encyclopedia page for canonical framing before falling back to a language page.
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

If the user asks about TypeScript, point at the Python or Go reference and note the upstream gap.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Recipes (the "use Standalone Activity X to send an email reliably" pattern) are allowed if every step cites a documented API or CLI invocation. No invented orchestration patterns.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end

Especially §3.4 (topic-specific traps) and §8 (regression patterns).

### Step 2: Set up the workspace

Work directly in `/Users/don/work/skills/skill-temporal-developer/`. Create new files only at the paths listed in §5. Do not rename or restructure existing files.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules including §3.4).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Update `SKILL.md`

After all reference-file subagents complete, the orchestrator edits `SKILL.md` to:

- Add a new section "Standalone Activities" under "Additional Topics" (or as its own top-level section, mirroring the existing "Task Queue Priority and Fairness" section's placement and tone).
- Point at `references/core/standalone-activities.md` and the four language-specific files.
- Note that TypeScript SDK coverage is upstream-pending.
- Do **not** restructure existing `SKILL.md` sections.

### Step 5: Produce the log

Append a "Standalone Activities" section to `AUTHORING_LOG.md` (create if absent) summarizing per-file citations and `<!-- VERIFY -->` markers.

### What NOT to do

- Do not modify `references/typescript/`.
- Do not modify reference files outside the new Standalone Activities files and the surgical `SKILL.md` edit.
- Do not read or reference any prior conversation about Standalone Activities beyond this plan.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — the core concept file establishes shared terminology that the language and CLI files inherit.

1. **`references/core/standalone-activities.md`** — concept, when-to-use, dual-use with Workflows, key features, conflict/reuse policies (with Public Preview gaps), observability, version requirements, billing framing, identifier-space separation, and a pointer table to language pages and the CLI page. Ground truth: `docs/encyclopedia/activities/standalone-activity.mdx`, `docs/encyclopedia/activities/activities.mdx`, `docs/encyclopedia/activities/activity-execution.mdx`, `docs/evaluate/development-production-features/job-queue.mdx`, `docs/cloud/metrics/openmetrics/metrics-reference.mdx`.
2. **`references/core/standalone-activities-cli.md`** — the `temporal activity` subcommand surface as it pertains to Standalone Activities: `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, `terminate` (and a note that `pause`, `reset`, `update-options` are not supported in Public Preview per the encyclopedia). Cite each subcommand heading and each non-trivial flag explicitly. Ground truth: `docs/cli/activity.mdx`, with a cross-cite to `docs/encyclopedia/activities/standalone-activity.mdx` for the Public Preview limitation note.
3. **`references/python/standalone-activities.md`** — Python SDK: writing the Activity (no code changes from a Workflow Activity), worker registration, `Client.execute_activity` / `start_activity`, getting a handle, waiting for result, listing, counting, Cloud connect (mTLS, API key). Ground truth: `docs/develop/python/activities/standalone-activities.mdx` only.
4. **`references/go/standalone-activities.md`** — Go SDK equivalent. Ground truth: `docs/develop/go/activities/standalone-activities.mdx` only.
5. **`references/java/standalone-activities.md`** — Java SDK equivalent. Ground truth: `docs/develop/java/activities/standalone-activities.mdx` only.
6. **`references/dotnet/standalone-activities.md`** — .NET SDK equivalent. Ground truth: `docs/develop/dotnet/activities/standalone-activities.mdx` only.
7. **`SKILL.md`** — **last**. Add a "Standalone Activities" section pointing at the six new references; note TypeScript gap.

Why this order matters: the core concept file fixes terminology (Standalone Activity vs. Workflow Activity, conflict/reuse policy names, Public Preview limitations) that every language and CLI file then references without restating. Authoring the core file first prevents drift across the language files. SKILL.md is last so its pointers reflect what was actually written.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, SDK method name, conflict/reuse policy value, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum / policy value is traceable to a docs file.
4. No subcommand / field / method appears that isn't in the relevant `docs/` file's headings or tables.
5. The Public Preview limitations (no pause/reset/update-options; no `TerminateExisting`/`TerminateIfRunning`) are stated explicitly in the core file and cross-referenced from the CLI file.
6. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

- **`AUTHORING_LOG.md`** at the skill root: per-file docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- **A git-visible diff** — one commit per reference file, one commit for the `SKILL.md` edit, so review can proceed file-by-file.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| Listing `TerminateExisting` as a supported conflict policy | List `USE_EXISTING`; explicitly note `TerminateExisting` is unsupported in Public Preview | docs/encyclopedia/activities/standalone-activity.mdx:84, 110 |
| Listing `TerminateIfRunning` as a supported reuse policy | List `REJECT_DUPLICATES`; explicitly note `TerminateIfRunning` is unsupported in Public Preview | docs/encyclopedia/activities/standalone-activity.mdx:84, 110 |
| Claiming pause/reset/update-options work for Standalone Activities | State they are not supported in Public Preview but planned for GA | docs/encyclopedia/activities/standalone-activity.mdx:109 |
| Stating CLI v1.6.x or Server v1.30.x is sufficient | CLI v1.7.0+ and Server v1.31.0+ | docs/encyclopedia/activities/standalone-activity.mdx:23, 114 |
| Writing a TypeScript Standalone Activities reference | Note in SKILL.md that TypeScript coverage is upstream-pending; do not author the file | n/a (absence of `docs/develop/typescript/activities/standalone-activities.mdx`) |
| Saying Standalone Activities share an ID space with Workflows | Separate ID space from Workflows | docs/encyclopedia/activities/standalone-activity.mdx:85 |
| Saying you must rewrite Activity functions for Standalone use | Same Activity Function runs as Standalone or Workflow Activity with no code changes | docs/encyclopedia/activities/standalone-activity.mdx:56–57 |
| Inventing Standalone-Activity-specific metric names | Use existing Activity metrics; cite metrics-reference | docs/encyclopedia/activities/standalone-activity.mdx:94–96 |
| Flattening `temporal activity` subcommands into one command with flags | Document each subcommand under its own heading | docs/cli/activity.mdx:37, 62, 83, 102, 119, 162, 182, 202, 238, 310, 327, 370, 390, 446 |
| Claiming Temporal Cloud GA for Standalone Activities | Public Preview in Temporal Cloud | docs/encyclopedia/activities/standalone-activity.mdx:23, 142 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- Standalone Activities are Public Preview in Temporal Cloud and require CLI v1.7.0+ with Server v1.31.0+ (`docs/encyclopedia/activities/standalone-activity.mdx:23`, `:114`).
- A Standalone Activity is a top-level Activity Execution started directly by a Client, without a Workflow (`docs/encyclopedia/activities/standalone-activity.mdx:50–52`).
- The same Activity Function can be executed as a Standalone Activity and a Workflow Activity with no code changes (`docs/encyclopedia/activities/standalone-activity.mdx:56–57`).
- Conflict policy includes `USE_EXISTING`; reuse policy includes `REJECT_DUPLICATES` (`docs/encyclopedia/activities/standalone-activity.mdx:84`).
- `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are not supported in Public Preview (`docs/encyclopedia/activities/standalone-activity.mdx:110`).
- Pause, reset, and update options are not supported in Public Preview but scheduled for GA (`docs/encyclopedia/activities/standalone-activity.mdx:109`).
- Standalone Activities have a separate ID space from Workflows (`docs/encyclopedia/activities/standalone-activity.mdx:85`).
- The `temporal activity` CLI surface includes `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, `terminate`, plus `pause`, `reset`, `unpause`, `update-options`, `complete`, `fail` (`docs/cli/activity.mdx:37, 62, 83, 102, 119, 162, 182, 202, 238, 310, 327, 370, 390, 446`).
- The encyclopedia's GET STARTED tip lists exactly four SDK quickstarts: Go, Python, .NET, Java (`docs/encyclopedia/activities/standalone-activity.mdx:63–66`) — TypeScript is intentionally absent.
- The Temporal Dev Server has Standalone Activities enabled by default (`docs/encyclopedia/activities/standalone-activity.mdx:138`).
- All existing Activity metrics apply to Standalone Activities — no new Standalone-specific metric names (`docs/encyclopedia/activities/standalone-activity.mdx:94–96`).

---

## 10. Non-goals

- **Do not re-architect the skill.** The existing file layout, section order, and `SKILL.md` frontmatter schema are fixed. Add pointers, do not move sections.
- **Do not expand scope.** This plan covers Standalone Activities only — not Activities in general, not Workflow Activities, not Schedules. Cross-link where the docs do.
- **Do not paraphrase docs prose verbatim.** Cite, don't copy.
- **Do not write tests, CI, or tooling.**
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`) unless the user asks.
- **Do not author a TypeScript reference.** Note the upstream gap in `SKILL.md` and stop.
- **Do not change the skill version field unless the user asks.** If they do, bump the patch version of the existing `version: 0.3.2` only.

---

## 11. Sibling handoff

This skill sits alongside:

- `skill-temporal-cli` — full `temporal` CLI reference. When the new Standalone Activities CLI reference cites a `temporal activity` subcommand, spell out the full invocation with citation to `docs/cli/activity.mdx`, but if the user is doing CLI-heavy work, point them at `skill-temporal-cli` for the broader command surface.
- `skill-temporal-cloud` — Temporal Cloud setup. The Cloud-connect snippets in the Python/Go/Java/.NET Standalone Activities references should cross-link to that skill rather than restating mTLS / API-key setup.
- `skill-temporal-triage` — incident/triage flows. If a Standalone Activity is stuck or failing, point at that skill's troubleshooting trees rather than authoring new ones here.

Handoff disciplines:

1. When this feature prescribes a command documented in a sibling, spell out the full invocation but cite the canonical docs file, not the sibling skill.
2. When a topic belongs to a sibling, cross-reference it; don't absorb it.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (the docs may have moved since this plan was written), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
