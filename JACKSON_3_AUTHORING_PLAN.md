# Skill Authoring Plan — `jackson-3`

**Mode:** rewrite

**Context:** The existing `references/java/data-handling.md` covers `JacksonJsonPayloadConverter` and `ObjectMapper` customization but predates Java SDK 1.35.0's Jackson 3 opt-in path. The planned feature lets developers opt into Jackson 3 payload conversion through a new startup API while staying wire-compatible with Jackson 2 converters. This plan adds a Jackson-3 section to the existing data-handling reference (and updates the Best Practices list) without changing any other Java reference file. The Temporal documentation clone at `../documentation/` is currently silent on Jackson 3 specifics — only `JacksonJsonPayloadConverter` (the Jackson 2 form) is documented. The plan treats that gap as a `<!-- VERIFY -->` boundary: any new token (class name, builder method, package, dependency coordinates) gets a VERIFY marker rather than a fabricated identifier.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `jackson-3`:

- `docs/develop/java/best-practices/converters-and-encryption.mdx` — describes `JacksonJsonPayloadConverter`, `ObjectMapper` customization, `DefaultDataConverter.newDefaultInstance()`, and `withPayloadConverterOverrides` (Jackson 2 baseline). This is the canonical Jackson page; Jackson 3 is not present here yet.
- `docs/develop/java/workflows/basics.mdx` — states that Workflow inputs "should be serializable by the default Jackson JSON Payload Converter" (line 150). Confirms Jackson is the default JSON path.
- `docs/develop/java/activities/basics.mdx` — same statement for Activity inputs (line 75).
- `docs/encyclopedia/data-conversion/payload-converter.mdx` — defines Composite Data Converters and converter ordering (cross-SDK). Useful for explaining how a Jackson 3 converter slots into the default chain.

**Secondary (only if primary is silent):** none available locally. There is **no sibling clone** of `temporalio/sdk-java` under `../` in this workspace, so SDK-source verification of class/method names is not possible in this run. Use VERIFY markers instead of guessing.

Prefer Read/Grep on the local docs clone over WebFetch or `gh api`. Do not fabricate token names from the topic description.

**Never trust:**

- The existing prose in `references/java/data-handling.md` for Jackson 3 — the file predates the feature and any "Jackson 3" content there (currently none) would be AI-fabricated.
- The one-line topic description in `pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json` — it confirms the feature exists and is wire-compatible, but says nothing about the actual API surface.

---

## 2. Preserve vs. rewrite

### Preserve (conceptual scaffolding that was good)

- The overall section ordering of `references/java/data-handling.md` (Overview → Default Data Converter → Jackson Integration → Custom Data Converter → Composition → Protobuf → Payload Encryption → Search Attributes → Memo → Deterministic APIs → Best Practices).
- The `DefaultDataConverter` chain enumeration in the "Default Data Converter" section — it accurately reflects what `converters-and-encryption.mdx` and `payload-converter.mdx` describe.
- The existing Jackson 2 example (`new JacksonJsonPayloadConverter(mapper)` + `withPayloadConverterOverrides`) — that token is verbatim in `docs/develop/java/best-practices/converters-and-encryption.mdx:227–235`.
- The Best Practices list at the bottom; we will append one new item for Jackson 3 opt-in.

### Rewrite (treat as untrusted)

- Any new content describing Jackson 3 must not invent class names, method names, builder names, Maven coordinates, or package paths. Each must either be cited from docs or marked `<!-- VERIFY -->`.
- Do not introduce import statements for `tools.jackson.*`, `com.fasterxml.jackson.*` v3, or `JacksonJson3PayloadConverter` unless those exact tokens appear in docs.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim. No exceptions.

### 3.1 The grep-first rule

Before writing any class name, method name, builder option, enum, or dependency coordinate, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what is the exact class name of the Jackson 3 payload converter?":

1. `Read ../documentation/docs/develop/java/best-practices/converters-and-encryption.mdx` end-to-end.
2. `Grep -i "jackson"` across `../documentation/docs/`.
3. If the token does not appear: do not write a guess. Add a `<!-- VERIFY: exact class name for Jackson 3 payload converter — not in docs as of this run -->` marker.

### 3.2 Citation/provenance format

