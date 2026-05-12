# Nexus

## What Nexus is

Temporal Nexus connects Temporal Applications across (and within) isolated Namespaces. <!-- docs/encyclopedia/nexus/nexus.mdx:37 --> Each team owns its own Namespace for security and fault isolation while exposing a clean service contract for other teams to consume through a Nexus Endpoint. <!-- docs/encyclopedia/nexus/nexus.mdx:38 --> Nexus is peer-to-peer, not hierarchical: caller and handler Workflows are siblings that communicate across Namespace boundaries. <!-- docs/encyclopedia/nexus/nexus.mdx:42 -->

Temporal Nexus is Generally Available for Temporal Cloud and self-hosted deployments. <!-- docs/encyclopedia/nexus/nexus.mdx:21 -->

This page covers cross-SDK concepts. For language-specific code, see the per-SDK references (for example `references/go/nexus.md`, `references/python/nexus.md`, `references/java/nexus.md`, `references/typescript/nexus.md`, `references/dotnet/nexus.md`).

## Core concepts

### Nexus Service

A Nexus Service is a named collection of Nexus Operations that a team exposes. <!-- docs/encyclopedia/nexus/nexus.mdx:56 --> Services are registered in a Worker that polls the Endpoint's target Task Queue, and multiple Services can run in the same Worker. <!-- docs/encyclopedia/nexus/nexus-services.mdx:31 --> Callers reference a Service by name when executing a Nexus Operation. <!-- docs/encyclopedia/nexus/nexus-services.mdx:35 -->

Operations abstract the underlying implementation: callers do not need to know whether an Operation starts a Workflow, sends a Signal, runs a Query, or executes other reliable code. <!-- docs/encyclopedia/nexus/nexus.mdx:57 -->

### Nexus Operation (sync vs async)

The Operation lifecycle supports two modes: <!-- docs/encyclopedia/nexus/nexus.mdx:59 -->

- **Asynchronous** — Starts a Workflow (same or different Task Queue, with optional Eager Start) and can run up to 60 days. <!-- docs/encyclopedia/nexus/nexus.mdx:61 -->
- **Synchronous** — Completes within the 10-second handler deadline. Use for Signals, Queries, Updates, or other reliable low-latency calls using the Temporal SDK Client. <!-- docs/encyclopedia/nexus/nexus.mdx:62 -->

Operations are defined using SDK builder concepts: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:57 -->

- **New-Workflow-Run-Operation** — Start a Workflow as an asynchronous Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:59 -->
- **New-Sync-Operation** — Run a synchronous Operation: invoke a Query, Signal, or Update, or execute other reliable code using the Temporal SDK Client. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:60 -->

Unlike a traditional RPC, an asynchronous Nexus Operation has an operation token that can be used to re-attach to a long-running Operation backed by a Workflow. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:40 -->

### Nexus Endpoint

A Nexus Endpoint is a fully managed reverse proxy for Nexus Services. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:25 --> It routes requests from a caller Workflow to a target Namespace and Task Queue. Callers only need to know the Endpoint name; the target Namespace, Task Queue, and internal implementation are encapsulated. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:26 -->

A Nexus Endpoint acts as a reverse proxy for a single Nexus Service, routing requests to one target Namespace and Task Queue. Unlike general-purpose proxies, it does not route to multiple backends. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:35 --> Multiple Endpoints can target different Task Queues in the same Namespace. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:30 -->

The Endpoint description field supports markdown for documenting available Operations, contact information, or schema links. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:32 -->

Adding an Endpoint to the Nexus Registry deploys it immediately. The Endpoint is available at runtime as soon as it is registered. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:44 -->

### Nexus Registry

The Nexus Registry manages Nexus Endpoints. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:30 --> Endpoint names must be unique within the Registry. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:33 --> In Temporal Cloud, the Registry is global across the entire Account, spanning all Namespaces; in self-hosted deployments it is scoped to a Cluster. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:34 -->

Endpoints can be managed using the Temporal UI, CLI, Terraform provider, or Cloud Ops API. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:39 -->

Everything except the Endpoint name can be edited; new Operations route to the updated target immediately. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:76 -->

#### Caveat: changing the target Namespace

- **In-flight async Operations** — Completion callbacks point to the original handler Namespace and are unaffected, but Cancel requests route to the new target. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:81 -->
- **Workflow ID uniqueness** — IDs are scoped per Namespace. Signal-With-Start creates a new Workflow in the new target even if the same ID is active in the old target, resulting in potential duplicates. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:82 -->
- **Recommendation:** Drain existing Nexus Operations and underlying handler Workflows before changing the target Namespace. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:83 -->

