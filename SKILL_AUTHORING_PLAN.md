# Skill Authoring Plan — `workflow-streams`

**Mode:** greenfield

**Context:** The Temporal Python SDK shipped a public-preview `temporalio.contrib.workflow_streams` module that provides a durable, offset-addressed event channel for streaming events out of a Workflow on top of Signals, Updates, and Queries. The existing `skill-temporal-developer` skill has Python references covering core SDK use, AI patterns, signals/updates/queries, and advanced features, but nothing on Workflow Streams. This new reference file lives under `references/python/` and is the single home for Workflow Streams guidance; SKILL.md gets a small pointer added. The audience is a developer who is already building a Python Workflow and wants to stream events (LLM tokens, order pipeline status, agent progress) to outside subscribers. No sibling skills cover this topic — it is Python-only and Python-SDK-only today.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `workflow-streams`:

- `docs/develop/python/workflows/workflow-streams.mdx` — the entire feature: hosting choice, init-time construction, Workflow-side publish, client publish (including `from_within_activity`), subscribe (single-topic and heterogeneous), closing the stream, Continue-As-New rollover, tuning settings, delivery semantics, architecture, gotchas, and the end-to-end LLM streaming example.

There are no other files in `../documentation/docs/` that mention `workflow_streams`, `WorkflowStream`, or "workflow streams." This single page is the entire source of truth.

**Secondary (only if primary is silent):** none for the API surface. Two related pages are linked from the primary doc and may be cited for context but not for new claims:

- `docs/develop/python/workflows/message-passing` — Signals/Updates/Queries primitives that Workflow Streams is built on (linked at the bottom of the source doc).
- `docs/external-storage/index` (or wherever External Storage lives) — referenced for large-payload offload. Only cite it as a pointer; do not transcribe External Storage details into the new file.

Prefer Read/Grep on a local clone over WebFetch or `gh api`. Check `../` for sibling clones before reaching for the network.

**Never trust:** any prior sketches, wiki pages, or recollection of an earlier API shape — treat as inputs to the Intent table, not as ground truth. In particular, do not assume Signal/Update names, default values, or method signatures from memory; transcribe from `workflow-streams.mdx`.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory — memory is what produces fabrications.

Example workflow for "what is the default value of `batch_interval` and `poll_cooldown`?":

