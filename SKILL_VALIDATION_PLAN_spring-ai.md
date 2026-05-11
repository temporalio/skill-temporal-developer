# Skill Validation Plan — `spring-ai`

**Scope:** the work introduced by branch `draft/0018-spring-ai` against `main`:

- New: `references/java/spring-ai.md` (the Spring AI integration reference for the Java SDK).
- Modified: `SKILL.md` (version bump 0.3.2 → 0.3.3; one bullet pointing Java developers to the new reference).
- Modified: `references/java/java.md` (one bullet referencing the new file under "Reference Files").

`{{SKILL_ROOT}}` = `.` (this repo root).
`{{SKILL_NAME}}` = `spring-ai`.

The companion authoring plan `SKILL_AUTHORING_PLAN_spring-ai.md` is also present but is **not consulted** for validation.

---

## 1. Independence requirement

This validation is run by a fresh session. Authoring artifacts (`SKILL_AUTHORING_PLAN_spring-ai.md`, any `AUTHORING_LOG.md`, prior authoring conversation) are **not** read. Validation works only from:

- The authored files listed above.
- The docs clone at `../documentation/docs/`.

---

## 2. Source of truth

- Primary: `../documentation/docs/`, specifically:
  - `docs/develop/java/integrations/spring-ai.mdx` — the single canonical doc cited throughout `references/java/spring-ai.md`.
  - `docs/develop/java/integrations/spring-boot.mdx` — companion integration (referenced indirectly via the "see spring-boot.md" pointer; not a citation target).
- Secondary: none. The skill cites only Temporal documentation; there are no Go-stdlib, gRPC-spec, or man-page sources to chase. External links to spring.io and GitHub samples appear in prose but are not relied on as citation targets — the cited fact is always also in the local docs.

Do not trust citations as proof — follow each one and confirm the cited text supports the claim. Citations can be wrong in three ways: wrong file, wrong line, or correct line with a claim subtly different from what the line says. All three must be caught.

---

## 3. Four-check validation protocol

Run all four checks. The skill passes only if all four pass.

### Check 1: citation audit

Mechanical. For every inline citation comment in `references/java/spring-ai.md`:

1. Confirm the cited file exists at `../documentation/docs/develop/java/integrations/spring-ai.mdx`.
2. Read the cited line range.
3. Confirm the authored claim is substantively supported by the cited text — not merely adjacent to it.

There are 47 citation comments in `references/java/spring-ai.md` (37 `<!-- docs/...:N -->` inline tags plus 7 `<!-- Source: docs/...:A–B (samples-…) -->` code-block tags and 3 `<!-- Sources: docs/…:A–B -->` table tags — count from `grep -n '<!-- ' references/java/spring-ai.md`). Two trivially-modified files also need scanning: `SKILL.md` (one new bullet, no citation) and `references/java/java.md` (one new bullet, no citation). Those two are out of scope for Check 1 because they introduce no citations.

**Pass criterion:** ≥ 98% of citations resolve cleanly (so ≤ 1 unresolved is acceptable; 2+ is a finding). Any unresolved citation that materially misrepresents the docs is itself a finding regardless of the percentage.

**How to run:** grep for `<!-- docs/` and `<!-- Source` in `references/java/spring-ai.md`, extract path + line range, Read the docs at those lines, verify the claim above the citation. The single reference file makes per-file parallelism unnecessary; one focused pass is sufficient.

### Check 2: reverse-grep audit

Extract every factual token from the authored files, then grep `../documentation/docs/develop/java/integrations/spring-ai.mdx` (the only doc this skill is grounded in) for each. Anything not found is a fabrication suspect.

Patterns to extract for `spring-ai`:

