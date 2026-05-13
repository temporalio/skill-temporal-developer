# Nexus (Cross-SDK Concepts)

Language-agnostic reference for Temporal Nexus concepts. Per-language reference files document SDK surfaces and link back here.

## Overview

Nexus connects Temporal Applications across (and within) isolated Namespaces. <!-- docs/encyclopedia/nexus/nexus.mdx:37 --> Each team gets its own Namespace for security and fault isolation while exposing a clean service contract through a Nexus Endpoint. <!-- docs/encyclopedia/nexus/nexus.mdx:38 -->

Nexus is peer-to-peer, not hierarchical. Caller and handler Workflows are siblings that communicate across Namespace boundaries. <!-- docs/encyclopedia/nexus/nexus.mdx:42-43 -->

The four building blocks: Services, Operations, Endpoints, Registry. <!-- docs/encyclopedia/nexus/nexus.mdx:54-82 -->

## Services and Operations

A Nexus Service is a named collection of Nexus Operations that a team exposes. <!-- docs/encyclopedia/nexus/nexus.mdx:56 --> Operations abstract the underlying implementation - callers don't need to know whether an Operation starts a Workflow, sends a Signal, runs a Query, or executes other reliable code. <!-- docs/encyclopedia/nexus/nexus.mdx:57 -->

Services are registered in a Worker that polls the Endpoint's target Task Queue. Multiple Services can run in the same Worker. <!-- docs/encyclopedia/nexus/nexus-services.mdx:31-32 -->

Callers reference a Service by name when executing a Nexus Operation. <!-- docs/encyclopedia/nexus/nexus-services.mdx:35 -->

Operations are built using two SDK builder shapes (different SDKs name these differently):

- **New-Workflow-Run-Operation** - Start a Workflow as an asynchronous Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:59 -->
- **New-Sync-Operation** - Run a synchronous Operation: invoke a Query, Signal, or Update, or execute other reliable code using the Temporal SDK Client. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:60 -->

The Operation lifecycle supports two modes:

- **Asynchronous** - Starts a Workflow (same or different Task Queue, with optional Eager Start). Can run up to 60 days. <!-- docs/encyclopedia/nexus/nexus.mdx:61 -->
- **Synchronous** - Completes within the 10-second handler deadline. Use for Signals, Queries, Updates, or other reliable low-latency calls using the Temporal SDK Client. <!-- docs/encyclopedia/nexus/nexus.mdx:62 -->

## Endpoints and Registry

A Nexus Endpoint is a fully managed reverse proxy for Nexus Services. It routes requests from a caller Workflow to a target Namespace and Task Queue. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:25-26 --> Callers only need to know the Endpoint name. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:27 -->

A Nexus Endpoint acts as a reverse proxy for a single Nexus Service, routing requests to **one** target Namespace and Task Queue. It does not route to multiple backends. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:35-37 --> The `EndpointSpec` target type is **Worker**: route to a target Namespace and Task Queue. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:40 -->

Multiple Endpoints can target different Task Queues in the same Namespace. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:30 -->

Adding an Endpoint to the Nexus Registry deploys it immediately - available at runtime as soon as it's registered. <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:44 -->

### Registry

The Nexus Registry manages Endpoints. Endpoint names must be unique within the Registry. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:30-33 --> In Temporal Cloud, the Registry is global across the entire Account, spanning all Namespaces. In self-hosted deployments it is scoped to a Cluster. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:34-35 -->

Manage Endpoints using the Temporal UI, CLI, Terraform provider, or Cloud Ops API. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:39 -->

Everything except the Endpoint name can be edited. New Operations route to the updated target immediately. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:76-77 -->

Changing the target Namespace: in-flight async Operation completion callbacks point to the original handler Namespace and are unaffected, but Cancel requests route to the new target. Workflow IDs are scoped per Namespace, so Signal-With-Start can create duplicates. Recommendation: drain existing Nexus Operations and underlying handler Workflows before changing the target Namespace. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:79-85 -->

### Access policy

Creating an Endpoint includes setting an Access Policy - the allowlist of caller Namespaces permitted to use the Endpoint. **No callers are allowed by default**, even if in the same Namespace as the Endpoint target. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:66-67 -->

