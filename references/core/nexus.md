# Temporal Nexus

Nexus connects Temporal Applications across (and within) isolated Namespaces.  Each team exposes a clean service contract through a **Nexus Endpoint**; callers reference an Endpoint by name and never need to know the handler's Namespace, Task Queue, or internal implementation.

Nexus is peer-to-peer, not hierarchical: caller and handler Workflows are siblings that communicate across Namespace boundaries.

**Support status (as of these docs):** Temporal Nexus is **Generally Available** for Temporal Cloud and self-hosted deployments.  SDK support:

- Go, Java, Python — **Generally Available**.
- TypeScript, .NET — **Public Preview**.

> Language-specific code and SDK tokens live in `references/{your_language}/nexus.md`. This file covers concepts shared across all five SDKs.

---

## Building blocks

### Nexus Services

A **Nexus Service** is a named collection of Nexus Operations that a team exposes as a contract for sharing across team boundaries.  Services are registered in a Worker that polls the Endpoint's target Task Queue; multiple Services can run in the same Worker, and they typically run alongside the Workflows they abstract (or in a dedicated router Worker — see [Patterns](#deployment-patterns)).  Callers reference a Service by name when executing an Operation.

### Nexus Operations

Operations abstract the underlying implementation. Callers don't need to know whether an Operation starts a Workflow, sends a Signal, runs a Query, or executes other reliable code.  Two builder-function flavors:

- **New-Workflow-Run-Operation** — start a Workflow as an **asynchronous** Operation.
- **New-Sync-Operation** — run a **synchronous** Operation: invoke a Query, Signal, or Update, or execute other reliable code using the Temporal SDK Client.

(Each SDK names these differently — see the language reference file.)

### Nexus Endpoints

A Nexus **Endpoint** is a fully managed reverse proxy for Nexus Services. It routes requests from a caller Workflow to a target Namespace and Task Queue.  An Endpoint is a reverse proxy for a **single** Nexus Service, routing requests to **one** target Namespace and Task Queue — it does not route to multiple backends.

The `EndpointSpec` supports the **Worker** target type (route to a target Namespace and Task Queue).

> The CLI also exposes a `--target-url` flag for an external Nexus Endpoint; this flag is **Experimental**.

Adding an Endpoint to the Nexus Registry deploys it immediately — it is available at runtime as soon as it is registered.

### Nexus Registry

The Nexus Registry manages Nexus Endpoints.  Endpoint names must be unique within the Registry.

- In **Temporal Cloud**, the Registry is **global across your Account**, spanning all Namespaces.
- In **self-hosted deployments**, it is scoped to a **Cluster**.

Manage Endpoints via the Temporal UI, CLI, Terraform provider, or Cloud Ops API.

### Nexus Machinery

When a caller Workflow executes a Nexus Operation, the **Nexus Machinery** handles delivery with **at-least-once** execution: automatic retries with exponential backoff, rate limiting and concurrency limiting, circuit breaking, and automatic load balancing.  The Machinery uses Nexus RPC on the wire (a protocol supporting arbitrary-duration Operations); you interact only with the Temporal SDK, not Nexus RPC directly.

---

## Operation lifecycle

When a caller Workflow executes a Nexus Operation, the command is atomically handed off to the Nexus Machinery, which ensures at-least-once execution with automatic retries and reliable result delivery.

### Synchronous

Synchronous Operations must complete within the **10-second handler deadline**, measured from the caller's Nexus Machinery.  Use sync for Signals, Queries, Updates, or other reliable low-latency calls.

Caller history records: `NexusOperationScheduled` → `NexusOperationCompleted` (or `Failed`). **There is no `NexusOperationStarted` event for synchronous Operations** — they complete as part of the start request.

