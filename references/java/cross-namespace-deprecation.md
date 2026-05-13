# Cross-Namespace Deprecation — Java SDK

This page covers the Java SDK surface affected by the cross-Namespace Command deprecation. For the cross-language concept — what "cross-Namespace operation" means, which Commands are gated, and the server-side dynamic configuration key `system.enableCrossNamespaceCommands` — see `references/core/cross-namespace-deprecation.md`. This page only addresses how that deprecation lands in Java code.

## Affected Java SDK APIs

The Java SDK exposes three call sites that historically could target a Workflow Execution in a different Namespace than the caller. Each emits one of the gated Commands.

### Child Workflow APIs

A Child Workflow stub is created with `Workflow.newChildWorkflowStub(GreetingChild.class)`. <!-- docs/develop/java/workflows/child-workflows.mdx:42 --> Options are built with `ChildWorkflowOptions.newBuilder()` and applied via the same stub factory. <!-- docs/develop/java/workflows/child-workflows.mdx:153 --> <!-- docs/develop/java/workflows/child-workflows.mdx:161 --> <!-- docs/develop/java/workflows/child-workflows.mdx:164 --> The untyped form is `Workflow.newUntypedChildWorkflowStub("GreetingChild", ChildWorkflowOptions.newBuilder().setWorkflowId("childWorkflow").build())`. <!-- docs/develop/java/workflows/child-workflows.mdx:52 --> <!-- docs/develop/java/workflows/child-workflows.mdx:55 -->

The child-workflows feature guide documents `setParentClosePolicy` <!-- docs/develop/java/workflows/child-workflows.mdx:153 --> <!-- docs/develop/java/workflows/child-workflows.mdx:162 --> and `setWorkflowId` <!-- docs/develop/java/workflows/child-workflows.mdx:55 --> on `ChildWorkflowOptions.Builder`, but it does **not** document a builder method for setting a target Namespace. The historical namespace-setter on `ChildWorkflowOptions.Builder` is not described in the current Java child-workflows feature guide. <!-- VERIFY: deprecated namespace builder method on ChildWorkflowOptions.Builder is not present in docs/develop/java/workflows/child-workflows.mdx --> If your codebase calls a namespace-setter on `ChildWorkflowOptions.Builder` to target a different Namespace, treat it as deprecated and remove it — do not assume a documented replacement exists in this guide.

These call sites emit `StartChildWorkflowExecution`, which is the Command gated by `system.enableCrossNamespaceCommands` for the cross-Namespace case. See the core page for the Command list.

### Signal External Workflow

A Workflow Signals another Workflow via `Workflow.newExternalWorkflowStub`. The documented forms are:

- `Workflow.newExternalWorkflowStub(OtherWorkflow.class, otherWorkflowID)` <!-- docs/develop/java/workflows/message-passing.mdx:291 --> — typed stub by Workflow Id.
- `Workflow.newExternalWorkflowStub(java.lang.Class, io.temporal.api.common.v1.WorkflowExecution)` <!-- docs/develop/java/workflows/message-passing.mdx:287 --> — typed stub by `WorkflowExecution`.

Signal methods are then called on the returned stub:

```java
OtherWorkflow other = Workflow.newExternalWorkflowStub(OtherWorkflow.class, otherWorkflowID);
other.mySignalMethod();
```

<!-- docs/develop/java/workflows/message-passing.mdx:291 --> <!-- docs/develop/java/workflows/message-passing.mdx:292 -->

Neither documented overload takes a Namespace argument. <!-- docs/develop/java/workflows/message-passing.mdx:287 --> <!-- docs/develop/java/workflows/message-passing.mdx:291 --> The Signal-external API emits `SignalExternalWorkflowExecution`, which is the gated Command when the target Workflow Execution lives in a different Namespace.

### Cancel External Workflow

A Java SDK call site for requesting cancellation of an external Workflow Execution is not described in the documentation files consulted here. <!-- VERIFY: cancel-external API for Java SDK not located in docs/develop/java/workflows/message-passing.mdx:270-330 or docs/develop/java/workflows/child-workflows.mdx --> At the protocol level the corresponding Command is `RequestCancelExternalWorkflowExecution` — see the core page for the Command name and gating. If your codebase issues a cancellation against another Workflow Execution from inside a Workflow, audit it on the same basis as the Signal-external path above.