### Roles and permissions (Temporal Cloud)

| Action | Required permissions |
|---|---|
| View or search Endpoints | Read-only role (or higher) at the Account level <!-- docs/encyclopedia/nexus/nexus-registry.mdx:116 --> |
| Manage Endpoints | Developer role (or higher) and Namespace Admin on target Namespace <!-- docs/encyclopedia/nexus/nexus-registry.mdx:117 --> |

For self-hosted deployments, custom Authorizers can implement access restrictions. <!-- docs/encyclopedia/nexus/nexus-registry.mdx:108 -->

## Operation lifecycle

When a caller Workflow executes a Nexus Operation, the command is atomically handed off to the Nexus Machinery, which ensures at-least-once execution with automatic retries and reliable result delivery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:65-66 -->

### Synchronous lifecycle

Synchronous Operations must complete within the 10-second handler deadline, as measured from the caller's Nexus Machinery. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:75 -->

Events recorded on the caller's history for a sync Operation: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:84-94 -->

1. `ScheduleNexusOperation` command
2. `NexusOperationScheduled` event
3. (Handler processes the task via New-Sync-Operation and responds with result)
4. `NexusOperationCompleted` or `NexusOperationFailed` event

There is **no** `NexusOperationStarted` event for sync Operations — they complete as part of the start request. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:197 -->

Timed-out sync handlers are retried until the Operation's Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:104 -->

### Asynchronous lifecycle

Asynchronous Operations can run up to 60 days (the maximum Schedule-to-Close timeout in Temporal Cloud). <!-- docs/encyclopedia/nexus/nexus-operations.mdx:110 -->

Events recorded on the caller's history for an async Operation: <!-- docs/encyclopedia/nexus/nexus-operations.mdx:118-130 -->

1. `ScheduleNexusOperation` command
2. `NexusOperationScheduled` event
3. (Handler processes via New-Workflow-Run-Operation; responds with start Operation response)
4. `NexusOperationStarted` event
5. Handler Workflow completes; a Nexus Completion Callback is delivered to the caller's Nexus Machinery
6. `NexusOperationCompleted` or `NexusOperationFailed` event

### Terminal events

The caller's Nexus Machinery records a NexusOperation event in caller Workflow History on terminal outcomes: `NexusOperationStarted`, `NexusOperationCompleted`, `NexusOperationFailed`, `NexusOperationCanceled`, or `NexusOperationTimedOut`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:169 -->

### Executing code from a sync handler

Synchronous handlers can execute code directly but must complete within the handler deadline. Use the Temporal SDK Client to invoke Signals, Queries, Updates, or other reliable code. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:139-140 -->

Use async Operations for long-running work. Repeated sync handler failures can trip the circuit breaker, blocking all Operations from that caller to the Endpoint. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:144-145 -->

### Nexus Machinery

Built-in Nexus Machinery handles delivery with at-least-once execution: automatic retries with exponential backoff, rate limiting and concurrency limiting, circuit breaking (trips after 5 consecutive retryable errors), automatic load balancing. <!-- docs/encyclopedia/nexus/nexus.mdx:102-107 --> The Machinery uses Nexus RPC on the wire - a protocol supporting arbitrary-duration Operations. You interact only with the Temporal SDK, not Nexus RPC directly. <!-- docs/encyclopedia/nexus/nexus.mdx:109-110 -->

## Timeouts

Nexus Operations support three timeout types, set by the caller when scheduling the Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:188-189 -->

### Schedule-to-Close

Limits the total duration from when the Operation is scheduled to when it completes. The Nexus Machinery automatically retries failed requests internally until this timeout is exceeded, at which point the Operation fails with a `NexusOperationTimedOut` event. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:193-195 -->

In Temporal Cloud, the maximum Schedule-to-Close timeout is 60 days. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:199 --> Self-hosted is configurable.

### Schedule-to-Start

Limits how long the caller is willing to wait for the Operation to be started (or completed, if synchronous) by the handler. If not started within this timeout, fails with `TIMEOUT_TYPE_SCHEDULE_TO_START`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:203-204 --> If not set or set to zero, no Schedule-to-Start timeout is enforced. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:206 -->

