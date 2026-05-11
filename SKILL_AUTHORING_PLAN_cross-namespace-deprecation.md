# Skill Authoring Plan — `cross-namespace-deprecation`

**Mode:** greenfield

**Context:** This adds a new topic to the existing `temporal-developer` skill covering the deprecation of cross-Namespace child Workflow APIs and Namespace fields in the Go and Java SDKs. The Temporal docs state that OSS-only `system.enableCrossNamespaceCommands` server configuration gates cross-Namespace commands (parent-child, SignalExternal, CancelExternal), that this configuration is disabled on Temporal Cloud, and that "Namespaces are isolated by default. The only way for Workflows in one Namespace to interact with Workflows in another Namespace is through [Temporal Nexus]". The skill must help a developer (a) recognize cross-Namespace patterns in Go and Java code that will stop working on Temporal Cloud or default-configured self-hosted servers, and (b) migrate to Nexus. Audience: Go/Java SDK users who already use child Workflows or external Workflow signal/cancel APIs. The temporal-developer skill is the only sibling skill in this workspace.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `cross-namespace-deprecation`:

- `docs/cloud/migrate/automated.mdx` — the only doc that names `system.enableCrossNamespaceCommands` and lists the affected command families (parent-child, SignalExternal, CancelExternal). Lines 419–422.
- `docs/evaluate/temporal-cloud/security.mdx` — Inter-Namespace communication section (line 74–78): Namespaces are isolated by default; Nexus is the only path between them.
- `docs/evaluate/development-production-features/temporal-nexus.mdx` — "Before Nexus" section (lines 48–55) documents that Child Workflows are "Limited to the same Namespace" and that cross-Namespace use "leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options". The "Should I use Nexus?" framing.
- `docs/encyclopedia/nexus/nexus.mdx` — Nexus architecture: caller and handler Workflows as siblings communicating across Namespace boundaries.
- `docs/develop/go/nexus/feature-guide.mdx` — Go SDK Nexus replacement APIs and cross-Namespace examples.
- `docs/develop/java/nexus/feature-guide.mdx` — Java SDK Nexus replacement APIs and cross-Namespace examples.
- `docs/develop/go/workflows/child-workflows.mdx` — Go `ChildWorkflowOptions` and `ExecuteChildWorkflow` as documented (does not document a Namespace field).
- `docs/develop/java/workflows/child-workflows.mdx` — Java `ChildWorkflowOptions` and `newChildWorkflowStub` (does not document a Namespace field).
- `docs/develop/go/workflows/message-passing.mdx` — Go `workflow.SignalExternalWorkflow` signature (does not document Namespace).
- `docs/develop/java/workflows/message-passing.mdx` — Java `Workflow.newExternalWorkflowStub` (does not document Namespace).
- `docs/references/commands.mdx` — `StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, `RequestCancelExternalWorkflowExecution` Command definitions.

**Secondary (only if primary is silent):** Go SDK and Java SDK source on disk are not in this workspace; the docs are the only ground truth available. For any SDK-token claim not in the primary docs, raise `<!-- VERIFY -->` rather than guess. Do **not** reach for WebFetch.

Prefer Read/Grep on the local docs clone over WebFetch or `gh api`.

**Never trust:** memory of cross-Namespace SDK API shapes. The docs do not show a `Namespace` field on Go `ChildWorkflowOptions` or Java `ChildWorkflowOptions`, do not show namespace parameters in `SignalExternalWorkflow` or `newExternalWorkflowStub` examples, and do not name a `ChildWorkflowFailureType.NAMESPACE_NOT_FOUND` enum or similar. Anything along those lines must be `<!-- VERIFY -->`.

---

## 2. Preserve vs. rewrite

(Greenfield — section deleted.)

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "What is the OSS server configuration that gates cross-Namespace commands?":

1. `Read ../documentation/docs/cloud/migrate/automated.mdx` §Limitations.
2. Confirm `system.enableCrossNamespaceCommands` appears verbatim at line 420 and 421.
3. Transcribe only the configuration name and the affected command families that appear in that text: "parent-child, SignalExternal, CancelExternal".
4. Record the line number in a citation comment.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:420 -->
```

