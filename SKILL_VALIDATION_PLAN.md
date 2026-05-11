# Skill Validation Plan — `payload-validation`

**Reader:** AI validator agent. This is the filled plan for validating the payload-validation skill addition on branch `draft/0013-payload-validation`. Phase 1 (filling) is complete; the CI run treats approval as automatic and proceeds directly into Phase 2 in the same session.

**Constraint:** validator must be a different session than the authoring session. This run satisfies that (no authoring artifacts read).

---

## Scope of validation

`{{SKILL_ROOT}}` = `.` (the repo at `skill-temporal-developer/`).

`{{SKILL_NAME}}` = payload-validation.

The work being validated is the uncommitted addition on `draft/0013-payload-validation`:

- Modified: `SKILL.md` — new top-level §"Payload Size Validation" listing the three new references.
- Added: `references/core/payload-validation.md`
- Added: `references/python/payload-validation.md`
- Added: `references/go/payload-validation.md`

(`git log main..HEAD` returns no commits — the diff lives in the working tree, matching `git status`.)

---

## 2. Source of truth

- Primary: `../documentation/docs/`, with topic-relevant subtrees:
  - `docs/troubleshooting/blob-size-limit-error.mdx` — the canonical troubleshooting page; source for limit values, error cause codes, per-SDK behavior matrix, mitigation list.
  - `docs/references/errors.mdx` — Workflow Task error catalog: `Bad Schedule Activity Attributes`, `Bad Modify Workflow Properties Attributes`, `Bad Continue as New Attributes`, `Bad Signal Input Size`, `gRPC Message Too Large`.
  - `docs/production-deployment/self-hosted-guide/defaults.mdx` — self-hosted defaults: gRPC 4 MB, `DefaultTransactionSizeLimit`, blob warn/error thresholds.
  - `docs/references/dynamic-configuration.mdx` — `limit.blobSize.warn`, `limit.blobSize.error`.
  - `docs/evaluate/temporal-cloud/limits.mdx` — Cloud non-configurable limits.
  - `docs/develop/python/best-practices/data-handling/external-storage.mdx` — `payload_size_threshold`, default 256 KiB, `=0` semantics.
  - `docs/develop/python/best-practices/data-handling/data-encryption.mdx` — `PayloadCodec` interface, snappy/cramjam example.
  - `docs/develop/go/best-practices/data-handling/external-storage.mdx` — `PayloadSizeThreshold`, default 256 KiB, `=1` and `=0` semantics, canonical snippet.
  - `docs/develop/go/best-practices/data-handling/data-encryption.mdx` — Go `PayloadCodec` example, `converter.NewCodecDataConverter` wiring.

All nine paths above were confirmed to exist under `../documentation/docs/`.

- Secondary sources: none. The authored files cite only `documentation/docs/…`. No `<!-- go: -->`, `<!-- grpc: -->`, `<!-- man: -->`, or `<!-- undocumented: -->` tags appear.

Citations in authored files use the form `<!-- documentation/docs/PATH:LINE -->` or `<!-- documentation/docs/PATH:START-END -->`.

---

## 3. Four-check validation protocol

### Check 1: citation audit

Mechanical. For every `<!-- documentation/docs/… -->` comment in `references/core/payload-validation.md`, `references/python/payload-validation.md`, `references/go/payload-validation.md`:

1. Confirm the cited file exists under `../documentation/docs/`.
2. Read the cited line (or line range).
3. Confirm the authored claim is substantively supported by the cited text.

**Pass criterion:** ≥ 98% of citations resolve cleanly.

### Check 2: reverse-grep audit

Token classes appearing in the authored files:

- **`WORKFLOW_TASK_FAILED_CAUSE_*` enum values**: regex `WORKFLOW_TASK_FAILED_CAUSE_[A-Z_]+`. For each, grep the docs subtree.
- **Quoted error / log strings**: each backtick-quoted string that looks like a literal error message (`TMPRL1103`, `BadScheduleActivityAttributes`, `ErrBlobSizeExceedsLimit`, `Blob size exceeds limit.`, `Complete result exceeds size limit`, `CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`, `Bad Schedule Activity Attributes`, `Bad Modify Workflow Properties Attributes`, `Bad Continue as New Attributes`, `Bad Signal Input Size`, `gRPC Message Too Large`, `ResourceExhausted`, `ScheduleToCloseTimeout`). Grep each verbatim against the docs.
- **API / config identifiers**: `payload_size_threshold`, `PayloadSizeThreshold`, `limit.blobSize.warn`, `limit.blobSize.error`, `DefaultTransactionSizeLimit`, `ExternalStorage`, `PayloadCodec`, `DataConverter`, `converter.NewCodecDataConverter`, `client.Options.DataConverter`, `cramjam`. Grep each against the docs.
- **Size values bound to constraints**: `2 MB`, `4 MB`, `256 KiB`, `256 KB`, `512 KB`, `1.23.0`. Confirm each appears in the cited docs locations next to the relevant constraint.

