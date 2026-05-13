# Temporal Nexus — Concepts and Management

Temporal Nexus lets a caller Workflow invoke operations exposed by another team's service through a typed contract, with Caller and handler Workflows running as siblings across Namespace boundaries via a managed reverse proxy <!-- docs/encyclopedia/nexus/nexus.mdx:37-43 -->. The Nexus Machinery handles delivery — automatic retries, rate and concurrency limiting, circuit breaking, and load balancing — using Nexus RPC on the wire while you interact only with the Temporal SDK <!-- docs/encyclopedia/nexus/nexus.mdx:100-110 -->. This file is the cross-SDK reference; per-SDK code (worker registration, builder functions, caller invocation, options structs) lives at `references/{sdk}/nexus.md`. Nexus the platform feature is Generally Available for Temporal Cloud and self-hosted deployments <!-- docs/encyclopedia/nexus/nexus.mdx:19-23 -->; per-SDK release stages vary and are documented in each per-SDK file.

## Core vocabulary

- **Nexus Service** — a named collection of Nexus Operations that provides a contract for sharing across team boundaries; a Nexus Endpoint exposes Services for callers to use <!-- docs/encyclopedia/nexus/nexus-services.mdx:28-29 -->. Multiple Services can run in the same Worker <!-- docs/encyclopedia/nexus/nexus-services.mdx:32 -->.
- **Nexus Operation** — the unit of work exposed by a Service; can be synchronous or asynchronous, and an asynchronous Operation carries an operation token used to re-attach to a long-running Workflow-backed Operation <!-- docs/encyclopedia/nexus/nexus-operations.mdx:40-41 -->.
- **Nexus Endpoint** — a fully managed reverse proxy for Nexus Services that routes requests from a caller Workflow to a target Namespace and Task Queue; callers only need to know the Endpoint name <!-- docs/encyclopedia/nexus/nexus-endpoints.mdx:25-27 -->.
- **Nexus Registry** — the place where Nexus Endpoints are managed; adding an Endpoint deploys it for immediate runtime use, and Endpoint names must be unique within the Registry <!-- docs/encyclopedia/nexus/nexus-registry.mdx:30-33 -->.
- **Nexus Machinery** — the platform component on each side that handles cross-Namespace delivery, at-least-once execution, retries, and result delivery <!-- docs/encyclopedia/nexus/nexus-operations.mdx:65-66; docs/encyclopedia/nexus/nexus.mdx:100-110 -->.
- **Caller Workflow** — a Workflow that executes a Nexus Operation through an Endpoint using the Temporal SDK <!-- docs/encyclopedia/nexus/nexus-operations.mdx:55 -->.
- **Handler Workflow** — for asynchronous Operations, the Workflow started by the handler that runs and ultimately delivers a completion callback to the caller <!-- docs/encyclopedia/nexus/nexus-operations.mdx:124-127 -->.
- **Service handler** — the implementation registered on a Worker that polls the Endpoint's target Task Queue; Operations are defined via SDK builder functions <!-- docs/encyclopedia/nexus/nexus-operations.mdx:57-60 -->.
- **Operation handler** — the specific Operation entry point built with `New-Workflow-Run-Operation` (asynchronous, starts a Workflow) or `New-Sync-Operation` (synchronous, runs Signal/Query/Update or other reliable code via the SDK Client) <!-- docs/encyclopedia/nexus/nexus-operations.mdx:59-60 -->.

## Operation lifecycle: synchronous vs. asynchronous

Nexus Operations execute in one of two modes, with different lifecycles, different recorded events, and different applicable timeouts. Do not flatten them together.

**Synchronous** Operations must complete within the 10-second handler deadline, measured from the caller's Nexus Machinery, and are appropriate for invoking a Signal, Query, or Update on a Workflow or executing other reliable low-latency code via the Temporal SDK Client <!-- docs/encyclopedia/nexus/nexus-operations.mdx:75-80; docs/encyclopedia/nexus/nexus.mdx:61-62 -->. The caller's Workflow history records `NexusOperationScheduled` then `NexusOperationCompleted` (or `NexusOperationFailed`); there is no intermediate Started event for a sync Operation because completion happens as part of the start request <!-- docs/encyclopedia/nexus/nexus-operations.mdx:86-94; docs/encyclopedia/nexus/nexus-operations.mdx:197 -->.

