# Cross-Namespace Deprecation (Go SDK)

## TL;DR

Cross-Namespace Workflow commands in the Go SDK are deprecated in effect: the calls still compile, but Temporal Cloud disables the server-side `system.enableCrossNamespaceCommands` configuration, so any command in the affected categories will not work against Cloud (and is off by default in current OSS releases when that configuration is disabled).  The affected categories are parent-child, SignalExternal, and CancelExternal.  Migrate cross-Namespace use cases to Temporal Nexus, which is the supported cross-Namespace communication mechanism on Cloud and self-hosted deployments.

## What "cross-Namespace" means here

The Temporal docs name three command categories as cross-Namespace commands gated by `system.enableCrossNamespaceCommands`: parent-child, SignalExternal, and CancelExternal.  "Cross-Namespace" in this document refers specifically to Workflow code that issues one of those commands targeting a Namespace different from the caller's Namespace. Same-Namespace usage of the same APIs is not affected.

## Why your code may have stopped working

OSS supports cross-Namespace commands through the `system.enableCrossNamespaceCommands` configuration.  This is a server-side dynamic configuration, not a client-side SDK flag. On Temporal Cloud, the configuration is disabled.  For self-hosted-to-Cloud migration, Temporal requires that `system.enableCrossNamespaceCommands` be disabled and that code using cross-Namespace calls be updated or removed before migration.

Namespaces on Temporal Cloud are isolated by default, and the only supported way for Workflows in one Namespace to interact with Workflows in another Namespace is through Temporal Nexus.

## The Go API shapes that are affected

### Parent-child Workflow API

The Go SDK starts a Child Workflow with `workflow.ExecuteChildWorkflow`, taking a `workflow.Context`, `workflow.ChildWorkflowOptions`, the Workflow Type, and any parameters.  `workflow.ChildWorkflowOptions` is applied to the context via `workflow.WithChildOptions`.

When the child is targeted at a Namespace different from the parent's, this is the cross-Namespace parent-child shape gated by `system.enableCrossNamespaceCommands`.  Same-Namespace child workflows are unaffected and remain the supported shape.

### SignalExternalWorkflow

The Go SDK sends a Signal from one Workflow to another via `workflow.SignalExternalWorkflow`. The docs example is:

```go
err := workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal).Get(ctx, nil)
```

The third positional argument is the target Namespace. In the documented example it is the empty string, meaning "same Namespace as the caller."  Passing a remote Namespace name there makes the call a SignalExternal cross-Namespace command — one of the categories gated by `system.enableCrossNamespaceCommands`.

### CancelExternal

The docs name "CancelExternal" as one of the affected command categories.

## What still works

- Same-Namespace Child Workflows via `workflow.ExecuteChildWorkflow` with `workflow.ChildWorkflowOptions`, including the inheritance behavior where Workflow Option fields automatically inherit from the parent.
- Same-Namespace external Signals via `workflow.SignalExternalWorkflow` with the third argument left as the empty string.
- Namespace isolation as a Cloud security property: Namespaces are isolated by default.

Nexus does not replace same-Namespace child workflows or same-Namespace external-workflow stubs. It is the replacement for the cross-Namespace cases only.

## Migrate to Nexus

Temporal Nexus is Generally Available for both Temporal Cloud and self-hosted deployments.  Go SDK support for Nexus is Generally Available.

The Temporal docs explicitly call out the pre-Nexus pain point: "Child Workflows ... Limited to the same Namespace. Cross-Namespace use leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options."  Nexus replaces those patterns with a service contract between caller and handler.

The Go Nexus feature guide models the migration as two separate Namespaces — a caller Namespace and a handler (target) Namespace — connected by a Nexus Endpoint:

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```

 `my-target-namespace` contains the Nexus Operation handler; `my-caller-namespace` runs the Workflow that calls the handler.

For the full migration recipe — defining the Nexus Service contract, implementing handlers, developing a caller Workflow, and running across Namespaces on a dev server and on Temporal Cloud — see `docs/develop/go/nexus/feature-guide.mdx`.  This file deliberately does not duplicate those steps.

For Namespace registration and management in Go more broadly, see `docs/develop/go/client/namespaces.mdx`.

## Common mistakes

- Assuming `system.enableCrossNamespaceCommands` is a client-side or SDK-level flag. It is a server-side configuration.
- Leaving cross-Namespace calls in code during a self-hosted-to-Cloud migration. The migration guide requires the calls to be updated or removed first.
- Treating a non-empty third argument to `workflow.SignalExternalWorkflow` as harmless against Temporal Cloud — it converts the call into a SignalExternal cross-Namespace command.
- Reaching for Nexus to replace same-Namespace child workflows. Nexus is the cross-Namespace replacement; same-Namespace child workflows remain the supported shape.
- Assuming Namespace isolation can be relaxed on Cloud by configuration. The only supported cross-Namespace path on Cloud is Nexus.
