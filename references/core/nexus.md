# Temporal Nexus

This document provides a conceptual overview of Temporal Nexus. See `references/{your_language}/nexus.md` for language-specific implementation details and code examples.

## Overview

Temporal Nexus connects Temporal Applications across Namespace boundaries. It provides modular service contracts so teams can expose durable operations to other teams while maintaining fault isolation, security, and independent deployment.

## Why Nexus

**Without Nexus**, cross-namespace communication requires ad-hoc integrations — direct API calls, shared databases, or message queues — that lose Temporal's durability guarantees at the boundary.

**With Nexus**, cross-namespace calls are first-class Temporal operations with built-in retries, circuit breaking, rate limiting, and load balancing — all managed by the Temporal Nexus Machinery.

## Core Concepts

### Nexus Endpoint

A reverse proxy that routes requests from a caller Namespace to a handler Namespace and Task Queue. Endpoints decouple callers from handlers — the caller only knows the endpoint name, not the target namespace or task queue.

The caller addresses an endpoint by name. The endpoint routes the request to its configured handler Namespace and Task Queue, where a handler Worker receives it. The result is delivered back to the caller through Temporal.

### Nexus Service

A contract that defines a set of operations exposed through an endpoint. Services declare operation names and their input/output types. The contract is shared between caller and handler code.

### Nexus Operation

A single unit of work within a service. Operations follow a lifecycle that supports both:

- **Synchronous operations** — Return immediately (within ~10 seconds). Suitable for quick lookups, validations, or triggering signals/updates on existing workflows.
- **Asynchronous operations (Workflow Run)** — Start a workflow and track it to completion. Suitable for long-running work that benefits from Temporal's durable execution.

### Nexus Registry

The registry manages endpoint configuration. It is scoped to an Account in Temporal Cloud or to a Cluster for self-hosted deployments. Adding an endpoint to the registry deploys it so it is available at runtime.

## How It Works

### Operation Lifecycle

A caller Workflow schedules an operation with `execute_operation()` or `start_operation()`. The Temporal Service records the request and routes it through the Nexus Endpoint to a Worker polling the handler's Task Queue. A synchronous handler returns its result during the request. A Workflow Run handler starts a Workflow and returns before it finishes; Temporal later delivers the Workflow's result through a completion callback.

### Built-in Nexus Machinery

The Nexus Machinery is the Temporal Service logic that tracks operation progress durably, retries requests after retryable failures, and delivers asynchronous results through completion callbacks. It provides:

- **At-least-once execution** with automatic retries
- **Circuit breaking** to prevent cascading failures
- **Rate limiting** and **load balancing**
- Support for arbitrary-duration operations via the Nexus RPC protocol

### Event History

Nexus operations called from a Workflow generate events in the caller workflow's history:

| Operation Type | Events |
|---------------|--------|
| Synchronous | `NexusOperationScheduled` → `NexusOperationCompleted` |
| Asynchronous | `NexusOperationScheduled` → `NexusOperationStarted` → `NexusOperationCompleted` |

## Multi-Level Calls

Nexus supports chaining across multiple namespaces: a Workflow in Namespace A calls a Nexus operation handled in Namespace B. That handler starts a Workflow, which can call another Nexus operation handled in Namespace C.

Each hop adds its own retry and fault isolation boundary.

## Error Handling

Nexus introduces two handler-side exception types and one caller-side type:

- **Operation Error** — Raised in handlers to report that the operation failed or was canceled. This is a terminal outcome; Nexus does not retry the operation automatically.
- **Handler Error** — Raised in handlers to report a request-processing failure, with explicit retryability control. Use for transient infrastructure failures (retryable) or permanent handler issues (non-retryable).
- **Nexus Operation Error** — Raised in the caller workflow when a Nexus operation fails. Wraps the underlying cause, accessible via the error chain.

Calling Nexus operations lets caller Workflows catch a Nexus Operation Error and inspect its cause, similarly to catching failures from Activities and Child Workflows. The Nexus Machinery automatically retries retryable handler failures until the operation's Schedule-to-Close timeout; those intermediate failures do not immediately fail the caller Workflow. See [Nexus error handling](https://docs.temporal.io/nexus/error-handling), [Workflow error handling patterns](patterns.md), and `references/{your_language}/error-handling.md`.

## Cancellation

Caller workflows can cancel in-progress Nexus operations. Cancellation types control the behavior:

| Cancellation Type | Behavior |
|-------------------|----------|
| `WAIT_COMPLETED` (default) | Wait for the operation to fully complete after cancellation |
| `WAIT_REQUESTED` | Wait for cancellation to be acknowledged by the handler |
| `TRY_CANCEL` | Request cancellation and immediately report as cancelled |
| `ABANDON` | Do not send a cancellation request |

## Infrastructure Setup

For operations called from a Workflow, set up:

1. **Separate namespaces** for independently managed caller and handler applications; they can share a Namespace when a service contract is useful within one Namespace. See [When to Use Nexus](#when-to-use-nexus) to choose between Nexus and Child Workflows.
2. **A Nexus Endpoint** in the registry, routing to the handler's namespace and task queue
3. **Handler workers** with Nexus service handlers registered
4. **Caller workers** with workflows that create Nexus clients

### Temporal Cloud

- Nexus connectivity works within and across regions
- Built-in access controls via namespace allowlists on endpoints
- Workers authenticate via mTLS client certificates or API keys

### Self-Hosted

- Supported within a single cluster
- Custom authorizers may be used for access control

## When to Use Nexus

| Scenario | Use Nexus? | Alternative |
|----------|-----------|-------------|
| Cross-team service contracts | Yes | — |
| Cross-namespace workflow orchestration | Yes | — |
| Same-namespace, same-team workflow composition | Maybe | Child workflows are simpler |
| Single workflow calling activities | No | Use activities directly |
| Simple parent-child workflow relationship | No | Use child workflows |

## Best Practices

1. **Keep service contracts shared** — Define in a module importable by both caller and handler code
2. **Use business-meaningful workflow IDs** — Keep the ID stable across retries of the same logical request and choose explicit conflict policies for running executions and reuse policies for completed executions so retries cannot start duplicate work
3. **Match operation type to duration** — Sync for <10s work, workflow run for anything longer
4. **Co-locate handlers and workflows** — Start with both registered on the same Worker: backing Workflows default to the handler's Task Queue, so this ensures a Worker can execute them. To deploy them separately, specify the backing Workflow's Task Queue and run Workers with its Workflow definition registered there.
5. **Design for at-least-once delivery** — Handlers should be idempotent, just like activities (see idempotency patterns in `references/core/patterns.md`)
6. **Isolate failure domains** — Put independently owned services in separate Namespaces, and deploy and scale their handler Workers independently of caller Workers so a handler rollout or capacity change does not require redeploying callers
