# Temporal Nexus — Java SDK

> See `references/core/nexus.md` for cross-SDK concepts (lifecycle, retries, circuit breaker, timeouts, request-deadline semantics). This file documents Java SDK identifiers only.

Support stage: Generally Available. <!-- docs/develop/java/nexus/feature-guide.mdx:22-24 -->

Recommended versions:
- Temporal CLI v1.3.0 or higher <!-- docs/develop/java/nexus/feature-guide.mdx:52-53 -->
- Temporal Java SDK v1.28.0 or higher <!-- docs/develop/java/nexus/feature-guide.mdx:54-55 -->

## Packages

- `io.temporal.nexus.*` — handler-side utilities <!-- docs/develop/java/nexus/feature-guide.mdx:203 -->
  - `Nexus.getOperationContext().getWorkflowClient()` — get the Temporal Client the Worker was initialized with <!-- docs/develop/java/nexus/feature-guide.mdx:205-206 -->
  - `WorkflowRunOperation.fromWorkflowMethod` — run a Workflow as an asynchronous Nexus Operation <!-- docs/develop/java/nexus/feature-guide.mdx:207 -->
- `io.temporal.workflow.*` — caller-side primitives:
  - `Workflow.newNexusServiceStub` <!-- docs/develop/java/nexus/feature-guide.mdx:448 -->
  - `Workflow.startNexusOperation` <!-- docs/develop/java/nexus/feature-guide.mdx:494 -->
  - `NexusServiceOptions` <!-- docs/develop/java/nexus/feature-guide.mdx:442 -->
  - `NexusOperationOptions` <!-- docs/develop/java/nexus/feature-guide.mdx:441 -->
  - `NexusOperationHandle` <!-- docs/develop/java/nexus/feature-guide.mdx:474 -->

## Define a Nexus Service contract

Annotate the interface with `@Service`; annotate each operation method with `@Operation`. <!-- docs/develop/java/nexus/feature-guide.mdx:111-190 -->

```java
@Service
public interface SampleNexusService {
  enum Language { EN, FR, DE, ES, TR }

  class HelloInput {
    private final String name;
    private final Language language;
    // @JsonCreator + @JsonProperty constructors/getters omitted
  }
  class HelloOutput { /* message field with JSON annotations */ }
  class EchoInput  { /* message field */ }
  class EchoOutput { /* message field */ }

  @Operation HelloOutput hello(HelloInput input);
  @Operation EchoOutput echo(EchoInput input);
}
```

The sample uses Java classes serialized to JSON via Jackson (`@JsonCreator`, `@JsonProperty`). <!-- docs/develop/java/nexus/feature-guide.mdx:101-105, 125-127 -->

## Develop Nexus Operation handlers

Annotate the implementation class with `@ServiceImpl(service = SampleNexusService.class)`. Each operation factory method is annotated with `@OperationImpl` and returns an `OperationHandler<In, Out>`. <!-- docs/develop/java/nexus/feature-guide.mdx:224-230 -->

### Synchronous operation handler

`OperationHandler.sync` exposes simple RPC-style handlers. The lambda receives `(ctx, details, input)`. <!-- docs/develop/java/nexus/feature-guide.mdx:215-238 -->

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

From within a sync handler, use `Nexus.getOperationContext().getWorkflowClient()` to Signal, Query, Update, or list Workflows. <!-- docs/develop/java/nexus/feature-guide.mdx:246-272 --> All calls must complete within the Nexus request timeout — see `references/core/nexus.md`. <!-- docs/develop/java/nexus/feature-guide.mdx:250-251 -->

Example accessing the Client:

```java
private GreetingWorkflow getWorkflowStub(String userId) {
  return Nexus.getOperationContext()
      .getWorkflowClient()
      .newWorkflowStub(GreetingWorkflow.class, getWorkflowId(userId));
}
```
<!-- docs/develop/java/nexus/feature-guide.mdx:266-272 -->

### Asynchronous workflow-run handler

Use `WorkflowRunOperation.fromWorkflowMethod` to expose a Workflow as an operation. <!-- docs/develop/java/nexus/feature-guide.mdx:279, 299 -->

