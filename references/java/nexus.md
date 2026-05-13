# Nexus — Java SDK

Java-SDK-specific programming model for Temporal Nexus. For shared concepts
(lifecycle, retries, circuit breaking, cancellation vs termination, deployment
patterns, security, debugging, metrics) see `references/core/nexus.md`. This
file covers Java annotations, builder methods, stubs, options builders,
cancellation scopes, and Worker registration.

## Support status

Temporal Java SDK support for Nexus is **Generally Available**.

Recommended minimum versions: Temporal CLI **v1.3.0 or higher** and Temporal
Java SDK **v1.28.0 or higher**.

Nexus utilities live in the `io.temporal.nexus.*` packages; caller-side stubs
and options live in `io.temporal.workflow.*`.

## Defining the Service contract

A Nexus Service is a plain Java interface annotated with `@Service`. Each
operation is a method annotated with `@Operation`. Input and output types are
declared as inner classes (or `enum`s) and serialized as JSON by the default
Data Converter, so they must be Jackson-friendly: provide a `@JsonCreator`
constructor and `@JsonProperty`-annotated accessors.

```java
@Service
public interface SampleNexusService {
  enum Language { EN, FR, DE, ES, TR }

  class HelloInput {
    private final String name;
    private final Language language;

    @JsonCreator(mode = JsonCreator.Mode.PROPERTIES)
    public HelloInput(
        @JsonProperty("name") String name,
        @JsonProperty("language") Language language) {
      this.name = name;
      this.language = language;
    }

    @JsonProperty("name")    public String getName()       { return name; }
    @JsonProperty("language") public Language getLanguage() { return language; }
  }

  class HelloOutput {
    private final String message;

    @JsonCreator(mode = JsonCreator.Mode.PROPERTIES)
    public HelloOutput(@JsonProperty("message") String message) {
      this.message = message;
    }

    @JsonProperty("message") public String getMessage() { return message; }
  }

  // EchoInput / EchoOutput follow the same shape.

  @Operation HelloOutput hello(HelloInput input);
  @Operation EchoOutput  echo(EchoInput input);
}
```

The annotations `@Service` and `@Operation` come from the `io.nexusrpc`
package (see the quickstart imports: `io.nexusrpc.Operation`,
`io.nexusrpc.Service`).

## Handler basics

The Service implementation is a plain class annotated with
`@ServiceImpl(service = ...)`. Each method is annotated with `@OperationImpl`
and returns an `OperationHandler<TIn, TOut>` matching an operation declared
on the interface.

```java
@ServiceImpl(service = SampleNexusService.class)
public class SampleNexusServiceImpl {
  @OperationImpl
  public OperationHandler<SampleNexusService.EchoInput, SampleNexusService.EchoOutput> echo() {
    return OperationHandler.sync(
        (ctx, details, input) ->
            new SampleNexusService.EchoOutput(input.getMessage()));
  }
}
```

Annotation imports come from `io.nexusrpc.handler` (`OperationHandler`,
`OperationImpl`, `ServiceImpl`).

## Synchronous Operation handler

`OperationHandler.sync(lambda)` (note the **lowercase** `sync`) is the entry
point for simple RPC-style handlers. The lambda has the signature
`(ctx, details, input) -> output` and should return quickly — sync handlers
must complete within the Nexus request deadline.

```java
@OperationImpl
public OperationHandler<EchoInput, EchoOutput> echo() {
  return OperationHandler.sync(
      (ctx, details, input) -> new EchoOutput(input.getMessage()));
}
```

## Using the Temporal Client from a sync handler

`Nexus.getOperationContext().getWorkflowClient()` returns the `WorkflowClient`
that the Worker was initialized with. Use it inside a sync handler to make
Signal, Query, Update, Signal-With-Start, or Update-With-Start calls. All
calls must complete within the Nexus request timeout, so keep Updates and
other interactions short.

```java
private GreetingWorkflow getWorkflowStub(String userId) {
  return Nexus.getOperationContext()
      .getWorkflowClient()
      .newWorkflowStub(GreetingWorkflow.class, getWorkflowId(userId));
}
```

## Asynchronous Workflow-Run Operation

