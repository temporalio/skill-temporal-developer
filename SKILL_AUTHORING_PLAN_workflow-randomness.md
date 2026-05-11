# Skill Authoring Plan — `workflow-randomness`

**Mode:** greenfield

**Context:** The `temporal-developer` skill at this repo root already covers Temporal development across all SDKs, with Python guidance in `references/python/`. It currently mentions `workflow.random()` and `workflow.uuid4()` in two places — `references/python/determinism.md` (one-line table entries) and `references/python/python.md` (no dedicated treatment). Neither expands on the API surface, the seeding model, or the rationale. This plan adds one focused Python reference file, `references/python/workflow-randomness.md`, that grounds those facts in the docs and answers "what does `workflow.random()` actually give me?" The audience is a Python Temporal developer who knows that randomness in workflows is forbidden and is now looking for the deterministic replacement. The skill is Python-only because the user's brief scopes it to Python; sibling SDKs already have their own docs for the equivalent primitives. The single existing top-level `SKILL.md` is updated to point to the new file from the "Additional Topics" / language references list. No new top-level SKILL.md frontmatter is created.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `workflow-randomness`:

- `docs/develop/python/workflows/basics.mdx` — §"Random numbers and UUIDs" (lines ~200–213), §"Develop Workflow logic" (lines ~161–183) listing what is forbidden ("no randomness") and the pattern of replay-safe alternatives.
- `docs/develop/python/workers/interceptors.mdx` — lines ~39–48 (the "Workflow interceptors and replay" warning) explaining that interceptors execute during replay and must use replay-safe APIs for randomness/time/logging.
- `docs/encyclopedia/workflow/workflow-definition.mdx` — §"Intrinsic non-deterministic logic" (lines ~245–266) describing why inline randomness produces non-deterministic Command sequences and why each SDK provides replay-safe APIs that record results in Event History.

**Secondary (only if primary is silent):** none. The Python SDK API reference URLs (`https://python.temporal.io/temporalio.workflow.html#random`, `#uuid4`) are linked from the primary docs and may be cited as the canonical signature source, but the docs already transcribe the signatures and behavior needed. Do not WebFetch — the Markdown link text in `basics.mdx` is sufficient.

Prefer Read/Grep on the local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** any prior phrasing about randomness/UUID in `references/python/determinism.md`, `references/python/gotchas.md`, or `references/python/python.md` — treat as inputs to the Intent table, not as ground truth. Re-derive every claim from the docs paths above.

---

## 2. Preserve vs. rewrite

Not applicable — greenfield mode.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a function name, method name, attribute, or sandbox behavior claim, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "what does `workflow.random()` return?":