Every new claim must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`JacksonJsonPayloadConverter` <!-- docs/develop/java/best-practices/converters-and-encryption.mdx:227 -->
```

Use the inline-comment-per-claim convention consistently within the new Jackson-3 section. Use local repo paths, no URLs.

### 3.3 Anti-fabrication rules (generic)

Refuse each pattern explicitly:

1. **No "probably exists" classes or builder methods.** If `JacksonJson3PayloadConverter` / `withJackson3` / `WorkerFactoryOptions.setJackson3(true)` is not in the docs, it does not exist for the purposes of this skill.
2. **No "probably accepts" enum values.** Only list enum values present verbatim.
3. **No "probably named" Maven artifacts.** Do not invent `io.temporal:temporal-jackson3` coordinates.
4. **No inferred package paths.** Do not derive `io.temporal.common.converter.jackson3.*` from existing `io.temporal.common.converter.*`.
5. **No conflating concept with interface.** "Jackson 3 opt-in" is the concept; the actual API token is unknown until docs catch up.
6. **No assumed defaults.** Do not write "Jackson 2 remains the default" or "Jackson 3 becomes the default in 1.36" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not invent the new startup API name.** The info.json hints at "a new startup API" but does not specify it. Mark it `<!-- VERIFY -->` and describe the *behavior* (opt-in at startup, wire-compatible with Jackson 2) without naming the method.
- **Do not invent migration semantics.** The wire-compatibility claim from info.json is the only confirmed semantic fact. Do not extrapolate to "old payloads will be decoded by Jackson 3 transparently" or "new payloads emit a different `encoding` metadata value" — these are guesses.
- **Do not invent Maven/Gradle coordinates** for a Jackson-3 module (e.g., `io.temporal:temporal-jackson3`). The docs list no such artifact.
- **Do not invent package names.** Do not write `com.fasterxml.jackson.*` *or* `tools.jackson.*` as the Jackson 3 root package — both are plausible-sounding but unverified here.
- **Do not invent a `WorkerFactoryOptions` / `WorkflowClientOptions` / `WorkflowServiceStubsOptions` setter** for Jackson 3. None is documented.
- **Preserve the Jackson 2 example verbatim.** The existing `new JacksonJsonPayloadConverter(mapper)` snippet must stay accurate; that token is at `docs/develop/java/best-practices/converters-and-encryption.mdx:227–235`.

### 3.5 When the docs are ambiguous or silent

The docs are silent on Jackson 3 in this run. Options in order of preference:

1. Describe behavior at the *concept* level (opt-in, wire-compatible) without naming unverified APIs.
2. Wrap each unknown token in `<!-- VERIFY: <specific question> — source of ambiguity: <what we'd need to know> -->`.
3. **Do not guess.** An empty subsection with a VERIFY marker is acceptable; a fabricated class name is not.

Never fabricate to fill a gap. A Jackson-3 section that says "this feature exists, the exact opt-in API is not yet documented — VERIFY when the docs ship" is more useful than one full of plausible-but-wrong class names.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Describe what the docs describe. Do not invent a Jackson-3 migration workflow ("step 1: bump dependency, step 2: call X, step 3: redeploy worker"). Recipes/playbooks must chain documented facts only.

---

## 4. Execution

Use a direct edit shape (single-file change). No orchestrator + subagent split is warranted because the scope is one targeted addition to one existing file.

### Step 1: Read this plan end-to-end

Read §3 (methodology), §8 (regression patterns), §9 (anchors) before editing.

### Step 2: Set up the workspace

Work directly in `.` (the skill root). No new files. No new directories.

### Step 3: Edit `references/java/data-handling.md`

- Append a new H2 section titled `## Jackson 3 Opt-In` immediately after the existing `## Jackson Integration` section. Section content describes:
  - The feature exists in Java SDK 1.35.0+: developers can opt into Jackson 3 for payload conversion at startup.
  - Wire-compatibility guarantee: Jackson 3 conversion produces payloads that Jackson 2 converters can decode (per info.json:3 — `<!-- planned-content/0017-jackson-3/info.json -->`).
  - The exact opt-in API method/class is `<!-- VERIFY -->`-marked; do not name a method.
  - Pointer to the Jackson 2 baseline above as the default for now.
  - Concrete code is omitted (a VERIFY note explains why). No fabricated snippet.
- Append one bullet to the existing "Best Practices" list at the bottom: `Prefer the documented Jackson 2 default until you have a specific reason to opt into Jackson 3; verify wire-compatibility in a staging environment.`
- Update the cross-reference inline comment on `JacksonJsonPayloadConverter` to point to the canonical line in `docs/develop/java/best-practices/converters-and-encryption.mdx` (currently line 227 / 231 / 234).

### Step 4: Update `references/java/java.md` description (only if needed)

The "Additional Resources" entry already reads `data-handling.md — Data converters, Jackson, payload encryption`. No change required unless the Jackson 3 section warrants surfacing in the top-level summary. Default: leave untouched (avoid scope creep per §10).

### Step 5: Skip `SKILL.md`

`SKILL.md` does not reference Jackson directly. No change.

### Step 6: Produce the log

After the edit, write a short `AUTHORING_LOG.md` at the skill root (or append if it already exists from prior runs) listing: file touched, docs files consulted, citation count, VERIFY markers raised, gap notes.

### What NOT to do

- Do not read or reference prior versions of the skill beyond §2's preserve list.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.
- Do not modify `references/java/spring-boot.md`, `references/java/patterns.md`, or any other reference file.
- Do not add `<!-- VERIFY -->` markers to Jackson 2 content that is already correctly cited.

---

## 5. Per-file execution order

Single file, single commit:

1. **`references/java/data-handling.md`** — add Jackson 3 opt-in subsection. Ground truth: `docs/develop/java/best-practices/converters-and-encryption.mdx`, `docs/develop/java/workflows/basics.mdx`, `docs/develop/java/activities/basics.mdx`.

No other reference files change. No `SKILL.md` change. No new file.

