# Skill Authoring Plan — `spring-ai`

**Mode:** greenfield

**Context:** The Java `temporal-spring-ai` module is a new Public Preview integration that makes Spring AI agents — model calls, tools, vector stores, embeddings, MCP clients — run durably through Temporal. It is built on the Java SDK Plugin system and sits alongside the existing `temporal-spring-boot-starter`. Java developers using the existing `references/java/spring-boot.md` reference need a companion document that explains how to wire Spring AI into the same application, what each dependency unlocks, how the four tool dispatch paths (`@ActivityInterface`, Nexus stubs, `@SideEffectTool`, plain `@Tool`) differ, and what guardrails (media size, retryable exceptions, no streaming) apply. Audience: Java developers already familiar with Temporal basics and Spring Boot; we assume the reader can read `references/java/java.md` and `references/java/spring-boot.md` first. No prior skill version exists for this topic.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `spring-ai`:

- `docs/develop/java/integrations/spring-ai.mdx` — the canonical reference page for the integration: prerequisites, dependency setup, auto-registered Activities, `ActivityChatModel`, `TemporalChatClient`, tool dispatch (Activity / Nexus / `@SideEffectTool` / plain), Activity options, per-model overrides, provider-specific chat options, media size cap, vector store / embeddings / MCP plugins, resource links.
- `docs/develop/java/integrations/index.mdx` — Java integrations landing page; lists Spring AI under "AI integrations" with a link to the canonical SDK docs.
- `docs/develop/java/integrations/spring-boot.mdx` — companion Spring Boot integration (referenced as a required dependency by `temporal-spring-ai`).

**Secondary (only if primary is silent):** none. The Spring AI integration is documented entirely in `docs/develop/java/integrations/spring-ai.mdx`. Do not fall back to `github.com/temporalio/sdk-java/temporal-spring-ai/README.md` or Spring AI's own docs for factual claims; if a fact is not in the .mdx, leave it out and raise a `<!-- VERIFY -->` marker.

Prefer Read/Grep on the local clone over WebFetch.

**Never trust:** anything inferred from "Spring AI usually works like X" or "this is probably how Plugins compose." The integration is in Public Preview and the surface is small — every type, method, annotation, and default belongs to a verbatim string in `spring-ai.mdx`.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a class name, method name, annotation, dependency coordinate, system property, default value, or enum value, open `docs/develop/java/integrations/spring-ai.mdx` and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what does `ActivityChatModel.forDefault()` set as the default Activity timeouts and retry behavior?":

1. `Read ../documentation/docs/develop/java/integrations/spring-ai.mdx` §"Activity options and retry behavior".
2. Transcribe only what appears in that section (2-minute start-to-close timeout, 3 attempts, `org.springframework.ai.retry.NonTransientAiException` and `java.lang.IllegalArgumentException` classified as non-retryable).
3. Record the line number where you found it.

### 3.2 Citation/provenance format