A sync handler can execute code directly but **must** finish within the handler deadline. Repeated sync handler failures can trip the [circuit breaker](#circuit-breaking) and block all Operations from that caller to the Endpoint — use async Operations for long-running work.

### Asynchronous

Asynchronous Operations can run up to **60 days** (the maximum Schedule-to-Close timeout in Temporal Cloud).  They start a Workflow (same or different Task Queue, with optional Eager Start).

Caller history records: `NexusOperationScheduled` → `NexusOperationStarted` → `NexusOperationCompleted` (or `Failed`, `Canceled`, `TimedOut`).  When the handler Workflow completes, a Nexus Completion Callback is delivered to the caller's Nexus Machinery.

### Multi-level calls

Operations can be composed across services: a handler Workflow can call another Nexus Operation, forming a chain (Workflow A → Op 1 → Workflow B → Op 2 → Workflow C). Each step is a separate, durable Operation with its own retries and failure handling.

---

## Timeouts

Three timeout types are set **by the caller** when scheduling the Operation.

| Timeout | What it bounds | Applies to | Default when unset |
|---|---|---|---|
| **Schedule-to-Close** | Total duration from scheduling to completion (the overall Operation timeout) | Both sync and async | Capped at the Cloud max of **60 days**  |
| **Schedule-to-Start** | Time waiting for the handler to start (or complete, if sync) the Operation | Both | **Not enforced** if not set or set to zero  |
| **Start-to-Close** | Time waiting for an async Operation to complete after it has started | **Async only** — sync Operations ignore this  | **Not enforced** if not set or set to zero  |

When Schedule-to-Close is exceeded, the Operation fails with a `NexusOperationTimedOut` event.  Schedule-to-Start failures surface as `TIMEOUT_TYPE_SCHEDULE_TO_START`; Start-to-Close as `TIMEOUT_TYPE_START_TO_CLOSE`.

> **Schedule-to-Start and Start-to-Close timeouts require Temporal Server 1.31.0 or later.**

---

## Automatic retries and error handling

Once a caller schedules an Operation, the Nexus Machinery keeps trying to start it. If a retryable Nexus error is returned, the Machinery retries until the Schedule-to-Start or Schedule-to-Close timeout is exceeded.

> Nexus error handling **differs from Activity and Workflow error handling**; don't carry over Activity assumptions.

### Handler error types

Handler errors are retryable by default unless they are Application Failures explicitly marked non-retryable, Nexus Operation errors that resolve as failed or canceled, or non-retryable Nexus errors.

Following the Nexus spec, predefined handler error types break down as:

- **Non-retryable:** `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`.
- **Retryable:** `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`.

### How errors surface

- **Non-retryable** — a `NexusOperationFailed` event is added to the caller's Workflow History.
- **Retryable** — the Nexus Machinery automatically retries; the error surfaces in Pending Operations.

When an Operation fails, the caller receives a Nexus Operation Failure containing the operation name, token, and failure reason; the `cause` field indicates the underlying error type (Application Error, Canceled Error, etc.).

---

## Circuit breaking

Nexus implements circuit breaking **per caller-Namespace/Endpoint pair** ("destination pair"). Each destination pair trips and resets independently.

By default, the circuit breaker activates after **5 consecutive retryable errors**.

State machine:

- **Open** — stops sending requests. After **60 seconds**, transitions to half-open.
- **Half-open** — allows a single probe request. If the probe succeeds, returns to **closed** (normal). If it fails, returns to **open** for another 60 seconds.

> Worker availability counts: if no workers are polling the handler Task Queue, Nexus requests time out, and **consecutive timeouts count as retryable errors** that trip the breaker just like application-level errors.

Different Operations within the same destination pair contribute to the trip count, so a given Operation may have fewer than 5 attempts when the breaker opens.

Inspect breaker state in **Pending Nexus Operations** (UI, CLI, or `DescribeWorkflowExecution`). When open, pending Operations show a `State: Blocked` with `BlockedReason: The circuit breaker is open.`

Cancellation requests show the same pattern via `CancelationState: Blocked` and `CancelationBlockedReason`.

---

## Execution semantics

### At-least-once

The Nexus Machinery provides at-least-once execution until the caller's Schedule-to-Close timeout is exceeded.  Handlers may be invoked multiple times for the same Operation, so they **should be idempotent** — similar to Activities. Not strictly required in all cases, but highly recommended.

### Exactly-once

To upgrade to exactly-once, back the Operation with a Workflow that uses `WorkflowIDReusePolicy` of `RejectDuplicates`. This allows only one Workflow Execution per Workflow ID within a Namespace for the Retention Period.

---

## Cancellation and termination

**Cancellation** of a caller Workflow automatically propagates to all pending Nexus Operations and their underlying handler Workflows. A canceled handler Workflow reports a Canceled Failure back to the caller.

**Termination** abandons all pending Nexus Operations. **Unlike cancellation, no cancel request is sent to the handler Namespace**, so handler Workflows continue running indefinitely, consuming resources until they time out or are stopped manually. Termination also leaves no opportunity to run compensation logic. **Prefer cancellation when possible.**

Cancellation semantics for the caller-side wait are exposed by each SDK as a **cancellation type** option (e.g. `ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`); see the language reference for the exact names. The cross-SDK default is "wait for completion."

Only **asynchronous** Operations can be canceled — cancellation is sent using the operation token. Sync Operations have no token and cannot be canceled.

Once the caller Workflow completes, the caller's Nexus Machinery makes no further attempts to cancel still-running Operations. To ensure cancellations are delivered, wait for all pending Operations to finish before exiting the caller Workflow.

---

## Versioning

**Task Routing** is the simplest way to version a Nexus Service. For backward-incompatible changes, use a different Service name and Task Queue (for example, `prod.payments.v2`). Callers migrate to the new version on their own deployment schedule.

---

## Attaching multiple callers to a handler Workflow

Operations started with New-Workflow-Run-Operation automatically attach a completion Callback to the handler Workflow. Additional callers can attach to the same handler Workflow using a **Conflict-Policy of Use-Existing**.

Each handler Workflow has a Callback limit (configurable for self-hosted). Callers that exceed the limit receive an error.

When a handler Workflow uses Continue-As-New, existing completion Callbacks are copied to the new Execution; the previous Execution's Callbacks remain in `Standby` indefinitely.

---

## Deployment patterns

There are two common patterns for building and deploying Nexus Services.

### Collocated (default)

Nexus Operation handlers run in the **same Worker and on the same Task Queue** as the underlying Workflows.  A single Worker registers both Nexus Services and Workflow types.

Use this pattern by default. Benefits:

- Simplest setup: one Worker, one Task Queue, one deployment.
- Enables **Eager Workflow Start**: the first Workflow Task runs locally without an extra round-trip to the Server, while still recording durable state.
- Clean facade: Operations act as a stable contract; the underlying implementation can change (Signal today, Workflow tomorrow) without impacting callers.

### Router-queue

Separates Nexus routing from Workflow execution. A dedicated Nexus Worker on a "router" Task Queue routes Operations to Workflows on other Task Queues **in the same Namespace**.

Use when you need:

- **Separate scaling** of Nexus routing vs. Workflow execution.
- A **dedicated routing layer** for many Workflow types on different Task Queues.
- **Different IAM permissions** per Worker fleet.
- To add Nexus to a Namespace **without modifying existing Workers**.

Mechanics: register a Nexus Worker polling a dedicated router Task Queue; point the Endpoint's target Task Queue at this router; in each Operation handler, specify a **different** target Task Queue in the Workflow start options. Existing Workers continue polling their own Task Queues.

---

## Security

### Runtime access controls

In Temporal Cloud, each Endpoint has an **access control policy: an allowlist of caller Namespaces**.  Workers authenticate with their Namespace via mTLS or API key. When a caller executes an Operation, Temporal Cloud verifies the caller's Namespace is in the Endpoint's allowlist before routing the request to the handler.

> **No callers are allowed by default**, even if they share a Namespace with the Endpoint target.

Self-hosted deployments can implement custom Authorizers.

### Secure connectivity

Temporal Cloud has built-in secure connectivity across all Namespaces in an Account. Workers authenticate to their Namespace using **mTLS or API key**, mTLS encrypts all cross-Namespace Nexus traffic (start, cancel, completion callbacks), and Endpoints are only accessible from within a Temporal Cloud Account **through the Temporal SDK** — they are not externally accessible.

Self-hosted deployments rely on the Temporal Cluster being secure.

### Payload encryption and the Data Converter

Nexus uses the same Data Converter as Workflows and Activities — JSON, Proto, and binary payloads are all supported. If you use a Codec for encryption, it also encrypts Nexus payloads.  Caller and handler Workers must have compatible Data Converters; payloads are encrypted by the sender.

Three common approaches for cross-Namespace payload encryption:

1. **Same encryption key** — both Namespaces share one key. Simplest; no extra configuration.
2. **Pass KMS key ID in payload metadata** — each Namespace uses its own key; the receiver reads the key ID from metadata and decrypts using KMS IAM permissions. Works bi-directionally.
3. **Wrapper types for Endpoint-specific encryption keys** — use a wrapper (e.g. `EndpointValue`) so the Data Converter selects an Endpoint-specific key. Encrypts only Nexus traffic with a dedicated key, without sharing Namespace keys across teams.

Options 1 and 2 work with the standard Data Converter; option 3 is more advanced and intended for teams that don't want to share Namespace encryption keys.

---

## Execution debugging

### Bi-directional linking

Links connect Nexus Operation events in the caller's Workflow History to the corresponding events in the handler's Workflow History — including across multi-level calls, across Namespaces, regions, and clouds.

- **Forward** — from a caller's Nexus Operation event to the handler's Workflow.
- **Backward** — from the handler's Workflow back to the caller's Nexus Operation event.

Links are automatically wired by SDK builder functions like `New-Workflow-Run-Operation`.

### Pending Operations

Pending Nexus Operations are displayed in the UI on the Workflow details page and can be listed from the CLI via `temporal workflow describe`.

Example CLI output:

```
Pending Nexus Operations: 1

  Endpoint                 myendpoint
  Service                  my-hello-service
  Operation                echo
  OperationToken
  State                    BackingOff
  Attempt                  6
  ScheduleToCloseTimeout   0s
  NextAttemptScheduleTime  20 seconds from now
  LastAttemptCompleteTime  11 seconds ago
  LastAttemptFailure       {"message":"handler error (INTERNAL): internal error","applicationFailureInfo":{}}
```

Retryable errors surface here. Non-retryable errors resolve the Operation with a `Failed`, `TimedOut`, or `Canceled` event.

### Pending Callbacks

Nexus completion callbacks are sent from the handler's Namespace to the caller's Namespace for asynchronous Operations. View them in the UI or via `temporal workflow describe`.

### Tracing

Temporal integrates with OpenTelemetry and OpenTracing to visualize call graphs across Activities, Nexus Operations, and Child Workflows. Enable tracing by installing an interceptor on the Client or Worker.

---

## Metrics

Nexus emits three categories of metrics.

### SDK metrics

Emitted from a Nexus Worker. Includes:

- `nexus_poll_no_task`
- `nexus_task_schedule_to_start_latency`
- `nexus_task_execution_failed`
- `nexus_task_execution_latency`
- `nexus_task_endtoend_latency`

### Cloud metrics

Emitted by Temporal Cloud.

- **Caller Namespace** — `RespondWorkflowTaskCompleted` (schedule a Nexus Operation).
- **Handler Namespace** — `PollNexusTaskQueue`, `RespondNexusTaskCompleted`, `RespondNexusTaskFailed`.

### OSS Cluster metrics

Emitted from an OSS Cluster: History Service metrics, Concurrency Limiter metrics, Frontend Service metrics.

---

## Managing Endpoints from the CLI

For self-hosted deployments, manage Endpoints via `temporal operator nexus endpoint`, which has five subcommands: `create`, `delete`, `get`, `list`, `update`.

Required flag on every subcommand except `list` is `--name`.  For `create`/`update`, set the target by providing **both** `--target-namespace` and `--target-task-queue` (Worker target type), or — _Experimental_ — provide `--target-url`.

Example (create):

```
temporal operator nexus endpoint create \
  --name your-endpoint \
  --target-namespace your-namespace \
  --target-task-queue your-task-queue \
  --description-file DESCRIPTION.md
```

For Temporal Cloud, use `tcld nexus endpoint create` with `--allow-namespace` to build the Endpoint allowlist.

> The CLI surface beyond what is summarized here lives in `skill-temporal-cli`. Cite `docs/cli/operator.mdx` directly when spelling out invocations.

---

## When to use Nexus

From the Nexus overview:

> Nexus connects Temporal Applications across (and within) isolated Namespaces. Each team gets their own Namespace for security and fault isolation, while exposing a clean service contract for others to use through a Nexus Endpoint.

> Designed for Durable Execution, Nexus combines a familiar SDK programming model with reliable execution, built-in observability, and multi-region connectivity in Temporal Cloud.

Pick Nexus when you need cross-team, cross-Namespace composition with durable, retried, queue-based calls — not for in-process function calls (use Activities or Child Workflows for those).
