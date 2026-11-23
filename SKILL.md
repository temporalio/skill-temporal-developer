---
name: temporal-developer
description: Develop, debug, and manage Temporal applications across Python, TypeScript, Go, Java, .NET, PHP, Ruby, and Rust. Use when the user is building workflows, activities, workers, or background job queues with a Temporal SDK, debugging issues like non-determinism errors, stuck workflows, or activity retries, using Temporal CLI, Temporal Server, or Temporal Cloud, running Temporal with Docker Compose, instrumenting Workers and Clients (metrics export, tracing, logging, Worker heartbeat settings), using Nexus, or working with durable execution concepts like signals, queries, heartbeats, versioning, continue-as-new, child workflows, or saga patterns. Also use when the user mentions "run a Temporal workflow from the CLI", "start a dev server", "run temporal server start-dev", "temporal workflow start", "temporal workflow execute", "temporal workflow signal", "temporal workflow query", "temporal workflow update". Not for metric queries or alerts (temporal-observability) or serverless Workers (temporal-serverless).
---

# Skill: temporal-developer

## Overview

Temporal is a durable execution platform that makes workflows survive failures automatically. This skill provides guidance for building Temporal applications in Python, TypeScript, Go, Java, .NET, PHP, Ruby, and Rust.

## Out of Scope