```java
@OperationImpl
public OperationHandler<SampleNexusService.HelloInput, SampleNexusService.HelloOutput> hello() {
  return WorkflowRunOperation.fromWorkflowMethod(
      (ctx, details, input) ->
          Nexus.getOperationContext()
              .getWorkflowClient()
              .newWorkflowStub(
                  HelloHandlerWorkflow.class,
                  WorkflowOptions.newBuilder().setWorkflowId(details.getRequestId()).build())
              ::hello);
}
```
<!-- docs/develop/java/nexus/feature-guide.mdx:292-315 -->

`details.getRequestId()` returns the request ID allocated by Temporal when the caller schedules the operation; it is guaranteed to be stable across retries. <!-- docs/develop/java/nexus/feature-guide.mdx:306-311 --> Task queue defaults to the task queue handling this operation. <!-- docs/develop/java/nexus/feature-guide.mdx:313 -->

### Multi-argument workflow start

A Nexus Operation only takes one input parameter. To start a Workflow that takes multiple arguments, use `WorkflowRunOperation.fromWorkflowHandle` with `WorkflowHandle.fromWorkflowMethod`. <!-- docs/develop/java/nexus/feature-guide.mdx:329-332, 361-363 -->

```java
@OperationImpl
public OperationHandler<SampleNexusService.HelloInput, SampleNexusService.HelloOutput> hello() {
  return WorkflowRunOperation.fromWorkflowHandle(
      (ctx, details, input) ->
          WorkflowHandle.fromWorkflowMethod(
              Nexus.getOperationContext()
                      .getWorkflowClient()
                      .newWorkflowStub(
                          HelloHandlerWorkflow.class,
                          WorkflowOptions.newBuilder()
                              .setWorkflowId(details.getRequestId())
                              .build())
                  ::hello,
              input.getName(),
              input.getLanguage()));
}
```
<!-- docs/develop/java/nexus/feature-guide.mdx:356-386 -->

## Register a Nexus Service in a Worker

```java
Worker worker = factory.newWorker(DEFAULT_TASK_QUEUE_NAME);
worker.registerWorkflowImplementationTypes(HelloHandlerWorkflowImpl.class);
worker.registerNexusServiceImplementation(new SampleNexusServiceImpl());

factory.start();
```
<!-- docs/develop/java/nexus/feature-guide.mdx:417-421 -->

## Caller-side: invoke a Nexus Operation

Create a stub with `Workflow.newNexusServiceStub`, then invoke either the typed method directly (blocking) or `Workflow.startNexusOperation` for handle-based control. <!-- docs/develop/java/nexus/feature-guide.mdx:447-455, 482-499 -->

### Blocking call

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

@Override
public String echo(String message) {
  return sampleNexusService.echo(new SampleNexusService.EchoInput(message)).getMessage();
}
```
<!-- docs/develop/java/nexus/feature-guide.mdx:446-461 -->

### Handle-based call

```java
NexusOperationHandle<SampleNexusService.HelloOutput> handle =
    Workflow.startNexusOperation(
        sampleNexusService::hello, new SampleNexusService.HelloInput(message, language));
