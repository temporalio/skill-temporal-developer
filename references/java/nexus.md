# Nexus — Java SDK

Temporal Java SDK support for Nexus is Generally Available <!-- docs/develop/java/nexus/feature-guide.mdx:22-23 -->. Use Nexus to connect Temporal Applications within and across Namespaces via a Nexus Endpoint, a Nexus Service contract, and Nexus Operations <!-- docs/develop/java/nexus/feature-guide.mdx:27-28 -->. For cross-SDK concepts (Endpoints, Services, Operations, lifecycle, retries, circuit breaking, timeouts), see `references/core/nexus.md`.

## Prerequisites

- Temporal CLI v1.3.0 or higher recommended <!-- docs/develop/java/nexus/feature-guide.mdx:52-53 -->
- Temporal Java SDK v1.28.0 or higher recommended <!-- docs/develop/java/nexus/feature-guide.mdx:54-55 -->

Start a development server with Nexus enabled:

```
temporal server start-dev
```

<!-- docs/develop/java/nexus/feature-guide.mdx:60 -->

## Define the Service contract

The contract is a plain Java interface annotated with `@Service` <!-- docs/develop/java/nexus/feature-guide.mdx:111 -->. Each Operation method is annotated with `@Operation` <!-- docs/develop/java/nexus/feature-guide.mdx:185,188 -->. Input/output classes use Jackson `@JsonCreator` / `@JsonProperty` so payloads serialize as JSON via the default Data Converter <!-- docs/develop/java/nexus/feature-guide.mdx:101-104,125 -->.

```java
import io.nexusrpc.Operation;
import io.nexusrpc.Service;

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

    @JsonProperty("name") public String getName() { return name; }
    @JsonProperty("language") public Language getLanguage() { return language; }
  }

  class HelloOutput { /* ... */ }
  class EchoInput  { /* ... */ }
  class EchoOutput { /* ... */ }

  @Operation HelloOutput hello(HelloInput input);
  @Operation EchoOutput  echo(EchoInput input);
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:110-191 -->

The Nexus annotations come from the `io.nexusrpc` package; the handler-side annotations live under `io.nexusrpc.handler` <!-- docs/develop/java/nexus/quickstart.mdx:58-59,92-94 -->.

A Nexus Operation can only take one input parameter. To start a Workflow whose method takes multiple arguments, use `WorkflowRunOperation.fromWorkflowHandle` (see below) <!-- docs/develop/java/nexus/feature-guide.mdx:331-332 -->.

## Synchronous Operation handler

Annotate the implementation class with `@ServiceImpl(service = SampleNexusService.class)` <!-- docs/develop/java/nexus/feature-guide.mdx:227 -->. Each Operation method is annotated with `@OperationImpl` and returns `OperationHandler<Input, Output>` <!-- docs/develop/java/nexus/feature-guide.mdx:229-230 -->. Use `OperationHandler.sync(...)` to expose a simple RPC handler — its lambda receives `(ctx, details, input)` <!-- docs/develop/java/nexus/feature-guide.mdx:215-216,232,238 -->.

```java
import io.nexusrpc.handler.OperationHandler;
import io.nexusrpc.handler.OperationImpl;
import io.nexusrpc.handler.ServiceImpl;
import io.temporal.nexus.Nexus;

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

Sync handlers should be reliable; the circuit breaker trips after 5 consecutive retryable errors and blocks all Operations from the caller to that Endpoint <!-- docs/develop/java/nexus/feature-guide.mdx:200-201 -->. All sync calls must complete within the Nexus request timeout; Updates should be short-lived to stay within this deadline <!-- docs/develop/java/nexus/feature-guide.mdx:250-251 -->.

### Use the Temporal Client from a handler

Inside a handler, obtain the Worker's `WorkflowClient` via `Nexus.getOperationContext().getWorkflowClient()` <!-- docs/develop/java/nexus/feature-guide.mdx:205-206,236-237 -->. Use it to Signal, Query, or Update a Workflow, or to Signal-With-Start / Update-With-Start <!-- docs/develop/java/nexus/feature-guide.mdx:248-249 -->.

```java
private GreetingWorkflow getWorkflowStub(String userId) {
  return Nexus.getOperationContext()
      .getWorkflowClient()
      .newWorkflowStub(GreetingWorkflow.class, getWorkflowId(userId));
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:266-270 -->

## Asynchronous Operation handler

Use `WorkflowRunOperation.fromWorkflowMethod` to expose a Workflow as an asynchronous Operation <!-- docs/develop/java/nexus/feature-guide.mdx:207,279 -->. The lambda receives `(ctx, details, input)` and returns a method reference to the Workflow method, using `details.getRequestId()` as a stable Workflow ID across retries <!-- docs/develop/java/nexus/feature-guide.mdx:299-314 -->.

```java
import io.temporal.client.WorkflowOptions;
import io.temporal.nexus.Nexus;
import io.temporal.nexus.WorkflowRunOperation;

