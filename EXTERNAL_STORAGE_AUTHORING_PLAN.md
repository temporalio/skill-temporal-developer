# Skill Authoring Plan — `external-storage`

**Reader:** you are an AI agent. The user has told you to write a Temporal skill section using this template. CI run: approval is automatic. Fill the plan, then proceed directly into execution.

---

**Mode:** greenfield

**Context:** The `temporal-developer` skill currently has no dedicated reference on External Storage. External Storage is a Pre-Release feature in the Go and Python SDKs that offloads large payloads to an external store (such as Amazon S3) and passes a small reference token through Event History (the [claim check pattern](https://dataengineering.wiki/Concepts/Software+Engineering/Claim+Check+Pattern)). Audience: developers building Temporal applications in Go or Python who need to handle payloads near or above the 2 MB per-payload limit, or who want to migrate large-history Workflows to Temporal Cloud. The skill must cover: the conceptual model (where it sits in the data conversion pipeline, lifecycle/TTL), per-SDK configuration (Go and Python), the built-in S3 driver, custom driver implementation, multiple-driver registration for migration scenarios, concurrent upload/download behaviour, and how a Codec Server must be set up to handle External Storage references (`/download` endpoint, `?preserveStorageRefs=true`, `NewPayloadHTTPHandler`). Sibling files in `references/{go,python}/data-handling.md` already cover Data Converter and Payload Codec — this skill cross-references those instead of duplicating.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `external-storage`:

- `docs/encyclopedia/data-conversion/external-storage.mdx` — conceptual overview, claim check pattern, why-use scenarios, data conversion pipeline placement, storage drivers, key configuration settings, lifecycle/TTL guidance.
- `docs/develop/go/best-practices/data-handling/external-storage.mdx` — Go SDK setup with S3 driver, custom driver implementation (`StorageDriver` interface with `Name()`, `Type()`, `Store()`, `Retrieve()`), threshold configuration, multiple-driver registration with `StorageDriverSelector`.
- `docs/develop/python/best-practices/data-handling/external-storage.mdx` — Python SDK setup with S3 driver, custom driver implementation (`StorageDriver` abstract class with `name()`, `store()`, `retrieve()`), threshold configuration, multiple-driver registration with `driver_selector`.
- `docs/encyclopedia/data-conversion/codec-server.mdx` — Codec Server with External Storage section: `NewPayloadHTTPHandler`, `PayloadHTTPHandlerOptions`, the `/download` endpoint, `?preserveStorageRefs=true` query parameter, end-to-end encode-store-encode and decode-retrieve-decode pipeline.
- `docs/production-deployment/data-encryption.mdx` — Codec Server endpoint reference confirming `/download` retrieves and decodes payloads from External Storage.
- `docs/troubleshooting/blob-size-limit-error.mdx` — context for why payload size limits exist (2 MB default), pre-release stability notice for External Storage, Slack channel.
- `docs/develop/{go,python}/best-practices/data-handling/index.mdx` — Data Converter three-layer model (PayloadConverter / PayloadCodec / ExternalStorage) and where ExternalStorage sits.

**Secondary:** none required. Topic lives entirely within `documentation/`.

Prefer Read/Grep on the local docs clone over WebFetch.

**Never trust:** any prior memory or sketches — the feature is Pre-Release and "APIs and configuration may change before the stable release" per the docs. The docs as cloned are the only ground truth.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, struct field, enum, method name, type name, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what methods does a Go custom storage driver implement?":

1. `Read ../documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx` §"Implement the StorageDriver interface".
2. Transcribe only what appears in that file: `Name()`, `Type()`, `Store()`, `Retrieve()`.
3. Record line numbers where you found them (lines 185–195).

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`PayloadSizeThreshold` <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:84 -->
```

Use this convention consistently: one HTML comment per claim, placed immediately after the token (or at end of the sentence for sentence-scale claims). No URLs — local repo paths only.

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" methods/types.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list values present in the docs.
3. **No "probably named" struct fields, option names, or parameter names.** Transcribe from the snippet.
4. **No inferred flag names** (do not derive Python option names from Go or vice-versa).
5. **No conflating concept with interface.** "External Storage" is the concept; `ExternalStorage` is the Go struct field / Python option. `StorageDriver` is the Go interface; `StorageDriver` is the Python abstract class. Document each in its own SDK section; do not unify them.
6. **No flattening across SDKs.** Go uses `Name()` AND `Type()`; Python uses only `name()`. Do not pretend they're symmetric.
7. **No assumed defaults.** Only state "default: 256 KiB" because the docs say so; do not invent other defaults.

### 3.4 Anti-fabrication rules (topic-specific)

- **Threshold semantics differ between SDKs.** Go: `PayloadSizeThreshold` of 0 means use default (256 KiB); set to 1 to externalize all payloads. Python: `payload_size_threshold` of 0 externalizes all payloads. Do not unify these — transcribe each from its own SDK doc.
- **`Type()` is Go-only.** The Python `StorageDriver` abstract class does not have a `Type()` method per the Python doc. Do not invent one.
- **`StorageDriverActivityInfo` is Go-only and only for standalone activities.** The Go doc explicitly says "StorageDriverActivityInfo is only used for standalone (non-workflow-bound) activities. Activities started by a workflow use StorageDriverWorkflowInfo." Do not generalize.
- **Multi-driver retrieval rule.** "Any driver in the list that is not selected for storing is still available for retrieval." This applies to both SDKs but is worded precisely — do not paraphrase loosely.
- **Selector return-nil/None semantics.** Go selector returns `nil` to keep payload inline; Python selector returns `None`. Do not swap.
- **Codec Server endpoint set is conditional.** `/download` only appears when the handler is configured with storage drivers. Do not present it as always-present. Source: `docs/encyclopedia/data-conversion/codec-server.mdx:93-94`.
- **`NewPayloadHTTPHandler` vs `NewPayloadCodecHTTPHandler`.** These are distinct handlers with a documented "do not use this as a target for a remote Data Converter or remote codec" caveat. Do not conflate. Source: `docs/encyclopedia/data-conversion/codec-server.mdx:96-103`.
- **Pre-Release stability.** Always preserve the "APIs and configuration may change before the stable release" framing. Do not present APIs as stable.
- **The conceptual section is SDK-agnostic.** When writing `references/core/external-storage.md`, never name a Go type (e.g. `s3driver`, `PayloadSizeThreshold`) or Python option (e.g. `aioboto3`, `payload_size_threshold`) — those go in language sections. Reverse also applies: language files must not invent platform-level claims.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Cross-check a sibling docs file (the per-SDK file vs. the encyclopedia file).
2. Note ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of prose.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

The docs do not document a stable on-disk format for the reference token or an explicit migration tool between Pre-Release format versions. If asked about reference format migration, point users at the multi-driver registration pattern (which is the documented mechanism for cross-driver migration) and the Pre-Release stability notice. Do not invent a format-version field.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Where the docs describe what a thing does, describe what it does. Where the docs don't prescribe a workflow (e.g. format-version migration), don't invent one. The recipes section can chain documented facts — each step must cite the doc the fact comes from.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end.

### Step 2: Set up the workspace.

Create the new files listed in §5 under `references/`. SKILL.md already exists; only update the Primary References list and "Additional Topics" pointers to surface the new files.

### Step 3: Author each reference file via a subagent.

For each file in §5 (in order), spawn one subagent. Give the subagent:

- The single file it owns.
- The docs paths from §1 relevant to that file.
- The full §3 methodology (grep-first, citation format, anti-fabrication rules).
- The §8 regression patterns — self-check against these before committing.
- Instructions: "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce the file contents. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Update SKILL.md (orchestrator does this).

Add a row to the Primary References list pointing to `references/core/external-storage.md` and the language-specific files. Do not re-architect the rest of SKILL.md.

### Step 5: Produce `AUTHORING_LOG.md` from subagent reports.

### What NOT to do

- Do not read or reference prior conversation or previous skill files beyond what §1 lists.
- Do not read the paired validation plan.
- Do not write reference files for SDKs not in scope (TypeScript, Java, .NET).
- Do not create files outside `references/` and the skill root.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/core/external-storage.md`** — SDK-agnostic concept page: claim check pattern, where External Storage sits in the data conversion pipeline, default size threshold (256 KiB), concurrent upload/download behaviour, lifecycle/TTL formula, Pre-Release stability. Ground truth: `docs/encyclopedia/data-conversion/external-storage.mdx`, `docs/troubleshooting/blob-size-limit-error.mdx` (size limits context), `docs/develop/{go,python}/best-practices/data-handling/index.mdx` (three-layer model).
2. **`references/go/external-storage.md`** — Go-specific setup: S3 driver (`s3driver.NewDriver`, `s3driver.Options`, `s3driver.StaticBucket`), `converter.ExternalStorage` struct on `client.Options`, `PayloadSizeThreshold` semantics (0 = default, 1 = all), custom `StorageDriver` interface (`Name()`, `Type()`, `Store()`, `Retrieve()`), `StorageDriverStoreContext` / `StorageDriverRetrieveContext`, `StorageDriverWorkflowInfo` / `StorageDriverActivityInfo`, multiple drivers with `StorageDriverSelector` interface. Ground truth: `docs/develop/go/best-practices/data-handling/external-storage.mdx`.
3. **`references/python/external-storage.md`** — Python-specific setup: `aioboto3` extra, `S3StorageDriver`, `new_aioboto3_client`, `ExternalStorage(drivers=[...])`, `payload_size_threshold` semantics (0 = all), custom `StorageDriver` abstract class (`name()`, `store()`, `retrieve()`), `StorageDriverStoreContext` / `StorageDriverRetrieveContext`, `StorageDriverWorkflowInfo`, `StorageDriverClaim`, `driver_selector` function (returns `None` to skip offload). Ground truth: `docs/develop/python/best-practices/data-handling/external-storage.mdx`.
4. **`references/core/external-storage-codec-server.md`** — Codec Server interaction with External Storage: `NewPayloadHTTPHandler` + `PayloadHTTPHandlerOptions`, the three endpoints (`/encode`, `/decode`, `/download`), `?preserveStorageRefs=true` query parameter, ordering between Codec and storage on encode/decode, distinction from `NewPayloadCodecHTTPHandler`. Ground truth: `docs/encyclopedia/data-conversion/codec-server.mdx` §"Codec Server with External Storage", `docs/production-deployment/data-encryption.mdx` (endpoint summary).
5. **`SKILL.md`** — **last**. Add `references/core/external-storage.md`, `references/go/external-storage.md`, `references/python/external-storage.md`, and `references/core/external-storage-codec-server.md` to the Primary References / Additional Topics sections. Note that External Storage is Pre-Release and currently supported in Go and Python only.

Why this order matters: the concept page establishes terminology (claim check, payload size threshold, storage driver, claim, lifecycle TTL formula) that the SDK files reuse. The Codec Server page depends on the concept page for terminology. SKILL.md is updated last so its pointers reflect what was actually written.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every type name, method name, option name, struct field, or query parameter appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every claim has a citation comment with a `docs/...:LINE` reference.
3. No subcommand / field / enum appears that isn't in the relevant `docs/` file.
4. A self-check Grep finds zero instances of the regression patterns listed in §8.
5. The Pre-Release stability notice is included where applicable (every SDK-specific file, the concept page intro).

---

## 7. Deliverables

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions.
- **A git-visible diff** — one logical group of changes per file is acceptable; the entire run can ship as one or several commits.

Do not create files outside `references/` and the skill root.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| Python `StorageDriver` has a `type()` method | Python `StorageDriver` has `name()`, `store()`, `retrieve()` only | docs/develop/python/best-practices/data-handling/external-storage.mdx:148-156 |
| Go `PayloadSizeThreshold: 0` externalizes all payloads | Go `PayloadSizeThreshold: 0` is interpreted as the default (256 KiB); use `1` to externalize all | docs/develop/go/best-practices/data-handling/external-storage.mdx:231-233 |
| Python `payload_size_threshold=1` to externalize all | Python `payload_size_threshold=0` externalizes all payloads regardless of size | docs/develop/python/best-practices/data-handling/external-storage.mdx:196-197 |
| Go selector returns `None` to keep payload inline | Go selector returns `nil` (Python returns `None`) | docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252; docs/develop/python/best-practices/data-handling/external-storage.mdx:216 |
| `/download` is always available on a Codec Server | `/download` becomes available only when the handler is configured with storage drivers | docs/encyclopedia/data-conversion/codec-server.mdx:93-94 |
| Use `NewPayloadHTTPHandler` as the remote Data Converter target for Workers | Use `NewPayloadCodecHTTPHandler` for remote codecs on Workers; `NewPayloadHTTPHandler` is for Web UI/CLI | docs/encyclopedia/data-conversion/codec-server.mdx:96-103 |
| External Storage is GA / stable | External Storage is in Pre-Release; APIs and configuration may change | docs/encyclopedia/data-conversion/external-storage.mdx:24-30 |
| Default payload size threshold is 2 MB | Default offload threshold is 256 KiB; 2 MB is the Temporal Service per-payload limit | docs/encyclopedia/data-conversion/external-storage.mdx:43,124 |
| Storing payloads inline always; External Storage replaces every payload | Payloads below the size threshold stay inline in Event History; only payloads above threshold are offloaded | docs/encyclopedia/data-conversion/external-storage.mdx:83-84 |
| TTL only needs to cover the Workflow runtime | TTL > Maximum Workflow Run Timeout + Namespace Retention Period | docs/encyclopedia/data-conversion/external-storage.mdx:135-140 |
| Codec runs after External Storage | External Storage runs after the Payload Codec; encryption codecs encrypt before upload | docs/encyclopedia/data-conversion/external-storage.mdx:72-99 |
| Renaming a driver after deployment is safe | Changing `Name()` after payloads have been stored breaks retrieval | docs/develop/go/best-practices/data-handling/external-storage.mdx:185-189; docs/develop/python/best-practices/data-handling/external-storage.mdx:151-153 |

This table is the input to the validation plan's regression check.

---

## 9. Known correct anchors

- External Storage is in Pre-Release; "APIs and configuration may change before the stable release" (`docs/encyclopedia/data-conversion/external-storage.mdx:24-30`).
- Claim check pattern: the SDK uploads payloads above threshold and passes a small reference token through Event History (`docs/encyclopedia/data-conversion/external-storage.mdx:32-33`).
- Default offload threshold: 256 KiB (`docs/encyclopedia/data-conversion/external-storage.mdx:124`).
- Temporal Cloud per-payload limit is fixed at 2 MB; self-hosted is configurable (`docs/encyclopedia/data-conversion/external-storage.mdx:43-44`).
- External Storage runs after the Payload Codec in the data conversion pipeline (`docs/encyclopedia/data-conversion/external-storage.mdx:72-74`, `98-99`).
- The SDK uploads/downloads multiple payloads in a single Task concurrently (`docs/encyclopedia/data-conversion/external-storage.mdx:90-92`).
- TTL formula: `TTL > Maximum Workflow Run Timeout + Namespace Retention Period` (`docs/encyclopedia/data-conversion/external-storage.mdx:138-140`).
- Go custom driver implements `Name()`, `Type()`, `Store()`, `Retrieve()` (`docs/develop/go/best-practices/data-handling/external-storage.mdx:185-195`).
- Python custom driver extends `StorageDriver` and implements `name()`, `store()`, `retrieve()` (`docs/develop/python/best-practices/data-handling/external-storage.mdx:150-156`).
- Go `PayloadSizeThreshold: 0` means default (256 KiB); use `1` to externalize all (`docs/develop/go/best-practices/data-handling/external-storage.mdx:231-233`).
- Python `payload_size_threshold=0` externalizes all payloads (`docs/develop/python/best-practices/data-handling/external-storage.mdx:196-197`).
- Multiple drivers: "any driver in the list that is not selected for storing is still available for retrieval" — useful for migration (`docs/develop/go/best-practices/data-handling/external-storage.mdx:250-252`, `docs/develop/python/best-practices/data-handling/external-storage.mdx:214-216`).
- `NewPayloadHTTPHandler` makes existing endpoints storage-aware and adds `/download` (`docs/encyclopedia/data-conversion/codec-server.mdx:90-94`).
- `?preserveStorageRefs=true` on `/decode` returns storage references as-is (`docs/encyclopedia/data-conversion/codec-server.mdx:111`).
- The Pre-Release feedback channel is the `#large-payloads` Slack channel (`docs/encyclopedia/data-conversion/external-storage.mdx:28`).

---

## 10. Non-goals

- **Do not** re-architect the skill.
- **Do not** write TypeScript / Java / .NET external storage docs — the SDKs do not have External Storage support per the docs as cloned.
- **Do not** invent a "reference format migration tool" or "format version" field. Document the multi-driver migration pattern and the Pre-Release stability notice; that is the documented path for cross-driver moves.
- **Do not** paraphrase docs prose verbatim.
- **Do not** write tests, CI, or tooling.
- **Do not** add meta-docs (`CHANGELOG.md`, etc.) unless asked.

---

## 11. Sibling handoff

This skill sits alongside:

- `references/{go,python}/data-handling.md` — covers Data Converter and Payload Codec; External Storage docs cross-reference these for Payload Codec specifics rather than restating them.

Handoff disciplines:

1. When this skill mentions a Payload Codec, link to the existing data-handling reference, not the encyclopedia.
2. The Pre-Release stability notice ("APIs and configuration may change before the stable release") is owned by this reference family — restate at the top of every file, do not assume readers came from a sibling page.

End of plan.