### Nexus Machinery

When a caller Workflow executes a Nexus Operation, the Nexus Machinery handles delivery with at-least-once execution: <!-- docs/encyclopedia/nexus/nexus.mdx:102 -->

- Automatic retries with exponential backoff. <!-- docs/encyclopedia/nexus/nexus.mdx:104 -->
- Rate limiting and concurrency limiting. <!-- docs/encyclopedia/nexus/nexus.mdx:105 -->
- Circuit breaking (trips after 5 consecutive retryable errors). <!-- docs/encyclopedia/nexus/nexus.mdx:106 -->
- Automatic load balancing. <!-- docs/encyclopedia/nexus/nexus.mdx:107 -->

The Machinery uses Nexus RPC on the wire — a protocol supporting arbitrary-duration Operations. You interact only with the Temporal SDK, not Nexus RPC directly. <!-- docs/encyclopedia/nexus/nexus.mdx:109 -->

## Operation lifecycle

When a caller Workflow executes a Nexus Operation, the command is atomically handed off to the Nexus Machinery, which ensures at-least-once execution with automatic retries and reliable result delivery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:65 -->

### Synchronous lifecycle

Synchronous Operations must complete within the 10-second handler deadline, as measured from the caller's Nexus Machinery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:75 -->

Steps: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:82 -->

1. Caller Workflow executes a Nexus Operation.
2. Caller Worker issues a `ScheduleNexusOperation` command.
3. Caller Namespace records a `NexusOperationScheduled` event.
4. Caller Nexus Machinery sends the start request.
5. Handler Nexus Machinery sync-matches the request to a handler Worker.
6. Handler Worker receives a Nexus Task by polling the Endpoint's target Task Queue.
7. Handler processes the task using New-Sync-Operation.
8. Handler responds with the Operation result.
9. Caller Namespace records a `Completed` or `Failed` event.
10. Caller Worker polls for a Workflow Task and the caller Workflow receives the result.

Stay within the request deadline to avoid timeouts. Timed-out handlers are retried until the Operation's Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:102 -->

Synchronous handlers can execute code directly but must complete within the handler deadline. Use the Temporal SDK Client to invoke Signals, Queries, Updates, or other reliable code. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:139 --> Use async Operations for long-running work — repeated sync handler failures can trip the circuit breaker, blocking all Operations from that caller to the Endpoint. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:144 -->

### Asynchronous lifecycle

Asynchronous Operations can run up to 60 days (the maximum Schedule-to-Close timeout in Temporal Cloud). <!-- docs/encyclopedia/nexus/nexus-operations.mdx:110 --> The lifecycle differs from synchronous in these steps: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:118 -->

1. Caller Workflow executes a Nexus Operation.
2. Caller Worker issues a `ScheduleNexusOperation` command.
3. Caller Namespace records a `NexusOperationScheduled` event.
4. Caller Nexus Machinery sends the start request.
5. Handler Nexus Machinery sync-matches the request to a handler Worker.
6. Handler Worker receives a Nexus Task by polling the Endpoint's target Task Queue.
7. Handler processes the task using New-Workflow-Run-Operation.
8. Handler responds with the start Operation response.
9. Caller Namespace records a `NexusOperationStarted` event.
10. Handler Workflow completes and a Nexus Completion Callback is delivered to the caller's Nexus Machinery.
11. Caller Namespace records a `Completed` or `Failed` event.
12. Caller Workflow receives the result.

### At-least-once execution and idempotency

The Nexus Machinery provides at-least-once execution semantics for a Nexus Operation, until the caller's Schedule-to-Close timeout is exceeded, at which point the overall Nexus Operation times out. The Machinery retries on handler timeouts or retryable errors, so a handler may be invoked multiple times for the same Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:316 -->

Nexus Operation handlers should be idempotent, similar to Activities — not strictly required in all cases, but highly recommended. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:319 -->

To upgrade to exactly-once, back an Operation with a Workflow that uses a `WorkflowIDReusePolicy` of `RejectDuplicates`, which allows only one Workflow Execution per Workflow ID within a Namespace for the Retention Period. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:324 -->

### Cancelation vs termination

Cancelling a caller Workflow automatically propagates to all pending Nexus Operations and their underlying handler Workflows. A canceled handler Workflow reports a Canceled Failure to the caller. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:329 -->

