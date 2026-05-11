# Java SDK — Cross-Namespace Deprecation

## What's affected

Three Workflow Commands historically targeted a Workflow Execution in a different Namespace: parent-child Workflow starts, SignalExternal, and CancelExternal. OSS Temporal Servers gate these behind the `system.enableCrossNamespaceCommands` configuration; that configuration is disabled on Temporal Cloud, and code using cross-Namespace calls must be updated or removed prior to migration. <!-- docs/cloud/migrate/automated.mdx:419-422 -->

For the cross-cutting concept and migration timeline that applies to every SDK, see `references/core/cross-namespace-deprecation.md`. This page focuses on the Java SDK surface and the Java Nexus migration path.

The Java-language migration target is Temporal Nexus, which "connect[s] Temporal Applications within and across Namespaces using a Nexus Endpoint, a Nexus Service contract, and Nexus Operations." <!-- docs/develop/java/nexus/feature-guide.mdx:27-28 --> Child Workflows themselves remain "Limited to the same Namespace" — cross-Namespace use leaks implementation details to callers. <!-- docs/evaluate/development-production-features/temporal-nexus.mdx:51 -->

## Spotting the pattern in Java code

The Java SDK reference docs in this repository document Child Workflows and External Workflow stubs as **same-Namespace** constructs. The documented shapes are:

Child Workflow stub (typed): <!-- docs/develop/java/workflows/child-workflows.mdx:42 -->

```java
GreetingChild child = Workflow.newChildWorkflowStub(GreetingChild.class);
Promise<String> greeting = Async.function(child::composeGreeting, "Hello", name);
```

Child Workflow stub (untyped) with options: <!-- docs/develop/java/workflows/child-workflows.mdx:52-55 -->

```java
ChildWorkflowStub childUntyped =
    Workflow.newUntypedChildWorkflowStub(
        "GreetingChild",
        ChildWorkflowOptions.newBuilder().setWorkflowId("childWorkflow").build());
```

`ChildWorkflowOptions.Builder` is documented for setters like `setParentClosePolicy` <!-- docs/develop/java/workflows/child-workflows.mdx:153 --> and `setWorkflowId` <!-- docs/develop/java/workflows/child-workflows.mdx:55 -->. <!-- VERIFY: docs/develop/java/workflows/child-workflows.mdx does not document setNamespace on ChildWorkflowOptions.Builder; consult io.temporal.workflow source --> If your codebase configures a Namespace on `ChildWorkflowOptions` via a setter not shown in the doc above, treat it as a cross-Namespace usage that must be migrated.

External Workflow stub for SignalExternal / CancelExternal: <!-- docs/develop/java/workflows/message-passing.mdx:287 -->

```java
OtherWorkflow other = Workflow.newExternalWorkflowStub(OtherWorkflow.class, otherWorkflowID);
other.mySignalMethod();
```

The documented overload takes `(Class, WorkflowExecution)` or `(Class, String workflowId)` — no Namespace parameter is part of the documented signature. <!-- docs/develop/java/workflows/message-passing.mdx:287,291 --> Sending an external Signal produces a `SignalExternalWorkflowExecutionInitiated` Event in the sender's history. <!-- docs/develop/java/workflows/message-passing.mdx:297 -->

Because the Java SDK reference does not document a cross-Namespace argument on either API, any historical cross-Namespace usage in Java codebases relied on the server-side gate described in `docs/cloud/migrate/automated.mdx:419-422`. Audit Workflow code that constructs `ChildWorkflowOptions` or calls `Workflow.newExternalWorkflowStub` against a Workflow Execution that lives in another Namespace, and plan to replace those call sites.

## Migration: Temporal Nexus (Java)

Temporal Nexus is a different programming model: caller Workflows invoke Nexus Operations through a typed Nexus Service stub, and handler Namespaces expose Operations that may run synchronously or start a backing Workflow. <!-- docs/develop/java/nexus/feature-guide.mdx:27-28 --> Nexus support in the Java SDK is Generally Available. <!-- docs/develop/java/nexus/feature-guide.mdx:22-23 -->

The minimum viable migration has four pieces.

### 1. Define a Nexus Service contract

The Service interface is annotated with `@Service`; each Operation method is annotated with `@Operation`. <!-- docs/develop/java/nexus/feature-guide.mdx:111,185,188 -->

