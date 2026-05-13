# Skill Authoring Plan — `payload-validation`

**Mode:** greenfield

**Context:** The Temporal Service enforces hard size limits on payloads (2 MB per payload by default; 2 MB on Temporal Cloud) and on gRPC messages (4 MB per request). When Workers send oversized data to the server, the failure modes are subtle and depend on which SDK version is in use and where the oversized data originated (Workflow input, Activity input, Activity result, Workflow result). The Python SDK 1.23.0+ adds an eager local check that fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` before sending the oversized data, leaving the Workflow open for recovery; older SDKs and the Go SDK rely on server rejection, which can terminate Workflows or produce silent retry loops. This skill is for Go and Python developers who need to understand which size limits apply, how their SDK behaves when those limits are crossed, and what mitigations exist (claim check pattern via External Storage, batching, custom Payload Codecs). It sits alongside the existing `references/{go,python}/data-handling.md` files (which cover converters and encryption codecs) and `references/core/gotchas.md` (which lists payload size as a known gotcha).

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `payload-validation`:

- `docs/troubleshooting/blob-size-limit-error.mdx` — canonical reference for the 2 MB payload limit and 4 MB gRPC message limit, the specific error strings, and the SDK-version-dependent failure behavior (Python 1.23.0+ vs. all others).
- `docs/references/errors.mdx` — Workflow Task failure causes related to payload/memo size (e.g. `gRPC Message Too Large`, `Bad Schedule Activity Attributes`, `Bad Modify Workflow Properties Attributes`, `Bad Signal Input Size`).
- `docs/evaluate/temporal-cloud/limits.mdx` — Temporal Cloud's non-configurable limits (per-message gRPC, Transaction Payload size, Event History transaction size, identifier length).
- `docs/production-deployment/self-hosted-guide/defaults.mdx` — self-hosted defaults including the 256 KB warn threshold and 2 MB error threshold for blob size; the `DefaultTransactionSizeLimit` of 4 MB.
- `docs/references/dynamic-configuration.mdx` — server-side dynamic config keys: `limit.blobSize.warn` (default 512 KB), `limit.blobSize.error` (default 2 MB), `limit.historySize.warn`/`error`, `limit.historyCount.warn`/`error`.
- `docs/encyclopedia/data-conversion/external-storage.mdx` — claim check pattern, the default 256 KiB offload threshold, lifecycle/retention requirements, how External Storage fits in the data conversion pipeline.
- `docs/develop/python/best-practices/data-handling/external-storage.mdx` — Python-specific External Storage setup (`ExternalStorage(drivers=[...])`, `payload_size_threshold` parameter, S3 driver, custom `StorageDriver`).
- `docs/develop/go/best-practices/data-handling/external-storage.mdx` — Go-specific External Storage setup (`converter.ExternalStorage{Drivers: [...], PayloadSizeThreshold: ...}`, S3 driver, custom `StorageDriver` interface).
- `docs/develop/python/activities/basics.mdx` — Python Activity argument and return-value size statements (2 MB single argument, 4 MB gRPC total).
- `docs/develop/go/activities/basics.mdx` — Go Activity argument and return-value size statements (2 MB single argument, 4 MB gRPC total).
- `docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx` — Memo concept and the note that Memos should not store data critical to execution.

**Secondary (only if primary is silent):** None used. Memo-specific size validation and per-SDK Worker options for *eager* payload/memo validation (beyond Python 1.23.0+'s documented `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` behavior) are not covered in `documentation/`. If a fact about Worker-side memo validation cannot be confirmed in `documentation/`, leave a `<!-- VERIFY: ... -->` comment rather than guessing from API name shapes.

Prefer Read/Grep on a local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** any prior sketches, hand-written wiki pages, AI-generated drafts, or memory of how an "eager validation" feature "should" be configured. Treat all SDK option names (e.g. hypothetical `disable_eager_payload_check`, `MaxPayloadSize`, `MemoSizeLimit`) as guilty until grep-verified in `documentation/`.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "what is the exact Workflow Task failure cause Python 1.23.0+ raises when a payload exceeds the 2 MB limit?":

1. `Read ../documentation/docs/troubleshooting/blob-size-limit-error.mdx` §"Error behavior" (the `#payload-error-behavior` heading).
2. Transcribe only what appears in that file: `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, "The SDK fails the Workflow Task with cause ...", "The Workflow is not terminated and remains open".
3. Record the line number where you found it (line 46 in current file).

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` <!-- docs/troubleshooting/blob-size-limit-error.mdx:46 -->
```

Pick one convention (inline comment per claim) and use it consistently across the three reference files. Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `TEMPORAL_PAYLOAD_SIZE_LIMIT` from `--payload-size-limit`. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** Platform concepts (e.g. "blob size limit") and CLI/SDK tokens (e.g. `limit.blobSize.error`, `ErrBlobSizeExceedsLimit`) often have subtly different names. Document the interface token; name the concept separately with a pointer.
6. **No flattening of subcommand groups.** If the docs show a group with N subcommands, don't flatten to one command with a flag.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Don't conflate the 2 MB payload limit with the 4 MB gRPC message limit.** These are separate limits with different error codes and different failure modes. `blob-size-limit-error.mdx` treats them as two top-level sections; preserve that split. Per-payload = 2 MB. Per-request (all commands + their payloads) = 4 MB. (`docs/troubleshooting/blob-size-limit-error.mdx:24,84`)
- **Don't claim Worker SDKs eagerly validate by default for all versions.** The only documented eager local validation is Python SDK 1.23.0+ failing the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. "All other SDK versions" rely on server-side rejection with different (and worse) failure modes. (`docs/troubleshooting/blob-size-limit-error.mdx:46,49,106`)
- **Don't invent Worker options for memo-size validation.** The docs cover Memo as a concept (`docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx:167`) and reference "the size of the Memo or payload" in error guidance (`docs/references/errors.mdx:66`), but they do not document an SDK option named "max memo size" or similar. If you need to discuss memo size, treat it as subject to the same 2 MB/4 MB payload/gRPC limits and cite the error-reference page. Mark anything more specific `<!-- VERIFY -->`.
- **Don't invent SDK option names for "disable eager validation" or "max outbound payload size".** Neither `disable_eager_payload_check`, `MaxOutboundPayloadSize`, nor `PayloadSizeLimiter` appear in the docs. The documented Python 1.23.0+ behavior is described as the SDK's behavior, not as a configurable option.
- **Don't confuse the External Storage `payload_size_threshold` / `PayloadSizeThreshold` with the server-enforced 2 MB limit.** The threshold (default 256 KiB) is the SDK's *offload* threshold for the claim check pattern, not a validation limit. (`docs/encyclopedia/data-conversion/external-storage.mdx:124`, `docs/develop/python/best-practices/data-handling/external-storage.mdx:79`, `docs/develop/go/best-practices/data-handling/external-storage.mdx:83`)
- **Don't conflate the Go `PayloadSizeThreshold` value semantics with Python's.** In Go, the docs say `PayloadSizeThreshold: 1` externalizes all payloads regardless of size and `0` is interpreted as the default (256 KiB). In Python, the docs say `payload_size_threshold=0` externalizes all payloads. Cite the language-specific page; do not cross-apply.
- **Distinguish soft (warn) from hard (error) limits.** The server warns at 256 KB / 512 KB (the latter from `limit.blobSize.warn`) but only errors at 2 MB. Don't describe 256 KB as a "limit" without the "warn" qualifier. (`docs/production-deployment/self-hosted-guide/defaults.mdx:40-41`, `docs/references/dynamic-configuration.mdx:209-210`)
- **Cloud is non-configurable; self-hosted is configurable.** The 2 MB payload limit and 4 MB gRPC message limit on Temporal Cloud are non-configurable. Self-hosted users can change the blob size limit via `limit.blobSize.error` dynamic config. Always state which deployment you're describing. (`docs/evaluate/temporal-cloud/limits.mdx:228,236`, `docs/encyclopedia/data-conversion/external-storage.mdx:42-43`)
- **Don't promise that External Storage prevents all size errors.** External Storage is in Pre-Release (`docs/encyclopedia/data-conversion/external-storage.mdx:26`) and addresses the per-payload 2 MB limit, but does not fix the 4 MB gRPC message limit when caused by too many commands per Workflow Task (`docs/troubleshooting/blob-size-limit-error.mdx:127-135` recommends batching for that case).

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source. None are pre-approved for this topic. Do not WebFetch SDK source code or release notes — the local docs are the contract.
2. Note the ambiguity in a `<!-- VERIFY: ... -->` comment and leave the claim out of the prose. The most likely VERIFY area is **Worker-side eager memo-size validation** — if you cannot find a docs page that names a configurable option, write the section as "the 2 MB payload limit applies to memos as well; for proactive mitigation, keep memo bodies small" and add a VERIFY comment asking whether the Go/Python SDK exposes a dedicated memo-size check.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

Never fabricate to fill a gap. An empty section with a VERIFY note is acceptable; a fabricated section is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Where the docs describe what a thing does, you describe what that thing does. Where the docs don't prescribe a workflow, don't invent one. The "How to resolve" sections in `blob-size-limit-error.mdx` are the canonical mitigation list — claim check / External Storage and compression for payload limit; batching for gRPC message limit. Don't add untested mitigations.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end

Do not start editing until you've read all sections, especially §8 (regression patterns) and §9 (known correct anchors).

### Step 2: Set up the workspace

For greenfield: create three new reference files (paths in §5). Do not create new subdirectories; place files in the existing `references/core/`, `references/go/`, and `references/python/` directories. Update `SKILL.md` last to add the cross-references.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Update SKILL.md

After all reference-file subagents complete, the orchestrator (you) adds entries to `SKILL.md` under "Primary References" or "Additional Topics" pointing to the new files. Update only the cross-reference list; do not restructure the front matter or top-level framing.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports: for each reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond the existing sibling reference files (which exist for *different* topics — payload-validation has no prior version).
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.
- Do not modify `references/core/gotchas.md`, `references/{python,go}/data-handling.md`, or any other existing file beyond `SKILL.md`.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/core/payload-validation.md`** — language-agnostic explanation of the two size limits (2 MB per payload, 4 MB per gRPC message), the soft/hard warn-vs-error thresholds, what failure modes look like (the failure-cause enums and where they surface), and a pointer to External Storage as the canonical mitigation. Ground truth: `docs/troubleshooting/blob-size-limit-error.mdx`, `docs/references/errors.mdx`, `docs/evaluate/temporal-cloud/limits.mdx`, `docs/production-deployment/self-hosted-guide/defaults.mdx`, `docs/references/dynamic-configuration.mdx`, `docs/encyclopedia/data-conversion/external-storage.mdx` (overview only), `docs/encyclopedia/workflow/workflow-execution/workflow-execution.mdx` (memo concept).
2. **`references/go/payload-validation.md`** — Go-specific: how the Go SDK surfaces oversized-payload failures (server-side rejection, retry-loop symptoms), the documented Go option `PayloadSizeThreshold` (External Storage offload — clarify this is NOT a validation gate), full `converter.ExternalStorage{Drivers: ..., PayloadSizeThreshold: ...}` setup, and 2 MB / 4 MB cite from `docs/develop/go/activities/basics.mdx`. Ground truth: `docs/develop/go/best-practices/data-handling/external-storage.mdx`, `docs/develop/go/activities/basics.mdx`, `docs/troubleshooting/blob-size-limit-error.mdx` (cross-refs into the core file).
3. **`references/python/payload-validation.md`** — Python-specific: the SDK 1.23.0+ behavior (fails Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, leaves Workflow open), the documented Python option `payload_size_threshold` (External Storage offload — clarify this is NOT a validation gate), full `ExternalStorage(drivers=[...], payload_size_threshold=...)` setup, and 2 MB / 4 MB cite from `docs/develop/python/activities/basics.mdx`. Ground truth: `docs/develop/python/best-practices/data-handling/external-storage.mdx`, `docs/develop/python/activities/basics.mdx`, `docs/troubleshooting/blob-size-limit-error.mdx` (especially the SDK-version split at lines 46–49 and 106–108).
4. **`SKILL.md`** — **last**. Add two bullets under "Additional Topics" pointing to `references/core/payload-validation.md` and (per-language) `references/{your_language}/payload-validation.md`. Do not change the Overview, Core Architecture, History Replay, or Getting Started sections.

