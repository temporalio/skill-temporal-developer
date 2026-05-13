# Temporal Nexus — Java SDK

Temporal Java SDK support for Nexus is Generally Available <!-- docs/develop/java/nexus/feature-guide.mdx:20-25 -->. See `references/core/nexus.md` for cross-SDK concepts (Endpoints, lifecycle, timeouts, retries, circuit breaking, cancellation semantics). Recommended minimum versions: Temporal CLI v1.3.0+ and Temporal Java SDK v1.28.0+ <!-- docs/develop/java/nexus/feature-guide.mdx:52-55 -->.

## Packages and key types

- `io.nexusrpc` — `@Service`, `@Operation` annotations on the Service contract <!-- docs/develop/java/nexus/quickstart.mdx:58-59 -->.
- `io.nexusrpc.handler` — `@ServiceImpl`, `@OperationImpl`, `OperationHandler` (with `OperationHandler.sync(...)`) <!-- docs/develop/java/nexus/quickstart.mdx:92-94 -->.
- `io.temporal.nexus` — `Nexus.getOperationContext()`, `WorkflowRunOperation.fromWorkflowMethod`, `WorkflowRunOperation.fromWorkflowHandle`, `WorkflowHandle` <!-- docs/develop/java/nexus/feature-guide.mdx:203-211 -->.
- `io.temporal.workflow` — `Workflow.newNexusServiceStub`, `Workflow.startNexusOperation`, `Workflow.newCancellationScope`, `NexusServiceOptions`, `NexusOperationOptions`, `NexusOperationHandle` <!-- docs/develop/java/nexus/feature-guide.mdx:441-478 -->.
- `io.temporal.worker` — `WorkerFactory`, `Worker.registerNexusServiceImplementation`, `WorkflowImplementationOptions` <!-- docs/develop/java/nexus/feature-guide.mdx:404-419, 519-542 -->.
- `io.temporal.client` — `WorkflowOptions` (for setting Workflow IDs when starting Workflows from inside an Operation handler) <!-- docs/develop/java/nexus/feature-guide.mdx:314 -->.

## Defining the Service contract

Define the contract as an interface annotated with `@Service`; methods annotated with `@Operation` declare the named Operations. Each Operation takes exactly one input and returns one output. Input and output classes are typically plain Java classes with Jackson `@JsonCreator(mode = JsonCreator.Mode.PROPERTIES)` constructors and `@JsonProperty(...)`-annotated accessors so they serialize cleanly through the default Data Converter <!-- docs/develop/java/nexus/feature-guide.mdx:101-191 -->.