**Asynchronous** Operations are backed by a Workflow started by `New-Workflow-Run-Operation` and can run up to 60 days, the maximum Schedule-to-Close timeout in Temporal Cloud <!-- docs/encyclopedia/nexus/nexus-operations.mdx:110; docs/encyclopedia/nexus/nexus-operations.mdx:199 -->. The caller's history records `NexusOperationScheduled` → `NexusOperationStarted` → one of `NexusOperationCompleted`, `NexusOperationFailed`, `NexusOperationCanceled`, or `NexusOperationTimedOut`, with the terminal event written when the Nexus Completion Callback is delivered back to the caller's Nexus Machinery <!-- docs/encyclopedia/nexus/nexus-operations.mdx:118-128; docs/encyclopedia/nexus/nexus-operations.mdx:169 -->.

## Timeouts

Three timeouts control how long the caller is willing to wait at different stages of the Operation lifecycle; all are set by the caller when scheduling the Operation <!-- docs/encyclopedia/nexus/nexus-operations.mdx:186-189 -->.

- **Schedule-to-Close** — the overall timeout covering the full Operation lifecycle from scheduling through completion. The Nexus Machinery automatically retries internally until this is exceeded, at which point the Operation fails with a `NexusOperationTimedOut` event <!-- docs/encyclopedia/nexus/nexus-operations.mdx:191-197 -->. In Temporal Cloud, the maximum Schedule-to-Close is 60 days <!-- docs/encyclopedia/nexus/nexus-operations.mdx:199 -->.
- **Schedule-to-Start** — limits how long the caller will wait for the Operation to be started (or completed, if synchronous) by the handler; on expiry the Operation fails with `TIMEOUT_TYPE_SCHEDULE_TO_START`. If not set or set to zero, no Schedule-to-Start timeout is enforced. Requires Temporal Server 1.31.0 or later <!-- docs/encyclopedia/nexus/nexus-operations.mdx:201-211 -->.
- **Start-to-Close** — limits how long the caller will wait for an asynchronous Operation to complete after it has been started; on expiry the Operation fails with `TIMEOUT_TYPE_START_TO_CLOSE`. **Applies only to asynchronous Operations**; synchronous Operations ignore it because they complete as part of the start request. If not set or set to zero, no Start-to-Close timeout is enforced. Requires Temporal Server 1.31.0 or later <!-- docs/encyclopedia/nexus/nexus-operations.mdx:214-227 -->.

## Automatic retries and circuit breaking

Once a caller Workflow schedules an Operation, the caller's Nexus Machinery keeps trying to start it; on retryable Nexus errors or upstream timeouts it retries until either the Schedule-to-Start or Schedule-to-Close timeout is exceeded <!-- docs/encyclopedia/nexus/nexus-operations.mdx:173-176 -->. To bound retries explicitly, handlers return a non-retryable Nexus error <!-- docs/encyclopedia/nexus/nexus-operations.mdx:183-184 -->.

Circuit breaking runs per caller-Namespace/Endpoint pair ("destination pair"); each pair trips and resets independently <!-- docs/encyclopedia/nexus/nexus-operations.mdx:231-233 -->. By default the circuit breaker activates after **5 consecutive retryable errors** <!-- docs/encyclopedia/nexus/nexus-operations.mdx:234 -->. After tripping, it enters the *open* state and stops sending requests; after **60 seconds** it transitions to *half-open*, allowing a single probe request, and either returns to *closed* on success or back to *open* for another 60 seconds on failure <!-- docs/encyclopedia/nexus/nexus-operations.mdx:236-239 -->.

Worker unavailability contributes to circuit-breaker trips: if no Workers are polling the handler Task Queue, Nexus requests time out, and consecutive timeouts count as retryable errors <!-- docs/encyclopedia/nexus/nexus-operations.mdx:241-247 -->. Different Operations within the same destination pair contribute to the same trip count, so a given Operation may have fewer than five attempts when the breaker opens <!-- docs/encyclopedia/nexus/nexus-operations.mdx:264-265 -->.

State surfaces in Pending Nexus Operations and Pending Callbacks (UI, CLI, or `DescribeWorkflowExecution`): pending Operations show a `State` of `Blocked` with `BlockedReason: The circuit breaker is open.`, and cancellation requests use the parallel fields `CancelationState: Blocked` and `CancelationBlockedReason` <!-- docs/encyclopedia/nexus/nexus-operations.mdx:254-285 -->. From the CLI:

```sh
temporal workflow describe -w my-workflow-id
```

## Execution semantics