Terminating a caller Workflow abandons all pending Nexus Operations. Unlike cancellation, no cancel request is sent to the handler Namespace, so handler Workflows continue running indefinitely, consuming resources until they time out or are manually stopped. Because the handler runs in a separate Namespace, it has no signal that the caller is gone, making orphaned Operations difficult to detect and correlate. Prefer cancellation when possible. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:334 -->

Cancellation type spellings vary by SDK; see the per-SDK Nexus reference.

## Timeouts

Nexus Operations support three types of timeouts that control how long the caller is willing to wait at different stages of the Operation lifecycle. These timeouts are set by the caller when scheduling the Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:188 -->

### Schedule-to-Close

Limits the total duration from when the Operation is scheduled to when it completes. This is the overall timeout for the entire Operation. The Nexus Machinery automatically retries failed requests internally until this timeout is exceeded, at which point the Operation fails with a `NexusOperationTimedOut` event. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:193 -->

The timeout covers the full Nexus Operation lifecycle. Asynchronous Operations are scheduled, started, and completed. Synchronous Operations don't have an intermediate started state because they complete as part of the start request. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:197 -->

In Temporal Cloud, the maximum Schedule-to-Close timeout is 60 days. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:199 -->

### Schedule-to-Start (Server v1.31.0+)

Limits how long the caller is willing to wait for the Operation to be started (or completed, if synchronous) by the handler. If the Operation is not started within this timeout, it fails with `TIMEOUT_TYPE_SCHEDULE_TO_START`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:203 -->

If not set or set to zero, no Schedule-to-Start timeout is enforced. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:206 -->

Requires Temporal Server version 1.31.0 or later. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:210 -->

### Start-to-Close (Server v1.31.0+)

Limits how long the caller is willing to wait for an asynchronous Operation to complete after it has been started. If the Operation does not complete within this timeout after starting, it fails with `TIMEOUT_TYPE_START_TO_CLOSE`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:216 -->

Applies only to asynchronous Operations. Synchronous Operations ignore this timeout because they complete as part of the start request. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:219 -->

If not set or set to zero, no Start-to-Close timeout is enforced. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:222 -->

Requires Temporal Server version 1.31.0 or later. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:226 -->

## Retries and circuit breaking

Once the caller Workflow schedules an Operation with the caller's Temporal Service, the caller's Nexus Machinery keeps trying to start the Operation. If a retryable Nexus error is returned, the Nexus Machinery retries until the Operation's Schedule-to-Start or Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:173 --> The Nexus request is retried up to the default Retry Policy's max attempts and expiration interval. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:176 -->

To control retry behavior, return a non-retryable Nexus error. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:183 -->

### Circuit breaker

Nexus implements circuit breaking per caller-Namespace/Endpoint pair ("destination pair"). Each destination pair trips and resets independently. By default, the circuit breaker activates after 5 consecutive retryable errors. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:232 -->

State machine: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:236 -->

- **Open** — After tripping, the breaker stops sending requests.
- **Half-open** — After 60 seconds, the breaker allows a single probe request.
- **Closed** — If the probe succeeds, the breaker returns to normal operation. If it fails, it returns to open for another 60 seconds.

Worker availability affects the breaker: if no workers are polling the handler Task Queue — due to a deployment issue, crash, or scale-down — Nexus requests time out, and consecutive timeouts count as retryable errors and trip the breaker just like application-level errors. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:242 -->

Different Operations within the same destination pair contribute to the trip count. A given Operation may have fewer than 5 attempts when the circuit breaker opens. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:264 -->

Circuit breaker state surfaces in Pending Nexus Operations and Pending Callbacks. Check it in the UI, CLI, or `DescribeWorkflowExecution` API. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:254 --> When open, pending Operations show a `Blocked` state with a `BlockedReason`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:257 --> Cancellation requests surface the same pattern with `CancelationState: Blocked` and `CancelationBlockedReason`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:285 -->

## Deployment patterns

There are two common patterns for building and deploying Nexus Services. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:26 -->

### Collocated (default)

The collocated pattern runs Nexus Operation handlers in the same Worker and on the same Task Queue as the underlying Workflows. The Nexus Endpoint targets the same Task Queue used by the underlying Workflows. A single Worker registers both Nexus Services and Workflow types, so everything runs together. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:33 -->

Why start here: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:40 -->

