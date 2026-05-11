# Skill Authoring Plan — `standalone-activities`

**Mode:** greenfield

**Context:** Add a new sub-topic to the `skill-temporal-developer` skill covering Standalone Activities — Temporal's job-queue primitive that lets a client start, manage, list, and count Activities directly without a Workflow. The topic is in Public Preview / Pre-release across SDKs and there is no prior content for it in this skill. Audience: developers who already know Temporal Workflow Activities and need to understand when and how to use Standalone Activities in their language. Scope is limited to the four SDKs the user named — Python, TypeScript, Java, .NET — plus a shared core/conceptual reference. The Go docs exist upstream but are explicitly out of scope for this run; we note that in the authoring log so a future pass can pick it up. The sibling skills (`skill-temporal-cli`, `skill-temporal-triage`) do not appear in this clone, so we won't add a sibling-handoff section.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `standalone-activities`:

- `docs/encyclopedia/activities/standalone-activity.mdx` — conceptual page: what a Standalone Activity is, key features, Public Preview limitations, CLI version requirements, Cloud support.
- `docs/evaluate/development-production-features/job-queue.mdx` — positions Standalone Activities as Temporal's job queue; overview of lifecycle, observability, and lifecycle controls.
- `docs/encyclopedia/activities/activity-execution.mdx` — explains that the failure for a Standalone Activity is returned to the Client (not a Workflow), and that Standalone Activity IDs occupy a separate ID space.
- `docs/encyclopedia/activities/activity-operations.mdx` — clarifies that Pause/Unpause/Reset/Update-Options do NOT apply to Standalone Activities.
- `docs/cli/activity.mdx` — auto-generated CLI reference for `temporal activity` subcommands (`start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, `terminate`, plus the workflow-Activity-only `pause`, `unpause`, `reset`, `update-options`, `complete`, `fail`).
- `docs/develop/python/activities/standalone-activities.mdx` — Python SDK quickstart, client methods, samples.
- `docs/develop/typescript/activities/standalone-activities.mdx` — TypeScript SDK quickstart, typed and untyped `ActivityClient`, samples.
- `docs/develop/java/activities/standalone-activities.mdx` — Java SDK quickstart, `ActivityClient`, `ActivityHandle`, samples.
- `docs/develop/dotnet/activities/standalone-activities.mdx` — .NET SDK quickstart, `ExecuteActivityAsync` / `StartActivityAsync` / `GetActivityHandle`, samples.
- `docs/cloud/metrics/openmetrics/metrics-reference.mdx` — confirms metrics shared with regular Activities, the `"__standalone_activity"` placeholder for `temporal_workflow_type`, and that `activity_terminate_count` applies only to Standalone Activities.
- `docs/evaluate/temporal-cloud/actions.mdx` — Cloud Action types specific to Standalone Activities (`start_standalone_activity`, `retry_standalone_activity`, `record_standalone_activity_heartbeat`, `record_standalone_activity_heartbeat_by_id`).

**Secondary (only if primary is silent):** none. Everything we need is in the `documentation/` clone.

Prefer Read/Grep on a local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** any AI memory about Standalone Activity APIs from prior conversations or training data. The feature is in Public Preview, SDK method names differ per language, and several details (CLI flag names, version floors, conflict/reuse policy enum values) are easy to fabricate. Every API token must be grep-confirmed from one of the paths above.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "what flags does `temporal activity execute` take?":

1. `Read ../documentation/docs/cli/activity.mdx` §execute.
2. Transcribe only what appears in that file.
3. Record the line number where you found it.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`temporal activity execute --start-to-close-timeout` <!-- docs/cli/activity.mdx:154 -->
```

Pick one convention (inline comment per claim *or* `<!-- Sources: … -->` footer per section) and use it consistently across a file. Inline-per-claim is preferred for API tables and command lists; section-level `<!-- Sources: … -->` is fine for prose paragraphs where individual tokens come from a single page.

Keep citations to local repo paths (no URLs). Use the form `docs/<path>:<line>` where `<path>` is relative to `../documentation/` and `<line>` is the line where the token actually appears.

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `TEMPORAL_X_Y_PATH` from `--x-y-path`. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** Platform concepts and CLI/SDK tokens often have subtly different names. Document the interface token; name the concept separately with a pointer.
6. **No flattening of subcommand groups.** If the docs show a group with N subcommands, don't flatten to one command with a flag.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Don't claim a CLI subcommand exists for both regular and Standalone Activities without checking.** The page explicitly notes that `pause`, `unpause`, `reset`, and `update-options` are "Not supported for Standalone Activities" (`docs/cli/activity.mdx:202, 236, 384, 436`) while `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate` are Standalone-specific or shared (`docs/encyclopedia/activities/standalone-activity.mdx:136-137`). The `complete` and `fail` subcommands accept either (they need `--workflow-id` for the workflow-Activity case and omit it for Standalone Activities) — `docs/cli/activity.mdx:77, 174`.
- **Don't invent conflict/reuse policy enum values.** The docs name only `USE_EXISTING` and `REJECT_DUPLICATES` as examples and explicitly note that `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are **not supported in Public Preview** (`docs/encyclopedia/activities/standalone-activity.mdx:85, 111`). CLI accepted values are listed in the flag tables: `--id-conflict-policy` accepts `Fail, UseExisting`; `--id-reuse-policy` accepts `AllowDuplicate, AllowDuplicateFailedOnly, RejectDuplicate` (`docs/cli/activity.mdx:140-141`). Don't conflate CLI casing with SDK enum casing without checking.
- **Don't conflate SDK method names across languages.** Each SDK has its own surface:
  - Python: `client.execute_activity()` / `client.start_activity()` / `client.get_activity_handle()` / `client.list_activities()` / `client.count_activities()` (`docs/develop/python/activities/standalone-activities.mdx:215, 279, 311, 342, 394`).
  - TypeScript: `client.activity.execute()` / `client.activity.start()` / `client.activity.getHandle()` / `client.activity.list()` / `client.activity.count()` and the typed variant via `client.activity.typed<typeof activities>()` (`docs/develop/typescript/activities/standalone-activities.mdx:224, 253, 287, 308, 339, 379`).
  - Java: `ActivityClient.execute()` / `ActivityClient.start()` / `client.getHandle()` / `client.listExecutions()` / `client.countExecutions()` (`docs/develop/java/activities/standalone-activities.mdx:198, 268, 309, 345, 383`).
  - .NET: `client.ExecuteActivityAsync()` / `client.StartActivityAsync()` / `client.GetActivityHandle()` / `client.ListActivitiesAsync()` / `client.CountActivitiesAsync()` (`docs/develop/dotnet/activities/standalone-activities.mdx:200, 275, 321, 352, 394`).
- **Don't invent SDK version floors.** Each SDK doc lists a specific minimum: Python `temporalio` v1.23.0+ (`docs/develop/python/activities/standalone-activities.mdx:69`), TypeScript SDK v1.17.0+ (`docs/develop/typescript/activities/standalone-activities.mdx:62`), Java SDK v1.35.0+ (`docs/develop/java/activities/standalone-activities.mdx:64`), .NET SDK v1.12.0+ (`docs/develop/dotnet/activities/standalone-activities.mdx:62`), Temporal CLI v1.7.0+ and Server v1.31.0+ (`docs/encyclopedia/activities/standalone-activity.mdx:23`, `docs/encyclopedia/activities/standalone-activity.mdx:115`). Cite the exact line.
- **Don't claim a "serialization context" or `ActivityInfo` nullability behavior that the docs don't state.** The task description hints at nullability changes (Standalone Activities have no parent Workflow, so workflow-derived fields don't apply), and the metrics page confirms the placeholder `"__standalone_activity"` for `temporal_workflow_type` (`docs/cloud/metrics/openmetrics/metrics-reference.mdx:315`). Beyond that, the public docs do not describe SDK-internal nullability changes in ActivityInfo / activity execution context. If you can't find a specific source, do not write the claim — leave a `<!-- VERIFY -->` marker stating the question (e.g. "Is `info.workflow_id` nullable when running standalone?") and move on. Authoring log should list these markers.
- **Don't claim Activity Operations work on Standalone Activities.** `docs/encyclopedia/activities/activity-operations.mdx:31` says: "Activity Operations don't apply to Local Activities or Standalone Activities." That includes Pause, Unpause, Reset, and Update Options.
- **Don't promise async-completion semantics for Standalone Activities beyond what the encyclopedia says.** The features list mentions "Manual completion by ID (or token): ignore activity return and wait for external completion" (`docs/encyclopedia/activities/standalone-activity.mdx:89`). Implementation details (which SDK calls to use) are not in the standalone-activities pages we've read; do not invent them.
- **Don't generalize from one SDK's example to another.** TypeScript shows a typed-vs-untyped client split, .NET shows lambda-vs-string-name, Python doesn't have either — each language's API surface is different. Keep them isolated in their per-language files.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source (e.g., the auto-generated CLI source noted at the top of `docs/cli/activity.mdx`, or the SDK changelog if present in the clone).
2. Note the ambiguity in a `<!-- VERIFY: <specific question> -->` comment and leave the claim out of the prose.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

Never fabricate to fill a gap. An empty section with a VERIFY note is acceptable; a fabricated section is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Where the docs describe what a thing does, you describe what that thing does. Where the docs don't prescribe a workflow, don't invent one. Recipes/playbooks are the one exception — they chain documented facts — and each step must cite the doc where the fact comes from.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end

Do not start editing until you've read all sections, especially §8 (regression patterns) and §9 (known correct anchors).

### Step 2: Set up the workspace

Greenfield: create one new file per language under the existing `references/<lang>/` directories, plus a shared `references/core/standalone-activities.md`. Do not touch any existing reference file except `SKILL.md`, which gets an Intent/section update at the end.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one file. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Author SKILL.md updates

After all reference-file subagents complete, update `SKILL.md` (the orchestrator does this directly). Add a new section in "Additional Topics" pointing to `references/core/standalone-activities.md` and the per-language files. Do not change the overall framing of `SKILL.md` — the rest of the skill is unchanged.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports: for each reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers. Note that Go was out of scope.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond what §1 names.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.
- Do not author a Go reference file for this topic (the user limited scope to Python, TypeScript, Java, .NET).
- Do not modify other reference files (e.g., `references/python/python.md`) beyond a cross-reference if a natural pointer exists. Major refactors of existing files are out of scope.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/core/standalone-activities.md`** — language-agnostic concept reference: what a Standalone Activity is, the job-queue framing, key features and Public Preview limitations, when to use it vs. a Workflow, CLI subcommand inventory, observability/metrics, Cloud Action types, separate ID space, support matrix (SDK versions, CLI/Server versions). Ground truth: `docs/encyclopedia/activities/standalone-activity.mdx`, `docs/evaluate/development-production-features/job-queue.mdx`, `docs/encyclopedia/activities/activity-execution.mdx`, `docs/encyclopedia/activities/activity-operations.mdx`, `docs/cli/activity.mdx`, `docs/cloud/metrics/openmetrics/metrics-reference.mdx`, `docs/evaluate/temporal-cloud/actions.mdx`.

2. **`references/python/standalone-activities.md`** — Python SDK reference: prerequisites and version floor, Activity definition (unchanged from Workflow Activities), Worker registration (unchanged), `client.execute_activity()` / `client.start_activity()` / `client.get_activity_handle()` / `client.list_activities()` / `client.count_activities()` usage, Temporal Cloud connection patterns. Ground truth: `docs/develop/python/activities/standalone-activities.mdx`.

3. **`references/typescript/standalone-activities.md`** — TypeScript SDK reference: prerequisites and version floor, Activity definition, Worker registration, typed-vs-untyped client surface (`client.activity.typed()` vs `client.activity.execute()` direct), `start` / `execute` / `getHandle` / `list` / `count`, Temporal Cloud connection patterns. Ground truth: `docs/develop/typescript/activities/standalone-activities.mdx`.

4. **`references/java/standalone-activities.md`** — Java SDK reference: prerequisites and version floor, Activity interface and impl, Worker setup with `WorkerFactory`, `ActivityClient.newInstance()` / `execute` / `start` / `getHandle` / `listExecutions` / `countExecutions`, sync vs async result fetch (`getResult` vs `getResultAsync`), Temporal Cloud connection patterns. Ground truth: `docs/develop/java/activities/standalone-activities.mdx`.

5. **`references/dotnet/standalone-activities.md`** — .NET SDK reference: prerequisites and version floor, `[Activity]` attribute usage, Worker setup with `TemporalWorker` and `AddActivity`, `ExecuteActivityAsync` (lambda and string-name variants) / `StartActivityAsync` / `GetActivityHandle` / `ListActivitiesAsync` / `CountActivitiesAsync`, `StartActivityOptions` requirements, Temporal Cloud connection patterns. Ground truth: `docs/develop/dotnet/activities/standalone-activities.mdx`.

6. **`SKILL.md`** — **last**. Add a new "Standalone Activities" subsection under "Additional Topics" with a one-paragraph framing and pointers to the core and per-language files. Update the top-level description if needed (do not rewrite the existing framing). Do not change other sections.

Why this order matters: the core file establishes vocabulary (Standalone Activity, separate ID space, conflict/reuse policy names, CLI inventory, Public Preview limitations, version floors) that the per-language files refer to without re-explaining. The per-language files are independent of each other but all depend on the core file's framing.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, field name, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file's headings or tables.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity. Note that Go was out of scope.
- **One commit per reference file** so review can proceed file-by-file (CI may bundle them; document either way).
- The filled `SKILL_AUTHORING_PLAN_standalone-activities.md` (this file) kept in the repo root.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| Standalone Activities support `pause` / `unpause` / `reset` / `update-options` | Activity Operations don't apply to Standalone Activities; the CLI subcommands are explicitly "Not supported for Standalone Activities" | `docs/encyclopedia/activities/activity-operations.mdx:31`, `docs/cli/activity.mdx:202`, `docs/cli/activity.mdx:236`, `docs/cli/activity.mdx:384`, `docs/cli/activity.mdx:436` |
| Conflict policy / reuse policy includes `TerminateExisting` / `TerminateIfRunning` | Those are explicitly **not supported** in Public Preview; the docs list `USE_EXISTING` and `REJECT_DUPLICATES` as the named examples for SDK enum values, and the CLI accepts `Fail, UseExisting` (`--id-conflict-policy`) and `AllowDuplicate, AllowDuplicateFailedOnly, RejectDuplicate` (`--id-reuse-policy`) | `docs/encyclopedia/activities/standalone-activity.mdx:85`, `docs/encyclopedia/activities/standalone-activity.mdx:111`, `docs/cli/activity.mdx:140-141` |
| Standalone Activity IDs share the same ID space as Workflow IDs | Standalone Activities have a separate ID space from Workflows | `docs/encyclopedia/activities/standalone-activity.mdx:86`, `docs/encyclopedia/activities/activity-execution.mdx:117-118` |
| Standalone Activities require a different Worker than Workflow Activities | The same Worker that runs Workflow Activities also runs Standalone Activities — no Worker code changes needed | `docs/encyclopedia/activities/standalone-activity.mdx:91`, `docs/develop/python/activities/standalone-activities.mdx:168-171`, `docs/develop/typescript/activities/standalone-activities.mdx:145-149`, `docs/develop/java/activities/standalone-activities.mdx:166-170`, `docs/develop/dotnet/activities/standalone-activities.mdx:149-153` |
| Standalone Activity errors are returned to the parent Workflow | A Standalone Activity has no Workflow; the error is returned to the Client that started it | `docs/encyclopedia/activities/activity-execution.mdx:49-51` |
| `temporal_workflow_type` label is omitted for Standalone Activities in metrics | The metric still has the label, but its value is the placeholder `"__standalone_activity"` | `docs/cloud/metrics/openmetrics/metrics-reference.mdx:315` |
| Generic Activity timeout flags apply only to Workflow Activities | `--schedule-to-close-timeout`, `--start-to-close-timeout`, `--schedule-to-start-timeout`, `--heartbeat-timeout` apply to `temporal activity start` / `execute` for Standalone Activities (one of schedule-to-close or start-to-close is required) | `docs/cli/activity.mdx:151-154`, `docs/cli/activity.mdx:352-355` |
| `temporal activity describe` / `cancel` / `terminate` work on workflow-Activity executions | Per the CLI page they describe / cancel / terminate **Standalone Activities** ("Display information about a Standalone Activity", "Request cancellation of a Standalone Activity", "Terminate a Standalone Activity") | `docs/cli/activity.mdx:39`, `docs/cli/activity.mdx:102`, `docs/cli/activity.mdx:363` |
| `client.list_activities()` returns both Workflow and Standalone Activities | The list/count APIs return **only** Standalone Activity Executions; Activities running inside Workflows are not included | `docs/develop/python/activities/standalone-activities.mdx:346`, `docs/develop/typescript/activities/standalone-activities.mdx:344`, `docs/develop/java/activities/standalone-activities.mdx:350-351`, `docs/develop/dotnet/activities/standalone-activities.mdx:356` |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync if the docs change.

---

## 9. Known correct anchors

- A Standalone Activity is "a top-level Activity Execution started directly by a Client, without using a Workflow" (`docs/encyclopedia/activities/standalone-activity.mdx:50-51`).
- Standalone Activities require Temporal CLI v1.7.0+ and Temporal Server v1.31.0+ (`docs/encyclopedia/activities/standalone-activity.mdx:23`, `docs/encyclopedia/activities/standalone-activity.mdx:115`).
- The `temporal activity` subcommands that support Standalone Activities are `start`, `execute`, `result`, `list`, `count`, `describe`, `cancel`, and `terminate` (`docs/encyclopedia/activities/standalone-activity.mdx:136-137`).
- `pause`, `unpause`, `reset`, and `update-options` are explicitly "Not supported for Standalone Activities" (`docs/cli/activity.mdx:202`, `docs/cli/activity.mdx:236`, `docs/cli/activity.mdx:384`, `docs/cli/activity.mdx:436`).
- `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are **not yet supported** in Public Preview (`docs/encyclopedia/activities/standalone-activity.mdx:111`).
- Python SDK version floor: `temporalio` v1.23.0+ (`docs/develop/python/activities/standalone-activities.mdx:69`).
- TypeScript SDK version floor: v1.17.0+ (`docs/develop/typescript/activities/standalone-activities.mdx:62`).
- Java SDK version floor: v1.35.0+ (`docs/develop/java/activities/standalone-activities.mdx:64`).
- .NET SDK version floor: v1.12.0+ (`docs/develop/dotnet/activities/standalone-activities.mdx:62`).
- The Python SDK is at Public Preview (`docs/develop/python/activities/standalone-activities.mdx:24-25`); .NET SDK is at Public Preview (`docs/develop/dotnet/activities/standalone-activities.mdx:24-25`); Java SDK is at Pre-release (`docs/develop/java/activities/standalone-activities.mdx:24-25`); TypeScript SDK is at Pre-release (`docs/develop/typescript/activities/standalone-activities.mdx:24-25`).
- An Activity Function/Implementation runs unchanged whether invoked from a Workflow or as a Standalone Activity (`docs/encyclopedia/activities/standalone-activity.mdx:56-57`).
- A Standalone Activity's failure is returned to the Client (not a Workflow) when the Client fetches the result (`docs/encyclopedia/activities/activity-execution.mdx:49-51`).
- Standalone Activities have a separate ID space from Workflows; conflict/reuse policies observe only that space (`docs/encyclopedia/activities/activity-execution.mdx:117-118`, `docs/encyclopedia/activities/standalone-activity.mdx:86`).
- For metrics, `temporal_workflow_type` is `"__standalone_activity"` (`docs/cloud/metrics/openmetrics/metrics-reference.mdx:315`).
- `temporal_cloud_v1_activity_terminate_count` applies only to Standalone Activities (`docs/cloud/metrics/openmetrics/metrics-reference.mdx:396`).
- Cloud billable Action types specific to Standalone Activities: `start_standalone_activity`, `retry_standalone_activity`, `record_standalone_activity_heartbeat`, `record_standalone_activity_heartbeat_by_id` (`docs/evaluate/temporal-cloud/actions.mdx:120-123`).
- Each SDK's `StartActivityOptions` / equivalent requires `id`, `taskQueue`, and at least one of `scheduleToCloseTimeout` or `startToCloseTimeout` (`docs/develop/dotnet/activities/standalone-activities.mdx:246-247`, `docs/develop/java/activities/standalone-activities.mdx:237-238`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** Go is out of scope. Production-deployment guides for self-hosted clusters with Standalone Activities enabled are out of scope. Async completion deep-dives are out of scope.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis and framing, not re-publication. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`) unless the user asks.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
