# Cross-Namespace Deprecation — Java SDK

A Child Workflow Execution in Temporal is canonically defined as a Workflow spawned from another Workflow *within the same Namespace* <!-- docs/encyclopedia/child-workflows/child-workflows.mdx:31 -->. OSS Temporal historically supported cross-Namespace child, signal-external, and cancel-external commands through a server dynamic-config toggle named `system.enableCrossNamespaceCommands`, but that configuration is disabled on Temporal Cloud and self-hosted operators are directed to disable it and remove cross-Namespace code prior to Cloud migration <!-- docs/cloud/migrate/automated.mdx:419-422 -->. Temporal Cloud isolates Namespaces by default, and the supported way for a Workflow in one Namespace to interact with a Workflow in another Namespace is [Temporal Nexus](/nexus) <!-- docs/evaluate/temporal-cloud/security.mdx:74-76 -->.

This page is scoped to the Java SDK: which Java APIs are affected, what is *not* affected, and where to go for the supported alternative.

## What is affected in the Java SDK

The cross-Namespace restriction concerns three Workflow Command families that Java exposes through Workflow-side stubs:

- `StartChildWorkflowExecution` — the Command emitted when you spawn a child <!-- docs/references/commands.mdx:51 -->. In Java this is reached through `Workflow.newChildWorkflowStub` plus `ChildWorkflowOptions` <!-- docs/develop/java/workflows/child-workflows.mdx:42 --> <!-- docs/develop/java/workflows/child-workflows.mdx:153 -->. A target Namespace can be set on the options builder; that builder method is documented in the linked Javadoc rather than inline in the local docs page. <!-- javadoc: io.temporal.workflow.ChildWorkflowOptions.Builder (linked from docs/develop/java/workflows/child-workflows.mdx:153) -->
- `SignalExternalWorkflowExecution` — the Command triggered when a Workflow Signals another Workflow Execution <!-- docs/references/commands.mdx:58-63 -->. In Java this is reached through `Workflow.newExternalWorkflowStub` (typed) <!-- docs/develop/java/workflows/message-passing.mdx:287 --> or `Workflow.newUntypedExternalWorkflowStub` <!-- docs/develop/java/workflows/message-passing.mdx:463 -->.
- `RequestCancelExternalWorkflowExecution` — the Command triggered when one Workflow requests cancellation of another <!-- docs/references/commands.mdx:67-72 -->. In Java this is reached through the same external-workflow stubs above.

When the target Workflow lives in a *different* Namespace than the caller, these Commands fall under the `system.enableCrossNamespaceCommands` umbrella and are not supported on Temporal Cloud <!-- docs/cloud/migrate/automated.mdx:419-422 -->.

<!-- VERIFY: the docs in scope do not name the exact server error string returned when a cross-Namespace Command is rejected with the flag disabled; do not invent one. -->

## Server configuration token

There is exactly one configuration token in the docs that governs this behavior:

- Name: `system.enableCrossNamespaceCommands` <!-- docs/cloud/migrate/automated.mdx:420 -->
- Where it lives: server-side dynamic configuration (it is referenced in the OSS-to-Cloud automated migration limitations section) <!-- docs/cloud/migrate/automated.mdx:419-422 -->
- Status on Temporal Cloud: disabled <!-- docs/cloud/migrate/automated.mdx:420 -->
- Status guidance for self-hosted operators migrating to Cloud: must be disabled, and code using cross-Namespace calls must be updated or removed prior to migration <!-- docs/cloud/migrate/automated.mdx:421-422 -->

There is no Java SDK worker flag, environment variable, or `WorkflowClientOptions` setting tied to this restriction in the docs in scope. The control surface is on the server, not the worker.

## Scope of the restriction — same-Namespace is unaffected

The restriction is on *cross-Namespace* use of these Commands. The Java APIs themselves remain the supported way to do same-Namespace work:

- `Workflow.newChildWorkflowStub` for same-Namespace Child Workflows is the canonical Java pattern <!-- docs/develop/java/workflows/child-workflows.mdx:42 --> <!-- docs/develop/java/workflows/child-workflows.mdx:81 -->, consistent with the platform definition that a Child Workflow Execution is spawned within the same Namespace as its parent <!-- docs/encyclopedia/child-workflows/child-workflows.mdx:31 -->.
- `Workflow.newExternalWorkflowStub` for Signaling another Workflow in the *same* Namespace is the documented Java pattern for External Signals <!-- docs/develop/java/workflows/message-passing.mdx:286-292 -->.
- `Workflow.newUntypedExternalWorkflowStub` likewise remains the untyped form <!-- docs/develop/java/workflows/message-passing.mdx:463 -->.