The Nexus Machinery provides at-least-once execution semantics until the Schedule-to-Close timeout is exceeded; a handler may be invoked multiple times for the same Operation, so handlers should be idempotent (not strictly required in all cases, but highly recommended) <!-- docs/encyclopedia/nexus/nexus-operations.mdx:314-320 -->. To upgrade to exactly-once, back the Operation with a Workflow that uses a `WorkflowIDReusePolicy` of `RejectDuplicates`, allowing only one Workflow Execution per Workflow ID within a Namespace for the Retention Period <!-- docs/encyclopedia/nexus/nexus-operations.mdx:322-325 -->.

## Cancellation and termination

Cancelling a caller Workflow automatically propagates to all pending Nexus Operations and their underlying handler Workflows; a canceled handler Workflow reports a Canceled Failure to the caller <!-- docs/encyclopedia/nexus/nexus-operations.mdx:328-330 -->. Only asynchronous Operations are cancelable in practice, because cancellation is routed using the operation token returned at start <!-- docs/encyclopedia/nexus/nexus-operations.mdx:40-41 -->.

Termination of a caller Workflow does **not** propagate. No cancel request is sent to the handler Namespace, so handler Workflows continue running indefinitely, consuming resources until they time out or are manually stopped; because the handler runs in a separate Namespace it has no signal that the caller is gone, making orphaned Operations difficult to detect and correlate, and leaving no opportunity to run compensation logic for multi-step processes. Prefer cancellation over termination whenever possible <!-- docs/encyclopedia/nexus/nexus-operations.mdx:332-339 -->.

## Attaching multiple callers to a handler Workflow

Operations started with `New-Workflow-Run-Operation` automatically attach a completion Callback to the handler Workflow, and additional callers can attach to the same handler Workflow using a Workflow ID Conflict-Policy of `Use-Existing` <!-- docs/encyclopedia/nexus/nexus-operations.mdx:350-351 -->. Each handler Workflow has a per-Workflow Callback limit (configurable for self-hosted, fixed by the Cloud limits documentation in Temporal Cloud); callers that exceed the limit receive an error <!-- docs/encyclopedia/nexus/nexus-operations.mdx:354-355 -->. When a handler Workflow uses Continue-As-New, existing completion Callbacks are copied to the new Execution, and the previous Execution's Callbacks remain in `Standby` state indefinitely <!-- docs/encyclopedia/nexus/nexus-operations.mdx:357-358 -->.

## Errors

Handler errors are retryable by default unless they are (a) Application Failures explicitly marked as non-retryable, (b) Nexus Operation errors that resolve an Operation as failed or canceled, or (c) Non-retryable Nexus errors <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:30-34 -->. When the caller's Nexus Machinery receives a non-retryable error, a `NexusOperationFailed` event is added to the caller's Workflow History; retryable errors are automatically retried by the Machinery and surface in Pending Operations until they succeed, are exhausted, or hit a timeout <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:36-39 -->.

On the caller side, a failed Nexus Operation produces a Nexus Operation Failure containing the operation name, token, and failure reason; the `cause` field indicates the underlying type (for example Application Error or Canceled Error) <!-- docs/encyclopedia/nexus/nexus-error-handling.mdx:48-51 -->. SDK-specific exception classes for catching and inspecting these failures are documented in each per-SDK file under `references/{sdk}/nexus.md`.

## Versioning

Task Routing is the simplest way to version Nexus service code: for backward-incompatible changes, use a different Service name and Task Queue (for example, `prod.payments.v2`), and let callers migrate to the new version on their own deployment schedule <!-- docs/encyclopedia/nexus/nexus-operations.mdx:343-345 -->.

## Deployment patterns

Two patterns are documented; use the collocated pattern by default and switch to the router-queue pattern only when you have a concrete reason <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:26-29 -->.

**Collocated (default).** Service handlers run in the same Worker and on the same Task Queue as the underlying Workflows. The Nexus Endpoint targets that Task Queue; a single Worker registers both Nexus Services and Workflow types. Benefits include the simplest setup (one Worker, one Task Queue, one deployment), Eager Workflow Start when the handler starts a Workflow in the same Worker (executes the first Workflow Task locally without an extra Server call while still recording durable state), and a clean facade where Operations are a stable contract decoupled from the underlying implementation <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:31-52 -->.

**Router-queue.** A dedicated Nexus Worker polls a "router" Task Queue and routes Operations to Workflows on other Task Queues in the same Namespace. The Endpoint's target Task Queue points at the router queue; each handler specifies a different target Task Queue in its Workflow start options; existing Workers continue to poll their own Task Queues and execute the Workflows the router starts. Use this pattern when you need independent scaling for routing vs. Workflow execution, different IAM permissions per Worker fleet, or to add Nexus to a Namespace without modifying existing Workers <!-- docs/encyclopedia/nexus/nexus-patterns.mdx:54-76 -->.