- **Simplest setup** — one Worker, one Task Queue, one deployment.
- **Eager Workflow Start** — when the handler starts a Workflow in the same Worker, the first Workflow Task can run locally without an extra call to the Temporal Server while still recording durable state.
- **Clean facade** — Operations act as a stable contract; you can change the underlying implementation (Signal today, Workflow tomorrow) without impacting callers.

Use this pattern by default unless you have a good reason to use the router-queue pattern. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:52 -->

### Router-queue

The router-queue pattern separates Nexus routing from Workflow execution. A dedicated Nexus Worker on a "router" Task Queue routes Operations to Workflows on other Task Queues in the same Namespace. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:56 -->

When to use: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:58 -->

- **Separate scaling** — scale Nexus routing independently from Workflow execution.
- **Dedicated routing layer** — a single Nexus Worker routes requests to multiple Workflow types on different Task Queues.
- **Different IAM permissions** — Worker fleets behind different Task Queues may have different IAM permissions to different underlying resources.
- **Avoid modifying existing Workers** — add a router Worker to a Namespace without changing any existing Workers or Workflows.

How it works: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:65 -->

1. Register a Nexus Worker that polls a dedicated "router" Task Queue.
2. Configure the Nexus Endpoint's target Task Queue to point to this router Task Queue.
3. In each Nexus Operation handler, specify a different target Task Queue in the Workflow start options.
4. Existing Workers continue to poll their own Task Queues and execute the Workflows started by the router.

## Error handling (cross-SDK)

Nexus Operations can return errors for a caller Workflow to handle. Errors from an asynchronous Operation's underlying Workflow propagate back to the caller. <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:24 -->

By default, handler errors are retryable unless they are: <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:30 -->

- Application Failures explicitly marked as non-retryable.
- Nexus Operation errors that resolve an Operation as failed or canceled.
- Non-retryable Nexus errors.

When the caller's Nexus Machinery receives an error: <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:36 -->

- **Non-retryable** — A `NexusOperationFailed` event is added to the caller's Workflow History.
- **Retryable** — The Nexus Machinery automatically retries. These errors surface in Pending Operations.

### Handler error types