// Optionally wait for the operation to be started. NexusOperationExecution will contain the
// operation token in case this operation is asynchronous.
handle.getExecution().get();
return handle.getResult().get().getMessage();
```
<!-- docs/develop/java/nexus/feature-guide.mdx:493-500 -->

`handle.getExecution().get()` waits for the operation to be started; `handle.getResult().get()` returns the final result. <!-- docs/develop/java/nexus/feature-guide.mdx:496-499 -->

## Configure the caller-side endpoint at Worker registration

Bind a Nexus Service name to an Endpoint via `WorkflowImplementationOptions.setNexusServiceOptions`. <!-- docs/develop/java/nexus/feature-guide.mdx:534-542 -->

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

## Timeouts

Set on `NexusOperationOptions.Builder`:

- `setScheduleToCloseTimeout(Duration)` <!-- docs/develop/java/nexus/feature-guide.mdx:453 -->

See `references/core/nexus.md` for the full set of timeouts and their semantics.

## Cancellation

To cancel a Nexus Operation from within a Workflow, create a `CancellationScope` using `Workflow.newCancellationScope`. It accepts a `Runnable`; any SDK methods (including Nexus operations) started inside that runnable are associated with the scope. Calling `cancel()` on the returned scope cancels the context and all SDK methods started within it. <!-- docs/develop/java/nexus/feature-guide.mdx:642-647 -->

The promise returned by `Workflow.startNexusOperation` resolves when the operation finishes — whether it succeeds, fails, times out, or is canceled. <!-- docs/develop/java/nexus/feature-guide.mdx:646-647 -->

Only asynchronous operations can be canceled; cancelation is sent using an operation token. The Workflow or other resources backing the operation may choose to ignore the cancelation request. <!-- docs/develop/java/nexus/feature-guide.mdx:649-651 -->

### Cancellation types

Set on `NexusServiceOptions.Builder` via `.setCancellationType()`. <!-- docs/develop/java/nexus/feature-guide.mdx:664-665 -->

- `ABANDON` — do not request cancellation of the operation. <!-- docs/develop/java/nexus/feature-guide.mdx:656 -->
- `TRY_CANCEL` — initiate a cancellation request and immediately report cancellation to the caller. Doesn't guarantee delivery if the caller exits before delivery completes. <!-- docs/develop/java/nexus/feature-guide.mdx:657-659 -->
- `WAIT_REQUESTED` — request cancellation and wait for confirmation that the request was received; doesn't wait for actual cancellation. <!-- docs/develop/java/nexus/feature-guide.mdx:660-661 -->
- `WAIT_COMPLETED` — wait for operation completion; operation may or may not complete as cancelled. <!-- docs/develop/java/nexus/feature-guide.mdx:662 -->

Default is `WAIT_COMPLETED`. <!-- docs/develop/java/nexus/feature-guide.mdx:664 -->

Once the caller Workflow completes, the caller's Nexus Machinery stops attempting to cancel operations that have not yet been canceled, letting them run to completion. To ensure cancelations are delivered, wait for all pending operations to deliver their cancellation requests before exiting the Workflow. <!-- docs/develop/java/nexus/feature-guide.mdx:667-671 -->

## CLI setup (local dev)

Create caller and handler Namespaces: <!-- docs/develop/java/nexus/feature-guide.mdx:73-76 -->

```
temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace
```

Create the Nexus Endpoint: <!-- docs/develop/java/nexus/feature-guide.mdx:86-90 -->

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

Start the dev server: <!-- docs/develop/java/nexus/feature-guide.mdx:59-61 -->

```
temporal server start-dev
```

## Observability

In the caller's Workflow history:

- Synchronous: `NexusOperationScheduled`, `NexusOperationCompleted`. <!-- docs/develop/java/nexus/feature-guide.mdx:792-793, 823-826 -->
- Asynchronous: `NexusOperationScheduled`, `NexusOperationStarted`, `NexusOperationCompleted`. <!-- docs/develop/java/nexus/feature-guide.mdx:797-798, 817-821 -->

`NexusOperationStarted` is not reported for synchronous operations. <!-- docs/develop/java/nexus/feature-guide.mdx:828-832 -->

Inspect via CLI: <!-- docs/develop/java/nexus/feature-guide.mdx:804-815 -->

```
temporal workflow describe -w <ID>
temporal workflow show -w <ID>
```

## Samples

- Main sample: `temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexus` <!-- docs/develop/java/nexus/feature-guide.mdx:44 -->
- Messaging (Signals/Queries/Updates through Nexus): `temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexusmessaging` <!-- docs/develop/java/nexus/feature-guide.mdx:253, 274 -->
- Multi-argument workflow start: `temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexusmultipleargs` <!-- docs/develop/java/nexus/feature-guide.mdx:336 -->
- Cancellation: `temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexuscancellation` <!-- docs/develop/java/nexus/feature-guide.mdx:673-675 -->
