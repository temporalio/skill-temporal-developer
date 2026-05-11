# Skill Validation Plan — `jackson-3`

**Scope of this validation.** The branch `draft/0017-jackson-3` introduces a single new topic — Java SDK opt-in support for Jackson 3.x — and touches only two files:

- `references/java/data-handling.md` — new "Jackson 3 (opt-in)" subsection inserted into the Jackson Integration section; renumbered Best Practices list to add one Jackson 3 item.
- `references/java/java.md` — one-line update to the `data-handling.md` index entry mentioning the Jackson 3 opt-in.

`{{SKILL_ROOT}}` = `.` (repo root); `{{SKILL_NAME}}` = `jackson-3`.

---

## 1. Independence requirement

This validator session has not read the authoring plan, the `AUTHORING_LOG.md`, or any prior conversation about authoring this change. The validation works only from the diff against `main` and from `../documentation/docs/` (plus secondary sources for ecosystem citations).

---

## 2. Source of truth

- **Primary (docs):** `../documentation/docs/`, with the only topic-relevant subtree being:
  - `docs/develop/java/best-practices/converters-and-encryption.mdx`
- **Secondary (ecosystem):** The Java SDK release notes for v1.34.0 — i.e. `https://github.com/temporalio/sdk-java/releases/tag/v1.34.0` (and the linked PR `temporalio/sdk-java#2783`). The authored file tags these claims with `<!-- sdk-java release notes: v1.34.0 -->`.

Citations in the authored file must be followed and confirmed (right file, right line, right claim).

---

## 3. Four-check validation protocol

### Check 1: citation audit

Grep the diff for `<!-- ... -->` citation comments. Two citation-comment forms appear:

- `<!-- docs/... -->` — must resolve to a file under `../documentation/docs/` and the cited line range must substantively support the claim.
- `<!-- sdk-java release notes: v1.34.0 -->` — must be substantively supported by the v1.34.0 release notes (fetched via WebFetch from `https://github.com/temporalio/sdk-java/releases/tag/v1.34.0`).

The diff also contains four `<!-- VERIFY: ... -->` markers; those are author-flagged uncertainty (not claims), but the body text adjacent to each VERIFY marker is still subject to the other checks.

**Pass criterion:** ≥ 98% of resolvable citations resolve cleanly. Any unresolved citation is a finding.

### Check 2: reverse-grep audit

The diff is small enough to enumerate factual tokens by inspection. Token classes for the Jackson 3 change:

- **Java identifier tokens (classes / methods):**
  - `JacksonJsonPayloadConverter`
  - `JacksonJsonPayloadConverter.setDefaultAsJackson3`
  - `withPayloadConverterOverrides`
  - `WorkflowClient.newInstance`
  - `ObjectMapper`
  - Regex: `[A-Z][A-Za-z0-9]*(?:\.[a-zA-Z][A-Za-z0-9]*)?`
- **Parameter names spelled in code fences:**
  - `jacksonCompatMode`
  - Lines matching `setDefaultAsJackson3\(` inside the code fence in `data-handling.md`.
- **Version strings / package coordinates:**
  - `Java SDK 1.34.0`, `v1.34.0`, `Java SDK 1.34`
  - `tools.jackson.*` (mentioned only inside a VERIFY marker — not asserted)
  - Regex: `\b1\.34(?:\.[0-9]+)?\b`
- **Issue / PR references:**
  - `temporalio/sdk-java#2783`
  - Regex: `temporalio/sdk-java#\d+`
- **Cited line numbers in `docs/...` comments:**
  - `converters-and-encryption.mdx:234`
  - `converters-and-encryption.mdx:239`

For each token, run Grep against:

1. `../documentation/docs/` for docs-class tokens (`JacksonJsonPayloadConverter`, `withPayloadConverterOverrides`, `WorkflowClient.newInstance`, `ObjectMapper`).
2. The cited `converters-and-encryption.mdx` lines for the precise-line-citation tokens.
3. The v1.34.0 release-notes page (via WebFetch) for `setDefaultAsJackson3`, `jacksonCompatMode`, `1.34.0`, `#2783`, "Jackson 3", multi-release JAR, wire-compatibility, and the "opt-in" framing.