The predefined handler error type set is: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, `NOT_IMPLEMENTED`, `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, `UPSTREAM_TIMEOUT`. <!-- docs/develop/python/nexus/feature-guide.mdx:335 --> <!-- docs/develop/typescript/nexus/feature-guide.mdx:348 -->

Default mapping when a handler throws an Application Failure: <!-- docs/references/failures.mdx:186 -->

| `non_retryable` | Nexus error                | HTTP status code          |
| :-------------- | :------------------------- | :------------------------ |
| false (default) | HandlerErrorTypeInternal   | 500 Internal Server Error |
| true            | UnsuccessfulOperationError | 424 Failed Dependency     |

Retryable Nexus error types: <!-- docs/references/failures.mdx:204 -->

| Nexus error type                  | `non_retryable` |
| :-------------------------------- | :-------------- |
| HandlerErrorTypeResourceExhausted | false           |
| HandlerErrorTypeInternal          | false           |
| HandlerErrorTypeNotImplemented    | false           |
| HandlerErrorTypeUnavailable       | false           |

Non-retryable Nexus error types: <!-- docs/references/failures.mdx:213 -->

| Nexus error type                | `non_retryable` |
| :------------------------------ | :-------------- |
| HandlerErrorTypeBadRequest      | true            |
| HandlerErrorTypeUnauthenticated | true            |
| HandlerErrorTypeUnauthorized    | true            |
| HandlerErrorTypeNotFound        | true            |
| UnsuccessfulOperationError      | true            |

<!-- VERIFY: Docs disagree on whether RESOURCE_EXHAUSTED is retryable. docs/references/failures.mdx:106 lists RESOURCE_EXHAUSTED among handler error types treated as non-retryable, while docs/develop/python/nexus/feature-guide.mdx:335 and docs/develop/typescript/nexus/feature-guide.mdx:348 list RESOURCE_EXHAUSTED as retryable (and the retryable Nexus errors table at docs/references/failures.mdx:204 lists HandlerErrorTypeResourceExhausted with non_retryable=false). Which source is authoritative? -->

<!-- VERIFY: docs/references/failures.mdx:106 omits NOT_IMPLEMENTED from the non-retryable handler error list, while the Python/TypeScript SDK feature guides list NOT_IMPLEMENTED as non-retryable. Confirm intended classification. -->

### Nexus Operation Failure

When a Nexus Operation fails, the caller receives a Nexus Operation Failure containing the operation name, token, and failure reason. The `cause` field indicates the type of error (for example, Application Error or Canceled Error). <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:50 -->

A Nexus Operation Failure includes: <!-- docs/references/failures.mdx:259 -->

- `Endpoint` — the name of the endpoint.
- `Service` — the name of the service.
- `Operation` — the name of the operation.
- `Operation_token` — set if this is an async operation; can be used to perform additional actions like cancelling the operation.
- `Scheduled_event_id` — the caller's event id that scheduled the operation.
- `Message` — a generic unsuccessful error message.
- `Cause` — the underlying Application Failure (`Non-retryable=true`, `Type`=error type name, `Message`=error message).
- `Nexus_error_code` — the underlying Nexus error code.

Application Errors thrown from a Workflow created by a Nexus New-Workflow-Run-Operation handler are automatically propagated to the caller as a non-retryable error and result in a Nexus Operation Execution Failure. <!-- docs/references/failures.mdx:121 -->

See `references/core/error-reference.md` for non-Nexus error semantics.

## Security

### Runtime access controls

In Temporal Cloud, each Endpoint has an access control policy: an allowlist of caller Namespaces. <!-- docs/encyclopedia/nexus/nexus-security.mdx:33 --> No callers are allowed by default, even if in the same Namespace as the Endpoint target. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:67 -->

Workers authenticate with their Namespace using mTLS or API key. When a caller Workflow executes a Nexus Operation, Temporal Cloud verifies the caller's Namespace is in the Endpoint's allowlist before routing the request to the handler. Temporal Cloud acts as a trusted broker across Namespace boundaries. <!-- docs/encyclopedia/nexus/nexus-security.mdx:40 -->

Self-hosted deployments can implement custom Authorizers. <!-- docs/encyclopedia/nexus/nexus-security.mdx:29 -->

### Secure connectivity

Temporal Cloud has built-in secure connectivity across all Namespaces in an Account. Self-hosted deployments rely on the Temporal Cluster being secure. <!-- docs/encyclopedia/nexus/nexus-security.mdx:50 -->

Temporal Cloud secures all Nexus communication: <!-- docs/encyclopedia/nexus/nexus-security.mdx:56 -->

- Workers authenticate to their Namespace using mTLS or API key.
- mTLS encrypts all cross-Namespace Nexus traffic (start, cancel, and completion callbacks) across cells and regions.
- Endpoints are only accessible from within a Temporal Cloud Account through the Temporal SDK — not externally accessible.

### Payload encryption (three approaches)

Nexus uses the same Data Converter as Workflows and Activities — JSON, Proto, and binary payloads are all supported. If you use a Codec for encryption, it also encrypts Nexus payloads. Caller and handler Workers must have compatible Data Converters; payloads are encrypted by the sender. <!-- docs/encyclopedia/nexus/nexus-security.mdx:64 -->

- **Option 1: Same encryption key** — Both Namespaces share the same encryption key. Simplest approach; no additional configuration needed. <!-- docs/encyclopedia/nexus/nexus-security.mdx:72 -->
- **Option 2: Pass KMS key ID in payload metadata** — Each Namespace uses its own encryption key, with the KMS key ID passed in Temporal payload metadata. The receiver reads the key ID from metadata and decrypts using KMS IAM permissions. Works bi-directionally. The Codec Server needs KMS decrypt permissions for all relevant keys. <!-- docs/encyclopedia/nexus/nexus-security.mdx:78 -->
- **Option 3: Wrapper types for endpoint-specific encryption keys** — Use wrapper types (for example, `EndpointValue`) so the Data Converter selects an Endpoint-specific encryption key. Encrypts only Nexus traffic with a dedicated key, without sharing Namespace keys across teams. <!-- docs/encyclopedia/nexus/nexus-security.mdx:87 -->

Options 1 and 2 work with the standard Data Converter. Option 3 is more advanced and is intended for teams that don't want to share their Namespace encryption keys with other teams. <!-- docs/encyclopedia/nexus/nexus-security.mdx:94 -->

## Multi-caller attachment and multi-level calls

Operations started with New-Workflow-Run-Operation automatically attach a completion Callback to the handler Workflow. Additional callers can attach to the same handler Workflow using a Conflict-Policy of Use-Existing. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:350 -->

Each handler Workflow has a Callback limit (configurable for self-hosted; see Cloud limits for Temporal Cloud). Callers that exceed the limit receive an error. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:354 -->

When a handler Workflow uses Continue-As-New, existing completion Callbacks are copied to the new Execution. The previous Execution's Callbacks remain in `Standby` state indefinitely. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:357 -->

Nexus Operations can be composed across multiple services and teams. A handler Workflow can call another Nexus Operation, forming a chain (Workflow A → Nexus Op 1 → Workflow B → Nexus Op 2 → Workflow C). Each step is a separate, durable Operation with its own retries and failure handling. <!-- docs/encyclopedia/nexus/nexus.mdx:114 -->

## Managing Endpoints

### Self-hosted: `temporal operator nexus endpoint`

Nexus Endpoint commands follow the syntax `temporal operator nexus endpoint [command] [options]`. <!-- docs/cli/operator.mdx:338 -->

#### `create` <!-- docs/cli/operator.mdx:341 -->

Create a Nexus Endpoint on the Server. The endpoint target may either be a Worker (in which case `--target-namespace` and `--target-task-queue` must both be provided) or an external URL (in which case `--target-url` must be provided). Fails if an Endpoint with the same name is already registered. <!-- docs/cli/operator.mdx:343 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--description` | No | Nexus Endpoint description (Markdown supported). |
| `--description-file` | No | Path to the Nexus Endpoint description file (Markdown supported). |
| `--name` | Yes | Endpoint name. |
| `--target-namespace` | No | Namespace where a handler Worker polls for Nexus tasks. |
| `--target-task-queue` | No | Task Queue that a handler Worker polls for Nexus tasks. |
| `--target-url` | No | External Nexus Endpoint that receives forwarded Nexus requests (Experimental). |
<!-- docs/cli/operator.mdx:363 -->