Use **inline comments per claim** (not section footers). Keep citations to local repo paths relative to `../documentation/` (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative source.
4. **No inferred flag/field names.** Don't derive a `Namespace` field on `ChildWorkflowOptions` from server-side command names — name-shape plausibility is not evidence.
5. **No conflating concept with interface.** "Cross-Namespace command" is a server concept; the SDK surface (`ExecuteChildWorkflow`, `SignalExternalWorkflow`, etc.) is the interface. Document the interface tokens that *are* documented; for SDK fields not documented, raise `<!-- VERIFY -->`.
6. **No flattening of subcommand groups.** Three distinct Commands (`StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, `RequestCancelExternalWorkflowExecution`) — keep them distinct, don't merge them into a single bucket called "cross-Namespace commands" without naming each.
7. **No assumed defaults.** Don't write "default: disabled" for `system.enableCrossNamespaceCommands` unless the docs say so. The docs say it is "disabled on Temporal Cloud" and that it "must be disabled" prior to migration — they do not state the OSS default.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not invent SDK fields.** The docs `develop/go/workflows/child-workflows.mdx` and `develop/java/workflows/child-workflows.mdx` examples do not show a Namespace field on `ChildWorkflowOptions`. Do **not** write `workflow.ChildWorkflowOptions{Namespace: "..."}` or `ChildWorkflowOptions.newBuilder().setNamespace(...)` as if it were documented. If you need to reference such a field, mark it `<!-- VERIFY: docs/develop/<lang>/workflows/child-workflows.mdx does not document a Namespace field on ChildWorkflowOptions; consult the Go/Java SDK source if needed -->`.
- **Do not invent error strings.** "Cross-Namespace command disabled" or "namespace not found" style error messages must come from a docs file. The docs that exist (`docs/references/errors.mdx`) cover `BadRequestCancelExternalWorkflowExecutionAttributes` and `BadSignalExternalWorkflowExecutionAttributes` but say nothing about cross-Namespace gating errors. If you describe runtime behavior, attribute it explicitly to `docs/cloud/migrate/automated.mdx:419–422`.
- **Do not over-scope the server configuration.** The docs name exactly one configuration: `system.enableCrossNamespaceCommands`. Don't add sibling dynamic-config keys.
- **Do not claim the Java `Workflow.newExternalWorkflowStub` accepts a Namespace.** The documented example takes a `Class` and a `WorkflowExecution` (`docs/develop/java/workflows/message-passing.mdx:287`). No Namespace parameter is shown.
- **Do not claim `workflow.SignalExternalWorkflow` accepts a Namespace.** The documented example in Go (`docs/develop/go/workflows/message-passing.mdx:295`) is `workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal)` — the third arg is the run ID (empty string for current), not a Namespace.
- **Do not claim Nexus replaces all cross-Namespace use cases identically.** The docs frame Nexus as a "clean service contract between caller and handler" (`docs/evaluate/development-production-features/temporal-nexus.mdx:55`); it is a different programming model, not a drop-in replacement. Recipes must walk through the Nexus model (Service, Endpoint, Operation) per the Nexus feature-guide files.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check whether the Nexus feature-guide for the relevant SDK clarifies the API shape.
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
3. Do **not** guess. The docs say nothing about SDK fields named `Namespace` on `ChildWorkflowOptions` — so this skill must describe the deprecation conceptually (server-side gating, Cloud-disabled, migrate to Nexus) without fabricating SDK field names.

Never fabricate to fill a gap. An empty section with a VERIFY note is acceptable; a fabricated section is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

The docs prescribe one migration path — Nexus — and one server-side gate — `system.enableCrossNamespaceCommands`. Recipes chain those documented facts; do not invent intermediate "compatibility shim" patterns the docs do not endorse.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end

Read all sections, especially §8 (regression patterns) and §9 (known correct anchors).

### Step 2: Set up the workspace

This is a greenfield addition to the existing `temporal-developer` skill. Create only these new files:

- `references/core/cross-namespace-deprecation.md`
- `references/go/cross-namespace-deprecation.md`
- `references/java/cross-namespace-deprecation.md`
- `AUTHORING_LOG.md` (top-level, summarizing the run)

Then update `SKILL.md` to add a single pointer under "Additional Topics" (one line per language plus one core line, mirroring the existing convention). Do **not** restructure `SKILL.md`. Do **not** bump the version field — that is a release-time decision.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed and the existing `references/<lang>/go.md`/`java.md`/`patterns.md` for tone/style. Do NOT read sibling cross-namespace-deprecation reference files. Produce the file. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Update SKILL.md

After all reference-file subagents complete, edit `SKILL.md` to add references under "Additional Topics". Keep the diff minimal — three new bullets, no other changes.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports: for each reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill.
- Do not read the paired validation plan.
- Do not create files outside `references/{core,go,java}/` and the skill root (`AUTHORING_LOG.md`, modified `SKILL.md`).
- Do not modify `references/python/`, `references/typescript/`, `references/dotnet/` — the topic does not apply to those SDKs.
- Do not change the SKILL.md `version:` frontmatter.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/core/cross-namespace-deprecation.md`** — The cross-cutting concept: what cross-Namespace commands are, the `system.enableCrossNamespaceCommands` server config, Cloud's posture, and Nexus as the migration path. Ground truth: `docs/cloud/migrate/automated.mdx`, `docs/evaluate/temporal-cloud/security.mdx`, `docs/evaluate/development-production-features/temporal-nexus.mdx`, `docs/encyclopedia/nexus/nexus.mdx`, `docs/references/commands.mdx`.
2. **`references/go/cross-namespace-deprecation.md`** — Go-specific: what the documented APIs look like today (single-Namespace shape), where cross-Namespace usage would have lived historically, and how to migrate to Nexus using `docs/develop/go/nexus/feature-guide.mdx`. Ground truth: `docs/develop/go/workflows/child-workflows.mdx`, `docs/develop/go/workflows/message-passing.mdx`, `docs/develop/go/nexus/feature-guide.mdx`, `docs/develop/go/client/namespaces.mdx`.
3. **`references/java/cross-namespace-deprecation.md`** — Java-specific: same shape as the Go file, sourced from Java docs. Ground truth: `docs/develop/java/workflows/child-workflows.mdx`, `docs/develop/java/workflows/message-passing.mdx`, `docs/develop/java/nexus/feature-guide.mdx`, `docs/develop/java/client/namespaces.mdx`.
4. **`SKILL.md`** — **last**. Add three pointer lines under "Additional Topics" (or a small new "Deprecations" subsection if cleaner — keep it tiny). Do not touch the version field, the feedback section, or unrelated framing.

Why this order matters: the core file establishes the vocabulary (`system.enableCrossNamespaceCommands`, "cross-Namespace commands", Nexus as the migration path) and grounds Cloud-vs-OSS behavior in the docs. The language files cite the core file for the concept and only document the language-specific surface, avoiding duplication. SKILL.md cites all three.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every server-config name, command name, SDK function name, and field name appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment pointing to a `docs/...` path with a line number.
3. Every enum/Command value (`StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, `RequestCancelExternalWorkflowExecution`) is traceable to `docs/references/commands.mdx`.
4. No SDK subcommand / field / enum appears that isn't in the relevant `docs/develop/<lang>/...` file.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.
6. The file recommends Nexus as the migration path with at least one concrete cite into `docs/develop/<lang>/nexus/feature-guide.mdx`.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- A modified `SKILL.md` with three new pointer lines.
- Three new reference files under `references/{core,go,java}/cross-namespace-deprecation.md`.
- No commit-per-file constraint (this is a single CI run); a single coherent set of new/modified files is fine.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `workflow.ChildWorkflowOptions{Namespace: "other-ns"}` shown as a documented API | Either omit (docs don't show this) or mark `<!-- VERIFY -->`; describe the deprecation conceptually as a server-side gate | docs/develop/go/workflows/child-workflows.mdx (no Namespace field shown) |
| `ChildWorkflowOptions.newBuilder().setNamespace(...)` shown as a documented Java API | Same — omit or `<!-- VERIFY -->` | docs/develop/java/workflows/child-workflows.mdx (no setNamespace shown) |
| Claiming the OSS default is disabled | Use docs phrasing: "disabled on Temporal Cloud", "must be disabled … prior to migration"; do not assert the OSS default | docs/cloud/migrate/automated.mdx:419–422 |
| Listing more than three cross-Namespace command families | List exactly the three the docs name: parent-child, SignalExternal, CancelExternal | docs/cloud/migrate/automated.mdx:419 |
| Suggesting Nexus is a "drop-in replacement" | Use the docs framing: "clean service contract between caller and handler" — a different programming model | docs/evaluate/development-production-features/temporal-nexus.mdx:55 |
| Saying child Workflows can target any Namespace | Use the docs framing: "Child Workflows … Limited to the same Namespace" | docs/evaluate/development-production-features/temporal-nexus.mdx:51 |
| Inventing a Nexus migration helper / shim API | Cite only what the Nexus feature-guides actually document | docs/develop/go/nexus/feature-guide.mdx, docs/develop/java/nexus/feature-guide.mdx |
| Using the cross-Namespace `enableCrossNamespaceCommands` server config to describe Workflow Namespace deprecation (the `DeprecateNamespace` API) | These are unrelated — `DeprecateNamespace` deprecates a whole Namespace; `system.enableCrossNamespaceCommands` gates inter-Namespace Commands | docs/develop/java/client/namespaces.mdx:147 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- "OSS supports cross-Namespace commands (e.g., parent-child, SignalExternal, CancelExternal) through the `system.enableCrossNamespaceCommands` configuration." (`docs/cloud/migrate/automated.mdx:419–420`).
- "This configuration is disabled on Temporal Cloud." (`docs/cloud/migrate/automated.mdx:420`).
- "The `system.enableCrossNamespaceCommands` configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration." (`docs/cloud/migrate/automated.mdx:421–422`).
- "Namespaces are isolated by default. The only way for Workflows in one Namespace to interact with Workflows in another Namespace is through Temporal Nexus, which provides controlled, secure cross-Namespace communication via Nexus Endpoints." (`docs/evaluate/temporal-cloud/security.mdx:76`).
- "**Child Workflows** - Limited to the same Namespace. Cross-Namespace use leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options." (`docs/evaluate/development-production-features/temporal-nexus.mdx:51`).
- Commands `StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, `RequestCancelExternalWorkflowExecution` are documented Worker Commands (`docs/references/commands.mdx:49`, `:58`, `:67`).
- Go: `workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal)` — third positional argument is the run ID, not a Namespace (`docs/develop/go/workflows/message-passing.mdx:295`).
- Java: `Workflow.newExternalWorkflowStub(OtherWorkflow.class, otherWorkflowID)` — takes a Class and a WorkflowExecution; no Namespace parameter (`docs/develop/java/workflows/message-passing.mdx:287, 291`).
- Go Nexus: `docs/develop/go/nexus/feature-guide.mdx` documents Nexus Service, Endpoint, and Operation as the cross-Namespace surface for Go.
- Java Nexus: `docs/develop/java/nexus/feature-guide.mdx` documents the equivalent for Java.
- Nexus Cloud framing: "Caller and handler Workflows are siblings that communicate across Namespace boundaries." (`docs/encyclopedia/nexus/nexus.mdx:43`).
- `DeprecateNamespace` is unrelated: it puts a Namespace into a `DEPRECATED` state preventing *new* Workflows on that Namespace (`docs/develop/java/client/namespaces.mdx:147`). Do not confuse with `system.enableCrossNamespaceCommands`.

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as is.
- **Do not expand scope to Python / TypeScript / .NET.** The user identified Go and Java only; the docs framing about Namespace isolation is universal, but the SDK surfaces and migration recipes here are Go/Java.
- **Do not paraphrase docs prose verbatim.** Cite, don't copy. The skill's value is synthesis: "here is the deprecated pattern in your code; here is the Nexus migration".
- **Do not write tests, CI, or tooling.** Documentation work only.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`).
- **Do not write a full Nexus tutorial.** Point at the existing Nexus feature-guide docs; the skill's job is to flag the deprecation and route the developer to the migration path, not to re-teach Nexus.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
