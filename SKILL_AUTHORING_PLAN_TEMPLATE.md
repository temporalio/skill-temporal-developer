# Skill Authoring Plan — `{{SKILL_NAME}}`

**Reader:** you are an AI agent. The user has told you to write a Temporal skill using this template. Your job has two phases:

1. **Phase 1 — Fill this plan.** Search the documentation clone, fill every `{{PLACEHOLDER}}`, resolve every `[CHOOSE: …]` fork, and delete any section marked optional that doesn't apply. Present the filled plan to the user for approval before proceeding.
2. **Phase 2 — Execute the filled plan.** Follow the plan you just produced to author the skill.

Do not start Phase 2 until the user approves the filled plan.

---

## How to fill the placeholders (Phase 1 instructions)

Work through these steps in order. Each step tells you how to derive the values for one or more placeholders below.

### Step A: Identify the topic

The user will name the topic (e.g. "nexus", "schedules", "operations"). If they haven't, ask. Record it as `{{SKILL_NAME}}`. The skill directory you're working in is `{{SKILL_ROOT}}`.

### Step B: Discover docs paths for §1

Search the local docs clone:

1. `find ../documentation/docs/ -iname "*<topic>*"` — find primary files.
2. Grep for the topic keyword across `docs/` — find secondary mentions.
3. Read the primary files to understand scope, subcommands, flags, enums, concepts.
4. Check `../` for sibling clones that might serve as secondary sources.

Fill the `docs/{{PATH}}` entries in §1 with specific file paths. Be specific — `docs/cli/workflow.mdx` not `docs/cli/`.

### Step C: Decide mode and fill §2

If a prior skill exists in this directory with files to rewrite, mode = **rewrite**. Read the existing files, identify what scaffolding is sound (section structure, framing, decision tables) vs. what body facts are untrusted. Fill §2.

If no prior skill exists, mode = **greenfield**. Delete §2 entirely.

### Step D: Fill the grep-first example in §3.1

Pick one concrete factual question from this topic (e.g. "what flags does `temporal schedule create` take?"). Fill `{{EXAMPLE_QUESTION}}`, `{{EXAMPLE_PATH}}`, `{{EXAMPLE_SECTION}}`, and `{{EXAMPLE_CLAIM}}` in §3.1 and §3.2.

### Step E: Decide on source-category tagging in §3.2

If the topic spans sources beyond the Temporal docs (Go stdlib, gRPC spec, tool man pages), uncomment the optional source-category tagging subsection. If it lives entirely within Temporal docs, delete it.

### Step F: Fill topic-specific anti-fabrication rules in §3.4

Read the docs files you found. For each category of factual token, note patterns an AI is likely to get wrong. Write concrete rules. If this is greenfield and you can't yet identify traps, write your best guesses and note that §8 will grow during validation.

### Step G: Design the reference-file layout for §5

Based on docs structure, decide how to decompose the skill into reference files under `references/`. Follow sibling skill conventions — check `../skill-temporal-cli/` and `../skill-temporal-triage/` for the standard layout (SKILL.md at root, reference files under `references/` or `references/core/`). Match the SKILL.md frontmatter schema.

Order files so shared concepts come first, recipes/playbooks last, SKILL.md always last. Fill §5.

### Step H: Build §8 regression table and §9 anchors

- **Regression table (§8):** For rewrite mode, review existing files and cross-check against docs — every wrong pattern goes in the table. For greenfield, the table may start empty.
- **Anchors (§9):** Pick 5–15 verified facts from the docs with line numbers.

### Step I: Check for sibling handoff

`ls ../skill-temporal-*/`. If the topic touches concepts in a sibling skill, uncomment the optional §11 and fill the handoff rules.

---

<!-- ═══════════════════════════════════════════════════════
     PLAN BODY — everything below is what the executing
     agent follows in Phase 2 (after placeholders are filled)
     ═══════════════════════════════════════════════════════ -->

**Mode:** [CHOOSE: greenfield | rewrite]