#### `delete` <!-- docs/cli/operator.mdx:372 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--name` | Yes | Endpoint name. |
<!-- docs/cli/operator.mdx:382 -->

#### `get` <!-- docs/cli/operator.mdx:386 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--name` | Yes | Endpoint name. |
<!-- docs/cli/operator.mdx:396 -->

#### `list` <!-- docs/cli/operator.mdx:400 -->

Lists all Nexus Endpoints on the Server. Uses global flags only. <!-- docs/cli/operator.mdx:408 -->

#### `update` <!-- docs/cli/operator.mdx:410 -->

Update an existing Nexus Endpoint on the Server. The Endpoint is patched; existing fields for which flags are not provided are left as they were. <!-- docs/cli/operator.mdx:419 -->

| Flag | Required | Description |
|------|----------|-------------|
| `--description` | No | Nexus Endpoint description (Markdown supported). |
| `--description-file` | No | Path to the Nexus Endpoint description file (Markdown supported). |
| `--name` | Yes | Endpoint name. |
| `--target-namespace` | No | Namespace where a handler Worker polls for Nexus tasks. |
| `--target-task-queue` | No | Task Queue that a handler Worker polls for Nexus tasks. |
| `--target-url` | No | External Nexus Endpoint that receives forwarded Nexus requests (Experimental). |
| `--unset-description` | No | Unset the description. |
<!-- docs/cli/operator.mdx:440 -->

### Temporal Cloud: `tcld nexus endpoint`

The `tcld nexus` commands manage Nexus resources in Temporal Cloud (alias `nxs`). <!-- docs/cloud/tcld/nexus.mdx:15 --> The `tcld nexus endpoint` group (alias `ep`) includes `allowed-namespace`, `create`, `delete`, `get`, `list`, and `update`. <!-- docs/cloud/tcld/nexus.mdx:26 -->

#### `tcld nexus endpoint create` <!-- docs/cloud/tcld/nexus.mdx:147 -->

Creates a new Nexus Endpoint on the Cloud Account. The endpoint target is a Worker, and `--target-namespace` and `--target-task-queue` must both be provided. Fails if an endpoint with the same name is already registered. <!-- docs/cloud/tcld/nexus.mdx:149 -->

| Flag | Alias | Description |
|------|-------|-------------|
| `--allow-namespace` | `ans` | Namespace that is allowed to call this endpoint (optional). |
| `--description` | `d` | Endpoint description in markdown format (optional). |
| `--description-file` | `df` | Endpoint description file in markdown format (optional). |
| `--name` | `n` | Endpoint name. |
| `--request-id` | `r` | The request-id to use for the asynchronous operation, if not set the server will assign one (optional). |
| `--target-namespace` | `tns` | Namespace in which a handler worker will be polling for Nexus tasks. |
| `--target-task-queue` | `ttq` | Task Queue in which a handler worker will be polling for Nexus tasks. |
<!-- docs/cloud/tcld/nexus.mdx:156 -->

