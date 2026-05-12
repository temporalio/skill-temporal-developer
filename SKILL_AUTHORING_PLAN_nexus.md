# Skill Authoring Plan — `nexus`

**Mode:** greenfield

**Context:** This plan authors a new reference section for the existing `temporal-developer` skill covering Temporal Nexus. Nexus lets workflows in one Namespace invoke operations exposed by services in another Namespace through typed operation handlers and clients, providing durable cross-Namespace (and cross-team) execution with retries, timeouts, and a global registry. The Temporal Cloud, Go, and Java SDKs are GA; .NET and TypeScript are Public Preview. Audience: developers building cross-team or cross-Namespace Temporal applications in Python, TypeScript, Go, Java, or .NET. The skill already has sibling reference categories (`core/`, `dotnet/`, `go/`, `java/`, `python/`, `typescript/`) and this work adds `references/core/nexus.md` plus a per-SDK `nexus.md` in each language directory.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `nexus`:

- `docs/encyclopedia/nexus/nexus.mdx` — top-level Nexus overview, services/operations summary, machinery, multi-level calls.
- `docs/encyclopedia/nexus/nexus-services.mdx` — Nexus Services: collections of Operations registered on a Worker that polls a target Task Queue.
- `docs/encyclopedia/nexus/nexus-operations.mdx` — Operation lifecycle (sync/async), automatic retries, timeouts (Schedule-to-Close, Schedule-to-Start, Start-to-Close), circuit breaking, execution semantics, cancelation, termination, versioning, multi-caller attachment.
- `docs/encyclopedia/nexus/nexus-endpoints.mdx` — Endpoints as reverse proxies; deployment via Registry.
- `docs/encyclopedia/nexus/nexus-registry.mdx` — Registry behavior, search/create/edit/delete via UI/CLI/Terraform/Cloud Ops API, roles, target-Namespace change caveats.
- `docs/encyclopedia/nexus/nexus-security.mdx` — Runtime access controls, secure connectivity, payload encryption approaches.
- `docs/encyclopedia/nexus/nexus-patterns.mdx` — Collocated vs router-queue deployment patterns.
- `docs/encyclopedia/nexus/nexus-error-handling.mdx` — Retryable vs non-retryable handler errors; caller-side surfacing.
- `docs/encyclopedia/nexus/nexus-execution-debugging.mdx` — Bi-directional linking, pending Operations, pending callbacks, tracing.
- `docs/encyclopedia/nexus/nexus-metrics.mdx` — SDK, Cloud, OSS metrics.
- `docs/develop/go/nexus/feature-guide.mdx` — Go SDK reference, builders, options, samples.
- `docs/develop/go/nexus/quickstart.mdx` — Go quickstart.
- `docs/develop/python/nexus/feature-guide.mdx` — Python SDK reference: `nexusrpc`, `temporalio.nexus`, decorators.
- `docs/develop/python/nexus/quickstart.mdx` — Python quickstart.
- `docs/develop/java/nexus/feature-guide.mdx` — Java SDK reference: `@Service`, `@OperationImpl`, `WorkflowRunOperation`.
- `docs/develop/java/nexus/quickstart.mdx` — Java quickstart.
- `docs/develop/typescript/nexus/feature-guide.mdx` — TypeScript SDK reference: `nexus-rpc`, `@temporalio/nexus`, `WorkflowRunOperationHandler`.
- `docs/develop/typescript/nexus/quickstart.mdx` — TypeScript quickstart.
- `docs/develop/dotnet/nexus/feature-guide.mdx` — .NET SDK reference: `NexusRpc`, `Temporalio.Nexus`, `WorkflowRunOperationHandler.FromHandleFactory`.
- `docs/develop/dotnet/nexus/quickstart.mdx` — .NET quickstart.
- `docs/cli/operator.mdx` — `temporal operator nexus endpoint` CLI flags.
- `docs/cloud/tcld/nexus.mdx` — `tcld nexus endpoint` CLI flags.
- `docs/cloud/nexus/index.mdx` — Temporal Cloud-specific features (global registry, access controls).
- `docs/cloud/nexus/limits.mdx` — Cloud limits affecting Nexus.
- `docs/cloud/nexus/security.mdx` — Cloud-specific security summary.
- `docs/references/failures.mdx` — Nexus errors and Nexus Operation Failure schema (§"Errors in Nexus Operations", §"Nexus errors", §"Nexus Operation Failure").