```java
@Service
public interface SampleNexusService {
  @Operation
  HelloOutput hello(HelloInput input);

  @Operation
  EchoOutput echo(EchoInput input);
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:111-190 -->

### 2. Implement the Service in the handler Namespace

Annotate the implementation class with `@ServiceImpl(service = ...)`, and each Operation method with `@OperationImpl`. Use `OperationHandler.sync` for synchronous RPC-style Operations and `WorkflowRunOperation.fromWorkflowMethod` to back an Operation with a Workflow. <!-- docs/develop/java/nexus/feature-guide.mdx:227-242,292-315 -->

```java
@ServiceImpl(service = SampleNexusService.class)
public class SampleNexusServiceImpl {
  @OperationImpl
  public OperationHandler<SampleNexusService.EchoInput, SampleNexusService.EchoOutput> echo() {
    return OperationHandler.sync(
        (ctx, details, input) -> new SampleNexusService.EchoOutput(input.getMessage()));
  }
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:227-242 -->

The handler Worker registers the implementation with `worker.registerNexusServiceImplementation(...)`. <!-- docs/develop/java/nexus/feature-guide.mdx:419 -->

### 3. Call the Service from a caller Workflow

The caller Workflow obtains a Nexus stub with `Workflow.newNexusServiceStub`, configured with `NexusServiceOptions` and `NexusOperationOptions`. Synchronous-style use looks like a method call; asynchronous use goes through `Workflow.startNexusOperation`, which returns a `NexusOperationHandle`. <!-- docs/develop/java/nexus/feature-guide.mdx:447-455,493-499 -->

```java
SampleNexusService sampleNexusService =
    Workflow.newNexusServiceStub(
        SampleNexusService.class,
        NexusServiceOptions.newBuilder()
            .setOperationOptions(
                NexusOperationOptions.newBuilder()
                    .setScheduleToCloseTimeout(Duration.ofSeconds(10))
                    .build())
            .build());

// Synchronous-style call
String reply = sampleNexusService.echo(new SampleNexusService.EchoInput(message)).getMessage();

// Asynchronous-style call returning a handle
NexusOperationHandle<SampleNexusService.HelloOutput> handle =
    Workflow.startNexusOperation(
        sampleNexusService::hello, new SampleNexusService.HelloInput(message, language));
handle.getExecution().get();
String result = handle.getResult().get().getMessage();
```

<!-- docs/develop/java/nexus/feature-guide.mdx:447-462,481-501 -->

### 4. Bind the caller Workflow to a Nexus Endpoint

The caller Worker registers the Workflow with `WorkflowImplementationOptions` that map the Service name to a `NexusServiceOptions` carrying the Endpoint name. <!-- docs/develop/java/nexus/feature-guide.mdx:534-542 -->

```java
worker.registerWorkflowImplementationTypes(
    WorkflowImplementationOptions.newBuilder()
        .setNexusServiceOptions(
            Collections.singletonMap(
                "SampleNexusService",
                NexusServiceOptions.newBuilder().setEndpoint("my-nexus-endpoint-name").build()))
        .build(),
    EchoCallerWorkflowImpl.class,
    HelloCallerWorkflowImpl.class);
```

<!-- docs/develop/java/nexus/feature-guide.mdx:534-542 -->

The Endpoint itself is created out of band, with `temporal operator nexus endpoint create` for local development <!-- docs/develop/java/nexus/feature-guide.mdx:86-90 --> or `tcld nexus endpoint create` for Temporal Cloud, where `--target-namespace` and `--allow-namespace` build the Endpoint's caller allowlist. <!-- docs/develop/java/nexus/feature-guide.mdx:733-742 -->

### Cancellation semantics differ

Nexus Operations have explicit cancellation types (`ABANDON`, `TRY_CANCEL`, `WAIT_REQUESTED`, `WAIT_COMPLETED`, default `WAIT_COMPLETED`) set via `NexusServiceOptions.Builder.setCancellationType()`, and only asynchronous Operations can be cancelled. <!-- docs/develop/java/nexus/feature-guide.mdx:649-665 --> This is not a drop-in replacement for `CancelExternal` against an arbitrary running Workflow; the cancellation flows through the Operation handle returned by `Workflow.startNexusOperation`.

## Distinguish from `DeprecateNamespace`

The `DeprecateNamespace` API "updates the state of a registered Namespace to 'DEPRECATED'" so that no new Workflow Executions can be started on it while existing ones continue to run. <!-- docs/develop/java/client/namespaces.mdx:147 --> That is an operator action on a single Namespace and has nothing to do with the deprecation of cross-Namespace Commands described above. Do not conflate the two when planning a migration.
