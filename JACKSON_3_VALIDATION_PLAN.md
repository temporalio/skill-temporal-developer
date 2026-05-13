# Skill Validation Plan — `jackson 3` (scoped to draft/0017-jackson-3)

**Scope of validation.** The draft branch `draft/0017-jackson-3` introduces **no commits**; the work is uncommitted: modifications to `references/java/data-handling.md` and an untracked `JACKSON_3_AUTHORING_PLAN.md`. Per the validation template, the authoring plan is excluded from the validator's read set. Validation is therefore scoped to the *diff* against `main` in `references/java/data-handling.md` — the Jackson 3 opt-in section plus the supporting citations the diff adds to the surrounding "Jackson Integration" section and the final best-practices bullet.

The pre-existing prose around the diff is out of scope; only newly added/modified lines are validated.

**Reader:** AI validator agent. Two-phase workflow:

1. **Phase 1 — Fill this plan.** (done in this file)
2. **Phase 2 — Execute the filled plan.** Run the four-check protocol; produce a go/no-go report.

In this CI run, approval is automatic — proceed straight from Phase 1 into Phase 2 in the same session.

---

## 2. Source of truth

- Primary: `../documentation/docs/`, with the topic-relevant subtree:
  - `docs/develop/java/best-practices/converters-and-encryption.mdx` (Jackson + custom data converter authoritative reference)
  - `docs/develop/java/workflows/basics.mdx` (workflow input serializability)
  - `docs/develop/java/activities/basics.mdx` (activity input serializability)
- Secondary: `../pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json` — the planned-content metadata for this topic. Citations to this file appear in the diff with the form `<!-- pipeline/planned-content/…/info.json:N -->`. The validator treats this as a legitimate secondary source for the "Jackson 3 opt-in exists; Java-only; wire-compatible" framing claims, because that information is not yet in the docs clone.

Citations are confirmed by reading the cited line range and checking that the authored claim is substantively supported, not merely adjacent.

---

## 3. Four-check validation protocol

### Check 1: citation audit

For every inline citation comment in the authored diff:

1. Confirm the cited file exists under `../documentation/docs/` (or `../pipeline/planned-content/…` for the secondary tag).
2. Read the cited line range.
3. Confirm the authored claim is substantively supported by the cited text.

Citations to verify (extracted from the diff):

| # | Citation | Claim it supports |
|---|---|---|
| 1 | `docs/develop/java/best-practices/converters-and-encryption.mdx:227` | The `JacksonJsonPayloadConverter` symbol is the documented default Jackson integration. |
| 2 | `docs/develop/java/best-practices/converters-and-encryption.mdx:232` | A custom `ObjectMapper` is the documented way to extend the converter. |
| 3 | `docs/develop/java/best-practices/converters-and-encryption.mdx:227-235` | The documented default is the Jackson 2 `JacksonJsonPayloadConverter` with `ObjectMapper`. |
| 4 | `docs/develop/java/workflows/basics.mdx:150` | Workflow inputs must be serializable by the default Jackson JSON Payload Converter. |
| 5 | `docs/develop/java/activities/basics.mdx:75` | Activity inputs must be serializable by the default Jackson JSON Payload Converter. |
| 6 | `pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:3` (×2) | Jackson 3 opt-in is wire-compatible with Jackson 2. |
| 7 | `pipeline/planned-content/skill-temporal-developer/0017-jackson-3/info.json:4-6` | Jackson 3 opt-in is Java-SDK-only (other SDKs unaffected). |

**Pass criterion:** ≥ 98% of citations resolve cleanly (7/7 expected; one miss = 86%, below threshold).

### Check 2: reverse-grep audit

Extract factual tokens from the authored diff. Grep the docs clone (and, for `tools.jackson`/Java-SDK-version tokens, accept absence iff guarded by a `<!-- VERIFY: … -->` marker).

Patterns to extract for `jackson 3`:

- **Java type/class names**, regex `[A-Z][A-Za-z]+(?:Converter|Options|Mapper|Module|Codec|Stubs|Client|Factory)` — confirm each appears either in `docs/develop/java/best-practices/converters-and-encryption.mdx` or elsewhere in the cited Java docs subtree.
- **API surface tokens** (method names, package paths) such as `withPayloadConverterOverrides`, `setDataConverter`, `io.temporal.common.converter`, `WorkflowClientOptions`, `WorkerFactoryOptions` — grep the docs subtree.
- **Wire-format / encoding tokens** quoted in code or prose (e.g. `json/plain`, `binary/encrypted`, `encoding` metadata key) — grep the docs subtree.
- **Version / artifact tokens** — `Java SDK 1.35.0+`, `tools.jackson.*`, `tools.jackson` — these MUST either appear in docs OR sit inside a `<!-- VERIFY: … -->` block that flags them as not-yet-documented. Loose use outside a VERIFY block is a finding.
- **Citation-target file paths** — confirm the file paths cited (`converters-and-encryption.mdx`, `workflows/basics.mdx`, `activities/basics.mdx`, `info.json`) actually exist.