**Secondary (only if primary is silent):** none. Topic lives entirely within `documentation/`.

Prefer Read/Grep on a local clone over WebFetch or `gh api`.

**Never trust:** any prior sketches, AI-written outlines, or memory of the Nexus API surface — only what is in the files listed above is authoritative.

---

## 2. Preserve vs. rewrite

(Greenfield — section deleted.)

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, builder/decorator name, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what flags does `temporal operator nexus endpoint create` take?":

1. `Read ../documentation/docs/cli/operator.mdx` §nexus / §create (around lines 341–371).
2. Transcribe only what appears in that file.
3. Record the line number where you found it.

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`temporal operator nexus endpoint create` <!-- docs/cli/operator.mdx:354 -->
```

Use inline comments per claim (one comment per non-obvious factual token). Keep citations to local repo paths (no URLs).

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `--target-ns` from `--target-namespace`. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** Platform concepts ("New-Workflow-Run-Operation") and SDK tokens (`WorkflowRunOperation.fromWorkflowMethod`, `nexus.workflow_run_operation`, `WorkflowRunOperationHandler`, etc.) differ across languages. Document the interface token; name the concept separately.
6. **No flattening of subcommand groups.** `temporal operator nexus endpoint` has its own sub-subcommands (`create`, `delete`, `get`, `list`, `update`). Don't collapse.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so. (E.g., circuit breaker tripping threshold is documented as 5; do not invent.)

### 3.4 Anti-fabrication rules (topic-specific)

- **Don't reuse one SDK's API surface for another.** Go's `temporalnexus.NewWorkflowRunOperation`, Python's `@nexus.workflow_run_operation`, Java's `WorkflowRunOperation.fromWorkflowMethod`, TypeScript's `WorkflowRunOperationHandler`, and .NET's `WorkflowRunOperationHandler.FromHandleFactory` are NOT interchangeable. Each per-SDK file must transcribe from its own feature-guide.
- **Don't conflate `tcld nexus endpoint` with `temporal operator nexus endpoint`.** The flags overlap but are not identical (`tcld` adds `--allow-namespace` and `--resource-version`; `temporal operator` adds `--target-url`). Each lives in a separate docs file.
- **Don't fabricate a `temporal nexus` top-level command.** Endpoint management is under `temporal operator nexus endpoint` (self-hosted) or `tcld nexus endpoint` (Cloud), per `docs/cli/operator.mdx:321` and `docs/cloud/tcld/nexus.mdx:15`.
- **Don't invent cancelation types.** The four documented cancelation types per SDK (Python: `ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`; Java: `ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`; .NET: `Abandon`, `TryCancel`, `WaitCancellationRequested`, `WaitCancellationCompleted`) are language-specific in spelling.
- **Don't claim the circuit breaker is per-Operation.** It is per "destination pair" (caller-Namespace + Endpoint), per `docs/encyclopedia/nexus/nexus-operations.mdx:232`.
- **Don't conflate Schedule-to-Close, Schedule-to-Start, and Start-to-Close.** Only Schedule-to-Close is enforced unconditionally; Schedule-to-Start and Start-to-Close are no-ops if unset/zero and require Server v1.31.0+ (per `docs/encyclopedia/nexus/nexus-operations.mdx:210, 226`).
- **Don't claim the 10s deadline is on the whole sync Operation.** It's the handler request deadline, measured from the caller's Nexus Machinery, per `docs/encyclopedia/nexus/nexus-operations.mdx:75`.
- **Don't invent error type names.** Handler error types are exactly: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`, `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`, per `docs/develop/python/nexus/feature-guide.mdx:335`.
- **Don't conflate retryable vs non-retryable mapping.** `RESOURCE_EXHAUSTED` is documented under "Handler errors" treated as non-retryable in `docs/references/failures.mdx:106`, but as **retryable** in `docs/develop/python/nexus/feature-guide.mdx:335` / `docs/develop/typescript/nexus/feature-guide.mdx:348`. Flag this with a `<!-- VERIFY -->` if it comes up; do not pick one without naming the source.