## Endpoint Registry

The Nexus Registry manages Nexus Endpoints. Adding an Endpoint to the Registry deploys it for immediate runtime use, and Endpoint names must be unique within the Registry <!-- docs/encyclopedia/nexus/nexus-registry.mdx:30-33 -->. In Temporal Cloud, the Registry is global across the entire Account, spanning all Namespaces; in self-hosted deployments it is scoped to a Cluster <!-- docs/encyclopedia/nexus/nexus-registry.mdx:34-35 -->. Manage Endpoints via the Temporal UI, CLI, Terraform provider, or Cloud Ops API <!-- docs/encyclopedia/nexus/nexus-registry.mdx:39 -->. Everything except the Endpoint name can be edited, and new Operations route to the updated target immediately <!-- docs/encyclopedia/nexus/nexus-registry.mdx:74-77 -->.

Changing the target Namespace mid-flight is consequential: in-flight async Operations' completion callbacks point to the original handler Namespace and are unaffected, but Cancel requests route to the new target; Workflow IDs are scoped per Namespace, so a Signal-With-Start creates a new Workflow in the new target even if the same ID is active in the old target, potentially producing duplicates. The documented recommendation is to drain existing Nexus Operations and underlying handler Workflows before retargeting <!-- docs/encyclopedia/nexus/nexus-registry.mdx:79-85 -->.

## Runtime access controls

Each Endpoint has an access control policy: an allowlist of caller Namespaces. **No callers are allowed by default, even if in the same Namespace as the Endpoint target** <!-- docs/encyclopedia/nexus/nexus-registry.mdx:66-67 -->. In Temporal Cloud, Workers authenticate with their Namespace via mTLS or API key; when a caller Workflow executes a Nexus Operation, Cloud verifies the caller's Namespace is in the Endpoint's allowlist before routing the request to the handler, acting as a trusted broker across Namespace boundaries <!-- docs/encyclopedia/nexus/nexus-security.mdx:40-42 -->. Self-hosted deployments can implement custom Authorizers <!-- docs/encyclopedia/nexus/nexus-security.mdx:28-29 -->.

## Secure connectivity and payload encryption

Temporal Cloud secures all cross-Namespace Nexus traffic: Workers authenticate to their Namespace via mTLS or API key, and mTLS encrypts start, cancel, and completion-callback traffic across cells and regions; Endpoints are only accessible from within a Temporal Cloud Account through the Temporal SDK, not externally <!-- docs/encyclopedia/nexus/nexus-security.mdx:56-60 -->. Self-hosted deployments rely on the Temporal Cluster being secure <!-- docs/encyclopedia/nexus/nexus-security.mdx:48-54 -->.

Nexus uses the same Data Converter as Workflows and Activities — JSON, Proto, and binary payloads are all supported — and if a Codec encrypts Workflow payloads it encrypts Nexus payloads too. Caller and handler Workers must have compatible Data Converters; payloads are encrypted by the sender (caller encrypts input, handler encrypts result) <!-- docs/encyclopedia/nexus/nexus-security.mdx:64-68 -->. Three common cross-Namespace encryption approaches are documented: a shared key on both sides (simplest), a per-Namespace key with the KMS key ID flowed in payload metadata so the receiver can decrypt with KMS IAM, or wrapper types (for example `EndpointValue`) so the Data Converter selects an Endpoint-specific key without sharing Namespace keys across teams <!-- docs/encyclopedia/nexus/nexus-security.mdx:70-97 -->.

## Execution debugging

Bi-directional links connect Nexus Operation events in the caller's Workflow History to corresponding events in the handler's Workflow History, automatically wired by SDK builder functions like `New-Workflow-Run-Operation`, enabling click-through navigation across Namespaces, regions, and clouds in the Temporal UI <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:28-30 -->. Pending Nexus Operations are visible in the UI on the Workflow details page and from the CLI via `temporal workflow describe`, surfacing fields like `Endpoint`, `Service`, `Operation`, `OperationToken`, `State`, `Attempt`, `ScheduleToCloseTimeout`, `NextAttemptScheduleTime`, `LastAttemptCompleteTime`, and `LastAttemptFailure` <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:42-70 -->. Pending Callbacks (sent from handler Namespace to caller Namespace for async Operations) are visible the same way <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:75-100 -->. Retryable errors surface in the Pending Operation; non-retryable errors resolve the Operation with a `NexusOperationFailed`, `NexusOperationTimedOut`, or `NexusOperationCanceled` event <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:72-73 -->.