**Requires Temporal Server 1.31.0 or later.** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:210 -->

### Start-to-Close

Limits how long the caller is willing to wait for an asynchronous Operation to complete after it has been started. If not completed in time, fails with `TIMEOUT_TYPE_START_TO_CLOSE`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:216-217 --> Only applies to asynchronous Operations; sync Operations ignore this timeout. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:219-220 --> If not set or set to zero, not enforced. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:222 -->

**Requires Temporal Server 1.31.0 or later.** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:226 -->

## Automatic retries and circuit breaking

### Retries

Once the caller Workflow schedules an Operation with the caller's Temporal Service, the caller's Nexus Machinery keeps trying to start the Operation. If a retryable Nexus error is returned, the Nexus Machinery retries until the Schedule-to-Start timeout or Schedule-to-Close timeout is exceeded. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:173-174 -->

Retries use the default Retry Policy's max attempts and expiration interval. This differs from Activity and Workflow error handling. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:176-180 -->

### Circuit breaking

Nexus implements circuit breaking per caller-Namespace/Endpoint pair (the "destination pair"). Each destination pair trips and resets independently. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:232-233 -->

- Trips after **5 consecutive retryable errors**. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:234 -->
- After tripping, enters _open_ state and stops sending requests. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:236 -->
- After **60 seconds**, transitions to _half-open_, allowing a single probe request. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:237 -->
- If the probe succeeds, returns to _closed_. If it fails, returns to _open_ for another 60 seconds. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:238-239 -->

Worker availability affects the circuit breaker. If no Workers are polling the handler Task Queue, Nexus requests will time out; consecutive timeouts count as retryable errors and trip the breaker. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:242-245 -->

Different Operations within the same destination pair contribute to the trip count. A given Operation may have fewer than 5 attempts when the circuit breaker opens. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:264-265 -->

Circuit breaker state surfaces in Pending Nexus Operations and Pending Callbacks. When open, pending Operations show a `Blocked` state with a `BlockedReason` of "The circuit breaker is open." Cancellation requests surface the same pattern with `CancelationState: Blocked` and `CancelationBlockedReason`. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:254-285 -->

## Execution semantics

### At-least-once and idempotency

The Nexus Machinery provides at-least-once execution semantics for a Nexus Operation, until the caller's Schedule-to-Close timeout is exceeded. The Machinery retries on handler timeouts or retryable errors, so a handler may be invoked multiple times for the same Operation. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:316-317 -->

Nexus Operation handlers should be idempotent, similar to Activities. Not strictly required in all cases, but highly recommended. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:319-320 -->

### Exactly-once

To upgrade to exactly-once, back the Operation with a Workflow that uses a `WorkflowIDReusePolicy` of `RejectDuplicates`. This allows only one Workflow Execution per Workflow ID within a Namespace for the Retention Period. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:324-325 -->

## Errors

### Retryable vs non-retryable

By default, handler errors are retryable unless they are: <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:30-34 -->

- Application Failures explicitly marked as non-retryable
- Nexus Operation errors that resolve an Operation as failed or canceled
- Non-retryable Nexus errors (the predefined handler error types listed below)

When the caller's Nexus Machinery receives an error: <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:36-39 -->

- **Non-retryable** - A `NexusOperationFailed` event is added to the caller's Workflow History.
- **Retryable** - The Nexus Machinery automatically retries. These errors surface in Pending Operations (not in Workflow History).

### Handler error types

Retryable Nexus errors: <!-- docs/references/failures.mdx:202-209 -->

| Nexus error type | `non_retryable` |
|---|---|
| `HandlerErrorTypeResourceExhausted` | false |
| `HandlerErrorTypeInternal` | false |
| `HandlerErrorTypeNotImplemented` | false |
| `HandlerErrorTypeUnavailable` | false |

Non-retryable Nexus errors: <!-- docs/references/failures.mdx:211-219 -->