1. `Read ../documentation/docs/develop/python/workflows/basics.mdx` §"Random numbers and UUIDs".
2. Transcribe only what appears in that file: it returns "a deterministic `random.Random` instance seeded per Workflow Execution."
3. Record the line number where you found it (e.g. `basics.mdx:202`).

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`workflow.random()` returns a deterministic `random.Random` instance seeded per Workflow Execution. <!-- docs/develop/python/workflows/basics.mdx:202 -->
```

Pick one convention (inline comment per claim) and use it consistently across `workflow-randomness.md`. Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" methods.** If `workflow.<name>` is not in the docs, it doesn't exist in this skill. Do not invent `workflow.random_int()`, `workflow.randint()`, `workflow.uuid1()`, `workflow.uuid7()`, or any other ergonomic helper.
2. **No "probably accepts" arguments.** `workflow.random()` and `workflow.uuid4()` are documented as no-argument calls. Do not document a `seed=` parameter on either.
3. **No inferred return types.** The docs say `workflow.random()` returns a `random.Random` instance; do not also claim it returns the seed, a `SystemRandom`, or any other type.
4. **No assumed defaults.** Don't write "default seed: workflow run ID" — the docs only say "seeded per Workflow Execution" without naming the seed source. If the reader needs to know, mark `<!-- VERIFY -->`.
5. **No conflating concept with interface.** The Temporal concept is "deterministic randomness via SDK-provided primitives that record results in Event History." The Python interface tokens are `workflow.random()` and `workflow.uuid4()`. Name them separately and don't claim the concept *is* either token.
6. **No flattening of subcommand groups.** There is no `workflow.random` group of subcommands; it is a single function. Do not invent member methods on it beyond what `random.Random` (Python stdlib) actually exposes.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not document `workflow.uuid4()` as returning a `str`.** The docs do not specify the return type. If you need to characterize it, write "use it in place of `uuid.uuid4()`" and link the API reference. Mark `<!-- VERIFY -->` if a concrete return type is needed.
- **Do not claim `workflow.random()` is the same instance across calls within a Workflow Execution.** The docs say "a deterministic `random.Random` instance seeded per Workflow Execution" — they do not say it is cached vs. constructed per call. Describe behavior at the observable level ("calls produce a deterministic sequence per execution"); mark `<!-- VERIFY -->` if instance identity matters.
- **Do not name a specific seed source.** The docs say "seeded per Workflow Execution"; they do not say "seeded by the Workflow ID" or "seeded by a server-provided value." Do not infer one. The user's brief mentioned "deterministic random seed data and callback methods from temporalio.workflow" — treat that as a hint about the topic surface, not as evidence of a specific seed source.
- **Do not invent additional `temporalio.workflow` callback methods related to randomness.** The only randomness-related members confirmed in the docs are `workflow.random()` and `workflow.uuid4()`. If the user's brief implied others, find them in the docs or do not document them.
- **Do not list `random.Random` methods that you have not verified are usable inside the sandbox.** The docs show `workflow.random().randint(1, 100)` — `randint` is grounded. If you list `random()`, `choice`, `shuffle`, `sample`, etc., either cite the docs or mark each `<!-- VERIFY -->`.
- **Do not claim the sandbox auto-substitutes the `random` module.** The docs say "Never use `random.random()` or other `random` module functions directly" — this implies the developer must avoid them, not that the sandbox silently rewrites them. Do not claim auto-substitution without evidence.
- **Do not introduce `workflow.unsafe.is_replaying` branching as a randomness pattern.** It is mentioned in the same docs section for a different purpose (replay detection for side effects in interceptors). Cross-reference it once; do not present it as a randomness API.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source (the linked `python.temporal.io` API page is acceptable to *cite* via the existing Markdown link in `basics.mdx`, but do not WebFetch — only restate what is already on the page in `basics.mdx`).
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

Never fabricate to fill a gap. An empty subsection with a VERIFY note is acceptable; a fabricated subsection is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

The docs prescribe: use `workflow.random()` instead of `random.*`, use `workflow.uuid4()` instead of `uuid.uuid4()`, and never branch on local randomness. Describe exactly that. Do not invent extra prescriptions like "always seed manually for tests," "wrap in a context manager," or "prefer `secrets` for cryptographic use" — none of these appear in the docs.

---

## 4. Execution

Use an **orchestrator + single subagent** shape, since there is only one new reference file plus a small SKILL.md edit.

### Step 1: Read this plan end-to-end

Do not start editing until you've read all sections, especially §8 (regression patterns) and §9 (known correct anchors).

### Step 2: Set up the workspace

Greenfield additions:

- Create `references/python/workflow-randomness.md`.
- Edit `SKILL.md` at the skill root to add a one-line pointer under "Additional Topics" / the language references list. Do not change `SKILL.md` frontmatter (`name`, `description`, `version`).

### Step 3: Author the reference file via a subagent

Spawn one subagent for `references/python/workflow-randomness.md`. Give it:

- **The single file it owns.** No cross-reading of sibling reference files (`determinism.md`, `gotchas.md`, `python.md`).
- **The docs paths** from §1:
  - `../documentation/docs/develop/python/workflows/basics.mdx`
  - `../documentation/docs/develop/python/workers/interceptors.mdx`
  - `../documentation/docs/encyclopedia/workflow/workflow-definition.mdx`
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before reporting done.
- **Instructions:** "You are writing `references/python/workflow-randomness.md`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Update SKILL.md (orchestrator)

After the subagent completes, the orchestrator edits `SKILL.md`:

- Add a one-line link to `references/python/workflow-randomness.md` under the "Additional Topics" section (the same area that lists `observability.md` and `advanced-features.md`), or under "Primary References" if it fits better — pick one location.
- Do not edit frontmatter. Do not change unrelated sections.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from the subagent report: for the one reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond what §1 permits as "inputs to the Intent table."
- Do not read the paired validation plan (none exists, but the rule stands).
- Do not create files outside `references/python/` and the skill root.
- Do not modify `references/python/determinism.md`, `references/python/gotchas.md`, or `references/python/python.md` — those are inputs only, not outputs. (If a later validation pass shows duplication, that's a separate cleanup task.)

---

## 5. Per-file execution order

Work in this order:

1. **`references/python/workflow-randomness.md`** — replay-safe randomness and UUIDs in Python workflows: what `workflow.random()` and `workflow.uuid4()` are, why direct `random.*`/`uuid.*` are forbidden, the interceptor-replay note, and a short pattern section showing the good/bad code from the docs. Ground truth: `docs/develop/python/workflows/basics.mdx` (primary, §"Random numbers and UUIDs" and §"Develop Workflow logic"), `docs/develop/python/workers/interceptors.mdx` (interceptor-replay caveat), `docs/encyclopedia/workflow/workflow-definition.mdx` (why-it-matters framing).
2. **`SKILL.md`** — **last**. Add a single pointer line; no other edits.

Why this order matters: the reference file is the only substantive deliverable; `SKILL.md` only routes readers to it, so it must be written after the reference's file path is final.

---

## 6. Per-file done criteria

`references/python/workflow-randomness.md` is done when:

1. Every API token (`workflow.random`, `workflow.uuid4`, `workflow.unsafe.is_replaying`, `random.Random`, `random.random`, `uuid.uuid4`) appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every claim has a citation comment with a `docs/...:line` pointer.
3. No `random.Random` method is documented as usable inside a workflow unless it (a) appears in the docs, or (b) is marked `<!-- VERIFY -->`.
4. The file does not introduce new tokens like `workflow.randint`, `workflow.choice`, `workflow.seed`, `workflow.random_seed`, etc.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

`SKILL.md` is done when the new pointer line is in place and nothing else is changed.

---

## 7. Deliverables

At the end of authoring, produce:

- **`references/python/workflow-randomness.md`** — the new reference file.
- **`SKILL.md`** — with one new pointer line.
- **`AUTHORING_LOG.md`** at the skill root: for the new file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- **A git-visible diff** — one commit covering the new file + SKILL.md edit, so review can proceed quickly.

Do not create files outside `references/python/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `workflow.random(seed=...)` or any argument to `workflow.random()` | `workflow.random()` (no args) | docs/develop/python/workflows/basics.mdx:202 |
| `workflow.randint(a, b)` as a top-level helper | `workflow.random().randint(a, b)` | docs/develop/python/workflows/basics.mdx:207 |
| `workflow.uuid()` or `workflow.uuid1()` | `workflow.uuid4()` | docs/develop/python/workflows/basics.mdx:203 |
| "The sandbox replaces `random.random()` with a deterministic version" | "Never use `random.random()` or other `random` module functions directly; use `workflow.random()` instead." | docs/develop/python/workflows/basics.mdx:202 |
| "`workflow.random()` is seeded by the Workflow ID" (or any specific seed source) | "a deterministic `random.Random` instance seeded per Workflow Execution" (do not name the seed source) | docs/develop/python/workflows/basics.mdx:202 |
| "Branch on `workflow.unsafe.is_replaying` to skip random calls during replay" | `workflow.unsafe.is_replaying` is for guarding side effects (e.g., metric emission), not for randomness; do not branch business logic on it | docs/develop/python/workflows/basics.mdx:223–230 |
| "Interceptors can use `random.random()` safely because they run outside the sandbox" | Workflow inbound/outbound interceptors execute during replay; they must use replay-safe APIs for randomness | docs/develop/python/workers/interceptors.mdx:41 |
| "`uuid.uuid4()` works inside workflows" | Use `workflow.uuid4()` instead of `uuid.uuid4()` | docs/develop/python/workflows/basics.mdx:203 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- `workflow.random()` returns a deterministic `random.Random` instance seeded per Workflow Execution (`docs/develop/python/workflows/basics.mdx:202`).
- `workflow.uuid4()` is the replay-safe replacement for `uuid.uuid4()` (`docs/develop/python/workflows/basics.mdx:203`).
- Documented good usage example: `value = workflow.random().randint(1, 100)` and `unique_id = workflow.uuid4()` (`docs/develop/python/workflows/basics.mdx:207–208`).
- Documented bad usage example: `import random; value = random.randint(1, 100)` inside a workflow (`docs/develop/python/workflows/basics.mdx:211–212`).
- Workflow logic must be deterministic; the constraints explicitly list "no randomness" (`docs/develop/python/workflows/basics.mdx:169–172`).
- The SDK provides replay-safe alternatives for common needs (logging, randomness, time, replay detection) (`docs/develop/python/workflows/basics.mdx:182`).
- Workflow inbound/outbound interceptors run during replay and must use replay-safe APIs for randomness and time (`docs/develop/python/workers/interceptors.mdx:41`).
- Intrinsic non-determinism: a Workflow Definition cannot have inline logic that branches on a local time setting or a random number (`docs/encyclopedia/workflow/workflow-definition.mdx:249`).
- Each Temporal SDK offers APIs for time, random numbers, and unreliable data; results are stored in Event History so re-execution issues the same Command sequence (`docs/encyclopedia/workflow/workflow-definition.mdx:262–263`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the existing file layout under `references/python/`. Do not introduce a new top-level skill, new `SKILL.md` frontmatter, or a new directory.
- **Do not expand scope.** This file is about randomness and UUIDs in Python workflows. Time (`workflow.now()`), logging, replay detection, sandbox passthrough, sandbox restrictions, and side effects are out of scope and live in sibling references (`references/python/determinism.md`, `references/python/determinism-protection.md`, `references/python/gotchas.md`). Cross-reference them; do not absorb them.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis (a one-page answer to "how do I get a random number in a Python workflow?") and framing, not re-publication of `basics.mdx`. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`).
- **Do not document non-Python SDKs.** The user's brief scopes this to Python. Other SDKs have their own equivalents (e.g., Go `workflow.SideEffect`, Rust `ctx.random_seed()`) and they are out of scope here.

## 11. Sibling handoff

This file sits alongside other Python references in the same skill:

- `references/python/determinism.md` — the broad "what is determinism / what is forbidden / how the sandbox helps" overview. Has a one-line table entry for `workflow.random()` and `workflow.uuid4()`.
- `references/python/determinism-protection.md` — sandbox internals, passthrough imports, `sandbox_unrestricted`. Does not currently mention randomness specifically.
- `references/python/gotchas.md` — anti-patterns. Currently mentions `asyncio.sleep` as a timer anti-pattern; does not yet have a randomness anti-pattern entry.
- `references/python/python.md` — top-level Python getting-started; lists `workflow.random()` in the "safe builtin alternatives" frame indirectly via the determinism.md link.

Handoff disciplines:

1. **From this file to siblings:** when introducing the concept of "why randomness is forbidden," link to `references/python/determinism.md` rather than re-explaining replay. When discussing sandbox enforcement of `random.*`, link to `references/python/determinism-protection.md`.
2. **From siblings to this file:** the orchestrator's `SKILL.md` edit makes this file discoverable. Do not edit sibling files in this task; leave their one-line entries alone — they're correct.
3. **Canonical citations stay in `docs/`.** When this file repeats a fact that also appears in a sibling, cite the docs file, not the sibling.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one. Likely VERIFY candidates for this topic: the exact seed source for `workflow.random()`, the return type of `workflow.uuid4()`, and whether `workflow.random()` returns the same `Random` instance across calls within one execution.
- If a whole subsection has no docs backing, delete the subsection and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (it was written from a point-in-time review), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