Every claim about a name, default, or annotation must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`ActivityChatModel.forDefault()` <!-- docs/develop/java/integrations/spring-ai.mdx:89 -->
```

Convention: inline comment per claim for proper names, defaults, and annotations. For descriptive paragraphs that synthesize a section, a `<!-- Sources: docs/develop/java/integrations/spring-ai.mdx:§<section title> -->` footer is acceptable.

Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" classes/methods.** If a class, factory method, or plugin isn't in the docs, it doesn't exist.
2. **No "probably accepts" annotation parameters.** Only describe annotation usage shown in the docs.
3. **No "probably named" properties, beans, or system properties.** Transcribe the exact identifier.
4. **No inferred names.** Don't derive bean names, system property names, or class names from "what Spring usually calls X."
5. **No conflating concept with interface.** "Tool" the Spring AI concept and `@Tool` the annotation are distinct; cite which is which.
6. **No flattening of the four dispatch paths.** Activity stubs, Nexus stubs, `@SideEffectTool`, and plain `@Tool` classes are four separate paths — never collapse them.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so explicitly.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not invent dependency coordinates.** The Maven groupId is `io.temporal` and the artifactId is `temporal-spring-ai`; do not write `temporal-spring-ai-starter`, `spring-ai-temporal`, or any other variant.
- **Do not invent Spring AI starter artifacts.** The docs mention only `spring-ai-starter-model-openai` as an example, and `spring-ai-rag` / `spring-ai-mcp` as the dependencies that gate optional Activity registration. Do not list `spring-ai-starter-model-anthropic` or other model starters unless you find them in the source file.
- **Do not invent `ChatModel` bean names.** The docs show `"openai"` and `"anthropicChatModel"` as bean-name examples. Don't write `"openaiChatModel"`, `"chatModel"`, or other guesses.
- **Pin the registered Activity names exactly:** `ChatModelActivity`, `VectorStoreActivity`, `EmbeddingModelActivity`, `McpClientActivity`. Do not pluralize or rename them.
- **Pin the plugin class names exactly:** `SpringAiPlugin`, `VectorStorePlugin`, `EmbeddingModelPlugin`, `McpPlugin`. Do not write `SpringAIPlugin` (capitalisation) or `VectorStoreModelPlugin`.
- **Pin the key constant exactly:** `ChatModelTypes.DEFAULT_MODEL_NAME` resolves to the literal string `"default"`. Don't write `DEFAULT_MODEL` or `default-model`.
- **Pin the system property exactly:** `io.temporal.springai.maxMediaBytes` (no hyphens, no `_BYTES` suffix).
- **Pin the media cap exactly:** 1 MiB default, 2 MiB Temporal Server history-event limit. Use MiB (not MB) — the docs say MiB.
- **Pin the version floors exactly:** Java 17, Spring Boot 3.x, Spring AI 1.1.0, Temporal Java SDK 1.35.0. Don't bump or substitute.
- **Do not claim streaming support.** The docs note streaming responses are not currently supported.
- **Do not invent retry-classification behavior.** Non-retryable defaults are exactly two classes: `org.springframework.ai.retry.NonTransientAiException` and `java.lang.IllegalArgumentException`. No others.
- **Do not invent `ActivityMcpClient` defaults.** Only documented fact: 30-second default timeout for the MCP Activity. Don't extrapolate other defaults.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Read the docs section again — most "ambiguities" come from skim-reading.
2. Note the ambiguity in a `<!-- VERIFY: <specific question> -->` comment and leave the claim out of the prose.
3. Do **not** guess. Do **not** synthesize from "this is how Spring AI probably works."

Never fabricate to fill a gap. An empty section with a VERIFY note is acceptable; a fabricated section is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Where the docs describe behavior, describe that behavior. Where the docs are silent (e.g., how to combine `@SideEffectTool` with `@ActivityInterface` on the same class — not documented), do not invent recommendations.

---

## 4. Execution

Single-author shape — this skill is one new reference file plus light edits to `SKILL.md` and `references/java/java.md`. No subagents required.

### Step 1: Read this plan end-to-end

Especially §3.4 (topic-specific anti-fabrication rules) and §8 (regression patterns).

### Step 2: Set up the workspace

Greenfield. Create `references/java/spring-ai.md`. No new directories.

### Step 3: Author `references/java/spring-ai.md`

Work through the source `docs/develop/java/integrations/spring-ai.mdx` section-by-section. For each fact written, add an inline citation comment. Stop and grep before writing any identifier.

### Step 4: Wire it into the skill index

- `references/java/java.md` — add a one-line bullet under "Reference Files" pointing at the new file, in alphabetical order alongside `spring-boot.md`.
- `SKILL.md` — the existing "Additional Topics" section mentions `ai-patterns.md` as "Currently Python only". Update this note to also point Java readers at `references/java/spring-ai.md`. Bump the `version` in frontmatter from `0.3.2` to `0.3.3` (semver patch: adding a reference file without restructuring).

### Step 5: Produce the log

Write `AUTHORING_LOG.md` listing docs files consulted, total citation count in the new reference, and any `<!-- VERIFY -->` markers raised.

### What NOT to do

- Do not read or reference any prior conversation.
- Do not create files outside `references/java/` and the skill root.
- Do not duplicate content already covered in `references/java/spring-boot.md` — link out instead.

---

## 5. Per-file execution order

1. **`references/java/spring-ai.md`** — the entire Spring AI integration reference. Ground truth: `docs/develop/java/integrations/spring-ai.mdx`.
2. **`references/java/java.md`** — add a single reference-list bullet.
3. **`SKILL.md`** — update Additional Topics note and bump version.

Why this order matters: the reference file is the source of truth for everything else; nothing depends on `java.md` or `SKILL.md` edits, but those edits depend on the new file existing.

---

## 6. Per-file done criteria

The reference file is done when:

1. Every class name, method name, annotation, system property, bean name, and default value appears verbatim in `docs/develop/java/integrations/spring-ai.mdx` (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every such token has a citation comment with file path and line number.
3. None of the regression patterns in §8 appear (run Grep over the finished file).
4. The four tool dispatch paths are documented as four — not flattened.
5. The 1 MiB media cap is described with the correct unit (MiB), the correct system property name, and the correct behavior on overflow (non-retryable `ApplicationFailure`).

---

## 7. Deliverables

- **`references/java/spring-ai.md`** — new file.
- **`references/java/java.md`** — one-line addition.
- **`SKILL.md`** — note + version bump.
- **`AUTHORING_LOG.md`** — at skill root: docs files consulted, citation count, any `<!-- VERIFY -->` markers.

Do not create any other files.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `temporal-spring-ai-starter` | `temporal-spring-ai` | docs/develop/java/integrations/spring-ai.mdx:50 |
| `SpringAIPlugin` (camelCase AI) | `SpringAiPlugin` | docs/develop/java/integrations/spring-ai.mdx:68 |
| 1 MB media cap | 1 MiB media cap | docs/develop/java/integrations/spring-ai.mdx:376 |
| `io.temporal.spring.ai.maxMediaBytes` | `io.temporal.springai.maxMediaBytes` | docs/develop/java/integrations/spring-ai.mdx:383 |
| Streaming responses supported | Streaming responses are NOT currently supported | docs/develop/java/integrations/spring-ai.mdx:134 |
| Java 11 / Spring Boot 2.x baseline | Java 17 / Spring Boot 3.x / Spring AI 1.1.0 / SDK 1.35.0 | docs/develop/java/integrations/spring-ai.mdx:39–44 |
| Treating `@SideEffectTool` and `@ActivityInterface` as equivalent | Four distinct dispatch paths: Activity stub, Nexus stub, `@SideEffectTool`, plain `@Tool` | docs/develop/java/integrations/spring-ai.mdx:138–260 |
| Default chat Activity start-to-close timeout 30s | 2-minute start-to-close timeout, 3 attempts | docs/develop/java/integrations/spring-ai.mdx:314 |
| `ChatModelTypes.DEFAULT` / `DEFAULT_MODEL` | `ChatModelTypes.DEFAULT_MODEL_NAME` (literal `"default"`) | docs/develop/java/integrations/spring-ai.mdx:325 |

This table is the input to the validation plan's regression check.

---

## 9. Known correct anchors

- The integration distributes as `io.temporal:temporal-spring-ai` and depends on `temporal-spring-boot-starter` plus a Spring AI model starter such as `spring-ai-starter-model-openai` (`docs/develop/java/integrations/spring-ai.mdx:46`, 50).
- Prerequisites: Java 17, Spring Boot 3.x, Spring AI 1.1.0, Temporal Java SDK 1.35.0 (`docs/develop/java/integrations/spring-ai.mdx:39–44`).
- `SpringAiPlugin` auto-registers `ChatModelActivity` with all Workers created by the Spring Boot integration when `temporal-spring-ai` is on the classpath (`docs/develop/java/integrations/spring-ai.mdx:68`).
- Optional Activities auto-register when their dependencies are present: `VectorStoreActivity` (`spring-ai-rag`), `EmbeddingModelActivity` (`spring-ai-rag`), `McpClientActivity` (`spring-ai-mcp`) (`docs/develop/java/integrations/spring-ai.mdx:70–74`).
- `ActivityChatModel.forDefault()` resolves to the default Spring AI `ChatModel` bean; `ActivityChatModel.forModel("openai")` targets a named bean (`docs/develop/java/integrations/spring-ai.mdx:130`).
- Default chat Activity options: 2-minute start-to-close timeout, 3 attempts, `org.springframework.ai.retry.NonTransientAiException` and `java.lang.IllegalArgumentException` are non-retryable (`docs/develop/java/integrations/spring-ai.mdx:314`).
- `ChatModelActivityOptions` bean keyed by model bean name, with `ChatModelTypes.DEFAULT_MODEL_NAME` (literal `"default"`) as global catch-all; typo'd keys fail plugin construction at startup (`docs/develop/java/integrations/spring-ai.mdx:325`, 343).
- `ActivityMcpClient.create()` / `create(ActivityOptions)`: 30-second default timeout (`docs/develop/java/integrations/spring-ai.mdx:345`).
- Provider-specific `ChatOptions` (e.g., `AnthropicChatOptions`, `OpenAiChatOptions`) pass through the Activity boundary via `ChatClient.defaultOptions(...)`, relying on the subclass's `copy()` override (`docs/develop/java/integrations/spring-ai.mdx:348–372`).
- Inline media cap: 1 MiB default; override via system property `io.temporal.springai.maxMediaBytes` (positive integer; `0` disables). 2 MiB Temporal Server history-event limit; overflow raises a non-retryable `ApplicationFailure` (`docs/develop/java/integrations/spring-ai.mdx:376–383`).
- Streaming responses are not currently supported (`docs/develop/java/integrations/spring-ai.mdx:134`).
- Four tool dispatch paths: `@ActivityInterface` + `@Tool` → Activity; Nexus service stub + `@Tool` → Nexus operation; `@SideEffectTool` class → `Workflow.sideEffect()`; plain class with `@Tool` → runs on the Workflow thread (`docs/develop/java/integrations/spring-ai.mdx:144–260`).
- Plugins can be registered explicitly: `new VectorStorePlugin(vectorStore)`, `new EmbeddingModelPlugin(embeddingModel)`, `new McpPlugin()` (`docs/develop/java/integrations/spring-ai.mdx:391–395`).

---

## 10. Non-goals

- **Not a Spring AI tutorial.** Do not explain Spring AI fundamentals; link to `https://docs.spring.io/spring-ai/reference/` for the framework itself, as the source page does.
- **Not a Spring Boot integration rewrite.** That topic lives in `references/java/spring-boot.md`; cross-reference, do not duplicate.
- **Not a Plugin system reference.** Link to `/develop/plugins-guide` (or the canonical local docs path if available) — do not absorb plugin-system content.
- **No new tests, CI, or tooling.** Documentation only.
- **No meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, etc.).

## 11. Sibling handoff

This skill's reference file sits alongside other Java references in `references/java/`:

- `references/java/java.md` — Java SDK basics; the new reference assumes the reader already knows interface/impl pattern and `Workflow.newActivityStub`.
- `references/java/spring-boot.md` — companion Spring Boot integration; the new reference will state it is required and link out.

Handoff disciplines:

1. When the new reference mentions `WorkflowClient` injection, `@WorkflowImpl`, `@ActivityImpl`, or auto-discovery, link to `references/java/spring-boot.md`, don't re-explain.
2. When the new reference mentions Activity options, retry policy, or `Workflow.sideEffect()`, link to the canonical Java docs (`/develop/java/activities/execution`, etc.) or to `references/java/error-handling.md` — don't restate the underlying semantics.

---

## 12. If you get stuck

- If a fact has no docs backing in `spring-ai.mdx`, delete it or mark `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- The integration is Public Preview; if the docs and this plan disagree, trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
