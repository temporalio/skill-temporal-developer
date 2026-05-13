# Cross-Namespace Deprecation (Java SDK)

## TL;DR

Cross-Namespace commands (parent-child Workflows, SignalExternalWorkflowExecution, CancelExternalWorkflowExecution) are gated by the server-side dynamic configuration `system.enableCrossNamespaceCommands`, which is disabled on Temporal Cloud.   The Java SDK still exposes the APIs for child Workflows and external-Workflow stubs, but invocations that target a different Namespace will not work against a server with the default configuration. Code using cross-Namespace calls must be updated or removed prior to migrating to Temporal Cloud.  The supported replacement for crossing Namespace boundaries is [Temporal Nexus](/evaluate/nexus), which is Generally Available on Temporal Cloud and self-hosted deployments.

## What "cross-Namespace" means here

"Cross-Namespace commands" in this context refers specifically to the categories called out by the Temporal Cloud migration documentation: parent-child Workflows, `SignalExternal`, and `CancelExternal`.  That is, a Workflow Execution running in one Namespace issuing a command that targets a Workflow Execution in a different Namespace.

OSS Temporal supports these commands through the `system.enableCrossNamespaceCommands` configuration.  Temporal Cloud has this configuration disabled.

## Why your code may have stopped working

`system.enableCrossNamespaceCommands` is a server-side dynamic configuration knob, not a client-side flag.  On Temporal Cloud the configuration is disabled, and Namespaces are isolated by default; the only supported way for Workflows in one Namespace to interact with Workflows in another Namespace on Cloud is through Temporal Nexus.

For automated server-to-Cloud (S2C) migration, the documented limitation states: "The `system.enableCrossNamespaceCommands` configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration."

These cross-Namespace APIs are therefore deprecated in effect for any deployment that follows the Cloud default. The Java SDK does not refuse to compile such calls; the behavior change is enforced by the server.

## The Java API shapes that are affected

### Child Workflows targeting a different Namespace

The standard same-Namespace shape uses `Workflow.newChildWorkflowStub(Class)` (or the untyped variant with `ChildWorkflowOptions.newBuilder()`).   Same-Namespace use is unaffected.

The affected shape is when `ChildWorkflowOptions` is configured to target a Namespace different from the parent Workflow's Namespace.

### External-Workflow stubs targeting a different Namespace

`Workflow.newExternalWorkflowStub(Class, workflowExecutionOrId)` is documented for sending Signals from one Workflow to another.  The untyped equivalent is `Workflow.newUntypedExternalWorkflowStub(String)`.

When the target Workflow lives in a different Namespace from the caller, the resulting `SignalExternalWorkflowExecution` (or `CancelExternalWorkflowExecution`) command is one of the categories gated by `system.enableCrossNamespaceCommands`.  Same-Namespace external Signals and cancellations are unaffected.

## What still works

- Same-Namespace child Workflows via `Workflow.newChildWorkflowStub` / `Workflow.newUntypedChildWorkflowStub`.
- Same-Namespace external-Workflow Signals via `Workflow.newExternalWorkflowStub`.
- Same-Namespace untyped external-Workflow stubs via `Workflow.newUntypedExternalWorkflowStub`.
- Namespace isolation as a Cloud security guarantee: Namespaces are isolated by default and the only supported cross-Namespace interaction path on Cloud is Temporal Nexus.

## Migrate to Nexus

Temporal Nexus is Generally Available for Temporal Cloud and self-hosted deployments.  The Java SDK's Nexus support is also Generally Available.

Before Nexus, "Child Workflows - Limited to the same Namespace. Cross-Namespace use leaks underlying implementation details, requiring callers to manage the target Namespace, Task Queue, and Workflow options."  Nexus replaces this pattern with a service contract between caller and handler.

The Java Nexus feature guide demonstrates the model using two Namespaces: `my-target-namespace` (which contains the Nexus Operation handler) and `my-caller-namespace` (which contains the Workflow that calls the handler).   A Nexus Endpoint routes requests from caller to handler.

For the migration recipe (Endpoint setup, Service contract definition, Operation handlers, caller Workflow integration, and Cloud-specific `tcld` Endpoint creation with `--allow-namespace` allowlists), refer to `docs/develop/java/nexus/feature-guide.mdx`.  This page intentionally does not duplicate those steps.

Note that Nexus is the replacement for *cross-Namespace* Child Workflow patterns. Same-Namespace child Workflows and same-Namespace external-Workflow stubs continue to be the appropriate tools for in-Namespace composition.

## Common mistakes

- Treating `system.enableCrossNamespaceCommands` as a client-side or SDK-side flag. It is a server dynamic configuration.
- Assuming Temporal Cloud can be opted into cross-Namespace commands. The configuration is disabled on Cloud.
- Attempting an S2C migration without first updating or removing code that issues cross-Namespace commands.
- Replacing all child Workflows with Nexus. Nexus is the cross-Namespace replacement; same-Namespace child Workflows remain a first-class pattern.
- Using an mTLS / activity-wrapper gateway as a stand-in for cross-Namespace communication on Cloud instead of Nexus. The documented inter-Namespace interaction path on Cloud is Nexus.