### 3.5 When the docs are ambiguous or silent

Options in order of preference:

1. Check a secondary authoritative source (e.g., quickstart `.mdx` for the same SDK).
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
3. Do **not** guess. Do **not** synthesize from "this is how it probably works."

Never fabricate to fill a gap.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

The skill mirrors what the docs describe and never invents API mechanics. The end-to-end recipe in `core/nexus.md` chains documented facts; each step must cite its source.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end
Done before editing.

### Step 2: Set up the workspace
Greenfield: add the six new files under existing `references/` subdirectories.

### Step 3: Author each reference file via a subagent
For each file in §5 (in order), spawn a subagent with:
- The single file it owns.
- The docs paths from §1 relevant to that file (listed in §5).
- The full methodology from §3.
- The regression patterns from §8.
- Instructions: "You are writing `FILE_NAME`. Read ONLY the docs paths listed. Do NOT read sibling reference files. Produce one commit. Report: citation count, docs files consulted, `<!-- VERIFY -->` markers raised."

### Step 4: Author SKILL.md
After all reference-file subagents complete, update `SKILL.md` (the orchestrator does this) to add a Nexus entry under "Additional Topics" pointing at `references/core/nexus.md` and the per-SDK `nexus.md` files.

### Step 5: Produce the log
Compose `AUTHORING_LOG.md` from subagent reports.

### What NOT to do
- Do not read or reference any prior conversation or previous version of the skill.
- Do not read the paired validation plan.
- Do not create files outside `references/` and the skill root.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it.

1. **`references/core/nexus.md`** — Cross-SDK Nexus concepts: what Nexus is, Services/Operations/Endpoints/Registry, sync vs async lifecycle, timeouts, retries, circuit breaking, security, patterns, debugging, metrics, CLI for endpoint management, when to use it. Ground truth: `docs/encyclopedia/nexus/*.mdx`, `docs/cli/operator.mdx` (§nexus), `docs/cloud/tcld/nexus.mdx`, `docs/cloud/nexus/index.mdx`, `docs/cloud/nexus/limits.mdx`, `docs/references/failures.mdx` (Nexus sections).
2. **`references/go/nexus.md`** — Go SDK Nexus: `nexus.NewSyncOperation`, `temporalnexus.NewWorkflowRunOperation`, `NexusOperationOptions`, `workflow.NewNexusClient`, Worker registration, cancelation. Ground truth: `docs/develop/go/nexus/feature-guide.mdx`, `docs/develop/go/nexus/quickstart.mdx`.
3. **`references/java/nexus.md`** — Java SDK Nexus: `@Service`, `@ServiceImpl`, `OperationHandler.sync`, `WorkflowRunOperation.fromWorkflowMethod`/`fromWorkflowHandle`, `Workflow.newNexusServiceStub`, cancelation types. Ground truth: `docs/develop/java/nexus/feature-guide.mdx`, `docs/develop/java/nexus/quickstart.mdx`.
4. **`references/python/nexus.md`** — Python SDK Nexus: `@nexusrpc.service`, `@nexusrpc.handler.service_handler`, `@nexusrpc.handler.sync_operation`, `@nexus.workflow_run_operation`, `workflow.create_nexus_client`, exception classes, cancellation types. Ground truth: `docs/develop/python/nexus/feature-guide.mdx`, `docs/develop/python/nexus/quickstart.mdx`.
5. **`references/typescript/nexus.md`** — TypeScript SDK Nexus: `nexus.service`, `nexus.serviceHandler`, `WorkflowRunOperationHandler`, `createNexusServiceClient`, `OpenTelemetryPlugin`, exceptions, cancellation scopes. Ground truth: `docs/develop/typescript/nexus/feature-guide.mdx`, `docs/develop/typescript/nexus/quickstart.mdx`.
6. **`references/dotnet/nexus.md`** — .NET SDK Nexus: `[NexusService]`, `[NexusOperation]`, `[NexusServiceHandler]`, `[NexusOperationHandler]`, `OperationHandler.Sync`, `WorkflowRunOperationHandler.FromHandleFactory`, `Workflow.CreateNexusWorkflowClient`, `NexusWorkflowOperationOptions`, cancellation types. Ground truth: `docs/develop/dotnet/nexus/feature-guide.mdx`, `docs/develop/dotnet/nexus/quickstart.mdx`.
7. **`SKILL.md`** — **last**. Add Nexus to the Additional Topics section with pointers to the new files. (Done by orchestrator after subagents finish.)

