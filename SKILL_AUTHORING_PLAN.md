# Skill Authoring Plan — `lambda-workers`

**Mode:** greenfield

**Context:** The Go, Python, and TypeScript SDKs ship pre-release packages (`go.temporal.io/sdk/contrib/aws/lambdaworker`, `temporalio.contrib.aws.lambda_worker`, `@temporalio/lambda-worker`) that let you run a Temporal Serverless Worker as an AWS Lambda function. This skill adds reference material so a developer using `skill-temporal-developer` can scaffold a Lambda-hosted Worker, configure Lambda-tuned defaults, wire up OpenTelemetry through the ADOT Lambda layer, and deploy with a Worker Deployment Version + compute provider. Sibling skills: `skill-temporal-cli` (worker deployment subcommands), `skill-temporal-triage` (live workflow debugging). Audience is the same as the parent skill: developers already writing Temporal Workflows/Activities who now want to host the Worker on Lambda.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths for `lambda-workers`:

- `docs/develop/go/workers/serverless-workers/aws-lambda.mdx` — Go SDK `lambdaworker` package: `RunWorker`, `Options`, Lambda-tuned defaults, OTel sub-package.
- `docs/develop/python/workers/serverless-workers/aws-lambda.mdx` — Python SDK `lambda_worker` contrib: `run_worker`, `LambdaWorkerConfig`, Lambda-tuned defaults, OTel module.
- `docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx` — TypeScript SDK `@temporalio/lambda-worker`: `runWorker`, configure callback, `workflowBundle` pre-bundling, OTel module.
- `docs/develop/go/workers/serverless-workers/index.mdx` — Go SDK serverless overview / package pointer.
- `docs/encyclopedia/workers/serverless-workers.mdx` — concept page: WCI, autoscaling, worker lifecycle (init/work/shutdown), failure handling, constraints, compute providers.
- `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` — end-to-end deploy guide: code → package → `aws lambda create-function` → CloudFormation IAM → `temporal worker deployment create-version` → set current → verify.
- `docs/production-deployment/worker-deployments/serverless-workers/index.mdx` — supported providers overview.
- `docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx` — self-hosted prerequisites: dynamic config keys, AWS credentials, self-hosted CloudFormation template.
- `docs/evaluate/development-production-features/serverless-workers/index.mdx` — evaluation framing: when to use, when not to use, comparison table.
- `docs/troubleshooting/serverless-workers.mdx` — invocation-flow troubleshooting decision tree.

**Secondary (only if primary is silent):** none. The topic lives entirely in `documentation/`. Do **not** reach out to upstream SDK repos for API shapes — if a token isn't in `docs/`, flag it `<!-- VERIFY -->` rather than guessing.

Prefer Read/Grep on a local clone over WebFetch or `gh api`.