Absence means one of:
- Token is fabricated — **finding**.
- Token is real ecosystem content but untagged — acceptable only if tagged with `<!-- sdk-java release notes: v1.34.0 -->` or similar.

**Pass criterion:** zero unexplained grep-misses.

### Check 3: regression on known bugs

**Universal patterns** (Temporal-skill-wide; expected to be absent from the diff):

| Wrong pattern | Should be |
|---|---|
| `--profile` as a flag in `temporal` command | `--env` |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | `TEMPORAL_TLS_CERT` |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | `TEMPORAL_TLS_KEY` |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | `TEMPORAL_TLS_CA` |
| `tcld service-account` | does not exist |
| `--output text` / `--output jsonl` | `table, json, card` only |
| `saas-api.tmprl.cloud:7233` | port 443 |

**Topic-specific patterns** for the Jackson 3 change:

| Wrong pattern | Should be | Source |
|---|---|---|
| Asserting Jackson 3 is now the default | Jackson 2 is still the default; Jackson 3 is opt-in | sdk-java v1.34.0 release notes |
| Pulling Jackson 3 in transitively / claiming the SDK adds the dep | Jackson 3.x is an optional dependency the user adds | sdk-java v1.34.0 release notes |
| Promising no replay-history risk silently | Wire compatibility *is* asserted; replay safety must be tied to that explicit guarantee | sdk-java v1.34.0 release notes |
| Naming a public `Jackson3JsonPayloadConverter` class | Entry point is `JacksonJsonPayloadConverter.setDefaultAsJackson3(...)` | sdk-java v1.34.0 release notes |
| Stating a minimum Java version for the opt-in | Release notes do not state a minimum; authored file explicitly disclaims | sdk-java v1.34.0 release notes |
| Treating `jacksonCompatMode` as a confirmed boolean / enum | Release notes show it as a placeholder identifier — type unspecified | sdk-java v1.34.0 release notes |

**Pass criterion:** zero hits against any regression pattern.

### Check 4: independent re-verification (sampling)

The change adds ≈ 13 substantive factual claims (1 file, small section). With a population that small, sampling is unnecessary — I will re-verify **every** non-VERIFY claim against the v1.34.0 release notes directly, plus the two `docs/...` line citations. Claims that fall *only* inside a `<!-- VERIFY: ... -->` marker are excluded (they are flagged uncertainty, not assertions).

The 13 claims to re-verify (one per author-asserted statement in the new section):

1. Java SDK 1.34.0 added optional Jackson 3.x support.
2. The mechanism is a multi-release JAR.
3. The default JSON converter remains Jackson 2.
4. Opt-in is via `JacksonJsonPayloadConverter.setDefaultAsJackson3(true, jacksonCompatMode)`.
5. The opt-in must be called once at process startup, before constructing any Temporal clients.
6. The opt-in's scope is global / process-wide.
7. The opt-in is not per-`WorkflowClient`.
8. Wire compatibility: Jackson 3-written payloads are readable by Jackson 2 and vice versa.
9. Mixed Jackson 2 / Jackson 3 worker fleets are supported without replay breakage.
10. Jackson 3.x is an optional dependency — not pulled in transitively.
11. The second argument controls Jackson-2 behavioral compatibility for the Jackson 3 converter.
12. Jackson 2 remains supported / users are not required to opt in.
13. PR reference is `temporalio/sdk-java#2783`.

Procedure for each:
1. Read the claim in the authored file.
2. WebFetch the release notes page (and PR if needed).
3. Write what the docs/release notes actually say.
4. Mark match / divergence / unverifiable.

**Pass criterion:** ≥ 95% match. Below 95% → re-author.

---

## 4. Execution shape

Single validator session (this one). I run all four checks in this session. Subagent delegation is unnecessary given the small diff (a single new ~30-line subsection plus a one-line index update).

---

## 5. Deliverables

Write `VALIDATION_REPORT.md` at the repo root with: go/no-go, per-check findings, statistics. Do not edit `references/`.

---

## 6. Stop conditions

- Docs clone empty / missing — abort. (Verified present.)
- Release notes URL unreachable via WebFetch — degrade Check 1/4 to "best effort" for ecosystem citations and flag in the report.
- Diff is empty / nothing to validate — abort.

---

End of filled plan.
