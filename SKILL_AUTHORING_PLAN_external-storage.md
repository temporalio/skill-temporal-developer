# Skill Authoring Plan — `external-storage`

**Mode:** greenfield

**Context:** This skill teaches developers how to offload large Temporal payloads to an external object store (such as Amazon S3) using the claim-check pattern, configure the SDK so payloads above a size threshold are uploaded transparently, retrieve them concurrently on the Worker side, surface them through a Codec Server for the Web UI and CLI, and run multiple drivers in parallel for migration. The topic affects two SDKs in scope: **Go** and **Python**. The feature is currently in **Pre-Release** — API names, configuration shapes, and the on-the-wire reference token format may change before the stable release, which makes grounded transcription from the docs critical. The skill sits alongside existing `references/{go,python}/data-handling.md` files in `skill-temporal-developer` and is intended to be linked from those rather than duplicating them.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `external-storage`:

- `docs/encyclopedia/data-conversion/external-storage.mdx` — concept page: claim-check pattern, data-conversion pipeline position, drivers, key settings, lifecycle (TTL) math.
- `docs/develop/go/best-practices/data-handling/external-storage.mdx` — Go SDK setup: `s3driver.NewDriver`, `converter.ExternalStorage`, `PayloadSizeThreshold`, custom `StorageDriver` interface with `Name()`/`Type()`/`Store()`/`Retrieve()`, `StorageDriverSelector` for multi-driver setups.
- `docs/develop/python/best-practices/data-handling/external-storage.mdx` — Python SDK setup: `S3StorageDriver`, `ExternalStorage`, `payload_size_threshold`, custom `StorageDriver` class (`name`/`store`/`retrieve`), `driver_selector` callable.
- `docs/encyclopedia/data-conversion/codec-server.mdx` — Codec Server with External Storage: `NewPayloadHTTPHandler`, `PayloadHTTPHandlerOptions`, `/download` endpoint, `?preserveStorageRefs=true` on `/decode`, why `NewPayloadHTTPHandler` is not interchangeable with `NewPayloadCodecHTTPHandler`.
- `docs/troubleshooting/blob-size-limit-error.mdx` — the 2 MB payload limit / 4 MB gRPC limit that motivates the feature; error strings.
- `docs/production-deployment/data-encryption.mdx` — Codec Server endpoint table, including `/download` when Workers use External Storage.

**Secondary (only if primary is silent):** none. The topic lives entirely inside `documentation/`. Do not reach for SDK source or upstream READMEs unless a `<!-- VERIFY -->` marker is being investigated.

Prefer Read/Grep on a local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** any prior sketches, wiki pages, or memory about external storage API shapes. Pre-Release status means tokens like `payload_size_threshold` vs. `PayloadSizeThreshold`, `driver_selector` vs. `DriverSelector`, and the meaning of threshold `0` (Python: externalize all; Go: interpreted as default) differ between SDKs and are easy to fabricate by analogy.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "what does setting the payload size threshold to 0 do in each SDK?":