#### `tcld nexus endpoint delete` <!-- docs/cloud/tcld/nexus.mdx:198 -->

| Flag | Alias | Description |
|------|-------|-------------|
| `--name` | `n` | Endpoint name. |
| `--request-id` | `r` | Request-id for the async operation (optional). |
| `--resource-version` | `v` | Resource-version (etag) to update from (optional). |
<!-- docs/cloud/tcld/nexus.mdx:205 -->

#### `tcld nexus endpoint get` <!-- docs/cloud/tcld/nexus.mdx:223 -->

| Flag | Alias | Description |
|------|-------|-------------|
| `--name` | `n` | Endpoint name. |
<!-- docs/cloud/tcld/nexus.mdx:229 -->

#### `tcld nexus endpoint list` <!-- docs/cloud/tcld/nexus.mdx:235 -->

Lists all Nexus Endpoint configurations on the Cloud Account. <!-- docs/cloud/tcld/nexus.mdx:237 -->

#### `tcld nexus endpoint update` <!-- docs/cloud/tcld/nexus.mdx:241 -->

Updates an existing Nexus Endpoint. The endpoint is patched; fields without flags are left unchanged. <!-- docs/cloud/tcld/nexus.mdx:243 -->

| Flag | Alias | Description |
|------|-------|-------------|
| `--description` | `d` | Endpoint description in markdown format (optional). |
| `--description-file` | `df` | Endpoint description file in markdown format (optional). |
| `--name` | `n` | Endpoint name. |
| `--request-id` | `r` | Request-id for the async operation (optional). |
| `--resource-version` | `v` | Resource-version (etag) to update from (optional). |
| `--target-namespace` | `tns` | Namespace in which a handler worker will be polling for Nexus tasks (optional). |
| `--target-task-queue` | `ttq` | Task Queue in which a handler worker will be polling for Nexus tasks (optional). |
| `--unset-description` | — | Unset endpoint description. |
<!-- docs/cloud/tcld/nexus.mdx:251 -->

#### `tcld nexus endpoint allowed-namespace`

Manage the allowed namespaces for a Nexus Endpoint (alias `an`). Subcommands: `add`, `list`, `remove`, `set`. <!-- docs/cloud/tcld/nexus.mdx:36 -->

| Subcommand | Key flags |
|------------|-----------|
| `add` | `--name`, `--namespace`, `--request-id`, `--resource-version` <!-- docs/cloud/tcld/nexus.mdx:45 --> |
| `list` | `--name` <!-- docs/cloud/tcld/nexus.mdx:75 --> |
| `remove` | `--name`, `--namespace`, `--request-id`, `--resource-version` <!-- docs/cloud/tcld/nexus.mdx:87 --> |
| `set` | `--name`, `--namespace`, `--request-id`, `--resource-version` <!-- docs/cloud/tcld/nexus.mdx:117 --> |

### UI, Terraform, and Cloud Ops API

Endpoints can be managed using the Temporal UI, CLI, Terraform provider, or Cloud Ops API. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:39 --> For Temporal Cloud, Nexus Endpoints can also be managed through the Temporal Cloud Terraform provider. <!-- docs/cloud/nexus/index.mdx:41 --> For self-hosted deployments, the Operator API provides programmatic access. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:129 -->

## Roles and permissions (Temporal Cloud)

| Action | Required permissions |
|--------|----------------------|
| View or search Endpoints | Read-only role (or higher) at the Account level |
| Manage Endpoints | Developer role (or higher) and Namespace Admin on target Namespace |
<!-- docs/encyclopedia/nexus/nexus-registry.mdx:114 -->

For self-hosted deployments, custom Authorizers can be implemented to restrict access. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:108 -->

## Debugging

Nexus supports end-to-end execution debugging across caller Workflows, Nexus Operations, and handler Workflows — even across multi-level calls spanning multiple Namespaces. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:25 -->

### Bi-directional linking

Bidirectional links connect Nexus Operation events in the caller's Workflow History to corresponding events in the handler's Workflow History. They are automatically wired by SDK builder functions like New-Workflow-Run-Operation, enabling click-through navigation across Namespaces, regions, and clouds in the Temporal UI. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:29 -->

- **Forward** — from a caller's Nexus Operation event to the handler's Workflow. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:38 -->
- **Backward** — from the handler's Workflow back to the caller's Nexus Operation event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:39 -->