- **Operational CLI commands** such as batch operations, health queries, Cloud administration, `tcld`, and scripting → use the [temporal-ops skill](https://github.com/temporalio/skill-temporal-ops).
- **Serverless Workers**, including deployment, troubleshooting, and the packages `temporalio.contrib.aws.lambda_worker`, `temporalio.contrib.gcp.cloud_run`, `go.temporal.io/sdk/contrib/aws/lambdaworker`, and `go.temporal.io/sdk/contrib/gcp/cloudrun` with their OpenTelemetry helpers → use the [temporal-serverless skill](https://github.com/temporalio/skill-temporal-serverless). Changes to those packages belong to that skill, not this one.
- **First-time Temporal Cloud setup** including a Namespace, API key, sample app, and first Workflow → use the [temporal-cloud-setup skill](https://github.com/temporalio/skill-temporal-cloud-setup).
- **Monitoring Temporal**, including the Temporal Cloud metrics endpoint, self-hosted Temporal Service monitoring, metric queries, dashboards, alerts, what each SDK metric means, and the documentation under `docs/cloud/metrics/` and `docs/production-deployment/cloud/metrics/` → use the [temporal-observability skill](https://github.com/temporalio/skill-temporal-observability).

If a task shifts into one of these areas, follow the relevant skill. Local development and developer-facing Workflow CLI commands remain covered here.

## Observability scope

This skill covers emitting and configuring telemetry in Worker and Client code: SDK metrics exporters, custom metrics, tracing plugins such as `contrib/opentelemetry`, logging, and Worker heartbeat settings, as documented under `docs/develop/<language>/observability.mdx`. Out of Scope lists the observability tasks other skills own.

## Core Architecture

The **Temporal Cluster** is the central orchestration backend. It maintains three key subsystems: the **Event History** (a durable log of all workflow state), **Task Queues** (which route work to the right workers), and a **Visibility** store (for searching and listing workflows). There are three ways to run a Cluster:

- **Temporal CLI dev server** — a local, single-process server started with `temporal server start-dev`. Suitable for development and testing only, not production.
- **Self-hosted** — you deploy and manage the Temporal server and its dependencies (e.g., database) in your own infrastructure for production use.
- **Temporal Cloud** — a fully managed production service operated by Temporal. No cluster infrastructure to manage.

**Workers** are long-running processes that you run and manage. They poll Task Queues for work and execute your code. You might run a single Worker process on one machine during development, or run many Worker processes across a large fleet of machines in production. Each Worker hosts two types of code:

- **Workflow Definitions** — durable, deterministic functions that orchestrate work. These must not have side effects.
- **Activity Implementations** — non-deterministic operations (API calls, file I/O, etc.) that can fail and be retried.

Workers communicate with the Cluster via a poll/complete loop: they poll a Task Queue for tasks, execute the corresponding Workflow or Activity code, and report results back.

## History Replay: Why Determinism Matters

Temporal achieves durability through **history replay**:

1. **Initial Execution** - Worker runs workflow, generates Commands, stored as Events in history
2. **Recovery** - On restart/failure, Worker re-executes workflow from beginning
3. **Matching** - SDK compares generated Commands against stored Events
4. **Restoration** - Uses stored Activity results instead of re-executing

**If Commands don't match Events = Non-determinism Error = Workflow blocked**

See [Commands and Events](references/core/determinism.md#commands-and-events) for a table showing how Workflow actions are recorded in Event History.

## Choose References for the Task

Identify the SDK language and the developer's task. Read the relevant core reference in the section below and its language-specific counterpart when available. Load additional references only as the task requires.

For a new project, a first implementation, or broad SDK guidance, read the appropriate SDK guide:

- Python -> [Python SDK guide](references/python/python.md)
- TypeScript -> [TypeScript SDK guide](references/typescript/typescript.md)
- Go -> [Go SDK guide](references/go/go.md)
- Java -> [Java SDK guide](references/java/java.md)
- .NET (C#) -> [.NET SDK guide](references/dotnet/dotnet.md)
- PHP -> [PHP SDK guide](references/php/php.md)
- Ruby -> [Ruby SDK guide](references/ruby/ruby.md)
- Rust -> [Rust SDK guide](references/rust/rust.md) (skill support in Public Preview)

For tasks that use Temporal CLI or start a local dev server, check whether `temporal` is installed before using it. If it is missing, follow the [Temporal CLI installation guide](references/core/install_cli.md).

## Primary References

- **[Temporal determinism rules](references/core/determinism.md)** - Why determinism matters, replay mechanics, basic concepts of activities
  - Language-specific info at `references/{your_language}/determinism.md`
- **Temporal workflow determinism protection** - SDK safeguards, analyzers, runtime checks, and their limits
  - Language-specific info at `references/{your_language}/determinism-protection.md`
- **[Temporal workflow patterns](references/core/patterns.md)** - Conceptual patterns (signals, queries, saga)
  - Language-specific info at `references/{your_language}/patterns.md`
- **[Temporal common pitfalls](references/core/gotchas.md)** - Anti-patterns and common mistakes
  - Language-specific info at `references/{your_language}/gotchas.md`
- **[Temporal versioning guide](references/core/versioning.md)** - Versioning strategies and concepts - how to safely change workflow code while workflows are running
  - Language-specific info at `references/{your_language}/versioning.md`
- **[Temporal standalone Activities guide](references/core/standalone-activities.md)** - Standalone Activities (GA): run an Activity directly from a Client without a Workflow — Temporal's job queue
  - Language-specific info at `references/{your_language}/standalone-activities.md` (not available for PHP); for Rust, see the [Rust SDK guide](references/rust/rust.md#standalone-activities)
- **[Temporal Task Queue priority and fairness guide](references/core/priority-fairness.md)** - Task Queue Priority and Fairness concepts, configuration, and limitations
  - Language-specific info at `references/{your_language}/priority-fairness.md`
- **[Temporal Workflow random streams guide](references/core/random-streams.md)** - SDK-provided named deterministic random streams for Workflow code, plugins, and interceptors
  - Language-specific info at `references/{your_language}/random-streams.md` (Go and TypeScript)
- **[Temporal troubleshooting guide](references/core/troubleshooting.md)** - Decision trees, recovery procedures
- **[gRPC transport compression](references/core/transport-compression.md)** - Connection defaults and SDK-specific opt-out settings
- **[Temporal error reference](references/core/error-reference.md)** - Common error types, workflow status reference
- **[Temporal interactive workflow guide](references/core/interactive-workflows.md)** - Testing signals, updates, queries
- **[Temporal development management guide](references/core/dev-management.md)** - Dev cycle & management of server and workers
- **[Temporal Docker Compose guide](references/core/docker-compose.md)** - Local Docker/Podman setup; default to the CLI dev server and check the [server management criteria](references/core/dev-management.md#server-management) before choosing Compose
- **[Temporal CLI workflow command guide](references/core/cli-workflow-commands.md)** - Developer-facing CLI commands for workflow interaction (start, execute, signal, query, update, cancel)
- **[Temporal AI integration patterns](references/core/ai-patterns.md)** - AI/LLM pattern concepts
  - Language-specific info at `references/{your_language}/ai-patterns.md`, if available. Currently Python only.

- **[Temporal Nexus guide](references/core/nexus.md)** - Nexus: cross-namespace service contracts, operations, endpoints
  - SDK implementation: [Go](references/go/nexus.md), [Java](references/java/nexus.md), [Python](references/python/nexus.md), [TypeScript](references/typescript/nexus.md), [.NET](references/dotnet/nexus.md)

## Task Queue Priority

Consider **Priority** when some work should be dispatched ahead of other work sharing a Task Queue—for example, online requests ahead of offline batch jobs. See the [Priority guide](references/core/priority-fairness.md#priority).

## Task Queue Fairness

Consider **Fairness** when customers, tenants, or workloads share a Task Queue and one group’s backlog could delay others. This includes noisy neighbor problems, sharing capacity across tenants or tiers, and preventing a high-volume job type or source from dominating a queue. See the [Fairness guide](references/core/priority-fairness.md#fairness).

## Job Queues and Background Jobs

**Temporal's job queue is Standalone Activities.** When the developer asks for a job queue, background or async jobs, a work queue, or whether Temporal can replace Celery, Sidekiq, BullMQ, Resque, Hangfire, or SQS-plus-workers, build it with a Standalone Activity — not a Workflow wrapping a single Activity, and not a dispatcher Workflow that receives jobs by Signal. PHP has no released Standalone Activity support. For PHP, use the fallback in the [Temporal job queue guide](references/core/job-queue.md).

Temporal **Task Queues** are the routing mechanism Workers poll, not a queue that producers push jobs into. Do not answer a job queue question by describing Temporal Task Queues.

When a developer says "task queue" they may mean "job queue": Celery, Dramatiq, Huey, and Asynq all use Task nomenclature, while Sidekiq, Hangfire, BullMQ, Resque, RQ, and Faktory use Job. Read "can I use Temporal as a task queue?" as a job queue question, and reserve Temporal's Task Queue meaning for your own reply.

- **[Temporal job queue guide](references/core/job-queue.md)** - Job-queue vocabulary mapped to Temporal, migrating off an existing job queue, anti-patterns, and per-language SDK guides and runnable samples

## Additional Topics

- **`references/{your_language}/observability.md`** - Instrumenting Workers and Clients: replay-safe logging, SDK metrics export and custom metrics, tracing, Worker heartbeat settings, and Search Attributes
  - OpenTelemetry plugins: `references/{your_language}/integrations/opentelemetry.md` (Go, Python, TypeScript); other SDKs cover tracing in `observability.md`
  - Rust: the Observability section of `references/rust/rust.md`
- **`references/{your_language}/advanced-features.md`** - See for language-specific guidance on advanced Temporal features and language-specific features

## Third-Party Integrations

For Temporal plugins and integrations with third-party frameworks and SDKs (Claude Agent SDK, OpenAI Agents SDK, OpenAI Codex SDK, Google ADK, LangGraph, DeepAgents, etc.), see the **[integrations catalog](references/core/integrations.md)** for supported languages, what each integration does, and local references or upstream guides.

## Feedback

### Reporting Issues in This Skill

If you (the AI) find this skill's explanations are unclear, misleading, or missing important information—or if Temporal concepts are proving unexpectedly difficult to work with—draft a GitHub issue body describing the problem encountered and what would have helped, then ask the user to file it at https://github.com/temporalio/skill-temporal-developer/issues/new. Do not file the issue autonomously.