Do not read this page as "stop using `newExternalWorkflowStub`." Read it as "do not target a different Namespace with these stubs when running on Temporal Cloud."

## Supported alternative: Temporal Nexus

Before Nexus, connecting Namespaces relied on cross-Namespace Child Workflows (which leak target Namespace, Task Queue, and Workflow options into the caller), per-target mTLS Activity wrappers, or extra gateway infrastructure <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:48-53 -->. Nexus replaces those use cases with a service contract between caller and handler, with built-in observability <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:55 -->. On Temporal Cloud specifically, Nexus is the only supported path for inter-Namespace communication <!-- docs/evaluate/temporal-cloud/security.mdx:74-76 -->.

Nexus is not a drop-in replacement for `newExternalWorkflowStub` or for cross-Namespace `ChildWorkflowOptions`; it has a different shape (Nexus Endpoint plus Nexus Service contract plus Nexus Operations) that you must define explicitly <!-- docs/develop/java/nexus/feature-guide.mdx:27-28 -->.

For the Java implementation details — endpoint creation, service contract definition, operation handlers, caller Workflows, and cross-Namespace Nexus calls on dev server and on Temporal Cloud — follow the Java Nexus Feature Guide rather than this page:

- [Java SDK — Temporal Nexus feature guide](/develop/java/nexus/feature-guide) <!-- docs/develop/java/nexus/feature-guide.mdx:1-46 -->

## Migration notes for Temporal Cloud

If you are planning an OSS-to-Cloud migration with any cross-Namespace Child, SignalExternal, or CancelExternal Commands in your Java codebase:

1. Confirm whether `system.enableCrossNamespaceCommands` is currently enabled on your self-hosted cluster <!-- docs/cloud/migrate/automated.mdx:420 -->.
2. Identify call sites that target a different Namespace than the caller Workflow. In Java these are typically:
   - `ChildWorkflowOptions` builders that set a target Namespace different from the caller's <!-- javadoc: io.temporal.workflow.ChildWorkflowOptions.Builder (linked from docs/develop/java/workflows/child-workflows.mdx:153) -->.
   - `Workflow.newExternalWorkflowStub` / `Workflow.newUntypedExternalWorkflowStub` invocations whose target `WorkflowExecution` resolves in another Namespace <!-- docs/develop/java/workflows/message-passing.mdx:287 --> <!-- docs/develop/java/workflows/message-passing.mdx:463 -->.
3. Update or remove those call sites prior to migration; the migration runbook is explicit that this must happen before the cutover <!-- docs/cloud/migrate/automated.mdx:421-422 -->.
4. Redesign those flows around a Nexus Endpoint and Service contract, using the Java Nexus Feature Guide <!-- docs/develop/java/nexus/feature-guide.mdx:27-46 -->.

Same-Namespace Child Workflows and same-Namespace External Signals do not require any migration work for this restriction.

## What NOT to do

- Do not assume the cross-Namespace toggle exists on Temporal Cloud — `system.enableCrossNamespaceCommands` is disabled there <!-- docs/cloud/migrate/automated.mdx:420 -->.
- Do not write the dynamic-config key with a capital `E`. It is `system.enableCrossNamespaceCommands`, lowercase `e` in `enable` <!-- docs/cloud/migrate/automated.mdx:420 -->.
- Do not look for a Java worker flag, `WorkflowClient` option, or environment variable to toggle this behavior — there is none in the docs in scope; the toggle is a server dynamic-config key <!-- docs/cloud/migrate/automated.mdx:419-422 -->.
- Do not describe `Workflow.newExternalWorkflowStub` or `Workflow.newUntypedExternalWorkflowStub` as deprecated wholesale. Only cross-Namespace use is restricted; same-Namespace External Signals remain the documented Java pattern <!-- docs/develop/java/workflows/message-passing.mdx:286-293 --> <!-- docs/develop/java/workflows/message-passing.mdx:463 -->.
- Do not describe Nexus as a "drop-in replacement" for cross-Namespace stubs. It is a different contract — Endpoint, Service, and Operations <!-- docs/develop/java/nexus/feature-guide.mdx:27-28 -->.
- Do not cite a specific Temporal version where cross-Namespace commands were deprecated or removed — no such version timeline is in the docs in scope.
- Do not invent the server-side error string returned when a cross-Namespace Command is rejected; the docs in scope do not name it. See the VERIFY marker above.