### Pending Nexus Operations

Pending Nexus Operations are displayed in the UI on the Workflow details page and can be listed from the CLI using `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:43 -->

Example CLI output: <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:55 -->

```
temporal workflow describe

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

Retryable errors surface in the Pending Operation. Non-retryable errors resolve the Operation with a `Failed`, `TimedOut`, or `Canceled` event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:72 -->

### Pending Callbacks

Nexus completion callbacks are sent from the handler's Namespace to the caller's Namespace for asynchronous Operations. View them in the UI or via `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:77 -->

### Tracing

Temporal integrates with OpenTelemetry and OpenTracing to visualize call graphs across Activities, Nexus Operations, and Child Workflows. Enable tracing by installing an interceptor on the Client or Worker. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:103 -->

## Metrics

Nexus provides SDK metrics, Cloud metrics, and OSS Cluster metrics in addition to integrated execution debugging. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:27 -->

### SDK metrics

Emitted from a Nexus Worker: <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:31 -->

- `nexus_poll_no_task`
- `nexus_task_schedule_to_start_latency`
- `nexus_task_execution_failed`
- `nexus_task_execution_latency`
- `nexus_task_endtoend_latency`

### Cloud metrics

Emitted by Temporal Cloud: <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:41 -->

- Caller Namespace
  - `RespondWorkflowTaskCompleted` — schedule a Nexus Operation.
- Handler Namespace
  - `PollNexusTaskQueue` — get a Nexus Task to process (for example, to start a Nexus Operation).
  - `RespondNexusTaskCompleted` — report the Nexus Task was successful.
  - `RespondNexusTaskFailed` — report the Nexus Task failed.

### OSS Cluster metrics

Emitted from an OSS Cluster: <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:52 -->

- History Service metrics
- Concurrency Limiter metrics
- Frontend Service metrics

## Versioning Nexus services

Task Routing is the simplest way to version Nexus service code. For backward-incompatible changes, use a different Service name and Task Queue (for example, `prod.payments.v2`). Callers migrate to the new version on their own deployment schedule. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:343 -->

## Temporal Cloud limits

Nexus limits applicable to Temporal Cloud: <!-- docs/cloud/nexus/limits.mdx:28 -->

- **Rate limits** — Nexus requests count toward the Namespace RPS limit. <!-- docs/cloud/nexus/limits.mdx:30 -->
- **Endpoint count** — 100 Endpoints per Account (default). <!-- docs/cloud/nexus/limits.mdx:31 -->
- **In-flight Operations** — 30 in-flight Operations per Workflow. <!-- docs/cloud/nexus/limits.mdx:32 -->
- **Request timeout** — Less than 10 seconds for a handler to process a start or cancel request. <!-- docs/cloud/nexus/limits.mdx:33 -->
- **Duration** — 60-day maximum Schedule-to-Close duration. <!-- docs/cloud/nexus/limits.mdx:34 -->
- **Callbacks** — 2000 callbacks per Workflow, governing how many Nexus callers can attach to a handler Workflow. <!-- docs/cloud/nexus/limits.mdx:35 -->

## Temporal Cloud extras

Temporal Cloud builds on the core Nexus experience with a global Nexus Registry scoped to an entire Account, built-in runtime access controls, audit logging for Registry actions, multi-region connectivity across AWS and GCP via a global mTLS-secured Envoy mesh (compatible with High Availability Namespaces as Endpoint targets), and Terraform support. <!-- docs/cloud/nexus/index.mdx:35 -->

## When to use Nexus

Use Nexus when you need cross-team service contracts, cross-Namespace orchestration, or multi-region connectivity within Temporal — without exposing each team's internal implementation. <!-- docs/encyclopedia/nexus/nexus.mdx:31 --> For an evaluation of whether Nexus fits a use case, see the evaluation guide at `/evaluate/nexus`. <!-- docs/encyclopedia/nexus/nexus.mdx:27 -->

## See also

- `references/go/nexus.md` — Go SDK Nexus code.
- `references/python/nexus.md` — Python SDK Nexus code.
- `references/java/nexus.md` — Java SDK Nexus code.
- `references/typescript/nexus.md` — TypeScript SDK Nexus code.
- `references/dotnet/nexus.md` — .NET SDK Nexus code.
- `references/core/error-reference.md` — non-Nexus error semantics.
- `references/core/troubleshooting.md` — general troubleshooting decision trees.