@OperationImpl
public OperationHandler<SampleNexusService.HelloInput, SampleNexusService.HelloOutput> hello() {
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

<!-- docs/develop/java/nexus/feature-guide.mdx:292-315 -->

### Map a Nexus Operation input to multiple Workflow arguments

When the Workflow method takes more than one argument, use `WorkflowRunOperation.fromWorkflowHandle` together with `WorkflowHandle.fromWorkflowMethod` to bind the additional arguments from the Nexus input <!-- docs/develop/java/nexus/feature-guide.mdx:331-332,361-385 -->.

```java
import io.temporal.nexus.WorkflowHandle;
import io.temporal.nexus.WorkflowRunOperation;

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

## Register the Service in a handler Worker

Register the Service implementation on the Worker alongside any Workflows it starts via `worker.registerNexusServiceImplementation(...)` <!-- docs/develop/java/nexus/feature-guide.mdx:419 -->.

```java
Worker worker = factory.newWorker("my-handler-task-queue");
worker.registerWorkflowImplementationTypes(HelloHandlerWorkflowImpl.class);
worker.registerNexusServiceImplementation(new SampleNexusServiceImpl());
factory.start();
```

<!-- docs/develop/java/nexus/feature-guide.mdx:417-421 -->

## Call a Nexus Operation from a caller Workflow

In the caller Workflow, build a stub with `Workflow.newNexusServiceStub(...)`. Pass a `NexusServiceOptions` whose `setOperationOptions(...)` carries a `NexusOperationOptions` with timeouts such as `setScheduleToCloseTimeout(Duration.ofSeconds(10))` <!-- docs/develop/java/nexus/feature-guide.mdx:441-455 -->.

```java
import io.temporal.workflow.NexusOperationOptions;
import io.temporal.workflow.NexusServiceOptions;
import io.temporal.workflow.Workflow;
import java.time.Duration;

SampleNexusService sampleNexusService =
    Workflow.newNexusServiceStub(
        SampleNexusService.class,
        NexusServiceOptions.newBuilder()
            .setOperationOptions(
                NexusOperationOptions.newBuilder()
                    .setScheduleToCloseTimeout(Duration.ofSeconds(10))
                    .build())
            .build());

public String echo(String message) {
  return sampleNexusService.echo(new SampleNexusService.EchoInput(message)).getMessage();
}
```

<!-- docs/develop/java/nexus/feature-guide.mdx:437-462 -->

### Access the Operation execution and result separately

`Workflow.startNexusOperation(...)` returns a `NexusOperationHandle<T>`. Call `handle.getExecution().get()` to wait until the Operation has been started (the returned `NexusOperationExecution` carries the operation token for async Operations), and `handle.getResult().get()` to wait for completion <!-- docs/develop/java/nexus/feature-guide.mdx:493-500 -->.

```java
NexusOperationHandle<SampleNexusService.HelloOutput> handle =
    Workflow.startNexusOperation(
        sampleNexusService::hello,
        new SampleNexusService.HelloInput(message, language));
handle.getExecution().get();
return handle.getResult().get().getMessage();
```

<!-- docs/develop/java/nexus/feature-guide.mdx:493-500 -->

### Register the caller Workflow with an Endpoint

On the caller Worker, pass `WorkflowImplementationOptions` whose `setNexusServiceOptions(...)` maps each Nexus Service name to a `NexusServiceOptions` that sets the Endpoint via `setEndpoint(...)` <!-- docs/develop/java/nexus/feature-guide.mdx:534-542 -->.

```java
import io.temporal.worker.WorkflowImplementationOptions;
import io.temporal.workflow.NexusServiceOptions;
import java.util.Collections;

Worker worker = factory.newWorker("my-caller-workflow-task-queue");
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
```

<!-- docs/develop/java/nexus/feature-guide.mdx:533-544 -->

## Cancelling an Operation

To cancel a Nexus Operation from within a caller Workflow, create a `CancellationScope` with `Workflow.newCancellationScope(Runnable)`. Any SDK methods started inside that `Runnable` — including Nexus Operations — are associated with the scope, and calling `cancel()` cancels the context and those methods <!-- docs/develop/java/nexus/feature-guide.mdx:642-645 -->. The promise returned by `Workflow.startNexusOperation` resolves when the Operation succeeds, fails, times out, or is canceled <!-- docs/develop/java/nexus/feature-guide.mdx:646-647 -->.

Only asynchronous Operations can be canceled; the Workflow or other resources backing the Operation may ignore the request <!-- docs/develop/java/nexus/feature-guide.mdx:649-651 -->.

Cancellation types control how the caller reacts to cancellation <!-- docs/develop/java/nexus/feature-guide.mdx:653-655 -->:

- `ABANDON` — do not request cancellation of the Operation <!-- docs/develop/java/nexus/feature-guide.mdx:656 -->.
- `TRY_CANCEL` — initiate a cancellation request and immediately report cancellation to the caller; delivery is not guaranteed if the caller exits first <!-- docs/develop/java/nexus/feature-guide.mdx:657-659 -->.
- `WAIT_REQUESTED` — request cancellation and wait for confirmation that the request was received; does not wait for actual cancellation <!-- docs/develop/java/nexus/feature-guide.mdx:660-661 -->.
- `WAIT_COMPLETED` — wait for Operation completion; the Operation may or may not complete as cancelled <!-- docs/develop/java/nexus/feature-guide.mdx:662 -->.

The default is `WAIT_COMPLETED`. Override it by calling `.setCancellationType(...)` on `NexusServiceOptions.Builder` <!-- docs/develop/java/nexus/feature-guide.mdx:664-665 -->.

Once the caller Workflow completes, the caller's Nexus Machinery stops attempting to cancel Operations that have not yet been canceled, letting them run to completion <!-- docs/develop/java/nexus/feature-guide.mdx:667-668 -->. To ensure cancellations are delivered, wait for all pending Operations to deliver their cancellation requests before exiting the Workflow <!-- docs/develop/java/nexus/feature-guide.mdx:670-671 -->.

## Creating the Endpoint

Endpoint creation is independent of the Java SDK. Use the Temporal CLI for self-hosted clusters:

```
temporal operator nexus endpoint create \
  --name my-nexus-endpoint-name \
  --target-namespace my-target-namespace \
  --target-task-queue my-handler-task-queue
```

<!-- docs/develop/java/nexus/feature-guide.mdx:86-90 -->

For Temporal Cloud, use `tcld nexus endpoint create` with `--allow-namespace` to build the Endpoint's caller allowlist <!-- docs/develop/java/nexus/feature-guide.mdx:733-741 -->. See `references/core/nexus.md` for full Endpoint and Access Policy details.

## Observability

Nexus events appear in the caller Workflow's history. For **synchronous** Operations the caller sees `NexusOperationScheduled` and `NexusOperationCompleted`; `NexusOperationStarted` is not reported for sync Operations <!-- docs/develop/java/nexus/feature-guide.mdx:792-793,823-830 -->. For **asynchronous** Operations the caller sees `NexusOperationScheduled`, `NexusOperationStarted`, and `NexusOperationCompleted` <!-- docs/develop/java/nexus/feature-guide.mdx:797-798,817-821 -->.

Use `temporal workflow describe -w <ID>` to inspect pending Nexus Operations on the caller and any attached callbacks on the handler; `temporal workflow show -w <ID>` prints the caller's full Nexus event history <!-- docs/develop/java/nexus/feature-guide.mdx:804-815 -->.

See `references/java/observability.md` for general logging, metrics, and tracing.

## Samples

Source samples used throughout the feature guide live under the [samples-java](https://github.com/temporalio/samples-java/tree/main/core/src/main/java/io/temporal/samples) repository <!-- docs/develop/java/nexus/feature-guide.mdx:43-46 -->:

- `io.temporal.samples.nexus` — base Nexus sample (service, handler, caller, starter) <!-- docs/develop/java/nexus/feature-guide.mdx:44 -->.
- `io.temporal.samples.nexusmessaging` — caller-pattern and on-demand-pattern Signal/Query/Update through Nexus <!-- docs/develop/java/nexus/feature-guide.mdx:253,274-275 -->.
- `io.temporal.samples.nexusmultipleargs` — mapping a Nexus input to a multi-argument Workflow <!-- docs/develop/java/nexus/feature-guide.mdx:336 -->.
- `io.temporal.samples.nexuscancellation` — Nexus Operation cancellation <!-- docs/develop/java/nexus/feature-guide.mdx:673-675 -->.

## See also

- `references/core/nexus.md` — cross-SDK Nexus concepts (Endpoints, Registry, lifecycle, retries, circuit breaking, timeouts, security, patterns).
- `references/java/error-handling.md` — `ApplicationFailure`, retry policies, non-retryable errors.
- `references/java/observability.md` — logging, metrics, tracing, Search Attributes.