## Expected behavior on Temporal Cloud

The SDK call sites above compile and run as written. The deprecation is enforced server-side, not in the SDK: "OSS supports cross-Namespace commands (e.g., parent-child, SignalExternal, CancelExternal) through the `system.enableCrossNamespaceCommands` configuration. This configuration is disabled on Temporal Cloud." <!-- docs/cloud/migrate/automated.mdx:419 --> <!-- docs/cloud/migrate/automated.mdx:420 -->

The migration guidance is explicit that this is a hard prerequisite, not a runtime fallback: "The `system.enableCrossNamespaceCommands` configuration must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration." <!-- docs/cloud/migrate/automated.mdx:420 --> <!-- docs/cloud/migrate/automated.mdx:421 --> <!-- docs/cloud/migrate/automated.mdx:422 -->

In practical terms, on Temporal Cloud a `Workflow.newChildWorkflowStub` or `Workflow.newExternalWorkflowStub` call that targets a Workflow Execution in a different Namespace is rejected at the server. The SDK does not raise a compile-time warning for this; the failure surfaces when the Command reaches the server.

## What to do

1. For any Child Workflow call site, ensure the target Workflow is in the same Namespace as the parent. Remove any Namespace-targeting affordance from `ChildWorkflowOptions` if your codebase sets one — even though the current child-workflows feature guide does not document such a setter. <!-- docs/develop/java/workflows/child-workflows.mdx:153 -->
2. For any `Workflow.newExternalWorkflowStub` call site, ensure the `otherWorkflowID` or `WorkflowExecution` you pass refers to a Workflow Execution in the same Namespace as the caller. The documented overloads do not carry a Namespace argument anyway. <!-- docs/develop/java/workflows/message-passing.mdx:287 --> <!-- docs/develop/java/workflows/message-passing.mdx:291 -->
3. For genuine cross-Namespace work, restructure the design around Temporal Nexus rather than swapping one call for another. The Java Nexus feature guide is the entry point. <!-- docs/develop/java/nexus/feature-guide.mdx:27 --> <!-- docs/develop/java/nexus/feature-guide.mdx:28 -->

The Java Nexus feature guide page TOC lists two sections specifically about cross-Namespace usage:

- "Make Nexus calls across Namespaces with a development Server" <!-- docs/develop/java/nexus/feature-guide.mdx:38 -->
- "Make Nexus calls across Namespaces in Temporal Cloud" <!-- docs/develop/java/nexus/feature-guide.mdx:39 -->

The corresponding section bodies are:

- Development server: "Make Nexus calls across Namespaces with a development Server" at `docs/develop/java/nexus/feature-guide.mdx:600`. <!-- docs/develop/java/nexus/feature-guide.mdx:600 -->
- Temporal Cloud: "Make Nexus calls across Namespaces in Temporal Cloud" at `docs/develop/java/nexus/feature-guide.mdx:677`. <!-- docs/develop/java/nexus/feature-guide.mdx:677 -->

This page deliberately does not re-document Nexus APIs — `NexusServiceOptions`, `Workflow.startNexusOperation`, Endpoint creation, mTLS setup, and the rest belong to the Java Nexus feature guide.

## What to grep for in your codebase

Search for the documented Java tokens that produce the gated Commands:

- `Workflow.newChildWorkflowStub` <!-- docs/develop/java/workflows/child-workflows.mdx:42 -->
- `Workflow.newUntypedChildWorkflowStub` <!-- docs/develop/java/workflows/child-workflows.mdx:53 -->
- `Workflow.newExternalWorkflowStub` <!-- docs/develop/java/workflows/message-passing.mdx:287 --> <!-- docs/develop/java/workflows/message-passing.mdx:291 -->
- `ChildWorkflowOptions.newBuilder` <!-- docs/develop/java/workflows/child-workflows.mdx:55 --> <!-- docs/develop/java/workflows/child-workflows.mdx:161 -->

For each hit, confirm the target Workflow Execution lives in the caller's Namespace. Anything that does not is a migration blocker for Temporal Cloud per `docs/cloud/migrate/automated.mdx:419-422`.