Why this order matters: the scope is one targeted insertion, so dependency order is trivial. The new section depends on the Jackson 2 section immediately above it for context (default converter chain, `withPayloadConverterOverrides`).

---

## 6. Per-file done criteria

`references/java/data-handling.md` is done when:

1. Every Jackson 2 token (`JacksonJsonPayloadConverter`, `ObjectMapper`, `DefaultDataConverter.newDefaultInstance()`, `withPayloadConverterOverrides`) appears verbatim in `docs/develop/java/best-practices/converters-and-encryption.mdx` and carries a citation comment.
2. The new Jackson 3 section contains **zero** invented class names, builder methods, package paths, or Maven coordinates. Any such token is replaced by a `<!-- VERIFY: ... -->` marker.
3. The section explicitly notes the docs gap (Temporal docs do not yet describe Jackson 3 specifics) and points readers to the SDK release notes / source for the exact API.
4. The wire-compatibility claim is attributed to `pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3`, not to a docs file.
5. A self-check Grep across the new section finds zero instances of the regression patterns in §8.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: file touched, docs files consulted, citation count, every `<!-- VERIFY -->` marker with its specific question.
- **One git commit** with a single-file diff on `references/java/data-handling.md`.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `JacksonJson3PayloadConverter` (invented class) | `<!-- VERIFY: Jackson 3 converter class name not in docs -->` | not in docs |
| `new JacksonJsonPayloadConverter(new JsonMapper())` (mixing Jackson 3 mapper with Jackson 2 converter) | Use the documented `ObjectMapper` form | docs/develop/java/best-practices/converters-and-encryption.mdx:232 |
| `import tools.jackson.databind.json.JsonMapper;` (Jackson 3 package guess) | `<!-- VERIFY: Jackson 3 package path -->` | not in docs |
| `import com.fasterxml.jackson.databind.json.JsonMapper;` (Jackson 2.13+ package, not Jackson 3) | `<!-- VERIFY: Jackson 3 package path -->` | not in docs |
| `WorkerFactoryOptions.newBuilder().setUseJackson3(true)` (invented builder) | `<!-- VERIFY: Jackson 3 opt-in API -->` | not in docs |
| `WorkflowClientOptions.newBuilder().setJackson3Enabled(true)` (invented builder) | `<!-- VERIFY: Jackson 3 opt-in API -->` | not in docs |
| `io.temporal:temporal-jackson3` (invented Maven coordinate) | `<!-- VERIFY: Jackson 3 dependency coordinates -->` | not in docs |
| "Jackson 3 is the default in SDK 1.35+" (invented default) | "Jackson 2 remains the documented default; Jackson 3 is opt-in" — both halves VERIFY-tagged for default-shift timing | not in docs |
| "Jackson 3 changes the wire format" (contradicts info.json) | "Jackson 3 conversion is wire-compatible with Jackson 2 converters" | pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- `JacksonJsonPayloadConverter` is the documented Jackson (v2) payload converter for the Java SDK (`docs/develop/java/best-practices/converters-and-encryption.mdx:227`, used at line 231, 234).
- The default Jackson converter uses `com.fasterxml.jackson.databind.ObjectMapper` (`docs/develop/java/best-practices/converters-and-encryption.mdx:232`).
- Custom mapper installation goes through `DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(...)` (`docs/develop/java/best-practices/converters-and-encryption.mdx:245–247`).
- Workflow inputs "should be serializable by the default Jackson JSON Payload Converter" (`docs/develop/java/workflows/basics.mdx:150`).
- Activity inputs use the same statement (`docs/develop/java/activities/basics.mdx:75`).
- The default `DefaultDataConverter` chain is Nil → ByteArray → ProtoJSON → Proto → JSON (Jackson) per the encyclopedia page (`docs/encyclopedia/data-conversion/payload-converter.mdx:38–46`).
- Jackson 3 opt-in is wire-compatible with Jackson 2 converters (`pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3`).
- Topic affects only the Java SDK (`pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:4–6`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep `SKILL.md` and file layout untouched.
- **Do not expand scope.** No new sections on data converter codecs, Spring Boot Jackson autowiring, or Kotlin module integration.
- **Do not paraphrase docs prose verbatim.** Cite, don't copy.
- **Do not write tests, CI, or tooling.** Documentation work only.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`) unless asked.
- **Do not modify any reference file other than `references/java/data-handling.md`.**

## 11. Sibling handoff

This skill sits alongside:

- `skill-temporal-cli` — covers Temporal CLI. Not relevant to Jackson 3.
- `skill-temporal-triage` — incident/triage skill. Not relevant to Jackson 3.

Handoff disciplines: none required for this topic — Jackson 3 lives entirely inside the Java SDK reference file.

---

## 12. If you get stuck

- If the Jackson 3 opt-in API surface is unclear and `<!-- VERIFY -->` markers would dominate a paragraph, **delete the paragraph and replace it with a single `<!-- VERIFY -->` note**. An absent claim is safer than a wrong one.
- If a whole subsection has no docs backing, delete it and note the deletion in `AUTHORING_LOG.md`.
- If the Temporal docs ship Jackson 3 content during this run, trust the docs over this plan and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
