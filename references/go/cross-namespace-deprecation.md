# Cross-Namespace Deprecation — Go SDK

Temporal historically allowed Workflow-issued Commands to target a Workflow Execution in a different Namespace from the caller. That behavior is gated by the server-side dynamic configuration key `system.enableCrossNamespaceCommands`, which is disabled on Temporal Cloud. For the cross-language concept, the affected Commands, and the framing of the deprecation, see `references/core/cross-namespace-deprecation.md`. This page is the Go SDK companion: it identifies the Go APIs that emit those Commands, describes the observable failure mode on Cloud, and points at the Go Nexus migration path.

## Affected Go SDK APIs

### Child Workflow

Spawning a Child Workflow Execution from a Workflow uses `workflow.ExecuteChildWorkflow`. <!-- docs/develop/go/workflows/child-workflows.mdx:34 --> The call requires an instance of `workflow.Context` with `workflow.ChildWorkflowOptions` applied to it via `workflow.WithChildOptions`. <!-- docs/develop/go/workflows/child-workflows.mdx:36 --> <!-- docs/develop/go/workflows/child-workflows.mdx:41 -->

The Go child-workflows feature guide does not document a `Namespace` field on `workflow.ChildWorkflowOptions`; it only states that the options struct "contain the same fields as `client.StartWorkflowOptions`" and that fields inherit from the Parent Workflow Options when not explicitly set. <!-- docs/develop/go/workflows/child-workflows.mdx:38 --> <!-- docs/develop/go/workflows/child-workflows.mdx:39 -->

The historical `Namespace` field on `workflow.ChildWorkflowOptions` is not documented in the current child-workflows feature guide. <!-- VERIFY: deprecated field name not present in docs/develop/go/workflows/child-workflows.mdx --> If your codebase sets such a field today, remove the cross-Namespace target; what is being deprecated is targeting a *different* Namespace, not `workflow.ChildWorkflowOptions` or `workflow.ExecuteChildWorkflow` as a whole. Both remain the supported way to spawn a Child Workflow within the *same* Namespace.

### Signal External Workflow

A Workflow signals another Workflow with `workflow.SignalExternalWorkflow`. The documented call site is:

```go
err := workflow.SignalExternalWorkflow(ctx, "some-workflow-id", "", "your-signal-name", signal).Get(ctx, nil)
```

<!-- docs/develop/go/workflows/message-passing.mdx:295 -->

The five positional arguments shown in the docs are `ctx`, a Workflow ID, an empty string, a Signal name, and the Signal payload. <!-- docs/develop/go/workflows/message-passing.mdx:295 --> The Go message-passing feature guide does not label the second positional argument as a Namespace parameter or describe how to target a different Namespace from this call. <!-- VERIFY: docs/develop/go/workflows/message-passing.mdx:270-330 does not name the empty-string argument or describe a cross-Namespace target for SignalExternalWorkflow --> Sending a Signal from a Workflow is what the docs call an "External Signal." <!-- docs/develop/go/workflows/message-passing.mdx:286 -->

At the Command layer, this call emits `SignalExternalWorkflowExecution`, which is one of the three Commands gated by `system.enableCrossNamespaceCommands` — see `references/core/cross-namespace-deprecation.md`.

### Cancel External Workflow

The cross-Namespace Command for requesting cancellation of another Workflow Execution is `RequestCancelExternalWorkflowExecution`, covered in the shared concept page. <!-- VERIFY: Go SDK cancel-external API name not in docs/develop/go/workflows/message-passing.mdx — the lines 270–330 cover SignalExternal but do not name a Go SDK function for cancel-external --> If your code requests cancellation of an external Workflow Execution from inside a Workflow today and that target is in a different Namespace, the underlying Command is the gated one, and the same deprecation applies regardless of which Go SDK function emits it. Consult the Go SDK reference on `pkg.go.dev` for the current function name; do not rely on guesses.

## Expected behavior on Temporal Cloud

Temporal Cloud has `system.enableCrossNamespaceCommands` disabled, and the migration documentation is explicit that "code using cross-Namespace calls must be updated or removed prior to migration." <!-- docs/cloud/migrate/automated.mdx:419 --> <!-- docs/cloud/migrate/automated.mdx:420 --> <!-- docs/cloud/migrate/automated.mdx:421 --> <!-- docs/cloud/migrate/automated.mdx:422 -->

What this means in practice for Go code:

- The SDK calls above still compile. The Go SDK is not what rejects a cross-Namespace target.
- The rejection happens server-side. A Workflow that emits a cross-Namespace `StartChildWorkflowExecution`, `SignalExternalWorkflowExecution`, or `RequestCancelExternalWorkflowExecution` against Temporal Cloud will see the Command fail because the gating dynamic configuration is off. <!-- docs/cloud/migrate/automated.mdx:419 --> <!-- docs/cloud/migrate/automated.mdx:420 -->
- Same-Namespace Child Workflows, Signals, and cancellations continue to work normally. The deprecation is about the *target Namespace*, not the APIs.

## What to do

1. Audit Workflow code for any place where `workflow.ExecuteChildWorkflow`, `workflow.SignalExternalWorkflow`, or an external-workflow cancellation targets a Workflow Execution in a Namespace other than the caller's. The shared concept page lists the three gated Commands. <!-- references/core/cross-namespace-deprecation.md -->
2. For genuinely cross-Namespace use cases, restructure around Temporal Nexus. The Go Nexus feature guide is the supported path; do not attempt a blind substitution of `workflow.ExecuteChildWorkflow` with `NexusClient.ExecuteOperation`, since Nexus Operations and Child Workflows have different shapes and lifecycles. <!-- docs/develop/go/nexus/feature-guide.mdx:560-572 -->
3. Use the Go Nexus feature guide for the cross-Namespace setup steps:
   - The TOC lists "Make Nexus calls across Namespaces with a development Server" <!-- docs/develop/go/nexus/feature-guide.mdx:37 --> and "Make Nexus calls across Namespaces in Temporal Cloud". <!-- docs/develop/go/nexus/feature-guide.mdx:38 -->
   - The dev-server section starts at the heading "Make Nexus calls across Namespaces with a development Server". <!-- docs/develop/go/nexus/feature-guide.mdx:513 -->
   - The Temporal Cloud section starts at the heading "Make Nexus calls across Namespaces in Temporal Cloud". <!-- docs/develop/go/nexus/feature-guide.mdx:574 -->

This page does not re-document Nexus. Follow the feature guide for the Endpoint, Service contract, Operation handler, and caller Workflow details.

## What to grep for in your codebase

Use these documented Go SDK tokens as a starting point. Each one appears verbatim in the docs sources cited above.

- `workflow.ExecuteChildWorkflow` <!-- docs/develop/go/workflows/child-workflows.mdx:34 -->
- `workflow.ChildWorkflowOptions` <!-- docs/develop/go/workflows/child-workflows.mdx:36 -->
- `workflow.WithChildOptions` <!-- docs/develop/go/workflows/child-workflows.mdx:41 -->
- `workflow.SignalExternalWorkflow` <!-- docs/develop/go/workflows/message-passing.mdx:295 -->

A hit on any of these is not, by itself, a problem — the deprecation is about cross-Namespace *targets*. Use the grep results to seed a review of which Namespace each call is aimed at.