```java
@Service
public interface SampleNexusService {
  enum Language { EN, FR, DE, ES, TR }

  class HelloInput {
    private final String name;
    private final Language language;

    @JsonCreator(mode = JsonCreator.Mode.PROPERTIES)
    public HelloInput(
        @JsonProperty("name") String name, @JsonProperty("language") Language language) {
      this.name = name;
      this.language = language;
    }
    @JsonProperty("name") public String getName() { return name; }
    @JsonProperty("language") public Language getLanguage() { return language; }
  }

  class HelloOutput { /* @JsonCreator / @JsonProperty as above */ }
  class EchoInput  { /* ... */ }
  class EchoOutput { /* ... */ }

  @Operation HelloOutput hello(HelloInput input);
  @Operation EchoOutput echo(EchoInput input);
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:110-191 -->

## Service implementation

Annotate the implementation class with `@ServiceImpl(service = SampleNexusService.class)`. Each `@OperationImpl` method returns an `OperationHandler<I, O>` matching the input and output types of the corresponding `@Operation` <!-- docs/develop/java/nexus/feature-guide.mdx:223-242 -->.

```java
@ServiceImpl(service = SampleNexusService.class)
public class SampleNexusServiceImpl {
  @OperationImpl
  public OperationHandler<SampleNexusService.EchoInput, SampleNexusService.EchoOutput> echo() {
    return OperationHandler.sync(
        (ctx, details, input) -> new SampleNexusService.EchoOutput(input.getMessage()));
  }
  // ...
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:227-241 -->

## Synchronous Operation handlers

`OperationHandler.sync` exposes simple RPC handlers; the lambda takes `(ctx, details, input)` and returns the Operation output synchronously <!-- docs/develop/java/nexus/feature-guide.mdx:215-241 -->.

Inside a sync handler, get the Temporal Client (the one the Worker was initialized with) via `Nexus.getOperationContext().getWorkflowClient()` to Signal, Query, Update, or list Workflows. All sync handler work must complete within the Nexus request timeout, so prefer short-lived calls <!-- docs/develop/java/nexus/feature-guide.mdx:205-218, 246-272 -->.

```java
private GreetingWorkflow getWorkflowStub(String userId) {
  return Nexus.getOperationContext()
      .getWorkflowClient()
      .newWorkflowStub(GreetingWorkflow.class, getWorkflowId(userId));
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:266-271 -->

## Asynchronous Operation handlers (Workflow-Run Operations)

Use `WorkflowRunOperation.fromWorkflowMethod` to expose a Workflow as an asynchronous Nexus Operation. The lambda receives `(ctx, details, input)` and returns a method-reference (`::workflowMethod`) on a typed Workflow stub <!-- docs/develop/java/nexus/feature-guide.mdx:279-315 -->.

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

`details.getRequestId()` is the Request ID allocated by Temporal when the caller Workflow schedules the Operation and is guaranteed to be stable across retries of the Operation; the handler's Task Queue defaults to the Task Queue this Operation is handled on <!-- docs/develop/java/nexus/feature-guide.mdx:305-313 -->. In production prefer business-meaningful Workflow IDs passed in the Operation input <!-- docs/develop/java/nexus/feature-guide.mdx:319-320 -->.

## Multi-argument Workflows

A Nexus Operation has exactly one input parameter. When the backing Workflow takes multiple arguments, use `WorkflowRunOperation.fromWorkflowHandle` together with `WorkflowHandle.fromWorkflowMethod` to map the Operation input to the Workflow's parameter list <!-- docs/develop/java/nexus/feature-guide.mdx:329-389 -->.

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

<!-- docs/develop/java/nexus/feature-guide.mdx:361-386 -->

## Registering the Service implementation on a Worker

On the handler-side Worker, register the `@ServiceImpl` class with `worker.registerNexusServiceImplementation(...)` alongside any handler Workflow implementation types <!-- docs/develop/java/nexus/feature-guide.mdx:417-422 -->.

```java
WorkerFactory factory = WorkerFactory.newInstance(client);

Worker worker = factory.newWorker(DEFAULT_TASK_QUEUE_NAME);
worker.registerWorkflowImplementationTypes(HelloHandlerWorkflowImpl.class);
worker.registerNexusServiceImplementation(new SampleNexusServiceImpl());

factory.start();
```

<!-- docs/develop/java/nexus/feature-guide.mdx:415-422 -->

## Caller Workflow: stub + Endpoint binding

The caller Workflow holds a typed stub created from the Service interface plus `NexusServiceOptions` carrying per-Operation defaults. The stub itself does **not** know the Endpoint — Endpoint binding lives on the caller-Worker's `WorkflowImplementationOptions`.

Inside the caller Workflow:

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

On the caller-side Worker, the Endpoint name for a given Service is wired into `WorkflowImplementationOptions.setNexusServiceOptions(...)`, keyed by the Service's simple name, and passed to `registerWorkflowImplementationTypes` <!-- docs/develop/java/nexus/feature-guide.mdx:519-543 -->.

```java
Worker worker = factory.newWorker(DEFAULT_TASK_QUEUE_NAME);
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

<!-- docs/develop/java/nexus/feature-guide.mdx:533-542 -->

## Async result and operation token

`Workflow.startNexusOperation(stub::operation, input)` returns a `NexusOperationHandle<O>`. Call `handle.getExecution().get()` to wait for the Operation to be started — this returns a `NexusOperationExecution` that, for asynchronous Operations, carries the operation token. Call `handle.getResult().get()` to obtain the Operation result <!-- docs/develop/java/nexus/feature-guide.mdx:491-501 -->.

```java
NexusOperationHandle<SampleNexusService.HelloOutput> handle =
    Workflow.startNexusOperation(
        sampleNexusService::hello, new SampleNexusService.HelloInput(message, language));
handle.getExecution().get();   // optional: NexusOperationExecution has the op token if async
return handle.getResult().get().getMessage();
```

<!-- docs/develop/java/nexus/feature-guide.mdx:492-500 -->

## Setting per-Operation timeouts

Per-Operation defaults are set with `NexusOperationOptions.Builder`. The feature guide shows `setScheduleToCloseTimeout(Duration)` <!-- docs/develop/java/nexus/feature-guide.mdx:451-454 -->. See `references/core/nexus.md` for the full Schedule-to-Close / Schedule-to-Start / Start-to-Close model.

<!-- VERIFY: feature-guide only demonstrates setScheduleToCloseTimeout on NexusOperationOptions.Builder; setScheduleToStartTimeout and setStartToCloseTimeout are not shown in the Java docs read here. Not asserted to avoid fabrication. -->

## Cancellation

`Workflow.newCancellationScope(Runnable)` creates a new scope; SDK methods started inside it — including Nexus Operations — are associated with the scope, and calling `.cancel()` on the returned scope cancels them. The promise returned by `Workflow.startNexusOperation` resolves when the Operation finishes (success, failure, timeout, or canceled) <!-- docs/develop/java/nexus/feature-guide.mdx:642-647 -->.

Only asynchronous Operations can be canceled; cancellation is sent using the operation token. The Workflow or other resources backing the Operation may choose to ignore the request and may then enter a terminal state regardless <!-- docs/develop/java/nexus/feature-guide.mdx:649-651 -->.

Cancellation types control how the caller reacts <!-- docs/develop/java/nexus/feature-guide.mdx:656-665 -->:

- `ABANDON` — do not request cancellation of the Operation.
- `TRY_CANCEL` — initiate a cancellation request and immediately report cancellation to the caller; delivery to the handler is not guaranteed if the caller exits first.
- `WAIT_REQUESTED` — request cancellation and wait for confirmation that the request was received (not for actual cancellation).
- `WAIT_COMPLETED` — wait for the Operation to complete; the Operation may or may not complete as canceled.

The default is `WAIT_COMPLETED`. Set a different type on `NexusServiceOptions` by calling `.setCancellationType()` on `NexusServiceOptions.Builder` <!-- docs/develop/java/nexus/feature-guide.mdx:664-665 -->.

Once the caller Workflow completes, the caller's Nexus Machinery stops attempting to cancel Operations that have not yet been canceled, letting them run to completion. To ensure cancellations are delivered, wait for all pending Operations to deliver their cancellation requests before exiting the Workflow <!-- docs/develop/java/nexus/feature-guide.mdx:667-671 -->.

## Worker development against a local server

Start a dev server with Nexus enabled, create handler and caller Namespaces, then create the Endpoint that routes from the caller to the handler's target Namespace and Task Queue <!-- docs/develop/java/nexus/feature-guide.mdx:59-90 -->:

```bash
temporal server start-dev

temporal operator namespace create --namespace my-target-namespace
temporal operator namespace create --namespace my-caller-namespace

temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

Run the handler Worker, then the caller Worker, then the starter <!-- docs/develop/java/nexus/feature-guide.mdx:606-629 -->:

```bash
./gradlew -q execute -PmainClass=io.temporal.samples.nexus.handler.HandlerWorker \
    --args="-target-host localhost:7233 -namespace my-target-namespace"

./gradlew -q execute -PmainClass=io.temporal.samples.nexus.caller.CallerWorker \
    --args="-target-host localhost:7233 -namespace my-caller-namespace"

./gradlew -q execute -PmainClass=io.temporal.samples.nexus.caller.CallerStarter \
    --args="-target-host localhost:7233 -namespace my-caller-namespace"
```

## See also

- `references/core/nexus.md` — cross-SDK concepts: Endpoints, lifecycle, timeouts, retries, circuit breaking, cancellation semantics.
- Java Nexus sample: <https://github.com/temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexus> <!-- docs/develop/java/nexus/feature-guide.mdx:43-46 -->.