| Nexus error type | `non_retryable` |
|---|---|
| `HandlerErrorTypeBadRequest` | true |
| `HandlerErrorTypeUnauthenticated` | true |
| `HandlerErrorTypeUnauthorized` | true |
| `HandlerErrorTypeNotFound` | true |
| `UnsuccessfulOperationError` | true |

<!-- VERIFY: The authoritative table at docs/references/failures.mdx:208 lists HandlerErrorTypeNotImplemented as retryable (non_retryable=false). Some per-language SDK feature guides may describe NOT_IMPLEMENTED as non-retryable; this concept reference follows the failures.mdx table. -->

The predefined handler-error subset called out as non-retryable in the lifecycle text: `BAD_REQUEST`, `UNAUTHENTICATED`, `UNAUTHORIZED`, `NOT_FOUND`, and `RESOURCE_EXHAUSTED`. <!-- docs/references/failures.mdx:106 --> <!-- VERIFY: failures.mdx:106 lists RESOURCE_EXHAUSTED as non-retryable in the bullet list of "errors are considered retryable, unless specified below", which conflicts with the table at failures.mdx:206 where HandlerErrorTypeResourceExhausted has non_retryable=false. The tables at failures.mdx:204-219 are the authoritative mapping for the SDK Nexus errors. -->

### Default Application Failure mapping

When a handler throws an Application Failure (rather than a typed Nexus error), it maps based on the `non_retryable` flag: <!-- docs/references/failures.mdx:184-191 -->

| `non_retryable` | Nexus error | HTTP status code |
|---|---|---|
| false (default) | `HandlerErrorTypeInternal` | 500 Internal Server Error |
| true | `UnsuccessfulOperationError` | 424 Failed Dependency |

For improved semantics and HTTP status mapping for external Nexus callers, prefer throwing a typed Nexus Error directly. <!-- docs/references/failures.mdx:195 -->

### Nexus Operation Failure on the caller side

A Nexus Operation Failure is delivered to the caller Workflow when a Nexus Operation fails. Cause is typically an Application Error or a Canceled Error. <!-- docs/references/failures.mdx:252-254 -->

A Nexus Operation Failure includes: <!-- docs/references/failures.mdx:259-271 -->

- `Endpoint` - name of the endpoint
- `Service` - name of the service
- `Operation` - name of the operation
- `Operation_token` - set if async (used to perform additional actions like cancelling)
- `Scheduled_event_id` - caller's event id that scheduled the operation
- `Message` - generic unsuccessful error message
- `Cause` - underlying Application Failure (`Non-retryable=true`, `Type`, `Message`)
- `Nexus_error_code` - underlying Nexus error code

### Workflow errors from async Operations

Application Errors thrown from a Workflow created by a Nexus New-Workflow-Run-Operation handler are automatically propagated to the caller as a non-retryable error and result in a Nexus Operation Execution Failure. <!-- docs/references/failures.mdx:121 -->

## Cancellation and termination

### Cancellation

Cancelling a caller Workflow automatically propagates to all pending Nexus Operations and their underlying handler Workflows. A canceled handler Workflow reports a Canceled Failure to the caller. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:329-330 -->

Only asynchronous Operations are cancelable (sync Operations complete as part of the start request). The Cancel pathway emits its own `NexusOperationCanceled` event when complete. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:169 -->

### Termination

Terminating a caller Workflow **abandons** all pending Nexus Operations. Unlike cancellation, no cancel request is sent to the handler Namespace, so handler Workflows continue running indefinitely, consuming resources until they time out or are manually stopped. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:334-336 -->

Because the handler runs in a separate Namespace, it has no signal that the caller is gone, making orphaned Operations difficult to detect. If the Nexus Operation was part of a multi-step process, termination leaves no opportunity to run compensation logic. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:336-338 -->

**Prefer cancellation over termination.** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:339 -->

## Versioning

Task Routing is the simplest way to version Nexus service code. For backward-incompatible changes, use a different Service name and Task Queue (for example, `prod.payments.v2`). Callers migrate to the new version on their own deployment schedule. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:343-345 -->

## Multi-level calls

Nexus Operations can be composed across multiple services and teams. A handler Workflow can call another Nexus Operation, forming a chain: <!-- docs/encyclopedia/nexus/nexus.mdx:114 -->

