# Temporal Nexus

Nexus connects Temporal Applications across (and within) isolated Namespaces. <!-- docs/encyclopedia/nexus/nexus.mdx:37-38 --> Each team exposes a clean service contract through a **Nexus Endpoint**; callers reference an Endpoint by name and never need to know the handler's Namespace, Task Queue, or internal implementation. <!-- docs/encyclopedia/nexus/nexus.mdx:78-80 -->

Nexus is peer-to-peer, not hierarchical: caller and handler Workflows are siblings that communicate across Namespace boundaries. <!-- docs/encyclopedia/nexus/nexus.mdx:42-43 -->

**Support status (as of these docs):** Temporal Nexus is **Generally Available** for Temporal Cloud and self-hosted deployments. <!-- docs/encyclopedia/nexus/nexus.mdx:21 --> SDK support:

- Go, Java, Python — **Generally Available**. <!-- docs/develop/go/nexus/feature-guide.mdx:22-25; docs/develop/java/nexus/feature-guide.mdx:22-25; docs/develop/python/nexus/feature-guide.mdx:22-24 -->
- TypeScript, .NET — **Public Preview**. <!-- docs/develop/typescript/nexus/feature-guide.mdx:21; docs/develop/dotnet/nexus/feature-guide.mdx:21 -->

> Language-specific code and SDK tokens live in `references/{your_language}/nexus.md`. This file covers concepts shared across all five SDKs.

---

## Building blocks

### Nexus Services

A **Nexus Service** is a named collection of Nexus Operations that a team exposes as a contract for sharing across team boundaries. <!-- docs/encyclopedia/nexus/nexus-services.mdx:28-29 --> Services are registered in a Worker that polls the Endpoint's target Task Queue; multiple Services can run in the same Worker, and they typically run alongside the Workflows they abstract (or in a dedicated router Worker — see [Patterns](#deployment-patterns)). <!-- docs/encyclopedia/nexus/nexus-services.mdx:31-33 --> Callers reference a Service by name when executing an Operation. <!-- docs/encyclopedia/nexus/nexus-services.mdx:35 -->

### Nexus Operations

Operations abstract the underlying implementation. Callers don't need to know whether an Operation starts a Workflow, sends a Signal, runs a Query, or executes other reliable code. <!-- docs/encyclopedia/nexus/nexus.mdx:56-57 --> Two builder-function flavors:

- **New-Workflow-Run-Operation** — start a Workflow as an **asynchronous** Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:59 -->
- **New-Sync-Operation** — run a **synchronous** Operation: invoke a Query, Signal, or Update, or execute other reliable code using the Temporal SDK Client. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:60 -->

(Each SDK names these differently — see the language reference file.)

### Nexus Endpoints

A Nexus **Endpoint** is a fully managed reverse proxy for Nexus Services. It routes requests from a caller Workflow to a target Namespace and Task Queue. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:25-27 --> An Endpoint is a reverse proxy for a **single** Nexus Service, routing requests to **one** target Namespace and Task Queue — it does not route to multiple backends. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:34-37 -->

The `EndpointSpec` supports the **Worker** target type (route to a target Namespace and Task Queue). <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:38-40 -->

> The CLI also exposes a `--target-url` flag for an external Nexus Endpoint; this flag is **Experimental**. <!-- docs/cli/operator.mdx:370 -->

Adding an Endpoint to the Nexus Registry deploys it immediately — it is available at runtime as soon as it is registered. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:42-44 -->

### Nexus Registry

The Nexus Registry manages Nexus Endpoints. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:30 --> Endpoint names must be unique within the Registry. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:33 -->

- In **Temporal Cloud**, the Registry is **global across your Account**, spanning all Namespaces. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:34 -->
- In **self-hosted deployments**, it is scoped to a **Cluster**. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:35 -->

Manage Endpoints via the Temporal UI, CLI, Terraform provider, or Cloud Ops API. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:39 -->

### Nexus Machinery

When a caller Workflow executes a Nexus Operation, the **Nexus Machinery** handles delivery with **at-least-once** execution: automatic retries with exponential backoff, rate limiting and concurrency limiting, circuit breaking, and automatic load balancing. <!-- docs/encyclopedia/nexus/nexus.mdx:102-108 --> The Machinery uses Nexus RPC on the wire (a protocol supporting arbitrary-duration Operations); you interact only with the Temporal SDK, not Nexus RPC directly. <!-- docs/encyclopedia/nexus/nexus.mdx:109-110 -->