1. `Read ../documentation/docs/develop/python/best-practices/data-handling/external-storage.mdx` §Configure payload size threshold.
2. `Read ../documentation/docs/develop/go/best-practices/data-handling/external-storage.mdx` §Configure payload size threshold.
3. Transcribe only what each file says. (Python: "set it to 0 to externalize all payloads regardless of size." Go: "set it to 1 to externalize all payloads regardless of size. A value of 0 is interpreted as the default (256 KiB).")
4. Record the line numbers where you found each statement.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`PayloadSizeThreshold: 1` <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:241 -->
```

Use **inline comment per claim** (not a section footer) — the API shapes diverge subtly between Go and Python and a per-claim citation is the only way to keep the divergence honest. Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `TEMPORAL_EXTERNAL_STORAGE_*` env vars from option names — none are documented.
5. **No conflating concept with interface.** "Claim check" is the pattern; `StorageDriverClaim` is the Go/Python type. "Reference token" is the on-history representation; the SDK type is not the same word.
6. **No flattening of subcommand groups.** The Codec Server exposes three endpoints (`/encode`, `/decode`, `/download`) — don't fold `/download` into `/decode`.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Go and Python option names differ in case and exact spelling.** Go uses `ExternalStorage.Drivers`, `PayloadSizeThreshold`, `DriverSelector`. Python uses `ExternalStorage(drivers=...)`, `payload_size_threshold`, `driver_selector`. Never write the Go name in a Python example or vice versa.
- **Threshold `0` is not symmetric between SDKs.** In Python, `payload_size_threshold=0` externalizes everything; in Go, `PayloadSizeThreshold: 0` falls back to the default (256 KiB), and `1` is the value that externalizes everything. Cite each separately.
- **Custom driver method counts differ.** Go's `converter.StorageDriver` interface has **four** methods (`Name()`, `Type()`, `Store()`, `Retrieve()`); Python's `StorageDriver` abstract class has **three** (`name()`, `store()`, `retrieve()`). Do not invent a `Type()` on Python or drop it from Go.
- **The driver selector return type for "stay inline" differs.** Python returns `None`; Go returns `nil`. Both keep the payload inline in Event History. Spell out the per-language idiom.
- **Codec Server has two distinct HTTP handler constructors.** `NewPayloadHTTPHandler` (used by Web UI/CLI; runs the full encode-store-encode and decode-retrieve-decode pipeline) and `NewPayloadCodecHTTPHandler` (used as a remote codec target by Workers). The docs explicitly warn against using `NewPayloadHTTPHandler` as a remote Data Converter target — call this out, don't soften it.
- **The `?preserveStorageRefs=true` parameter is on `/decode`, not `/download`.** When set, `/decode` returns storage references as-is; without it, `/decode` internally calls download logic. Get the verb-to-endpoint mapping right.
- **External Storage is Pre-Release.** Every reference file must surface the Pre-Release banner and the warning that APIs and configuration may change before the stable release (including the reference token format). Do not omit this for brevity.
- **TTL formula is exact.** The docs give: `TTL > Maximum Workflow Run Timeout + Namespace Retention Period`. Transcribe verbatim; don't paraphrase to "TTL ≥ run timeout + retention" or invert the inequality.
- **Built-in driver scope.** Only Amazon S3 is documented as a built-in driver in both SDKs. Do not list GCS, Azure Blob, or any other built-in. If you mention them, mark with `<!-- VERIFY -->`.
- **Pre-Release reference format migration is documented as driver migration, not format migration.** The docs cover registering multiple drivers so an old driver remains available for retrieval while a new driver handles new writes. Do not describe an on-history reference token format migration unless you can cite it; if a reader needs that, flag with `<!-- VERIFY -->`.

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

Greenfield: create three new reference files under `references/` (one core, two language-specific) and update `SKILL.md` to point at them. Do not touch unrelated reference files.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Author SKILL.md

After all reference-file subagents complete, write `SKILL.md` yourself (the orchestrator). Add a single bullet under "Additional Topics" pointing at `references/core/external-storage.md` and at the language-specific files, mirroring the existing pattern (e.g. how `data-handling.md` is referenced from language overviews). Do not introduce a new top-level section if a bullet under "Additional Topics" suffices.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports: for each reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond what §2 tells you to keep.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.
- Do not create `references/java/external-storage.md`, `references/typescript/external-storage.md`, or `references/dotnet/external-storage.md`. The feature is documented only for Go and Python; other SDKs are out of scope.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/core/external-storage.md`** — Concept page. Covers: the claim check pattern, where External Storage sits in the data-conversion pipeline (after Payload Codec), concurrent upload/download behavior, storage driver responsibilities (Store/Retrieve), key configuration settings (size threshold, drivers, driver selector), lifecycle management (TTL formula), Codec Server integration (`NewPayloadHTTPHandler`, `/download`, `?preserveStorageRefs=true`), Pre-Release status. Ground truth: `docs/encyclopedia/data-conversion/external-storage.mdx`, `docs/encyclopedia/data-conversion/codec-server.mdx` (the §Codec Server with External Storage section), `docs/troubleshooting/blob-size-limit-error.mdx` (motivation only).
2. **`references/go/external-storage.md`** — Go SDK usage. Covers: S3 driver setup (`s3driver.NewDriver`, `s3driver.StaticBucket`, `awssdkv2.NewClient`), wiring to client (`converter.ExternalStorage{Drivers: ...}` in `client.Options`), threshold (`PayloadSizeThreshold`; document the 0-means-default / 1-means-everything quirk), custom driver (four-method interface: `Name`, `Type`, `Store`, `Retrieve`; type switch on `Target` between `StorageDriverWorkflowInfo` and `StorageDriverActivityInfo`), multi-driver setup (implement `StorageDriverSelector` with a `SelectDriver` method; return `nil` to keep inline), pre-release banner. Ground truth: `docs/develop/go/best-practices/data-handling/external-storage.mdx`.
3. **`references/python/external-storage.md`** — Python SDK usage. Covers: S3 driver setup (`S3StorageDriver`, `aioboto3.Session`, `new_aioboto3_client`), wiring to client/Worker via `DataConverter` with `external_storage=ExternalStorage(drivers=...)`, threshold (`payload_size_threshold`; 0 externalizes everything), custom driver (three-method abstract class: `name`, `store`, `retrieve`; isinstance check on `StorageDriverWorkflowInfo`), multi-driver setup (`driver_selector` callable; return `None` to keep inline), the `temporalio[aioboto3]` extra, Pre-Release banner. Ground truth: `docs/develop/python/best-practices/data-handling/external-storage.mdx`.
4. **`SKILL.md`** — **last**. Add one bullet under "Additional Topics" linking to `references/core/external-storage.md` with a one-sentence description; cross-link the language-specific files from there. Do not touch any unrelated parts of SKILL.md.

