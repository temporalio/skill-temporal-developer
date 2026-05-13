# Cross-Namespace Operations: Deprecation and Migration

Temporal historically allowed certain Workflow-issued Commands to target a Workflow Execution in a *different* Namespace from the caller. That behavior is gated by a server-side dynamic configuration flag, and it is disabled on Temporal Cloud. Code that still relies on it must be updated or removed before migrating to Temporal Cloud.

This page is the cross-language concept reference. For SDK-specific API guidance, see the language siblings linked at the bottom.

## What "cross-Namespace operation" means

A Child Workflow Execution is, by definition, "a Workflow Execution that is spawned from within another Workflow in the same Namespace." <!-- docs/encyclopedia/child-workflows/child-workflows.mdx:31 --> Same-Namespace is the design intent: parent/child semantics, Parent Close Policy propagation, and the rest of the child Workflow contract are scoped to one Namespace.

A "cross-Namespace operation" is the historical behavior where a Workflow issues one of the following Commands against a Workflow Execution in a *different* Namespace than its own:

- `StartChildWorkflowExecution` <!-- docs/references/commands.mdx:49 --> — spawning a Child Workflow Execution. <!-- docs/references/commands.mdx:51 -->
- `SignalExternalWorkflowExecution` <!-- docs/references/commands.mdx:58 --> — signaling another Workflow Execution. <!-- docs/references/commands.mdx:60 -->
- `RequestCancelExternalWorkflowExecution` <!-- docs/references/commands.mdx:67 --> — requesting cancellation of another Workflow Execution. <!-- docs/references/commands.mdx:69 -->

These are the three Commands affected by the deprecation framing below. They are still valid Commands when used *within* a single Namespace; only the cross-Namespace variants are gated.

## The server-side gate

A single dynamic configuration key controls whether the server accepts the cross-Namespace forms of these Commands:

`system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:420 -->

The docs describe the gate as follows: "OSS supports cross-Namespace commands (e.g., parent-child, SignalExternal, CancelExternal) through the `system.enableCrossNamespaceCommands` configuration. This configuration is disabled on Temporal Cloud." <!-- docs/cloud/migrate/automated.mdx:419 --> <!-- docs/cloud/migrate/automated.mdx:420 -->

For migration to Cloud, the docs are explicit: "The `system.enableCrossNamespaceCommands` configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration." <!-- docs/cloud/migrate/automated.mdx:420 --> <!-- docs/cloud/migrate/automated.mdx:421 --> <!-- docs/cloud/migrate/automated.mdx:422 -->

The migration docs do not state a default value for this dynamic configuration key on OSS; they only say OSS "supports" the behavior through it, and Cloud has it "disabled". Treat any assumption about the OSS default as something to verify against your own Cluster's configuration.

## What this means for your code

- **If you target Temporal Cloud**, any code path that issues `StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, or `RequestCancelExternalWorkflowExecution` against a different Namespace will not work. It must be updated or removed prior to migration. <!-- docs/cloud/migrate/automated.mdx:421 --> <!-- docs/cloud/migrate/automated.mdx:422 -->
- **If you run self-hosted OSS** with `system.enableCrossNamespaceCommands` enabled, existing cross-Namespace calls continue to function on that Cluster — but they are a migration blocker the moment you plan to move to Cloud, or to disable the flag. <!-- docs/cloud/migrate/automated.mdx:419 --> <!-- docs/cloud/migrate/automated.mdx:420 -->
- **The SDK surface area is what changes in your code.** Each SDK historically exposed a way to express a target Namespace alongside Child Workflow / Signal-external / Cancel-external APIs. Those affordances are being phased out in line with the server-side gate. The specific field names, options structs, and migration recipes are SDK-specific — see the language pages.

## Why same-Namespace is the design intent

The encyclopedia framing is unambiguous: a Child Workflow Execution is "spawned from within another Workflow in the same Namespace." <!-- docs/encyclopedia/child-workflows/child-workflows.mdx:31 --> The parent/child relationship — including Parent Close Policy and Cancellation propagation — is a single-Namespace contract. Cross-Namespace use of these Commands was an extension of that contract that the platform is moving away from.

If your application is structured so that a Workflow in one Namespace needs to drive work in another Namespace, the supported mechanism is Temporal Nexus, not a cross-Namespace Child Workflow.

## The supported cross-Namespace mechanism: Temporal Nexus

Temporal Nexus is the supported way to connect Temporal Applications within and across Namespaces. It is now Generally Available for Temporal Cloud and self-hosted deployments. <!-- docs/encyclopedia/nexus/nexus-security.mdx:24 -->

Nexus models cross-Namespace communication as Nexus Operations against a Nexus Endpoint, with Temporal Cloud acting as a trusted broker across Namespace boundaries — verifying the caller's Namespace against the Endpoint's allowlist before routing the request to the handler. <!-- docs/encyclopedia/nexus/nexus-security.mdx:41 --> <!-- docs/encyclopedia/nexus/nexus-security.mdx:42 --> Workers authenticate with their Namespace using mTLS or API key, and mTLS encrypts all cross-Namespace Nexus traffic — including start, cancel, and completion callbacks — across cells and regions. <!-- docs/encyclopedia/nexus/nexus-security.mdx:40 --> <!-- docs/encyclopedia/nexus/nexus-security.mdx:58 --> <!-- docs/encyclopedia/nexus/nexus-security.mdx:59 -->

Note: Nexus is not a literal one-to-one replacement for Child Workflows. Child Workflows remain the right tool for same-Namespace workflow composition. Nexus is the right tool when the work genuinely needs to cross a Namespace boundary. Re-shape the design around Nexus Operations rather than expecting to swap a Child Workflow call for a Nexus call without changes.

For the API and configuration details, follow the language-specific Nexus feature guides linked from the Temporal documentation rather than re-deriving them here.

## Language-specific guidance

The deprecated SDK surface and the migration steps differ between SDKs. See:

- Go: `references/go/cross-namespace-deprecation.md`
- Java: `references/java/cross-namespace-deprecation.md`

These pages cover the affected SDK APIs, what to remove, and how to restructure code that previously relied on a cross-Namespace target.