1. `Read ../documentation/docs/develop/python/workflows/workflow-streams.mdx` §Tuning.
2. Transcribe only what appears in that file: `batch_interval` default 2 seconds; `poll_cooldown` default 100 ms.
3. Record the line number where you found it.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`batch_interval` default 2 seconds <!-- docs/develop/python/workflows/workflow-streams.mdx:370 -->
```

Pick one convention (inline comment per claim *or* `<!-- Sources: … -->` footer per section) and use it consistently. Keep citations to local repo paths (no URLs).

Use the inline-comment-per-claim convention for this file: most claims (defaults, method names, error names, default timings) need an individual line citation, and the section-footer convention loses precision when one section mixes a half-dozen facts.

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `TEMPORAL_{{X}}_{{Y}}_PATH` from `--{{x}}-{{y}}-path`. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** Platform concepts and CLI/SDK tokens often have subtly different names. Document the interface token; name the concept separately with a pointer.
6. **No flattening of subcommand groups.** If the docs show a group with N subcommands, don't flatten to one command with a flag.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not invent constructor arguments for `WorkflowStream`.** The docs list exactly one keyword argument used in user code: `prior_state=`. Don't add `topics=`, `id=`, `dedup=`, or similar. If you need a configuration arg you can't find in the doc, leave it out with a `<!-- VERIFY -->` comment rather than guessing.
- **Do not invent constructor arguments for `WorkflowStreamClient.create()` and `.from_within_activity()`.** The docs show `client`, `workflow_id=`, `batch_interval=` for `create()` and `batch_interval=` for `from_within_activity()`. Other settings (`max_batch_size`, `poll_cooldown`, `max_retry_duration`, `publisher_ttl`) are named in the Tuning section but the docs do not show their exact constructor placement. If you transcribe them, transcribe them as named tunables only; do not show fabricated `WorkflowStreamClient.create(..., max_batch_size=...)` invocations unless that invocation appears in the doc.
- **Do not invent default values.** Only these defaults appear in the doc: `batch_interval` 2 seconds, `poll_cooldown` 100 ms, `max_retry_duration` 10 minutes, `publisher_ttl` 15 minutes, `max_batch_size` unbounded. If you write a different default, you fabricated it.
- **Do not invent topic types or sentinel event names.** `RETRY`, `STATUS_CHANGE`, `TEXT_DELTA`, `TEXT_COMPLETE`, `AGENT_START`, `delta`, `close`, `status`, `progress` are illustrative event/topic names that appear in the docs as examples — they are not library-provided constants. Present them as application-defined names, not Temporal-supplied enums.
- **Do not invent the wire-handler names.** The docs name exactly three: `__temporal_workflow_stream_publish`, `__temporal_workflow_stream_poll`, `__temporal_workflow_stream_offset`. Don't invent a fourth (e.g. `__temporal_workflow_stream_close`).
- **Do not invent return types or exception classes.** The docs name `RuntimeError` (constructing more than one stream, or constructing from `@workflow.run`), `AttributeError` (when `prior_state` deserializes as a `dict`), `TimeoutError` (from `max_retry_duration` exhaustion and from the `wait_condition` fallback), `WorkflowUpdateFailedError` (validator rejection on CAN handoff), `AcceptedUpdateCompletedWorkflow` (poll Update still in flight when Workflow returns), and `ApplicationError("TruncatedOffset")` (internal, swallowed by the client). Do not add `WorkflowStreamError`, `StreamClosedError`, etc.
- **Do not confuse `force_flush=True` with `await client.flush()`.** The first wakes the background flusher and returns immediately after appending to the buffer; the second is an awaitable mid-stream barrier that returns only once prior publications are durable in the Workflow log. The doc draws this distinction explicitly; mirroring it is required, not optional.
- **Do not claim subscribers can attach from inside the host Workflow.** The docs say it is "intentionally unsupported." If you mention subscriber-side patterns, state this explicitly.
- **Do not invent ordering guarantees across publishers.** The doc says ordering is preserved within one publisher; across publishers, the interleaving is whatever the Workflow saw when serializing inbound Signals. Don't promise FIFO across publishers, don't promise timestamp ordering.
- **Do not promise exactly-once delivery to subscribers.** The doc says "exactly-once at the execution layer" — meaning each `(publisher_id, sequence)` batch lands in the log at most once. Subscribers that crash before persisting their offset will reprocess; truncation can cause a subscriber to re-receive items. Use the doc's language ("exactly-once at the execution layer"), not a blanket "exactly-once."
- **Do not invent a `close()` API.** The doc explicitly says end-of-stream is application-level and shows two patterns: a sentinel + `workflow.sleep`, or a sentinel + acknowledgment Signal. No `stream.close()` method exists.
- **Do not promise cross-language clients.** The doc says "Only the Python client is available today" — cross-language is on the roadmap. Mark this explicitly when introducing the feature.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source (upstream repo README, generator source file like `commands.yml`, SDK source). For this topic that means the `temporalio.contrib.workflow_streams` API reference at `https://python.temporal.io/temporalio.contrib.workflow_streams.html` (linked from the doc). Prefer a local clone of `temporalio/sdk-python` if one is present under `../`.
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

Greenfield: create the single new reference file `references/python/workflow-streams.md`. SKILL.md and `references/python/python.md` will be updated by the orchestrator, not by the subagent.

### Step 3: Author each reference file via a subagent

For each file in §5 (in order), spawn a subagent. Give the subagent:

- **The single file it owns.** One file per subagent — no cross-reading of sibling reference files.
- **The docs paths** from §1 that are relevant to that file (listed in §5).
- **The full methodology** from §3 (grep-first rule, citation format, all anti-fabrication rules).
- **The regression patterns** from §8 — self-check against these before committing.
- **Instructions:** "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

For this skill there is only one new reference file, so the subagent shape collapses to a single subagent call. The orchestrator handles SKILL.md and the `references/python/python.md` cross-reference itself.

### Step 4: Author SKILL.md

After the reference-file subagent completes, the orchestrator adds:

- A one-line pointer to `references/python/workflow-streams.md` from `references/python/python.md` (in the "Additional Resources → Reference Files" list).
- A brief mention in `SKILL.md` itself only if the streaming use case warrants surfacing in the Intent table. Given the public-preview status and Python-only scope, the right shape is a bullet under "Additional Topics" rather than a top-level Intent entry. Do not add a Cross-language streaming section to SKILL.md.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from the subagent report: for the one reference file, docs files consulted, citation count, `<!-- VERIFY -->` markers.

### What NOT to do

- Do not read or reference any prior conversation or previous version of the skill beyond what §2 tells you to keep. (N/A — greenfield.)
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts established early are inherited by later files.

1. **`references/python/workflow-streams.md`** — the entire Workflow Streams feature: host choice, init-time construction, Workflow-side publish, client-side publish (including `from_within_activity` and standalone-Activity caveat), `force_flush` vs `await client.flush()`, subscribe (single-topic and heterogeneous via `RawValue`), closing the stream (sentinel + sleep, sentinel + ack), Continue-As-New rollover, tuning (`batch_interval`, `max_batch_size`, `poll_cooldown`, `max_retry_duration`, `publisher_ttl`), delivery semantics (exactly-once at the execution layer, ordering, activity retries surfacing to subscribers, the `max_retry_duration < publisher_ttl` invariant), architecture (in-Workflow log, wire-level handlers, batching/dedup, `truncate(up_to_offset)`), known gotchas (asyncio-only, first-activation handler race, type bindings per-publisher), and the LLM-streaming application. Ground truth: `docs/develop/python/workflows/workflow-streams.mdx`.
2. **`SKILL.md`** — **last**. Add one line under "Additional Topics" referencing the new file. Also add one line to `references/python/python.md`'s "Reference Files" list. No other content changes.