Why this order matters: the core conceptual page establishes the shared vocabulary (claim check, reference token, threshold, driver, selector, lifecycle TTL formula, Codec Server `/download`). The language pages then describe *how that vocabulary maps to API tokens in each SDK*, where the divergence is sharpest (Go `PayloadSizeThreshold` vs. Python `payload_size_threshold`; Go four-method interface vs. Python three-method class; 0-means-default-in-Go vs. 0-means-everything-in-Python). SKILL.md is last so its description reflects what was actually written.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, field name, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file's headings or tables.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.
6. The Pre-Release banner appears at or near the top of the file.

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
| `payload_size_threshold=0` externalizes default | In Python, 0 externalizes **all** payloads regardless of size | docs/develop/python/best-practices/data-handling/external-storage.mdx:197 |
| `PayloadSizeThreshold: 0` externalizes all in Go | In Go, **0 is the default (256 KiB)**; use `PayloadSizeThreshold: 1` to externalize everything | docs/develop/go/best-practices/data-handling/external-storage.mdx:233 |
| Python `StorageDriver` has a `type()` method | Python's `StorageDriver` has **three** methods: `name()`, `store()`, `retrieve()` | docs/develop/python/best-practices/data-handling/external-storage.mdx:150-156 |
| Go `StorageDriver` interface has three methods | Go's `StorageDriver` has **four** methods: `Name()`, `Type()`, `Store()`, `Retrieve()` | docs/develop/go/best-practices/data-handling/external-storage.mdx:185-195 |
| Selector returns `nil`/`None` to externalize | Return `nil` (Go) / `None` (Python) to **keep the payload inline** in Event History | docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252, docs/develop/python/best-practices/data-handling/external-storage.mdx:216 |
| `/download` accepts `?preserveStorageRefs=true` | The `?preserveStorageRefs=true` parameter is on **`/decode`**, causing it to skip retrieval and return refs as-is | docs/encyclopedia/data-conversion/codec-server.mdx:111 |
| Use `NewPayloadHTTPHandler` as remote codec for Workers | `NewPayloadHTTPHandler` is for Web UI/CLI. For Workers, use `NewPayloadCodecHTTPHandler` | docs/encyclopedia/data-conversion/codec-server.mdx:98-101 |
| TTL ≥ run timeout | `TTL > Maximum Workflow Run Timeout + Namespace Retention Period` | docs/encyclopedia/data-conversion/external-storage.mdx:139 |
| External Storage is GA | External Storage is in **Pre-Release**; APIs and configuration may change | docs/encyclopedia/data-conversion/external-storage.mdx:26-28 |
| Built-in drivers include GCS and Azure | Built-in driver documented in both SDKs is **Amazon S3 only** | docs/develop/go/best-practices/data-handling/external-storage.mdx:31, docs/develop/python/best-practices/data-handling/external-storage.mdx:31 |
| Python install command is `pip install temporalio-s3` | Install extra: `python -m pip install "temporalio[aioboto3]"` | docs/develop/python/best-practices/data-handling/external-storage.mdx:37 |
| Cloud payload limit is configurable | Cloud payload limit is **fixed at 2 MB**; only self-hosted is configurable | docs/encyclopedia/data-conversion/external-storage.mdx:43-45 |
| External Storage runs before the Payload Codec | External Storage runs **after** the Payload Codec; encryption codecs encrypt before upload | docs/encyclopedia/data-conversion/external-storage.mdx:98-99 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- External Storage is in Pre-Release; APIs and configuration may change before stable release (`docs/encyclopedia/data-conversion/external-storage.mdx:26-30`).
- Default payload size threshold is 256 KiB (`docs/encyclopedia/data-conversion/external-storage.mdx:124`).
- Cloud per-payload limit is fixed at 2 MB; self-hosted is configurable and defaults to 2 MB (`docs/encyclopedia/data-conversion/external-storage.mdx:43-45`).
- External Storage sits at the end of the data conversion pipeline, after the Payload Converter and the Payload Codec (`docs/encyclopedia/data-conversion/external-storage.mdx:72-73`).
- The SDK parallelizes uploads and downloads when a Task carries multiple payloads above the threshold (`docs/encyclopedia/data-conversion/external-storage.mdx:90-92`).
- The Temporal UI displays a reference token for offloaded payloads; the SDK retrieves the full payload transparently for application code (`docs/encyclopedia/data-conversion/external-storage.mdx:94-96`).
- TTL formula: `TTL > Maximum Workflow Run Timeout + Namespace Retention Period` (`docs/encyclopedia/data-conversion/external-storage.mdx:139`).
- Python install extra: `python -m pip install "temporalio[aioboto3]"` (`docs/develop/python/best-practices/data-handling/external-storage.mdx:37`).
- Go install command: `go get go.temporal.io/sdk/contrib/aws/s3driver go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 github.com/aws/aws-sdk-go-v2/config github.com/aws/aws-sdk-go-v2/service/s3` (`docs/develop/go/best-practices/data-handling/external-storage.mdx:37`).
- Python `payload_size_threshold=0` externalizes all payloads (`docs/develop/python/best-practices/data-handling/external-storage.mdx:80`, `196-197`).
- Go `PayloadSizeThreshold: 1` externalizes all payloads; `0` is interpreted as the default 256 KiB (`docs/develop/go/best-practices/data-handling/external-storage.mdx:233`).
- Go `converter.StorageDriver` has four methods: `Name()`, `Type()`, `Store()`, `Retrieve()` (`docs/develop/go/best-practices/data-handling/external-storage.mdx:185-195`).
- Python `StorageDriver` abstract class has three methods: `name()`, `store()`, `retrieve()` (`docs/develop/python/best-practices/data-handling/external-storage.mdx:150-156`).
- Codec Server with External Storage: `NewPayloadHTTPHandler` + `PayloadHTTPHandlerOptions`; new `/download` endpoint becomes available (`docs/encyclopedia/data-conversion/codec-server.mdx:90-95`).
- `/decode` with `?preserveStorageRefs=true` skips retrieval and returns storage references as-is (`docs/encyclopedia/data-conversion/codec-server.mdx:109-111`).
- `NewPayloadHTTPHandler` must not be used as a remote Data Converter target; use `NewPayloadCodecHTTPHandler` for that (`docs/encyclopedia/data-conversion/codec-server.mdx:96-103`).
- Driver migration scenario: register old and new drivers; the unselected driver remains available for retrieval (`docs/develop/python/best-practices/data-handling/external-storage.mdx:213-228`, `docs/develop/go/best-practices/data-handling/external-storage.mdx:249-265`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** Java, TypeScript, and .NET are not in scope — the documented SDKs for External Storage are Go and Python only.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis and framing, not re-publication. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`) unless the user asks.
- **Do not absorb the Codec Server.** Cross-reference `references/core/external-storage.md` to the Codec Server docs for the slice that involves storage references; do not re-document the full Codec Server setup.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
