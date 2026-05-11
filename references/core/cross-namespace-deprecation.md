# Cross-Namespace Deprecation

## Overview

Temporal has historically supported a small set of cross-Namespace Commands — parent-child Workflow start, SignalExternal, and CancelExternal — gated by a server configuration named `system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:419-420 -->. That configuration is disabled on Temporal Cloud <!-- docs/cloud/migrate/automated.mdx:420 -->, and Temporal Cloud isolates Namespaces by default: the only supported way for Workflows in one Namespace to interact with Workflows in another is [Temporal Nexus](#migration-path-temporal-nexus) <!-- docs/evaluate/temporal-cloud/security.mdx:76 -->. Code that previously issued cross-Namespace Commands must be updated or removed before migrating to Cloud <!-- docs/cloud/migrate/automated.mdx:421-422 -->.

Language-specific guidance lives in:

- `references/go/cross-namespace-deprecation.md`
- `references/java/cross-namespace-deprecation.md`

## What is gated

`system.enableCrossNamespaceCommands` governs three Workflow Commands <!-- docs/cloud/migrate/automated.mdx:419 -->:

- `StartChildWorkflowExecution` — spawns a [Child Workflow Execution](/child-workflows) <!-- docs/references/commands.mdx:49-51 -->.
- `SignalExternalWorkflowExecution` — sends a Signal to another Workflow Execution <!-- docs/references/commands.mdx:58-60 -->.
- `RequestCancelExternalWorkflowExecution` — requests cancellation of another Workflow Execution <!-- docs/references/commands.mdx:67-69 -->.

When the configuration is off, these Commands cannot cross Namespace boundaries. Same-Namespace use of all three Commands is unaffected.

## Server-side configuration

The setting is named `system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:420 -->. The docs describe two postures:

- **Temporal Cloud**: the configuration is disabled <!-- docs/cloud/migrate/automated.mdx:420 -->. Namespaces are isolated by default, and inter-Namespace communication goes through Temporal Nexus <!-- docs/evaluate/temporal-cloud/security.mdx:76 -->.
- **OSS / self-hosted migrating to Cloud**: the configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration <!-- docs/cloud/migrate/automated.mdx:421-422 -->.

<!-- VERIFY: what is the default value of system.enableCrossNamespaceCommands on a fresh OSS install? The docs only say OSS "supports" cross-Namespace commands "through" this configuration; they do not state the default. -->

## Why Namespaces are isolated

On Temporal Cloud, Namespaces are isolated by default. The only supported way for Workflows in one Namespace to interact with Workflows in another Namespace is through Temporal Nexus, which provides controlled, secure cross-Namespace communication via Nexus Endpoints <!-- docs/evaluate/temporal-cloud/security.mdx:74-76 -->. Each team retains ownership of its own Namespace while sharing capabilities through clean service contracts <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:45 -->.

## Migration path: Temporal Nexus

Temporal Nexus is the documented replacement for cross-Namespace interaction <!-- docs/evaluate/temporal-cloud/security.mdx:76 -->. The Nexus documentation explicitly calls out the limitations of the old approaches under a "Before Nexus" heading <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:48 -->:

- **Child Workflows** — "Limited to the same Namespace. Cross-Namespace use leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options." <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:51 -->
- **Activity wrappers** — require per-target mTLS clients and error-prone boilerplate for async results <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:52 -->.
- **Extra gateway infrastructure** — not durable and adds another service to manage <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:53 -->.

Nexus replaces these with "a clean service contract between caller and handler" <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:55 -->. Caller and handler Workflows are siblings that communicate across Namespace boundaries through a Nexus Endpoint, a reverse proxy that decouples callers from handlers <!-- docs/encyclopedia/nexus/nexus.mdx:42-43 --> <!-- docs/encyclopedia/nexus/nexus.mdx:78-80 -->. Callers reference an Endpoint by name and never need to know the handler's Namespace, Task Queue, or internal implementation <!-- docs/encyclopedia/nexus/nexus.mdx:79-80 -->.

For SDK-level migration steps and code, see the language-specific references:

- `references/go/cross-namespace-deprecation.md`
- `references/java/cross-namespace-deprecation.md`

## Not the same as `DeprecateNamespace`

Do not confuse cross-Namespace deprecation (the gating of three Commands by `system.enableCrossNamespaceCommands`) with the `DeprecateNamespace` API. `DeprecateNamespace` updates the state of a registered Namespace to "DEPRECATED"; once a Namespace is deprecated you cannot start new Workflow Executions on it, and all existing and running Workflow Executions on a deprecated Namespace continue to run <!-- docs/develop/java/client/namespaces.mdx:147 -->. That is a whole-Namespace lifecycle operation. Cross-Namespace command deprecation is a server-config-driven restriction on three specific Commands and does not change any Namespace's registered state.

## Affected SDKs

The skill covers cross-Namespace deprecation migration for:

- Go — see `references/go/cross-namespace-deprecation.md`.
- Java — see `references/java/cross-namespace-deprecation.md`.