Why this order matters: the core file establishes the limits, the failure-cause enums, and the deployment-specific configurability story (Cloud non-configurable vs. self-hosted dynamic config). The Go and Python files inherit those facts and add SDK-specific surface (option names, code shape). SKILL.md only references files that already exist on disk.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, field name, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value (e.g. `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`, `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`) is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file's headings or tables.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- **A git-visible diff** — one commit per reference file, so review can proceed file-by-file. (In this CI run, a single commit is acceptable if the executor is operating in non-interactive mode.)

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| "2 MB gRPC limit" / "4 MB payload limit" (axes swapped) | "2 MB per-payload limit"; "4 MB per gRPC message limit" | docs/troubleshooting/blob-size-limit-error.mdx:24,84 |
| "Workers eagerly validate payloads against server limits" (without SDK version qualifier) | "Python SDK 1.23.0+ fails the Workflow Task locally with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`; all other SDK versions rely on server rejection" | docs/troubleshooting/blob-size-limit-error.mdx:46-56,106-123 |
| `payload_size_threshold` (Python) or `PayloadSizeThreshold` (Go) described as a "validation limit" | Described as the External Storage *offload* threshold (default 256 KiB) for the claim check pattern | docs/develop/python/best-practices/data-handling/external-storage.mdx:79; docs/develop/go/best-practices/data-handling/external-storage.mdx:83 |
| "256 KB payload limit" or "256 KiB hard limit" | 256 KB is a *warn* threshold on self-hosted (`Blob size exceeds limit.`); 256 KiB is the External Storage default *offload* threshold; the hard error limit is 2 MB | docs/production-deployment/self-hosted-guide/defaults.mdx:40-41; docs/encyclopedia/data-conversion/external-storage.mdx:124 |
| "Workflow is terminated when payload exceeds limit" (universal claim) | Behavior depends on SDK version and operation. Python 1.23.0+ leaves the Workflow open. Other SDKs: input → terminate; activity result → activity fails; workflow result → stuck retry loop | docs/troubleshooting/blob-size-limit-error.mdx:46-56 |
| `ErrBlobSizeExceedsLimit` written as an SDK-facing error | `ErrBlobSizeExceedsLimit: Blob data size exceeds limit.` is the *server-side* error message at the 2 MB threshold | docs/production-deployment/self-hosted-guide/defaults.mdx:41 |
| Claim that External Storage is generally available / stable | External Storage is in Pre-Release; APIs and config may change | docs/encyclopedia/data-conversion/external-storage.mdx:24-30 |
| "External Storage solves the 4 MB gRPC limit too" | External Storage addresses per-payload size, not per-message gRPC size from too many commands. Use batching for gRPC-message-size issues | docs/troubleshooting/blob-size-limit-error.mdx:127-135 |
| `WORKFLOW_TASK_FAILED_CAUSE_PAYLOAD_TOO_LARGE` (singular) | `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` (plural) | docs/troubleshooting/blob-size-limit-error.mdx:35,46,106 |
| Inventing memo-specific size options (e.g. `MaxMemoSize`, `memo_size_limit`) | Memos are subject to the same payload limits; cite the error-reference page for "size of the Memo or payload"; mark anything more specific `<!-- VERIFY -->` | docs/references/errors.mdx:49,66 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- The default per-payload size limit is 2 MB; Temporal Cloud fixes it at 2 MB and self-hosted defaults to 2 MB (configurable). (`docs/troubleshooting/blob-size-limit-error.mdx:26-28`, `docs/evaluate/temporal-cloud/limits.mdx:232-236`)
- The gRPC message size limit is 4 MB per request and applies to the full request including all payload data and command metadata. (`docs/troubleshooting/blob-size-limit-error.mdx:86-89`)
- Python SDK 1.23.0+ fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` and the Workflow remains open. (`docs/troubleshooting/blob-size-limit-error.mdx:46-47`)
- Python SDK 1.23.0+ for oversized gRPC messages fails the Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` (yes — the docs use the same cause name for the gRPC oversize case in Python 1.23.0+, while older SDKs surface `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`). (`docs/troubleshooting/blob-size-limit-error.mdx:99,106-108`)
- For non-Python-1.23.0+ SDKs, oversized inputs terminate the Workflow; oversized Activity results fail the Activity; oversized Workflow results cause a stuck retry loop. (`docs/troubleshooting/blob-size-limit-error.mdx:49-55`)
- For non-Python-1.23.0+ SDKs, oversized Activity gRPC messages cause the Activity to retry until `ScheduleToCloseTimeout` (or indefinitely if no timeout). The `ResourceExhausted` gRPC error only appears in Worker logs. (`docs/troubleshooting/blob-size-limit-error.mdx:118-123`)
- Self-hosted servers warn at 256 KB blob size and error at 2 MB. (`docs/production-deployment/self-hosted-guide/defaults.mdx:40-41`)
- Dynamic config keys: `limit.blobSize.warn` defaults to 512 KB; `limit.blobSize.error` defaults to 2 MB. (`docs/references/dynamic-configuration.mdx:209-210`)
- External Storage's default offload threshold is 256 KiB; Python uses `payload_size_threshold` (set to `0` to externalize all); Go uses `PayloadSizeThreshold` (set to `1` to externalize all; `0` means default). (`docs/develop/python/best-practices/data-handling/external-storage.mdx:79-81,195-209`, `docs/develop/go/best-practices/data-handling/external-storage.mdx:83-85,229-245`)
- External Storage is in Pre-Release; APIs and configuration may change. (`docs/encyclopedia/data-conversion/external-storage.mdx:24-30`)
- The canonical mitigation for the 2 MB payload limit is the claim check pattern (External Storage), with compression via a custom Payload Codec as a secondary option. (`docs/troubleshooting/blob-size-limit-error.mdx:59-82`)
- The canonical mitigation for the 4 MB gRPC message limit is batching — process Activities or Child Workflows in smaller groups within or across Workflow Tasks. (`docs/troubleshooting/blob-size-limit-error.mdx:127-133`)
- The Workflow Task failure cause `gRPC Message Too Large` corresponds to "Workflow Task response exceeds the gRPC message size limit of 4 MB. The Workflow Execution is automatically terminated because this is a non-recoverable error." (`docs/references/errors.mdx:195-202`)
- Several error-reference entries acknowledge memo-related size violations: `Bad Modify Workflow Properties Attributes` mentions "Adjust the size of the Memo or payload to fit within the system's limits." (`docs/references/errors.mdx:62-66`); `Bad Continue as New Attributes` mentions "If the payload or memo exceeded size limits, adjust the input size." (`docs/references/errors.mdx:43-49`)

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** Memo *querying* / Search Attribute design, Codec Server architecture, and Payload Converter authoring belong to other reference files (`references/{python,go}/data-handling.md`, `references/{python,go}/observability.md`). Don't pull those topics in.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis and framing, not re-publication. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`) unless the user asks.
- **Do not author TypeScript, Java, .NET, Ruby, PHP, or Rust variants of this file.** The user identified Go and Python as the in-scope SDKs. Other SDKs may have related behavior in `docs/develop/{lang}/activities/basics.mdx`, but they are out of scope for this skill.

## 11. Sibling handoff

This skill sits alongside:

- `references/{python,go}/data-handling.md` — covers Payload Converters, custom converters, and Payload Codec (encryption). Payload-validation defers all converter/codec authoring to these files; it only cites them as the place where compression-as-mitigation lives.
- `references/core/gotchas.md` and `references/{python,go}/gotchas.md` — list "large payloads" as a known gotcha. Payload-validation owns the depth; gotchas owns the pointer.
- `references/core/troubleshooting.md` and `references/core/error-reference.md` — own general failure-mode triage and the workflow-task failure-cause enumeration. Payload-validation owns only the size-specific failure causes and links out to error-reference for the broader list.

Handoff disciplines:

1. When this skill prescribes a command documented in a sibling, spell out the full invocation but cite the canonical docs file, not the sibling skill.
2. When a topic belongs to a sibling (e.g. how to author a `PayloadCodec` for compression), cross-reference it, don't absorb it.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one. Strong candidates for VERIFY in this skill: any Worker-side option that pre-validates memo size before upload; any per-language config flag for "fail fast on oversized payload" beyond the documented Python 1.23.0+ behavior.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