`WorkflowRunOperation.fromWorkflowMethod` exposes a Workflow as an
asynchronous Nexus Operation. The lambda has signature
`(ctx, details, input)` and must return a method reference to the
Workflow's `@WorkflowMethod` (e.g. `stub::workflowMethodName`). The handler
returns immediately once the underlying Workflow Execution has started.

```java
@OperationImpl
public OperationHandler<HelloInput, HelloOutput> hello() {
  return WorkflowRunOperation.fromWorkflowMethod(
      (ctx, details, input) ->
          Nexus.getOperationContext()
              .getWorkflowClient()
              .newWorkflowStub(
                  HelloHandlerWorkflow.class,
                  WorkflowOptions.newBuilder()
                      .setWorkflowId(details.getRequestId())
                      .build())
              ::hello);
}
```

`details.getRequestId()` returns the request ID allocated by Temporal when the
caller scheduled the operation; it is **stable across retries**, which makes
it a safe deduplication key when no business ID is available. In production,
prefer a business-meaningful Workflow ID passed through the Operation input.

The Task Queue defaults to the queue this operation is handled on, so you
typically do not need to set one on `WorkflowOptions`.

## Mapping one Operation input to multiple Workflow args

A Nexus Operation can only take **one** input parameter. When the handler
Workflow takes multiple arguments, use `WorkflowRunOperation.fromWorkflowHandle`
together with `WorkflowHandle.fromWorkflowMethod(methodReference, arg1, arg2, ...)`
to expand the single Operation input into multiple Workflow arguments.

```java
@OperationImpl
public OperationHandler<HelloInput, HelloOutput> hello() {
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

## Registering a Nexus Service in the handler Worker

On the handler Worker, register the Workflow types that back async operations
with `worker.registerWorkflowImplementationTypes(...)` and register the
Service implementation instance with `worker.registerNexusServiceImplementation(...)`.

```java
public class HandlerWorker {
  public static final String DEFAULT_TASK_QUEUE_NAME = "my-handler-task-queue";

  public static void main(String[] args) {
    WorkflowClient client = ClientOptions.getWorkflowClient(args);
    WorkerFactory factory = WorkerFactory.newInstance(client);

    Worker worker = factory.newWorker(DEFAULT_TASK_QUEUE_NAME);
    worker.registerWorkflowImplementationTypes(HelloHandlerWorkflowImpl.class);
    worker.registerNexusServiceImplementation(new SampleNexusServiceImpl());

    factory.start();
  }
}
```

## Caller Workflow

A caller Workflow obtains a typed Nexus stub via `Workflow.newNexusServiceStub`,
passing the Service interface and a `NexusServiceOptions`. Operation-level
defaults (such as `setScheduleToCloseTimeout`) are nested in a
`NexusOperationOptions` builder.

```java
public class EchoCallerWorkflowImpl implements EchoCallerWorkflow {
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
    return sampleNexusService.echo(
        new SampleNexusService.EchoInput(message)).getMessage();
  }
}
```

### Handle-based calls

For asynchronous operations, use `Workflow.startNexusOperation(methodRef, input)`
to get a `NexusOperationHandle<TOut>`. Call `handle.getExecution().get()` to
wait for the "started" signal — the returned `NexusOperationExecution` carries
the **operation token** for async operations. Call `handle.getResult().get()`
to wait for completion.

```java
public class HelloCallerWorkflowImpl implements HelloCallerWorkflow {
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
  public String hello(String message, SampleNexusService.Language language) {
    NexusOperationHandle<SampleNexusService.HelloOutput> handle =
        Workflow.startNexusOperation(
            sampleNexusService::hello,
            new SampleNexusService.HelloInput(message, language));
    handle.getExecution().get();           // wait for "started" + token
    return handle.getResult().get().getMessage();
  }
}
```

## Endpoint binding at the caller Worker

The Nexus Endpoint name is bound to the Service **at the caller Worker** via
`WorkflowImplementationOptions`. Build a per-service map of `NexusServiceOptions`
using the Service interface's simple name as the key, set the `endpoint` on
that options object, and pass the `WorkflowImplementationOptions` to
`worker.registerWorkflowImplementationTypes(opts, CallerWorkflowImpl.class, ...)`.

```java
public class CallerWorker {
  public static final String DEFAULT_TASK_QUEUE_NAME = "my-caller-workflow-task-queue";