For each extracted token, run Grep against `../documentation/docs/`. Absence → fabrication suspect. Acceptable exceptions:

- Token is real but undocumented → only if file carries `<!-- undocumented: source = … -->` (none present in this skill).
- Token is an ecosystem token → only if tagged with its source category (none present in this skill).

**Pass criterion:** zero unexplained grep-misses.

### Check 3: regression on known bugs

**Universal patterns** (every Temporal skill):

| Wrong pattern | Should be |
|---|---|
| `--profile` flag in a `temporal` command | `--env` |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | `TEMPORAL_TLS_CERT` |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | `TEMPORAL_TLS_KEY` |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | `TEMPORAL_TLS_CA` |
| `tcld service-account` (entire command group) | absent |
| `--output text` / `--output jsonl` | `table, json, card` only |
| `saas-api.tmprl.cloud:7233` | port 443 |

**Topic-specific patterns** for payload validation:

| Wrong pattern | Should be | Source |
|---|---|---|
| Per-payload limit stated as anything other than 2 MB | 2 MB | docs/troubleshooting/blob-size-limit-error.mdx:26 |
| gRPC message limit stated as anything other than 4 MB | 4 MB | docs/troubleshooting/blob-size-limit-error.mdx:91, docs/production-deployment/self-hosted-guide/defaults.mdx:36 |
| Invented `WORKFLOW_TASK_FAILED_CAUSE_*` values beyond `PAYLOADS_TOO_LARGE`, `GRPC_MESSAGE_TOO_LARGE`, `BAD_UPDATE_WORKFLOW_EXECUTION_MESSAGE` (the three the authored files use) | only documented values | docs/troubleshooting/blob-size-limit-error.mdx:35,40,99 |
| Python `payload_size_threshold=0` claim other than "externalize all payloads" | "externalizes all payloads regardless of size" | docs/develop/python/best-practices/data-handling/external-storage.mdx:195-197 |
| Go `PayloadSizeThreshold=0` claim other than "default (256 KiB)" | "0 means default; 1 means externalize all" | docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 |
| Eager-fail attributed to any SDK other than Python 1.23.0+ | only Python 1.23.0+ | docs/troubleshooting/blob-size-limit-error.mdx:46 |
| Memo described with a separate size limit | memo subject to same per-blob constraints | docs/references/errors.mdx:60-66 |

No ecosystem-claim section — the skill avoids `x509:` / `tls:` / `openssl:` claims.

**Pass criterion:** zero hits.

### Check 4: independent re-verification (sampling)

For each of the three reference files, sample 10 claims (citations) at random:

- `references/core/payload-validation.md`
- `references/python/payload-validation.md`
- `references/go/payload-validation.md`

Total sample: 30 claims.

Selection rule: number all citations in each file in source order; use Nth-citation stride `N = floor(total / 10)` to spread the sample. Record sampled indices in the report.

For each sampled claim:

1. Read only the authored claim (not the citation).
2. Open the cited doc independently and read the relevant section fresh.
3. Write the claim you would have made given only the docs.
4. Compare. Substantively different = a reader following one would behave differently than a reader following the other.

**Pass criterion:** ≥ 95% match (≤ 1 divergence across the 30 samples; ≤ 2 leaves it borderline).

---

## 4. Execution shape

One orchestrator (this session). Parallelize where useful:

1. Phase 1 — fill this plan. **Done.**
2. Check 1 — three parallel subagents, one per reference file.
3. Check 2 — three parallel subagents, one per reference file (each delegated its own token extraction + grep against the relevant docs subtree).
4. Check 3 — single grep pass across all authored files (the wrong patterns are short and exhaustive).
5. Check 4 — three parallel subagents, one per reference file, each reading only the docs.
6. Write `VALIDATION_REPORT.md`.

Subagents read only authored files + docs. They do not read each other's output or `AUTHORING_LOG.md` (no such file in this skill).

---

## 5. Deliverables

`VALIDATION_REPORT.md` at the skill root with sections:

- Go/no-go verdict.
- Check 1 findings.
- Check 2 findings.
- Check 3 findings.
- Check 4 findings.
- Statistics (citation count, grep-miss count, sample size, match rate).

No edits to authored files.

Overall verdict rubric:

- **GO** — all four checks pass thresholds.
- **RE-RUN AUTHORING** — Check 3 has any hit, or Check 4 < 95%, or Check 1 < 98%.
- **MINOR FIXES** — Check 2 has ≤ 5 unexplained misses that look like typos.

---

## 6. Stop conditions

- Authored files missing → not applicable; files present.
- Docs clone empty → not applicable; all 9 cited docs exist.
- > 30% citations fail Check 1 → escalate.
- Files added outside expected layout (new `docs/` dirs, tutorials) → none observed; only `references/{core,python,go}/payload-validation.md` and `SKILL.md` change.

---

End of filled plan. Proceeding to Phase 2.