Tracing integrates with OpenTelemetry and OpenTracing; install an interceptor on the Client or Worker to visualize call graphs across Activities, Nexus Operations, and Child Workflows <!-- docs/encyclopedia/nexus/nexus-execution-debugging.mdx:103-111 -->.

## Metrics

**SDK metrics** are emitted from a Nexus Worker: `nexus_poll_no_task`, `nexus_task_schedule_to_start_latency`, `nexus_task_execution_failed`, `nexus_task_execution_latency`, and `nexus_task_endtoend_latency` <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:31-37 -->.

**Cloud metrics** are emitted by Temporal Cloud. On the caller Namespace, `RespondWorkflowTaskCompleted` covers scheduling a Nexus Operation. On the handler Namespace, `PollNexusTaskQueue` polls for a Nexus Task to process (for example, to start an Operation), `RespondNexusTaskCompleted` reports a Nexus Task that succeeded, and `RespondNexusTaskFailed` reports one that failed <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:41-48 -->.

**OSS Cluster metrics** include History Service, Concurrency Limiter, and Frontend Service families <!-- docs/encyclopedia/nexus/nexus-metrics.mdx:52-56 -->. Refer out to `/references/cluster-metrics#nexus-metrics` for the full tables.

## Endpoint management via CLI

Two separate CLIs manage Nexus Endpoints; do not merge them.

### Self-hosted: `temporal operator nexus endpoint`

Subcommands `create`, `delete`, `get`, `list`, and `update` <!-- docs/cli/operator.mdx:331-448 -->. The full command path includes the `operator` group — `temporal operator nexus endpoint …`, not `temporal nexus endpoint …` <!-- docs/cli/operator.mdx:325-329 -->.

For `create` and `update`, the documented flags are `--name`, `--description`, `--description-file`, `--target-namespace`, `--target-task-queue`, and `--target-url` *(Experimental)*; `update` additionally supports `--unset-description` <!-- docs/cli/operator.mdx:363-370; docs/cli/operator.mdx:440-448 -->. The target may either be a Worker (in which case both `--target-namespace` and `--target-task-queue` must be provided) or an external URL via `--target-url` <!-- docs/cli/operator.mdx:345-348 -->.

```
temporal operator nexus endpoint create \
  --name your-endpoint \
  --target-namespace your-namespace \
  --target-task-queue your-task-queue \
  --description-file DESCRIPTION.md
```

<!-- docs/cli/operator.mdx:353-359 -->

### Temporal Cloud: `tcld nexus endpoint`

`tcld nexus` (alias `nxs`) provides `endpoint` (alias `ep`) <!-- docs/cloud/tcld/nexus.mdx:15-26 -->. Subcommands are `create`, `delete`, `get`, `list`, `update`, plus `allowed-namespace { add | list | remove | set }` for managing the allowlist on an existing Endpoint <!-- docs/cloud/tcld/nexus.mdx:28-43 -->.

For `tcld nexus endpoint create`, both `--target-namespace` and `--target-task-queue` must be provided (the target is a Worker), and supported flags include `--name`, `--target-namespace`, `--target-task-queue`, `--allow-namespace`, `--description`, `--description-file`, and `--request-id` <!-- docs/cloud/tcld/nexus.mdx:147-196 -->. Note that the create flag is `--allow-namespace` (singular allow) even though the post-creation management subcommand group is `allowed-namespace` <!-- docs/cloud/tcld/nexus.mdx:156-160 -->.

```
tcld nexus endpoint create \
  --name your-endpoint \
  --target-namespace your-namespace.your-account \
  --target-task-queue your-task-queue \
  --allow-namespace caller-namespace.your-account
```

<!-- docs/cloud/tcld/nexus.mdx:147-196 -->

## RBAC for the Registry (Cloud)

In Temporal Cloud the Nexus Registry respects RBAC permissions:

| Action                    | Required permissions                                                  |
|---------------------------|-----------------------------------------------------------------------|
| View or search Endpoints  | Read-only role (or higher) at the Account level                       |
| Manage Endpoints          | Developer role (or higher) and Namespace Admin on target Namespace    |

<!-- docs/encyclopedia/nexus/nexus-registry.mdx:114-117 -->

For self-hosted deployments, use custom Authorizers to restrict access <!-- docs/encyclopedia/nexus/nexus-registry.mdx:106-110 -->.