> Workflow A -> Nexus Op 1 -> Workflow B -> Nexus Op 2 -> Workflow C <!-- docs/encyclopedia/nexus/nexus.mdx:116 -->

Each step is a separate, durable Operation with its own retries and failure handling. This enables service composition across Namespaces without requiring direct connectivity or shared configuration between teams. <!-- docs/encyclopedia/nexus/nexus.mdx:118 -->

## Attaching multiple callers to one handler Workflow

Operations started with New-Workflow-Run-Operation automatically attach a completion Callback to the handler Workflow. Additional callers can attach to the same handler Workflow using a **Conflict-Policy of Use-Existing**. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:350-351 -->

Each handler Workflow has a Callback limit (configurable for self-hosted; see Cloud limits for Temporal Cloud). Callers that exceed the limit receive an error. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:354-355 -->

When a handler Workflow uses Continue-As-New, existing completion Callbacks are copied to the new Execution. The previous Execution's Callbacks remain in `Standby` state indefinitely. <!-- docs/encyclopedia/nexus/nexus-operations.mdx:357-358 -->

## Patterns

Two common deployment patterns: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:26-29 -->

### Collocated pattern (default)

Runs Nexus Operation handlers in the same Worker and on the same Task Queue as the underlying Workflows. The Nexus Endpoint targets the same Task Queue used by the underlying Workflows. A single Worker registers both Nexus Services and Workflow types. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:33-37 -->

Benefits: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:41-43 -->

- Simplest setup - one Worker, one Task Queue, one deployment
- Eager Workflow Start when the handler starts a Workflow in the same Worker
- Clean facade: Operations are a stable contract; underlying implementation can change

Use by default unless there's a good reason for the router-queue pattern. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:52 -->

### Router-queue pattern

Separates Nexus routing from Workflow execution. A dedicated Nexus Worker on a "router" Task Queue routes Operations to Workflows on other Task Queues in the same Namespace. <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:54-56 -->

When to use: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:58-63 -->

- Separate scaling: scale Nexus routing independently from Workflow execution
- Dedicated routing layer: single Nexus Worker routes to multiple Workflow types
- Different IAM permissions per Worker fleet
- Add Nexus to a Namespace without modifying existing Workers

How it works: <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:65-70 -->

1. Register a Nexus Worker that polls a dedicated "router" Task Queue
2. Configure the Nexus Endpoint's target Task Queue to point to this router Task Queue
3. In each Nexus Operation handler, specify a different target Task Queue in the Workflow start options
4. Existing Workers continue to poll their own Task Queues and execute the Workflows started by the router

## Security

### Runtime access controls

In Temporal Cloud, each Endpoint has an access control policy: an allowlist of caller Namespaces. <!-- docs/encyclopedia/nexus/nexus-security.mdx:33 --> When a caller Workflow executes a Nexus Operation, Temporal Cloud verifies the caller's Namespace is in the Endpoint's allowlist before routing to the handler. Temporal Cloud acts as a trusted broker across Namespace boundaries. <!-- docs/encyclopedia/nexus/nexus-security.mdx:41-42 -->

Self-hosted deployments can implement custom Authorizers. <!-- docs/encyclopedia/nexus/nexus-security.mdx:29 -->

### Secure connectivity

In Temporal Cloud: <!-- docs/encyclopedia/nexus/nexus-security.mdx:56-60 -->

- Workers authenticate to their Namespace using mTLS or API key
- mTLS encrypts all cross-Namespace Nexus traffic (start, cancel, and completion callbacks) across cells and regions
- Endpoints are only accessible from within a Temporal Cloud Account through the Temporal SDK - not externally accessible

Self-hosted deployments rely on the Temporal Cluster being secure. <!-- docs/encyclopedia/nexus/nexus-security.mdx:52 -->

### Payload encryption (three approaches)

Nexus uses the same Data Converter as Workflows and Activities. If you use a Codec for encryption, it also encrypts Nexus payloads. Caller and handler Workers must have compatible Data Converters. Payloads are encrypted by the sender. <!-- docs/encyclopedia/nexus/nexus-security.mdx:64-68 -->