- **Java class / type names** introduced by the integration: regex `\b(ActivityChatModel|TemporalChatClient|ChatModelActivity|ChatModelActivityOptions|ChatModelTypes|VectorStoreActivity|VectorStorePlugin|EmbeddingModelActivity|EmbeddingModelPlugin|McpClientActivity|McpPlugin|SpringAiPlugin|ActivityMcpClient|SideEffectTool|AnthropicChatOptions|OpenAiChatOptions|TemporalChatClient|ApplicationFailure)\b`. Each must appear in `spring-ai.mdx`.
- **Method names** quoted in code or backticks: regex `\b(forDefault|forModel|defaultActivityOptions|defaultTools|defaultSystem|defaultAdvisors|defaultOptions|sideEffect|create|copy)\b\(` — same expectation.
- **Maven coordinates / artifacts** in code fences: regex `\b(io\.temporal:temporal-spring-ai|io\.temporal:temporal-sdk|spring-ai-rag|spring-ai-mcp|spring-ai-starter-model-openai|temporal-spring-boot-starter)\b` — every coordinate must appear in `spring-ai.mdx`.
- **System property names** referenced in prose: regex `io\.temporal\.springai\.[A-Za-z]+` — must appear in `spring-ai.mdx`.
- **String-literal special keys** in tables / prose: e.g. `"default"`, `DEFAULT_MODEL_NAME` — confirm each appears next to the relevant feature in `spring-ai.mdx`.
- **Annotation names** in code / prose: regex `@(WorkflowInit|WorkflowInterface|WorkflowMethod|ActivityInterface|ActivityMethod|Tool|ToolParam|SideEffectTool|Bean)` — confirm each appears in `spring-ai.mdx` (or, for Temporal core annotations like `@ActivityInterface`/`@WorkflowMethod` that are intentionally common Temporal API tokens, that they are also a normal Temporal API token covered by the broader Temporal Java reference — these are acceptable without an `<!-- undocumented: -->` tag because they are core SDK identifiers documented elsewhere).
- **Numeric constants** quoted as defaults: `17`, `3.x`, `1.1.0`, `1.35.0`, `2 minutes`, `30 seconds`, `3 attempts`, `2 MiB`, `1 MiB`, `20` (`maxMessages`), `30` (timeout seconds in code) — for each, confirm the same value appears next to the same concept in `spring-ai.mdx`.

For each extracted token, run Grep against the docs file. Absence means one of:

- The token is fabricated — **finding**.
- The token is real but undocumented — acceptable only if the authored file explicitly marks it with `<!-- undocumented: source = … -->`. The current file contains no such markers, so all unexplained misses count.
- The token is a generic Temporal Java SDK identifier (e.g. `@ActivityInterface`, `Workflow.newActivityStub`) — acceptable if it also appears in the broader Java SDK references already in the repo. Note these in the report as "core SDK identifier, accepted" but do not count as findings.

**Pass criterion:** zero unexplained grep-misses against `spring-ai.mdx` for the categories above.

### Check 3: regression on known bugs

Any of these patterns appearing in `references/java/spring-ai.md`, the modified bullets in `SKILL.md`, or the modified bullet in `references/java/java.md` is a failure.

**Universal patterns (apply to every Temporal skill):**

| Wrong pattern | Should be |
|---|---|
| `--profile` as a flag in a `temporal` command | `--env` |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | `TEMPORAL_TLS_CERT` |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | `TEMPORAL_TLS_KEY` |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | `TEMPORAL_TLS_CA` |
| `tcld service-account` (entire command group) | does not exist — should be absent |
| `--output text` / `--output jsonl` | `table, json, card` only |
| `saas-api.tmprl.cloud:7233` | port 443 |

**Topic-specific patterns (Spring AI):**