**Never trust:** any prior sketches, model memory of Lambda runtime ABIs, or SDK names "as you'd expect" (e.g. don't assume the Go package is `lambda` — it's `lambdaworker`; don't assume the TypeScript package is `@temporalio/aws-lambda`).

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a package import path, function name, option/field name, env var, default value, runtime string, or CLI flag, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what is the Python contrib package import path?":

1. `Read ../documentation/docs/develop/python/workers/serverless-workers/aws-lambda.mdx` § Create and run a Worker in Lambda.
2. Transcribe only what appears in that file: `from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker`.
3. Record the line number where you found it (e.g. `docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48`).

### 3.2 Citation/provenance format

Every reference file must carry inline provenance. Use HTML comments so the rendered page stays clean:

```markdown
`from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 -->
```

Convention: one inline comment per fact-bearing claim (command, identifier, default, runtime name). For long tables of defaults, a single `<!-- Sources: … -->` footer pointing at the docs table is acceptable.

### 3.3 Anti-fabrication rules (generic)

1. **No "probably exists" commands/subcommands.** If it's not in the docs, it doesn't exist.
2. **No "probably accepts" enum values.** Only list enum values present in the docs.
3. **No "probably named" env vars, flags, or fields.** Transcribe from the authoritative table.
4. **No inferred flag names.** Don't derive `--aws-lambda-role-arn` from "the role arn flag should be" — the actual flag is `--aws-lambda-assume-role-arn`.
5. **No conflating concept with interface.** "Worker Versioning" is the platform concept; `WorkerDeploymentVersion` (Go), `WorkerDeploymentVersion` (Python), and `{ deploymentName, buildId }` (TypeScript) are the SDK interfaces.
6. **No flattening of subcommand groups.** `temporal worker deployment create` and `temporal worker deployment create-version` are distinct.
7. **No assumed defaults.** Don't write "default: X" unless the docs say so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Package names differ across SDKs.** Go: `go.temporal.io/sdk/contrib/aws/lambdaworker` (and `…/otel` sub-package). Python: `temporalio.contrib.aws.lambda_worker` (and `.otel` module). TypeScript: `@temporalio/lambda-worker` (and `@temporalio/lambda-worker/otel`). Do not unify the spelling.
- **Entry-point function names differ.** Go: `lambdaworker.RunWorker`. Python: `run_worker` (returns a handler). TypeScript: `runWorker` (returns a handler). The Python and TS forms return a Lambda handler value; the Go form is invoked from `main()` and does not return a handler.
- **Default-value tables differ across SDKs** — do not copy a Go default into Python prose, etc. In particular:
  - Sticky/workflow cache is `Sticky cache size: 100` in Go but `max_cached_workflows: 30` / `maxCachedWorkflows: 30` in Python and TypeScript. Do **not** harmonize.
  - The shutdown-buffer field is `ShutdownDeadlineBuffer` (Go), `shutdown_deadline_buffer` (Python), and `shutdownDeadlineBufferMs` (TypeScript, milliseconds).
  - The poller-behavior fields are named distinctly: Go uses `MaxConcurrentActivityTaskPollers` / `MaxConcurrentWorkflowTaskPollers` / `MaxConcurrentNexusTaskPollers`; Python and TypeScript use `..._poller_behavior` / `…TaskPollerBehavior` with a `SimpleMaximum(N)` value.
- **Eager Activities are always disabled, but the field name differs.** Go: `DisableEagerActivities: true`. Python: `disable_eager_activity_execution: True`. TypeScript: "Eager Activities are not supported." Do not invent a TypeScript field name — the TS doc states the behavior in prose only.
- **OTel env var spelling differs.** Go and TS docs use `OPENTELEMETRY_COLLECTOR_CONFIG_URI`; the Python doc uses `OPENTELEMETRY_COLLECTOR_CONFIG_FILE`. Don't unify.
- **Versioning behavior names are SDK-cased.** Go: `AutoUpgrade`, `Pinned` (and constants like `workflow.VersioningBehaviorPinned`). Python: `PINNED`, `AUTO_UPGRADE` (`VersioningBehavior.PINNED`). TypeScript: `'AUTO_UPGRADE'`, `'PINNED'` (string literal) with a default of `PINNED`. Do not translate one to another.
- **The `temporal` CLI flags for AWS Lambda compute provider** are `--aws-lambda-function-arn`, `--aws-lambda-assume-role-arn`, `--aws-lambda-assume-role-external-id`. Don't invent variants. The deployment-name/build-id flags are `--deployment-name` and `--build-id`.
- **Runtime strings are specific.** Go uses `provided.al2023` with handler name `bootstrap`. Python uses `python3.13` (or another supported version) with `module.function` form. TypeScript uses `nodejs22.x` (or 20+) with `module.export` form. Don't substitute one runtime string for another.
- **Pre-release status.** Every SDK doc opens with a "Pre-release" admonition. The skill should surface this rather than describe the feature as GA.
- **Lambda invocation limit is 15 minutes.** This is from `docs/encyclopedia/workers/serverless-workers.mdx`. Do not write "an hour" or extrapolate from other Lambda features.

### 3.5 When the docs are ambiguous or silent

1. Check a secondary authoritative section in the same `documentation/` clone (e.g., link from `develop/...` to `encyclopedia/...`).
2. Note the ambiguity in a `<!-- VERIFY: … -->` comment and leave the claim out of the prose.
3. Do **not** guess.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

The deploy-guide page (`docs/production-deployment/.../aws-lambda.mdx`) is the canonical prescribed flow. Reference recipes must chain its steps in order and cite each. Do not invent new orderings, scripts, or "best practices" not present in the docs.

---

## 4. Execution

Use an **orchestrator + per-file subagent** shape.

### Step 1: Read this plan end-to-end

Already done by the orchestrator.

### Step 2: Set up the workspace

Greenfield. Create five new files under the skill root:

- `references/core/lambda-workers.md`
- `references/go/lambda-workers.md`
- `references/python/lambda-workers.md`
- `references/typescript/lambda-workers.md`
- update `SKILL.md` to point at `references/core/lambda-workers.md`

### Step 3: Author each reference file via a subagent

Spawn one subagent per file. Each subagent receives: the file it owns, the docs paths from §1 it may read, the full methodology from §3, the regression table from §8, and instructions to produce a single file (no cross-reading of sibling reference files).

### Step 4: Author SKILL.md

The orchestrator (not a subagent) edits `SKILL.md` to add a "Lambda Workers (AWS) — Pre-release" section pointing at the new references.

### Step 5: Produce the log

Compose `AUTHORING_LOG.md` from subagent reports.

### What NOT to do

- Do not create files outside `references/` and the skill root.
- Do not write tutorials, CONTRIBUTING, or CHANGELOG files.
- Do not paraphrase entire docs sections — cite and synthesize.

---

## 5. Per-file execution order

Work in this order. Each file's correctness depends on the files above it — shared concepts are established once in `core/` and inherited.

1. **`references/core/lambda-workers.md`** — concept & deploy framing: what a Serverless Worker is, WCI, invocation flow, lifecycle phases (init/work/shutdown), tuning for long-running Activities, constraints (15-min invocation limit, versioning required), failure modes, the six-step deploy flow (write → package → `aws lambda create-function` → CloudFormation IAM → `temporal worker deployment create-version` → set current → verify), troubleshooting decision tree, self-hosted prerequisites at a high level. SDK-agnostic. Ground truth: `docs/encyclopedia/workers/serverless-workers.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/index.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx`, `docs/troubleshooting/serverless-workers.mdx`, `docs/evaluate/development-production-features/serverless-workers/index.mdx`.

2. **`references/go/lambda-workers.md`** — Go SDK: `go.temporal.io/sdk/contrib/aws/lambdaworker` package, `RunWorker(WorkerDeploymentVersion, func(*Options) error)`, registration methods, Lambda-tuned defaults table, OTel via `lambdaworker/otel` (`ApplyDefaults`, `ApplyMetrics`, `ApplyTracing`), build/package (`GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap`), runtime `provided.al2023` / handler `bootstrap`. Ground truth: `docs/develop/go/workers/serverless-workers/aws-lambda.mdx`, `docs/develop/go/workers/serverless-workers/index.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` (Go tabs only).

3. **`references/python/lambda-workers.md`** — Python SDK: `temporalio.contrib.aws.lambda_worker` (`run_worker`, `LambdaWorkerConfig`), `configure(config)` callback that sets `config.worker_config["task_queue"|"workflows"|"activities"]`, Lambda-tuned defaults table, OTel via `temporalio.contrib.aws.lambda_worker.otel.apply_defaults` (and `build_metrics_telemetry_config` / `apply_tracing`), packaging (`pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: temporalio`, `temporalio[lambda-worker-otel]` extra), runtime `python3.13`. Ground truth: `docs/develop/python/workers/serverless-workers/aws-lambda.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` (Python tabs only).

4. **`references/typescript/lambda-workers.md`** — TypeScript SDK: `@temporalio/lambda-worker` (`runWorker`, configure callback), `workflowBundle` pre-bundling rationale (avoid webpack on cold start), default `defaultVersioningBehavior = 'PINNED'`, Lambda-tuned defaults table, OTel via `@temporalio/lambda-worker/otel` (`applyDefaults`, `makeOtelPlugin` when pre-bundling), packaging (`ts-node build-workflow-bundle.ts && tsc && npm install --omit=dev && zip`), runtime `nodejs22.x`. Ground truth: `docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx`, `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` (TypeScript tabs only).

5. **`SKILL.md`** — **last**. Add an "AWS Lambda Workers (Pre-release)" section that:
   - Surfaces the pre-release admonition.
   - Lists the three SDK packages (one line each).
   - Points the reader at `references/core/lambda-workers.md` for the concept + deploy flow, then at `references/{language}/lambda-workers.md` for SDK-specific setup.
   - Calls out that Worker Versioning is required and that each Workflow must declare a versioning behavior.

Why this order matters: the concept page (`core/`) establishes terms (WCI, compute provider, Worker Deployment Version, lifecycle phases, shutdown deadline buffer). Each SDK page reuses those terms without re-defining them, so authoring `core/` first prevents drift between SDK files. The deploy flow appears in `core/` once and each SDK file links to it for the cross-SDK steps (CloudFormation, deployment-version creation).

---

## 6. Per-file done criteria

A reference file is done when:

1. Every package import path, command string, field name, default value, env var, runtime string, or CLI flag appears verbatim in the docs (or has a `<!-- VERIFY -->` marker with a specific question).
2. Every name/token has a citation comment.
3. Every enum value (e.g., `AUTO_UPGRADE`, `PINNED`) is traceable to a docs file.
4. No subcommand / field / enum appears that isn't in the relevant `docs/` file.
5. A self-check Grep of the file finds zero instances of the regression patterns listed in §8.
6. The pre-release admonition is surfaced at least once (matching what the docs do for every Serverless Workers page).

---

## 7. Deliverables

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, docs files consulted, total citation count, `<!-- VERIFY -->` markers and the questions they raise.
- **A git-visible diff** — one commit per reference file plus a SKILL.md commit.

No files outside `references/` and the skill root.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| `@temporalio/aws-lambda` (TS package) | `@temporalio/lambda-worker` | docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:46 |
| `temporalio.aws.lambda` (Py import) | `temporalio.contrib.aws.lambda_worker` | docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 |
| `go.temporal.io/sdk/contrib/lambda` (Go import) | `go.temporal.io/sdk/contrib/aws/lambdaworker` | docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51 |
| `lambdaworker.Run` / `lambdaworker.Start` | `lambdaworker.RunWorker` | docs/develop/go/workers/serverless-workers/aws-lambda.mdx:58 |
| `start_worker` (Python entry point) | `run_worker` | docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 |
| `createWorker` / `startWorker` (TS) | `runWorker` | docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:46 |
| `shutdownDeadlineBuffer` (TS field, seconds) | `shutdownDeadlineBufferMs` (milliseconds) | docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:116 |
| Sticky cache size 30 (Go) | Sticky cache size 100 (Go); 30 only applies to Python/TS `max_cached_workflows` / `maxCachedWorkflows` | docs/develop/go/workers/serverless-workers/aws-lambda.mdx:115; docs/develop/python/...:119; docs/develop/typescript/...:115 |
| Setting `DisableEagerActivities` to false on Go | Always `true`, cannot be overridden | docs/develop/go/workers/serverless-workers/aws-lambda.mdx:118 |
| `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` for Go/TS | `OPENTELEMETRY_COLLECTOR_CONFIG_URI` for Go and TS; `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` only for Python | docs/develop/go/...:227; docs/develop/typescript/...:210; docs/develop/python/...:219 |
| `--aws-lambda-role-arn` / `--lambda-role-arn` | `--aws-lambda-assume-role-arn` | docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:549 |
| `temporal worker deployment create-current-version` | `temporal worker deployment set-current-version` | docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:576 |
| Lambda runtime `go1.x` | `provided.al2023` with handler `bootstrap` | docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:255–267 |
| Lambda runtime `nodejs18.x` (only) | `nodejs22.x` (or another supported Node.js version 20+) | docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:296,308 |
| Worker is invoked over HTTPS by Temporal | Temporal assumes an IAM role and calls `lambda:InvokeFunction` | docs/encyclopedia/workers/serverless-workers.mdx:73; docs/production-deployment/.../aws-lambda.mdx:359 |
| Lambda invocation limit of 1 hour or longer | 15 minutes | docs/encyclopedia/workers/serverless-workers.mdx:243; docs/evaluate/.../index.mdx:91 |
| Eager Activities can be re-enabled with a flag | Always disabled; the docs state this is not overridable for Go and Python, and "not supported" for TS | docs/develop/go/...:118; docs/develop/python/...:123; docs/develop/typescript/...:118 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- Go package import: `lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"` (`docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51`).
- Go entry point: `lambdaworker.RunWorker(worker.WorkerDeploymentVersion{...}, func(opts *lambdaworker.Options) error {...})` (`docs/develop/go/workers/serverless-workers/aws-lambda.mdx:58-72`).
- Python entry point: `lambda_handler = run_worker(WorkerDeploymentVersion(deployment_name="my-app", build_id="build-1"), configure)` (`docs/develop/python/workers/serverless-workers/aws-lambda.mdx:60-63`).
- Python config field setters: `config.worker_config["task_queue"|"workflows"|"activities"]` (`docs/develop/python/workers/serverless-workers/aws-lambda.mdx:54-56`).
- TypeScript entry point: `export const handler = runWorker({ deploymentName: 'sdk-demo', buildId: 'v1' }, (config) => {...})` (`docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:51-58`).
- TypeScript default versioning behavior is `PINNED` (`docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:65`).
- Config file resolution order is `TEMPORAL_CONFIG_FILE` env, then `temporal.toml` in `$LAMBDA_TASK_ROOT`, then cwd (`docs/develop/go/...:88-92`, `docs/develop/python/...:94-98`, `docs/develop/typescript/...:90-94`).
- Lambda invocation limit (concept): 15 minutes (`docs/encyclopedia/workers/serverless-workers.mdx:243`).
- Go shutdown buffer default: `WorkerStopTimeout + 2 seconds` (`docs/develop/go/workers/serverless-workers/aws-lambda.mdx:123`).
- TypeScript shutdown buffer default: `shutdownGraceTime (5s) + 2s` (`docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:122`).
- CLI flag for compute provider: `--aws-lambda-function-arn`, `--aws-lambda-assume-role-arn`, `--aws-lambda-assume-role-external-id` (`docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:547-559`).
- WCI workflow ID pattern: `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>` (`docs/encyclopedia/workers/serverless-workers.mdx:84`).
- Self-hosted dynamic config keys: `workercontroller.enabled`, `workercontroller.compute_providers.enabled`, `workercontroller.scaling_algorithms.enabled` (`docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:58-69`).
- Self-hosted Temporal Service requirement: v1.31.0 or later (`docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:29`).

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as dictated by this plan.
- **Do not expand scope.** Java and .NET are out of scope (no SDK packages exist yet per the docs). Cloud Run and other future providers are out of scope.
- **Do not paraphrase docs prose verbatim.** Cite, synthesize, point.
- **Do not write tests, CI, or tooling.**
- **Do not invent SDK features.** If a token isn't in `docs/`, mark `<!-- VERIFY -->`.

## 11. Sibling handoff

This skill sits alongside:

- `skill-temporal-cli` — covers `temporal worker deployment` subcommands in general.
- `skill-temporal-triage` — covers live debugging of stuck workflows.

Handoff disciplines:

1. When this skill prescribes `temporal worker deployment create-version` with AWS-Lambda-specific flags, spell out the full invocation but cite the canonical docs file (`docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx`), not the sibling skill.
2. When debugging a stuck Workflow on a Lambda Worker, follow the troubleshooting tree in `references/core/lambda-workers.md` for invocation-specific checks, then hand off to `skill-temporal-triage` for Workflow-level debugging.

---

## 12. If you get stuck

- If a fact has no docs backing, delete it or mark it `<!-- VERIFY -->`.
- If a whole section has no docs backing, delete the section and note it in `AUTHORING_LOG.md`.
- If the docs contradict this plan, trust the docs and flag the conflict in `AUTHORING_LOG.md`.

End of plan.