1. **Same encryption key** - Both Namespaces share the same encryption key. Simplest; no additional configuration. <!-- docs/encyclopedia/nexus/nexus-security.mdx:72-75 -->
2. **KMS key ID in payload metadata** - Each Namespace uses its own encryption key; the KMS key ID is passed in Temporal payload metadata. Receiver reads the key ID from metadata and decrypts using KMS IAM permissions. Works bi-directionally. The Codec Server needs KMS decrypt permissions for all relevant keys. <!-- docs/encyclopedia/nexus/nexus-security.mdx:77-83 -->
3. **Wrapper types for endpoint-specific encryption keys** - Use wrapper types (for example, `EndpointValue`) so the Data Converter selects an Endpoint-specific encryption key. Encrypts only Nexus traffic with a dedicated key, without sharing Namespace keys across teams. <!-- docs/encyclopedia/nexus/nexus-security.mdx:87-90 -->

Options 1 and 2 work with the standard Data Converter. Option 3 is more advanced and intended for teams that don't want to share Namespace encryption keys with other teams. <!-- docs/encyclopedia/nexus/nexus-security.mdx:94-97 -->

## Observability

### Bidirectional linking

Bidirectional links connect Nexus Operation events in the caller's Workflow History to corresponding events in the handler's Workflow History. They are automatically wired by SDK builder functions like New-Workflow-Run-Operation, enabling click-through navigation across Namespaces, regions, and clouds in the Temporal UI. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:29-30 -->

- **Forward** - From a caller's Nexus Operation event to the handler's Workflow.
- **Backward** - From the handler's Workflow back to the caller's Nexus Operation event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:38-39 -->

### Pending Operations and Pending Callbacks

Pending Nexus Operations are displayed in the UI on the Workflow details page and can be listed via `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:43 -->

Retryable errors surface in the Pending Operation. Non-retryable errors resolve the Operation with a `NexusOperationFailed`, `NexusOperationTimedOut`, or `NexusOperationCanceled` event. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:72-73 -->

Nexus completion callbacks are sent from the handler's Namespace to the caller's Namespace for asynchronous Operations. Viewable in the UI or via `temporal workflow describe`. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:77-78 -->

### Tracing

Temporal integrates with OpenTelemetry and OpenTracing to visualize call graphs across Activities, Nexus Operations, and Child Workflows. Enable tracing by installing an interceptor on the Client or Worker. <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:104-105 -->

### Metrics

Three sources: SDK metrics, Cloud metrics, OSS Cluster metrics. <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:27 -->

**SDK metrics** (emitted from a Nexus Worker): <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:31-37 -->

- `nexus_poll_no_task`
- `nexus_task_schedule_to_start_latency`
- `nexus_task_execution_failed`
- `nexus_task_execution_latency`
- `nexus_task_endtoend_latency`

**Cloud metrics** (emitted by Temporal Cloud): <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:43-48 -->

- Caller Namespace: `RespondWorkflowTaskCompleted` (schedule a Nexus Operation)
- Handler Namespace: `PollNexusTaskQueue`, `RespondNexusTaskCompleted`, `RespondNexusTaskFailed`

**OSS Cluster metrics**: <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:54-56 -->

- History Service metrics
- Concurrency Limiter metrics
- Frontend Service metrics

## When to use Nexus

- Cross-team service contracts within or across Namespaces — each team owns its own Namespace and exposes a clean contract via an Endpoint. <!-- docs/encyclopedia/nexus/nexus.mdx:37-38 -->
- Service composition: multi-level calls chain durable Operations across Namespaces without requiring direct connectivity or shared configuration between teams. <!-- docs/encyclopedia/nexus/nexus.mdx:118 -->
- Peer-to-peer Workflow communication across Namespace boundaries (siblings, not hierarchical). <!-- docs/encyclopedia/nexus/nexus.mdx:42-43 -->
- Queue-based decoupling: if a Nexus Service is down, caller Workflows continue to schedule Operations and process them when the service is back up. <!-- docs/encyclopedia/nexus/nexus.mdx:88 -->