| Wrong pattern | Should be | Source |
|---|---|---|
| `ActivityChatModel.create(…)` as the factory method (instead of `forDefault` / `forModel`) | `ActivityChatModel.forDefault()` / `ActivityChatModel.forModel(name)` | docs/develop/java/integrations/spring-ai.mdx:89, 130 |
| Claiming streaming chat responses are supported | "Streaming responses are not currently supported." | docs/develop/java/integrations/spring-ai.mdx:134 |
| Five (or other ≠4) tool dispatch paths | Exactly four: Activity stub, Nexus stub, `@SideEffectTool`, plain `@Tool` class | docs/develop/java/integrations/spring-ai.mdx:145, 187, 191, 260 |
| `DEFAULT_MODEL` / `"DEFAULT"` literal for the catch-all key | `ChatModelTypes.DEFAULT_MODEL_NAME` (literal `"default"`, lower-case) | docs/develop/java/integrations/spring-ai.mdx:325 |
| 2 MiB or other cap value for default media inline byte limit | **1 MiB** default cap; 2 MiB is the server history-event hard limit | docs/develop/java/integrations/spring-ai.mdx:376 |
| MCP default timeout other than 30 seconds | 30 seconds | docs/develop/java/integrations/spring-ai.mdx:345 |
| Java/Spring Boot/Spring AI/SDK min versions other than 17 / 3.x / 1.1.0 / 1.35.0 | 17 / 3.x / 1.1.0 / 1.35.0 | docs/develop/java/integrations/spring-ai.mdx:39–44 |
| Stating `spring-ai-rag` gates only one of vector store or embeddings | `spring-ai-rag` gates **both** `VectorStoreActivity` and `EmbeddingModelActivity` | docs/develop/java/integrations/spring-ai.mdx:72–73 |
| Statement that `@SideEffectTool` wraps in `Workflow.mutableSideEffect()` (or any other primitive) | wrapped in `Workflow.sideEffect()` | docs/develop/java/integrations/spring-ai.mdx:191 |
| Asserting `temporal-spring-ai` is GA | "Public Preview" | docs/develop/java/integrations/spring-ai.mdx:30 |

(No ecosystem-regression subsection — this skill makes no `x509:` / `tls:` / `openssl` / `nc` claims and no gRPC status-code claims.)

**Pass criterion:** zero hits against any regression pattern.

### Check 4: independent re-verification (sampling)

Pick **10 claims at random** from `references/java/spring-ai.md` (the only newly-authored content file; the two-bullet diffs in `SKILL.md` and `references/java/java.md` contain no substantive factual claims beyond a file pointer, so they are out of scope for sampling). For each:

1. Read *only* the claim in the authored file — not the citation.
2. Open `spring-ai.mdx` independently and read the relevant section fresh.
3. Write down what the correct claim should be, given only the docs.
4. Compare to the authored version.

"Substantively different" = a reader following one would do something different than a reader following the other. Typographical / stylistic differences do not count.

**Randomization:** number the 47 citation comments in document order (1..47). Sample positions 1, 6, 11, 16, 21, 26, 31, 36, 41, 46 (every fifth, starting at 1). Record the sampled positions and surrounding claim text in the report.

**Pass criterion:** ≥ 95% of sampled claims match (≥ 10 of 10 → pass; 1 mismatch → 90% → flag for second authoring pass).

---

## 4. Execution shape

One validator orchestrator agent (this session). The agent:

1. Reads this plan.
2. Reads the authored files in `.` (specifically `references/java/spring-ai.md`, plus the two-bullet diffs in `SKILL.md` and `references/java/java.md`).
3. Runs Check 1 directly — one reference file, no parallelism needed.
4. Runs Check 2 directly — same.
5. Runs Check 3 — single regex pass across the three affected files.
6. Runs Check 4 directly — single-file sample.
7. Produces the report per §5.

---

## 5. Deliverables

- **`VALIDATION_REPORT.md`** at `.` (skill root) with sections:
  - **Go/no-go** — one-line verdict per check, overall verdict.
  - **Check 1 findings** — unresolved citations, with file:line and the cited-vs-actual difference.
  - **Check 2 findings** — tokens not found in `spring-ai.mdx`, grouped by category.
  - **Check 3 findings** — any regression-pattern hits, file:line, the wrong text.
  - **Check 4 findings** — sampled claims that diverged from docs, with both versions.
  - **Statistics** — citation count, grep-miss count, sample size, match rate.
- Do *not* edit the authored files.

Overall verdict rubric:

- **GO** — all four checks pass their thresholds.
- **RE-RUN AUTHORING** — Check 3 has any hit, or Check 4 < 95%, or Check 1 < 98%.
- **MINOR FIXES** — Check 2 has ≤ 5 unexplained misses that look like typos or missing citation comments.

---

## 6. Stop conditions

Abort and escalate if:

- The single authored reference file is missing — already confirmed present.
- The docs clone at `../documentation/` is absent or empty — already confirmed populated.
- More than 30% of citations fail Check 1.
- The authoring added files outside the expected layout (this branch is clean on this point: it adds one reference file and a planning artifact, with no new docs subdirs or tutorials in the skill).

---

End of plan.