Why this order matters: `core/nexus.md` establishes shared concepts (Endpoint, Service, Operation, Machinery, lifecycle, timeouts, retries, circuit breaking) so per-SDK files can refer to them by name without redefining. Per-SDK files don't read each other — they read only their own feature-guide and quickstart so they don't accidentally swap API tokens across languages.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every command string, builder/decorator/attribute name, error string, or API shape appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value (handler error types, cancelation types, etc.) is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file's headings or tables.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers with questions.
- **A git-visible diff** — one commit per reference file plus one for SKILL.md and one for the log.

Do not create files outside `references/` and the skill root.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `temporal nexus endpoint create` | `temporal operator nexus endpoint create` | docs/cli/operator.mdx:354 |
| `--target-task-q` / `--target-tq` / `--tq` | `--target-task-queue` | docs/cli/operator.mdx:369 |
| Cross-SDK API mix-up: using Go's `NewWorkflowRunOperation` in a Python file | Each SDK has its own builder; transcribe from that SDK's feature-guide. | docs/develop/go/nexus/feature-guide.mdx:128, docs/develop/python/nexus/feature-guide.mdx:135, docs/develop/java/nexus/feature-guide.mdx:207, docs/develop/typescript/nexus/feature-guide.mdx:152, docs/develop/dotnet/nexus/feature-guide.mdx:142 |
| Claiming circuit breaker trips after N retries on a single Operation | Trips per caller-Namespace/Endpoint destination pair after 5 consecutive retryable errors. | docs/encyclopedia/nexus/nexus-operations.mdx:232 |
| Saying sync Operations have a "10-second timeout" | Sync Operations must complete within the 10-second handler request deadline, measured from the caller's Nexus Machinery. | docs/encyclopedia/nexus/nexus-operations.mdx:75 |
| Stating async Operations have unlimited duration | Max Schedule-to-Close in Temporal Cloud is 60 days. | docs/encyclopedia/nexus/nexus-operations.mdx:110 |
| Calling endpoints "general-purpose proxies" | Endpoints are reverse proxies for a single Nexus Service, single target Namespace/Task Queue. | docs/encyclopedia/nexus/nexus-endpoints.mdx:34 |
| Saying endpoints accept callers from the same Namespace by default | No callers are allowed by default; an Access Policy allowlist is required. | docs/encyclopedia/nexus/nexus-registry.mdx:66 |
| Listing Schedule-to-Start as always available | Requires Temporal Server v1.31.0 or later. | docs/encyclopedia/nexus/nexus-operations.mdx:210 |
| Claiming Nexus Operations support multiple input parameters | A Nexus Operation can only take one input parameter; multi-arg Workflows use SDK-specific helpers. | docs/develop/go/nexus/feature-guide.mdx:231 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- A Nexus Endpoint is a reverse proxy that routes requests from a caller Workflow to a target Namespace and Task Queue (`docs/encyclopedia/nexus/nexus-endpoints.mdx:25`).
- Nexus is GA on Temporal Cloud and self-hosted (`docs/encyclopedia/nexus/nexus.mdx:21`).
- Sync handler deadline is 10 seconds, measured from the caller's Nexus Machinery (`docs/encyclopedia/nexus/nexus-operations.mdx:75`).
- Max Schedule-to-Close for async Operations is 60 days in Temporal Cloud (`docs/encyclopedia/nexus/nexus-operations.mdx:110`).
- Circuit breaker trips after 5 consecutive retryable errors per caller-Namespace/Endpoint destination pair; transitions through open (60s) → half-open (single probe) → closed (`docs/encyclopedia/nexus/nexus-operations.mdx:232–239`).
- Two deployment patterns: collocated (default) and router-queue (`docs/encyclopedia/nexus/nexus-patterns.mdx:26–30`).
- `temporal operator nexus endpoint create --name … --target-namespace … --target-task-queue …` (`docs/cli/operator.mdx:354`).
- `tcld nexus endpoint create --name … --target-namespace … --target-task-queue … --allow-namespace …` (`docs/cloud/tcld/nexus.mdx:147–197`).
- Endpoint Access Policy: no callers allowed by default (`docs/encyclopedia/nexus/nexus-registry.mdx:66`).
- Operations can be sync (Signals/Queries/Updates/reliable code) or async (Workflow-backed, with attached completion callback) (`docs/encyclopedia/nexus/nexus.mdx:60–63`).
- Non-retryable handler error types: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`. Retryable types: `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT` (`docs/develop/python/nexus/feature-guide.mdx:335`).
- Cloud caps: 100 Endpoints per Account, 30 in-flight Operations per Workflow, 2000 callbacks per Workflow (`docs/cloud/nexus/limits.mdx:31–35`).
- Go builder: `temporalnexus.NewWorkflowRunOperation` (`docs/develop/go/nexus/feature-guide.mdx:128`).
- Python decorator: `@nexus.workflow_run_operation` (`docs/develop/python/nexus/feature-guide.mdx:135`).
- Java builder: `WorkflowRunOperation.fromWorkflowMethod` (`docs/develop/java/nexus/feature-guide.mdx:207`).
- TypeScript builder: `WorkflowRunOperationHandler` (`docs/develop/typescript/nexus/feature-guide.mdx:153`).
- .NET builder: `WorkflowRunOperationHandler.FromHandleFactory` (`docs/develop/dotnet/nexus/feature-guide.mdx:142`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema.
- **Do not expand scope.** Don't pull in topics that belong in `versioning.md`, `error-handling.md`, etc. — reference them.
- **Do not paraphrase docs prose verbatim.** Cite, don't copy.
- **Do not write tests, CI, or tooling.**
- **Do not add meta-docs** unless the user asks.

## 11. Sibling handoff

This Nexus content sits alongside the rest of the `temporal-developer` skill:

- `references/core/error-reference.md` — Generic Workflow/Activity error semantics. Nexus error coverage in `references/core/nexus.md` cross-references it, doesn't duplicate it.
- `references/core/troubleshooting.md` — General troubleshooting trees. Nexus-specific debugging (pending Operations, callbacks, circuit breaker open) lives in `references/core/nexus.md` and links to the troubleshooting file.
- `references/{lang}/observability.md` — General per-SDK observability. Nexus SDK metrics are mentioned briefly in `core/nexus.md` with a pointer.

Handoff disciplines:

1. When this skill prescribes a command documented elsewhere, spell out the full invocation but cite the canonical docs file.
2. When a topic belongs to a sibling reference, cross-reference it, don't absorb it.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan, trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