  public static void main(String[] args) {
    WorkflowClient client = ClientOptions.getWorkflowClient(args);
    WorkerFactory factory = WorkerFactory.newInstance(client);

    Worker worker = factory.newWorker(DEFAULT_TASK_QUEUE_NAME);
    worker.registerWorkflowImplementationTypes(
        WorkflowImplementationOptions.newBuilder()
            .setNexusServiceOptions(
                Collections.singletonMap(
                    "SampleNexusService",
                    NexusServiceOptions.newBuilder()
                        .setEndpoint("my-nexus-endpoint-name")
                        .build()))
            .build(),
        EchoCallerWorkflowImpl.class,
        HelloCallerWorkflowImpl.class);

    factory.start();
  }
}
```

## Cancellation

To cancel a Nexus Operation from within a caller Workflow, wrap the call in a
`Workflow.newCancellationScope(Runnable)`. This returns a `CancellationScope`;
calling `.cancel()` on it cancels the scope and any SDK methods (including
Nexus operations) started inside that `Runnable`. The promise returned by
`Workflow.startNexusOperation` resolves when the operation finishes,
regardless of whether it succeeded, failed, timed out, or was canceled.

Only **asynchronous** operations can be canceled, because cancellation is
delivered using the operation token. The Workflow or other resource backing
the operation may choose to ignore the cancellation request; if ignored, the
operation may still reach a terminal state on its own.

### Cancellation types

When starting a Nexus operation the caller can choose how it reacts to a
cancellation request. Set the type on `NexusServiceOptions.Builder` via
`.setCancellationType(...)`:

- `ABANDON` — do not request cancellation of the operation.
- `TRY_CANCEL` — send a cancellation request and immediately report
  cancellation to the caller; delivery to the handler is not guaranteed if
  the caller exits before delivery completes.
- `WAIT_REQUESTED` — request cancellation and wait for confirmation that the
  request was received, but do not wait for the operation to finish.
- `WAIT_COMPLETED` — wait for the operation to complete (it may or may not
  complete as canceled).

The **default is `WAIT_COMPLETED`**.

Once the caller Workflow completes, the caller's Nexus machinery stops trying
to cancel operations that have not yet been canceled and lets them run. To
ensure cancellations are delivered, wait for all pending operations to
deliver their cancellation requests before exiting the caller Workflow.

See the
[Nexus cancellation sample](https://github.com/temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples/nexuscancellation)
referenced in the feature guide for a runnable example.

## End-to-end flow (dev server)

1. `temporal server start-dev` — launches the dev server with Nexus enabled.

2. Create caller and handler Namespaces with
   `temporal operator namespace create --namespace <name>`.

3. Create the Endpoint with
   `temporal operator nexus endpoint create --name my-nexus-endpoint-name --target-namespace my-target-namespace --target-task-queue my-handler-task-queue`.

4. Run the handler Worker:
   `./gradlew -q execute -PmainClass=io.temporal.samples.nexus.handler.HandlerWorker --args="-target-host localhost:7233 -namespace my-target-namespace"`.

5. Run the caller Worker:
   `./gradlew -q execute -PmainClass=io.temporal.samples.nexus.caller.CallerWorker --args="-target-host localhost:7233 -namespace my-caller-namespace"`.

6. Run the starter:
   `./gradlew -q execute -PmainClass=io.temporal.samples.nexus.caller.CallerStarter --args="-target-host localhost:7233 -namespace my-caller-namespace"`.

See the feature guide for the full cross-Namespace walkthrough.

## Cross-Namespace in Temporal Cloud

In Temporal Cloud, the Nexus Endpoint is created with the `tcld` CLI. The
`--allow-namespace <caller-namespace.account>` flag builds the allowlist of
caller Namespaces that are permitted to use the Endpoint; this is the runtime
access-control mechanism for cross-Namespace Nexus calls. Creating an
Endpoint requires a Developer (or higher) account role and `NamespaceAdmin`
permission on the `--target-namespace`.

```
tcld nexus endpoint create \
  --name <my-nexus-endpoint-name> \
  --target-task-queue my-handler-task-queue \
  --target-namespace <my-target-namespace.account> \
  --allow-namespace <my-caller-namespace.account> \
  --description-file ./path/to/description.md
```

Refer to the feature guide for the full Cloud setup (certificate generation
with `tcld gen ca`, Namespace creation with `tcld namespace create`, and
running Workers with mTLS arguments).