---

## Operation lifecycle

When a caller Workflow executes a Nexus Operation, the command is atomically handed off to the Nexus Machinery, which ensures at-least-once execution with automatic retries and reliable result delivery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:64-66 -->

### Synchronous

Synchronous Operations must complete within the **10-second handler deadline**, measured from the caller's Nexus Machinery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:75 --> Use sync for Signals, Queries, Updates, or other reliable low-latency calls. <!-- docs/encyclopedia/nexus/nexus.mdx:62 -->

Caller history records: `NexusOperationScheduled` → `NexusOperationCompleted` (or `Failed`). **There is no `NexusOperationStarted` event for synchronous Operations** — they complete as part of the start request. <!-- docs/develop/go/nexus/feature-guide.mdx:761-770 -->

A sync handler can execute code directly but **must** finish within the handler deadline. Repeated sync handler failures can trip the [circuit breaker](#circuit-breaking) and block all Operations from that caller to the Endpoint — use async Operations for long-running work. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:139-147 -->

### Asynchronous

Asynchronous Operations can run up to **60 days** (the maximum Schedule-to-Close timeout in Temporal Cloud). <!-- docs/encyclopedia/nexus/nexus-operations.mdx:110 --> They start a Workflow (same or different Task Queue, with optional Eager Start). <!-- docs/encyclopedia/nexus/nexus.mdx:61 -->

Caller history records: `NexusOperationScheduled` → `NexusOperationStarted` → `NexusOperationCompleted` (or `Failed`, `Canceled`, `TimedOut`). <!-- docs/encyclopedia/nexus/nexus-operations.mdx:169; docs/develop/go/nexus/feature-guide.mdx:755-759 --> When the handler Workflow completes, a Nexus Completion Callback is delivered to the caller's Nexus Machinery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:127 -->

### Multi-level calls

Operations can be composed across services: a handler Workflow can call another Nexus Operation, forming a chain (Workflow A → Op 1 → Workflow B → Op 2 → Workflow C). Each step is a separate, durable Operation with its own retries and failure handling. <!-- docs/encyclopedia/nexus/nexus.mdx:114-118 -->

---

## Timeouts

Three timeout types are set **by the caller** when scheduling the Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:188-189 -->

| Timeout | What it bounds | Applies to | Default when unset |
|---|---|---|---|
| **Schedule-to-Close** | Total duration from scheduling to completion (the overall Operation timeout) | Both sync and async | Capped at the Cloud max of **60 days** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:199 --> |
| **Schedule-to-Start** | Time waiting for the handler to start (or complete, if sync) the Operation | Both | **Not enforced** if not set or set to zero <!-- docs/encyclopedia/nexus/nexus-operations.mdx:206 --> |
| **Start-to-Close** | Time waiting for an async Operation to complete after it has started | **Async only** — sync Operations ignore this <!-- docs/encyclopedia/nexus/nexus-operations.mdx:218-220 --> | **Not enforced** if not set or set to zero <!-- docs/encyclopedia/nexus/nexus-operations.mdx:222 --> |

When Schedule-to-Close is exceeded, the Operation fails with a `NexusOperationTimedOut` event. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:195 --> Schedule-to-Start failures surface as `TIMEOUT_TYPE_SCHEDULE_TO_START`; Start-to-Close as `TIMEOUT_TYPE_START_TO_CLOSE`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:204, :217 -->

> **Schedule-to-Start and Start-to-Close timeouts require Temporal Server 1.31.0 or later.** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:208-212, :224-228 -->

---

## Automatic retries and error handling

Once a caller schedules an Operation, the Nexus Machinery keeps trying to start it. If a retryable Nexus error is returned, the Machinery retries until the Schedule-to-Start or Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:173-176 -->

> Nexus error handling **differs from Activity and Workflow error handling**; don't carry over Activity assumptions. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:178-181 -->

### Handler error types

Handler errors are retryable by default unless they are Application Failures explicitly marked non-retryable, Nexus Operation errors that resolve as failed or canceled, or non-retryable Nexus errors. <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:29-35 -->

Following the Nexus spec, predefined handler error types break down as:

- **Non-retryable:** `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`. <!-- docs/develop/python/nexus/feature-guide.mdx:335; docs/develop/typescript/nexus/feature-guide.mdx:348 -->
- **Retryable:** `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`. <!-- docs/develop/python/nexus/feature-guide.mdx:335; docs/develop/typescript/nexus/feature-guide.mdx:348 -->

### How errors surface

- **Non-retryable** — a `NexusOperationFailed` event is added to the caller's Workflow History. <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:38 -->
- **Retryable** — the Nexus Machinery automatically retries; the error surfaces in Pending Operations. <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:39 -->

When an Operation fails, the caller receives a Nexus Operation Failure containing the operation name, token, and failure reason; the `cause` field indicates the underlying error type (Application Error, Canceled Error, etc.). <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:50-51 -->

---

## Circuit breaking

Nexus implements circuit breaking **per caller-Namespace/Endpoint pair** ("destination pair"). Each destination pair trips and resets independently. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:232-233 -->

By default, the circuit breaker activates after **5 consecutive retryable errors**. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:234 -->

State machine:

- **Open** — stops sending requests. After **60 seconds**, transitions to half-open. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:237-239 -->
- **Half-open** — allows a single probe request. If the probe succeeds, returns to **closed** (normal). If it fails, returns to **open** for another 60 seconds. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:238-239 -->

> Worker availability counts: if no workers are polling the handler Task Queue, Nexus requests time out, and **consecutive timeouts count as retryable errors** that trip the breaker just like application-level errors. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:241-247 -->

Different Operations within the same destination pair contribute to the trip count, so a given Operation may have fewer than 5 attempts when the breaker opens. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:264-265 -->

Inspect breaker state in **Pending Nexus Operations** (UI, CLI, or `DescribeWorkflowExecution`). When open, pending Operations show a `State: Blocked` with `BlockedReason: The circuit breaker is open.` <!-- docs/encyclopedia/nexus/nexus-operations.mdx:254-283 -->

Cancellation requests show the same pattern via `CancelationState: Blocked` and `CancelationBlockedReason`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:285-309 -->

---

## Execution semantics

### At-least-once

The Nexus Machinery provides at-least-once execution until the caller's Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:314-316 --> Handlers may be invoked multiple times for the same Operation, so they **should be idempotent** — similar to Activities. Not strictly required in all cases, but highly recommended. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:317-320 -->

### Exactly-once

To upgrade to exactly-once, back the Operation with a Workflow that uses `WorkflowIDReusePolicy` of `RejectDuplicates`. This allows only one Workflow Execution per Workflow ID within a Namespace for the Retention Period. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:322-325 -->

---

## Cancellation and termination

**Cancellation** of a caller Workflow automatically propagates to all pending Nexus Operations and their underlying handler Workflows. A canceled handler Workflow reports a Canceled Failure back to the caller. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:328-330 -->

**Termination** abandons all pending Nexus Operations. **Unlike cancellation, no cancel request is sent to the handler Namespace**, so handler Workflows continue running indefinitely, consuming resources until they time out or are stopped manually. Termination also leaves no opportunity to run compensation logic. **Prefer cancellation when possible.** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:332-339 -->

Cancellation semantics for the caller-side wait are exposed by each SDK as a **cancellation type** option (e.g. `ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`); see the language reference for the exact names. The cross-SDK default is "wait for completion." <!-- docs/develop/python/nexus/feature-guide.mdx:344-351; docs/develop/go/nexus/feature-guide.mdx:560-571 -->

Only **asynchronous** Operations can be canceled — cancellation is sent using the operation token. Sync Operations have no token and cannot be canceled. <!-- docs/develop/python/nexus/feature-guide.mdx:340-341 -->

Once the caller Workflow completes, the caller's Nexus Machinery makes no further attempts to cancel still-running Operations. To ensure cancellations are delivered, wait for all pending Operations to finish before exiting the caller Workflow. <!-- docs/develop/python/nexus/feature-guide.mdx:353-355 -->

---

## Versioning

**Task Routing** is the simplest way to version a Nexus Service. For backward-incompatible changes, use a different Service name and Task Queue (for example, `prod.payments.v2`). Callers migrate to the new version on their own deployment schedule. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:343-345 -->

---

## Attaching multiple callers to a handler Workflow

Operations started with New-Workflow-Run-Operation automatically attach a completion Callback to the handler Workflow. Additional callers can attach to the same handler Workflow using a **Conflict-Policy of Use-Existing**. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:350-351 -->

Each handler Workflow has a Callback limit (configurable for self-hosted). Callers that exceed the limit receive an error. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:354-355 -->

When a handler Workflow uses Continue-As-New, existing completion Callbacks are copied to the new Execution; the previous Execution's Callbacks remain in `Standby` indefinitely. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:357-358 -->

---

## Deployment patterns

There are two common patterns for building and deploying Nexus Services. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:26 -->

### Collocated (default)

Nexus Operation handlers run in the **same Worker and on the same Task Queue** as the underlying Workflows. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:33-34 --> A single Worker registers both Nexus Services and Workflow types. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:36-37 -->

Use this pattern by default. Benefits:

- Simplest setup: one Worker, one Task Queue, one deployment. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:41 -->
- Enables **Eager Workflow Start**: the first Workflow Task runs locally without an extra round-trip to the Server, while still recording durable state. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:42 -->
- Clean facade: Operations act as a stable contract; the underlying implementation can change (Signal today, Workflow tomorrow) without impacting callers. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:43 -->

### Router-queue

Separates Nexus routing from Workflow execution. A dedicated Nexus Worker on a "router" Task Queue routes Operations to Workflows on other Task Queues **in the same Namespace**. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:55-56 -->

Use when you need:

- **Separate scaling** of Nexus routing vs. Workflow execution. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:60 -->
- A **dedicated routing layer** for many Workflow types on different Task Queues. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:61 -->
- **Different IAM permissions** per Worker fleet. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:62 -->
- To add Nexus to a Namespace **without modifying existing Workers**. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:63 -->

Mechanics: register a Nexus Worker polling a dedicated router Task Queue; point the Endpoint's target Task Queue at this router; in each Operation handler, specify a **different** target Task Queue in the Workflow start options. Existing Workers continue polling their own Task Queues. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:66-70 -->

---

## Security

### Runtime access controls

In Temporal Cloud, each Endpoint has an **access control policy: an allowlist of caller Namespaces**. <!-- docs/encyclopedia/nexus/nexus-security.mdx:33 --> Workers authenticate with their Namespace via mTLS or API key. When a caller executes an Operation, Temporal Cloud verifies the caller's Namespace is in the Endpoint's allowlist before routing the request to the handler. <!-- docs/encyclopedia/nexus/nexus-security.mdx:40-42 -->

> **No callers are allowed by default**, even if they share a Namespace with the Endpoint target. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:66-68 -->

Self-hosted deployments can implement custom Authorizers. <!-- docs/encyclopedia/nexus/nexus-security.mdx:29 -->

### Secure connectivity

Temporal Cloud has built-in secure connectivity across all Namespaces in an Account. Workers authenticate to their Namespace using **mTLS or API key**, mTLS encrypts all cross-Namespace Nexus traffic (start, cancel, completion callbacks), and Endpoints are only accessible from within a Temporal Cloud Account **through the Temporal SDK** — they are not externally accessible. <!-- docs/encyclopedia/nexus/nexus-security.mdx:56-60 -->

Self-hosted deployments rely on the Temporal Cluster being secure. <!-- docs/encyclopedia/nexus/nexus-security.mdx:53 -->

### Payload encryption and the Data Converter

Nexus uses the same Data Converter as Workflows and Activities — JSON, Proto, and binary payloads are all supported. If you use a Codec for encryption, it also encrypts Nexus payloads. <!-- docs/encyclopedia/nexus/nexus-security.mdx:64-65 --> Caller and handler Workers must have compatible Data Converters; payloads are encrypted by the sender. <!-- docs/encyclopedia/nexus/nexus-security.mdx:67-68 -->

Three common approaches for cross-Namespace payload encryption: <!-- docs/encyclopedia/nexus/nexus-security.mdx:70 -->

1. **Same encryption key** — both Namespaces share one key. Simplest; no extra configuration. <!-- docs/encyclopedia/nexus/nexus-security.mdx:72-75 -->
2. **Pass KMS key ID in payload metadata** — each Namespace uses its own key; the receiver reads the key ID from metadata and decrypts using KMS IAM permissions. Works bi-directionally. <!-- docs/encyclopedia/nexus/nexus-security.mdx:77-85 -->
3. **Wrapper types for Endpoint-specific encryption keys** — use a wrapper (e.g. `EndpointValue`) so the Data Converter selects an Endpoint-specific key. Encrypts only Nexus traffic with a dedicated key, without sharing Namespace keys across teams. <!-- docs/encyclopedia/nexus/nexus-security.mdx:87-92 -->

Options 1 and 2 work with the standard Data Converter; option 3 is more advanced and intended for teams that don't want to share Namespace encryption keys. <!-- docs/encyclopedia/nexus/nexus-security.mdx:96-97 -->

---

## Execution debugging

### Bi-directional linking

Links connect Nexus Operation events in the caller's Workflow History to the corresponding events in the handler's Workflow History — including across multi-level calls, across Namespaces, regions, and clouds. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:29-30 -->

- **Forward** — from a caller's Nexus Operation event to the handler's Workflow.
- **Backward** — from the handler's Workflow back to the caller's Nexus Operation event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:38-39 -->

Links are automatically wired by SDK builder functions like `New-Workflow-Run-Operation`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:29-30 -->

### Pending Operations

Pending Nexus Operations are displayed in the UI on the Workflow details page and can be listed from the CLI via `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:43 -->

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
<!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:58-70 -->

Retryable errors surface here. Non-retryable errors resolve the Operation with a `Failed`, `TimedOut`, or `Canceled` event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:72-73 -->

### Pending Callbacks

Nexus completion callbacks are sent from the handler's Namespace to the caller's Namespace for asynchronous Operations. View them in the UI or via `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:77-79 -->

### Tracing

Temporal integrates with OpenTelemetry and OpenTracing to visualize call graphs across Activities, Nexus Operations, and Child Workflows. Enable tracing by installing an interceptor on the Client or Worker. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:103-105 -->

---

## Metrics

Nexus emits three categories of metrics. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:27 -->

### SDK metrics

Emitted from a Nexus Worker. Includes: <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:31 -->

- `nexus_poll_no_task` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:33 -->
- `nexus_task_schedule_to_start_latency` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:34 -->
- `nexus_task_execution_failed` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:35 -->
- `nexus_task_execution_latency` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:36 -->
- `nexus_task_endtoend_latency` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:37 -->

### Cloud metrics

Emitted by Temporal Cloud. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:41 -->

- **Caller Namespace** — `RespondWorkflowTaskCompleted` (schedule a Nexus Operation). <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:43-44 -->
- **Handler Namespace** — `PollNexusTaskQueue`, `RespondNexusTaskCompleted`, `RespondNexusTaskFailed`. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:45-48 -->

### OSS Cluster metrics

Emitted from an OSS Cluster: History Service metrics, Concurrency Limiter metrics, Frontend Service metrics. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:52-56 -->

---

## Managing Endpoints from the CLI

For self-hosted deployments, manage Endpoints via `temporal operator nexus endpoint`, which has five subcommands: `create`, `delete`, `get`, `list`, `update`. <!-- docs/cli/operator.mdx:321-449 -->

Required flag on every subcommand except `list` is `--name`. <!-- docs/cli/operator.mdx:367, :384, :398, :444 --> For `create`/`update`, set the target by providing **both** `--target-namespace` and `--target-task-queue` (Worker target type), or — _Experimental_ — provide `--target-url`. <!-- docs/cli/operator.mdx:368-370, :445-447 -->

Example (create):

```
temporal operator nexus endpoint create \
  --name your-endpoint \
  --target-namespace your-namespace \
  --target-task-queue your-task-queue \
  --description-file DESCRIPTION.md
```
<!-- docs/cli/operator.mdx:354-358 -->

For Temporal Cloud, use `tcld nexus endpoint create` with `--allow-namespace` to build the Endpoint allowlist. <!-- docs/develop/python/nexus/feature-guide.mdx:410-418 -->

> The CLI surface beyond what is summarized here lives in `skill-temporal-cli`. Cite `docs/cli/operator.mdx` directly when spelling out invocations.

---

## When to use Nexus

From the Nexus overview:

> Nexus connects Temporal Applications across (and within) isolated Namespaces. Each team gets their own Namespace for security and fault isolation, while exposing a clean service contract for others to use through a Nexus Endpoint. <!-- docs/encyclopedia/nexus/nexus.mdx:37-38 -->

> Designed for Durable Execution, Nexus combines a familiar SDK programming model with reliable execution, built-in observability, and multi-region connectivity in Temporal Cloud. <!-- docs/encyclopedia/nexus/nexus.mdx:40 -->

Pick Nexus when you need cross-team, cross-Namespace composition with durable, retried, queue-based calls — not for in-process function calls (use Activities or Child Workflows for those).
