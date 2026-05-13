# Cross-Namespace Deprecation — Go SDK

A Child Workflow Execution is "spawned from within another Workflow in the same Namespace" <!-- docs/encyclopedia/child-workflows/child-workflows.mdx:31 -->. Cross-Namespace parent-child, SignalExternal, and CancelExternal commands were possible on OSS Temporal Server through the `system.enableCrossNamespaceCommands` configuration, but that configuration is disabled on Temporal Cloud <!-- docs/cloud/migrate/automated.mdx:419-420 -->. The supported alternative for inter-Namespace interaction on Temporal Cloud is [Temporal Nexus](/nexus) <!-- docs/evaluate/temporal-cloud/security.mdx:76 -->.

This reference scopes which Go SDK APIs are affected, what remains supported, and where to go next.

## What is affected

The restriction applies only to commands that target a Workflow in a *different* Namespace from the caller. Specifically, the server commands implicated are `SignalExternalWorkflowExecution` and `RequestCancelExternalWorkflowExecution` <!-- docs/references/commands.mdx:58 --> <!-- docs/references/commands.mdx:67 -->, plus the parent-child `StartChildWorkflowExecutionInitiated` path <!-- docs/develop/go/workflows/child-workflows.mdx:25 -->.

In the Go SDK these surface as:

- `workflow.ExecuteChildWorkflow` <!-- docs/develop/go/workflows/child-workflows.mdx:34 --> together with `workflow.ChildWorkflowOptions` <!-- docs/develop/go/workflows/child-workflows.mdx:36 -->. The `Namespace` field on `ChildWorkflowOptions` <!-- godoc: workflow#ChildWorkflowOptions (linked from docs/develop/go/workflows/child-workflows.mdx:36) --> is what makes a child cross-Namespace; omitting it (or setting it equal to the parent's Namespace) keeps the call same-Namespace.
- `workflow.SignalExternalWorkflow` <!-- docs/develop/go/workflows/message-passing.mdx:295 -->. The third argument is the target Namespace string; an empty string targets the caller's own Namespace. Passing a different Namespace name makes the call cross-Namespace.
- `workflow.RequestCancelExternalWorkflow` <!-- godoc: workflow#RequestCancelExternalWorkflow (linked from docs/references/commands.mdx:67) -->. Same shape: a Namespace argument decides whether the call is cross-Namespace.

None of these Go functions are deprecated wholesale. They remain the correct API for same-Namespace use. Only the cross-Namespace variant is rejected on Temporal Cloud.

## Server configuration: `system.enableCrossNamespaceCommands`

`system.enableCrossNamespaceCommands` is a Temporal Server dynamic-configuration key. On self-hosted OSS it gates parent-child across Namespaces, `SignalExternal`, and `CancelExternal`. On Temporal Cloud the key is disabled, and this is not a per-Namespace toggle a customer can flip <!-- docs/cloud/migrate/automated.mdx:419-422 -->.

There is no corresponding Go SDK option, no worker-side flag, and no CLI flag that controls this — the only switch is the server dynamic-config key, and it lives on the server side.

## Scope of the restriction — same-Namespace is unaffected

Same-Namespace use of every API above remains fully supported:

- `workflow.ExecuteChildWorkflow` without setting the `Namespace` field, or with `Namespace` equal to the parent's, is unchanged <!-- docs/develop/go/workflows/child-workflows.mdx:34 -->.
- `workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal)` — empty Namespace string targets the caller's Namespace — is the documented Go pattern <!-- docs/develop/go/workflows/message-passing.mdx:295 -->.
- `workflow.RequestCancelExternalWorkflow` with the caller's own Namespace stays supported <!-- godoc: workflow#RequestCancelExternalWorkflow (linked from docs/references/commands.mdx:67) -->.

If you are not crossing a Namespace boundary, nothing here applies.

## Supported alternative: Temporal Nexus

For interaction *across* Namespaces, Temporal Nexus is the supported model on Temporal Cloud: "The only way for Workflows in one Namespace to interact with Workflows in another Namespace is through Temporal Nexus" <!-- docs/evaluate/temporal-cloud/security.mdx:76 -->.

Before Nexus, cross-Namespace Child Workflows were "Limited to the same Namespace. Cross-Namespace use leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options." <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:51 -->. Nexus replaces these patterns with a service contract between caller and handler <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:55 -->.

Nexus is not a drop-in for the Child Workflow / SignalExternal / CancelExternal APIs — it introduces a different contract built from a Nexus Endpoint, a Nexus Service contract, and Nexus Operations <!-- docs/develop/go/nexus/feature-guide.mdx:27 -->. Migrating means redesigning the cross-Namespace boundary as a Nexus Service rather than a renamed function call.

For the full Go SDK Nexus walkthrough — running a dev Server, creating caller and handler Namespaces, defining a Nexus Service contract, implementing Operation handlers, and calling Nexus from a Workflow — see the Go Nexus feature guide: `docs/develop/go/nexus/feature-guide.mdx` <!-- docs/develop/go/nexus/feature-guide.mdx:29-38 -->.

## Migration notes for Temporal Cloud

If you are migrating from a self-hosted OSS Temporal Server to Temporal Cloud, the automated-migration limitations note is explicit: "The `system.enableCrossNamespaceCommands` configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration." <!-- docs/cloud/migrate/automated.mdx:421-422 -->.

Practical implication for a Go codebase planning Cloud migration:

1. Audit `workflow.ChildWorkflowOptions` literals for a non-empty `Namespace` value.
2. Audit `workflow.SignalExternalWorkflow` and `workflow.RequestCancelExternalWorkflow` call sites for a Namespace argument that differs from the caller's Namespace.
3. For each cross-Namespace call site, design a replacement Nexus Service and Operation per the Go Nexus feature guide. Same-Namespace call sites need no change.
4. Disable `system.enableCrossNamespaceCommands` on the source self-hosted cluster before migration so that any remaining cross-Namespace command surfaces as a server-side failure during testing rather than silently after cutover. <!-- VERIFY: the docs do not name the specific server error string returned when a cross-Namespace command is rejected; treat the error type as opaque and test for failure rather than parsing the message. -->

## What NOT to do

- Do not treat `workflow.SignalExternalWorkflow` or `workflow.RequestCancelExternalWorkflow` as deprecated. Only cross-Namespace use is restricted on Cloud; same-Namespace use is the supported pattern <!-- docs/develop/go/workflows/message-passing.mdx:295 -->.
- Do not look for a worker config flag or a Go SDK option to "re-enable" cross-Namespace commands. The only toggle is the server dynamic-config key `system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:420 -->, and it is disabled on Cloud.
- Do not invent a CLI flag (e.g. `--enable-cross-namespace`) or an environment variable (e.g. `TEMPORAL_ENABLE_CROSS_NAMESPACE`). No such flag or variable is documented.
- Do not assume Nexus is a drop-in replacement for cross-Namespace Child Workflows. The contract shape is different — Endpoint, Service, Operation <!-- docs/develop/go/nexus/feature-guide.mdx:27 -->.
- Do not pin behavior to a specific Temporal Server or SDK version: the documentation cited here does not pin the change to a versioned deprecation/removal timeline. Treat the Cloud restriction as a present-tense Cloud configuration <!-- docs/cloud/migrate/automated.mdx:419-422 -->.