Absence means one of:

- Token is fabricated → **finding**.
- Token is real-but-undocumented inside a `<!-- VERIFY: … -->` → acceptable.
- Token is an ecosystem token → must be tagged or self-evidently ecosystem (e.g. `tools.jackson` is a Jackson 3 ecosystem token; acceptable inside a VERIFY block).

**Pass criterion:** zero unexplained grep-misses.

### Check 3: regression on known bugs

Any of these patterns appearing in the authored diff is a failure.

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
| A code example showing a fabricated Jackson 3 class name (e.g. `Jackson3JsonPayloadConverter`, `JacksonV3PayloadConverter`) used without a `<!-- VERIFY: … -->` guard | No code example for the opt-in surface until the docs catch up | `docs/develop/java/best-practices/converters-and-encryption.mdx` does not contain a Jackson 3 symbol |
| A specific Maven/Gradle coordinate for the Jackson 3 module asserted as fact | No coordinate until docs confirm; must sit inside a VERIFY guard | `docs/develop/java/best-practices/converters-and-encryption.mdx` does not mention Jackson 3 artifact coordinates |
| Assertion that Jackson 3 is the default / will replace Jackson 2 | Default stays Jackson 2; opt-in only | `pipeline/planned-content/.../info.json:3` describes opt-in semantics |

**Pass criterion:** zero hits against any regression pattern.

### Check 4: independent re-verification (sampling)

The diff is small (one file, ~25 added lines, 7 distinct citations). Sample size: **all 7 citations** rather than a randomized subset — at this volume, exhaustive coverage is cheaper than a sample.

For each:

1. Read *only* the authored claim (not the citation).
2. Open the cited doc/info.json *independently* and read the cited line range fresh.
3. Write down what the claim should be, given only the cited source.
4. Compare to the authored version. "Substantively different" = a reader following one would do something different than a reader following the other.

**Pass criterion:** ≥ 95% match (≥ 7/7; ≤ 1 miss = 6/7 ≈ 86%, below threshold → fail).

---

## 4. Execution shape

Single-session, single-orchestrator execution (the diff is too small to fan out to subagents).

1. Read this plan.
2. Read the diff and the authored file `references/java/data-handling.md`.
3. Run Check 1 — direct Reads against each cited source.
4. Run Check 2 — Grep tokens against `../documentation/docs/`.
5. Run Check 3 — grep regression patterns across the diff.
6. Run Check 4 — exhaustive per-citation re-read.
7. Write `VALIDATION_REPORT.md` per §5.

---

## 5. Deliverables

- **`VALIDATION_REPORT.md`** at `./VALIDATION_REPORT.md` with sections:
  - **Go/no-go** — one-line verdict per check, overall verdict.
  - **Check 1 findings** — unresolved citations, with file:line and the cited-vs-actual difference.
  - **Check 2 findings** — tokens not found in docs, grouped by reference file.
  - **Check 3 findings** — any regression-pattern hits, file:line, the wrong text.
  - **Check 4 findings** — sampled claims that diverged from docs, with both versions.
  - **Statistics** — citation count, grep-miss count, sample size, match rate.

Overall verdict rubric:

- **GO** — all four checks pass their thresholds.
- **RE-RUN AUTHORING** — Check 3 has any hit, Check 4 < 95%, or Check 1 < 98%.
- **MINOR FIXES** — Check 2 has ≤ 5 unexplained misses that look like typos.

---

## 6. Stop conditions

- No authored output to validate (no diff, no uncommitted changes) — abort. *(Not triggered: diff exists.)*
- Docs clone at `../documentation/` absent or empty — abort. *(Not triggered: clone present.)*
- > 30% of citations fail Check 1 — full re-authoring needed.
- Authoring added files outside the expected skill layout — flag as scope violation. *(`JACKSON_3_AUTHORING_PLAN.md` at repo root is meta-doc artifact from authoring, not part of the skill payload; mention but do not block on it.)*

End of plan.