**Context:** {{ONE-PARAGRAPH CONTEXT. For greenfield: why this skill, what topic, what audience, what sibling skills exist. For rewrite: the existing skill was AI-generated without grounding and contains factual errors; your job is a grounded rewrite of the body, preserving scaffolding where it's sound.}}

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `{{SKILL_NAME}}`:

- `docs/{{PATH_1}}` — {{ONE-LINE DESCRIPTION}}.
- `docs/{{PATH_2}}` — {{…}}.
- `docs/{{PATH_3}}` — {{…}}.

**Secondary (only if primary is silent):** {{LIST UPSTREAM SOURCES IF ANY. Omit if topic lives entirely in `documentation/`.}}

Prefer Read/Grep on a local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** {{FOR REWRITE: the existing files for factual claims — treat as outline only. FOR GREENFIELD: any prior sketches or wiki pages — treat as inputs to the Intent table, not as ground truth.}}

---

## 2. Preserve vs. rewrite

<!-- Delete this entire section for greenfield mode. -->

### Preserve (conceptual scaffolding that was good)

- {{BULLET each piece of structure worth keeping.}}

### Rewrite (treat as untrusted)

- Every command string, flag name, flag value, enum, env var, endpoint, port, file path, and example in every reference file.
- {{ADD topic-specific items that are known-untrusted.}}

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "{{EXAMPLE_QUESTION}}":

1. `Read ../documentation/docs/{{EXAMPLE_PATH}}` §{{EXAMPLE_SECTION}}.
2. Transcribe only what appears in that file.
3. Record the line number where you found it.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`{{EXAMPLE_CLAIM}}` <!-- docs/{{PATH}}:{{LINE}} -->
```

Pick one convention (inline comment per claim *or* `<!-- Sources: … -->` footer per section) and use it consistently. Keep citations to local repo paths (no URLs).

<!-- OPTIONAL source-category tagging — keep only if the topic spans Temporal docs + ecosystem sources. Otherwise delete this block.

Tag each claim with its origin:

```markdown
`{{TEMPORAL_CLAIM}}` <!-- docs/{{PATH}}:{{LINE}} -->
`{{GO_CLAIM}}` <!-- go: crypto/x509 -->
`{{GRPC_CLAIM}}` <!-- grpc: canonical-status-codes -->
`{{TOOL_CLAIM}}` <!-- man: {{TOOL}}(1) -->
```

This is defensive: it surfaces when a claim is sourced from the wrong place.
end optional -->

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `TEMPORAL_{{X}}_{{Y}}_PATH` from `--{{x}}-{{y}}-path`. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** Platform concepts and CLI/SDK tokens often have subtly different names. Document the interface token; name the concept separately with a pointer.
6. **No flattening of subcommand groups.** If the docs show a group with N subcommands, don't flatten to one command with a flag.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- {{TOPIC-SPECIFIC TRAP 1}}
- {{TOPIC-SPECIFIC TRAP 2}}
- {{TOPIC-SPECIFIC TRAP 3}}

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source (upstream repo README, generator source file like `commands.yml`, SDK source).
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
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

For rewrite: work directly in `{{SKILL_ROOT}}`.
For greenfield: create the skill directory layout (`SKILL.md`, `references/` with files per §5).

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Author SKILL.md

After all reference-file subagents complete, write `SKILL.md` yourself (the orchestrator). Update the Intent table and framing to reflect verified content.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports: for each reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond what §2 tells you to keep.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/{{FILE_1}}.md`** — {{ONE-LINE TOPIC}}. Ground truth: `docs/{{PATH}}`.
2. **`references/{{FILE_2}}.md`** — {{…}}. Ground truth: `docs/{{PATH}}`.
3. **`references/{{FILE_3}}.md`** — {{…}}. Ground truth: `docs/{{PATH}}`.
4. {{…}}
5. **`references/{{RECIPES_FILE}}.md`** — end-to-end flows. Each step must already be grounded in earlier files; copy citations forward.
6. **`SKILL.md`** — **last**. Update the Intent decision table / top-level framing to reflect verified content; update install/setup commands from their canonical docs file.

Why this order matters: {{ONE OR TWO SENTENCES ON THE DEPENDENCY GRAPH.}}

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

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- **A git-visible diff** — one commit per reference file, so review can proceed file-by-file.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| {{WRONG_PATTERN_1}} | {{CORRECT_FORM}} | docs/{{PATH}}:{{LINE}} |
| {{WRONG_PATTERN_2}} | {{CORRECT_FORM}} | docs/{{PATH}}:{{LINE}} |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- {{FACT_1}} (`docs/{{PATH}}:{{LINE}}`).
- {{FACT_2}} (`docs/{{PATH}}:{{LINE}}`).
- {{FACT_3}} (`docs/{{PATH}}:{{LINE}}`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** The Out-of-scope section defines what belongs in sibling skills. Don't pull those topics in.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis and framing, not re-publication. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`) unless the user asks.

<!-- OPTIONAL sibling handoff — keep only if the skill sits in a family and prescribes commands/concepts documented elsewhere.

## 11. Sibling handoff

This skill sits alongside:

- `{{SIBLING_SKILL_1}}` — {{WHAT IT COVERS}}.
- `{{SIBLING_SKILL_2}}` — {{WHAT IT COVERS}}.

Handoff disciplines:

1. When this skill prescribes a command documented in a sibling, spell out the full invocation but cite the canonical docs file, not the sibling skill.
2. When a topic belongs to a sibling, cross-reference it, don't absorb it.
end optional -->

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