Why this order matters: the entire skill lives in a single new reference file, so there is no inter-file dependency to track. SKILL.md is updated last so the pointer text reflects the file's final framing.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, field name, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file's headings or tables.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: for the new reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions and sources of ambiguity.
- **A git-visible diff** — the new `references/python/workflow-streams.md`, the SKILL.md and `references/python/python.md` pointer updates, and the AUTHORING_LOG.md. One commit is acceptable since there is one reference file.

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| Construct `WorkflowStream()` in `@workflow.run` | Construct it in `@workflow.init`; constructing from `@workflow.run` raises `RuntimeError` | docs/develop/python/workflows/workflow-streams.mdx:61 |
| Multiple `WorkflowStream` instances per Workflow | Single `WorkflowStream` per Workflow; constructing a second raises `RuntimeError` | docs/develop/python/workflows/workflow-streams.mdx:82 |
| Subscribe from inside the host Workflow | Subscribing from inside the host Workflow is intentionally unsupported | docs/develop/python/workflows/workflow-streams.mdx:206 |
| `WorkflowStreamClient.from_within_activity()` in a standalone Activity | Raises in standalone Activities; use `WorkflowStreamClient.create(activity.client(), workflow_id=...)` with the target Workflow Id threaded through input | docs/develop/python/workflows/workflow-streams.mdx:171 |
| `force_flush=True` waits for delivery | `publish(..., force_flush=True)` returns immediately after appending to the buffer and signaling the flusher; it does not wait for delivery to the Workflow or subscribers | docs/develop/python/workflows/workflow-streams.mdx:175 |
| Use `await client.flush()` interchangeably with `force_flush=True` | `await client.flush()` is a mid-stream barrier that completes only once prior publications are durable in the Workflow log; `force_flush=True` is a wake signal to the background flusher | docs/develop/python/workflows/workflow-streams.mdx:183 |
| `prior_state: Any` on Workflow input | Must be `WorkflowStreamState \| None`; using `Any` causes the data converter to rebuild as a `dict` and raises `AttributeError` | docs/develop/python/workflows/workflow-streams.mdx:347 |
| `stream.close()` method to end the stream | No `close()` API exists; end-of-stream is application-level (sentinel event + sleep, or sentinel + ack Signal) | docs/develop/python/workflows/workflow-streams.mdx:255 |
| `batch_interval` default of 200 ms | Default is 2 seconds; 200 ms is a recommended starting point for LLM token streams | docs/develop/python/workflows/workflow-streams.mdx:370 |
| `poll_cooldown` default of 1 second | Default is 100 ms | docs/develop/python/workflows/workflow-streams.mdx:379 |
| `max_retry_duration` ≥ `publisher_ttl` | Must satisfy `max_retry_duration < publisher_ttl` (defaults 10 min < 15 min); inverting the relation lets dedup state age out before a retry lands, producing duplicates | docs/develop/python/workflows/workflow-streams.mdx:406 |
| Promise "exactly-once delivery to subscribers" | Doc language is "exactly-once at the execution layer" — each `(publisher_id, sequence)` batch lands in the log at most once. Subscribers can reprocess on crash or after `truncate()` | docs/develop/python/workflows/workflow-streams.mdx:387 |
| Promise FIFO ordering across publishers | Ordering is preserved within one publisher; across publishers, interleaving is whatever the Workflow saw when serializing inbound Signals — stable once recorded, not application-controlled | docs/develop/python/workflows/workflow-streams.mdx:389 |
| Claim Activity retries do not surface to subscribers | Both attempts' events appear in the stream; convention is to publish a `RETRY` sentinel with `force_flush=True` and have consumers reset on it | docs/develop/python/workflows/workflow-streams.mdx:391 |
| Topic types are global to the Workflow | Each `WorkflowStream` and each `WorkflowStreamClient` records topic types only for its own instance; mismatched bindings across publishers surface as a decoder error at the subscriber | docs/develop/python/workflows/workflow-streams.mdx:433 |
| Publish `force_flush=True` per token by default | Per-token `force_flush=True` on a 500-token completion produces 500 publish Signals; reserve `force_flush=True` for first delta and punctuated sentinels | docs/develop/python/workflows/workflow-streams.mdx:372 |
| Cross-language Workflow Streams clients exist today | Only the Python client is available today; cross-language is on the roadmap | docs/develop/python/workflows/workflow-streams.mdx:35 |
| Workflow Streams is generally available | It is in Public Preview; the API may change before GA | docs/develop/python/workflows/workflow-streams.mdx:30 |
| `truncate()` shrinks Workflow history | `truncate(up_to_offset)` drops in-memory log entries (and the carried CAN payload); only Continue-As-New shrinks history | docs/develop/python/workflows/workflow-streams.mdx:415 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- Module path is `temporalio.contrib.workflow_streams`; it is in Public Preview and the API may change before GA (`docs/develop/python/workflows/workflow-streams.mdx:30-37`).
- `WorkflowStream` must be constructed in `@workflow.init`; constructing from `@workflow.run` raises `RuntimeError` and would miss publishes that arrived before the run body started (`docs/develop/python/workflows/workflow-streams.mdx:61`).
- Constructing more than one `WorkflowStream` on the same Workflow raises `RuntimeError` (`docs/develop/python/workflows/workflow-streams.mdx:82`).
- Bind a topic via `self.stream.topic("name", type=Type)`; `type=` is optional and defaults to `Any` (`docs/develop/python/workflows/workflow-streams.mdx:88, 124`).
- `WorkflowStreamClient.create(client, workflow_id)` and `WorkflowStreamClient.from_within_activity()` are the two construction paths; `from_within_activity()` raises in standalone Activities (`docs/develop/python/workflows/workflow-streams.mdx:128, 153, 171`).
- `publish()` is non-blocking and applies no backpressure; from a client it appends to the in-memory buffer, from a Workflow it appends synchronously to the in-memory log (`docs/develop/python/workflows/workflow-streams.mdx:198`).
- `publish(..., force_flush=True)` wakes the background flusher and returns immediately; it does not wait for delivery (`docs/develop/python/workflows/workflow-streams.mdx:175`).
- `await client.flush()` is a mid-stream barrier; successful completion proves prior publications have landed in the Workflow log (`docs/develop/python/workflows/workflow-streams.mdx:183`).
- Subscribing from inside the host Workflow is intentionally unsupported (`docs/develop/python/workflows/workflow-streams.mdx:206`).
- Heterogeneous topics: `client.subscribe([...], result_type=RawValue)` and dispatch on `item.topic`; `subscribe([])` covers every topic (`docs/develop/python/workflows/workflow-streams.mdx:233-247`).
- Defaults: `batch_interval` 2 seconds, `poll_cooldown` 100 ms, `max_retry_duration` 10 minutes, `publisher_ttl` 15 minutes, `max_batch_size` unbounded (`docs/develop/python/workflows/workflow-streams.mdx:370, 378, 379, 380, 381`).
- Invariant: `max_retry_duration < publisher_ttl` (`docs/develop/python/workflows/workflow-streams.mdx:406`).
- Delivery guarantee is **exactly-once at the execution layer**: each `(publisher_id, sequence)` batch lands in the log at most once, even across SDK/network Signal retries (`docs/develop/python/workflows/workflow-streams.mdx:387`).
- Activity retries surface to subscribers: both attempts' events appear in the stream; convention is to publish a `RETRY` sentinel with `force_flush=True` and reset consumer state on it (`docs/develop/python/workflows/workflow-streams.mdx:391-393`).
- Continue-As-New rollover uses `WorkflowStream.continue_as_new(build_args)` for the simple case, or the explicit `detach_pollers()` → `wait_condition(workflow.all_handlers_finished)` → `workflow.continue_as_new(...)` recipe for the parameterized case (`docs/develop/python/workflows/workflow-streams.mdx:305, 351-358`).
- Wire-level handlers are `__temporal_workflow_stream_publish`, `__temporal_workflow_stream_poll`, `__temporal_workflow_stream_offset` (`docs/develop/python/workflows/workflow-streams.mdx:421`).
- `truncate(up_to_offset)` shrinks the in-memory log and the carried CAN payload but not history; only Continue-As-New shrinks history (`docs/develop/python/workflows/workflow-streams.mdx:415-417`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** The Out-of-scope section defines what belongs in sibling skills. Don't pull those topics in.
- **Do not paraphrase docs prose verbatim.** The skill's value is synthesis and framing, not re-publication. Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`) unless the user asks.
- **Do not generalize to other languages.** Cross-language client support is on the roadmap but not shipped; do not write a `references/core/workflow-streams.md` or claim Go/Java/TypeScript/.NET parity.
- **Do not absorb message-passing into this file.** Cross-reference `references/python/patterns.md` and the Signals/Updates/Queries source doc for primitives. This file is about the streams library, not about the underlying message primitives.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`. An absent claim is safer than a wrong one.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan (plan was written from a point-in-time review and docs may have moved), trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
