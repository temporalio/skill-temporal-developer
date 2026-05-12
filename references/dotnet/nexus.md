# Nexus — .NET (C#) SDK

Temporal .NET SDK support for Nexus is in **Public Preview**. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:22 -->
Nexus connects Temporal Applications within and across Namespaces using a Nexus Endpoint, a Nexus Service contract, and Nexus Operations. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:25 -->
For cross-SDK concepts (Endpoints, request lifecycle, sync vs async semantics), see `references/core/nexus.md`.

## Prerequisites

- Temporal CLI v1.3.0 or higher recommended. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:48 -->
- Temporal .NET SDK v1.9.0 or higher. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:49 -->

Start a development Temporal Server (Nexus is enabled by default in current versions):

```
temporal server start-dev
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:54 -->

## Define the Service contract

Apply `[NexusService]` to an interface and `[NexusOperation]` to each method. Inputs and outputs are typically `record` types. Share the endpoint name through a `static readonly` field so the handler and caller use the same value. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:99-128 -->

```csharp
using NexusRpc;

[NexusService]
public interface IHelloService
{
    static readonly string EndpointName = "nexus-simple-endpoint";

    [NexusOperation]
    EchoOutput Echo(EchoInput input);

    [NexusOperation]
    HelloOutput SayHello(HelloInput input);

    public record EchoInput(string Message);
    public record EchoOutput(string Message);
    public record HelloInput(string Name, HelloLanguage Language);
    public record HelloOutput(string Message);

    public enum HelloLanguage { En, Fr, De, Es, Tr }
}
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:98-129 -->

## Synchronous Operation handler

Apply `[NexusServiceHandler(typeof(IHelloService))]` to the handler class. Each method bearing `[NexusOperationHandler]` returns an `IOperationHandler<In, Out>`. Use `OperationHandler.Sync<In, Out>((ctx, input) => ...)` for simple RPC handlers. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:154-167 -->

```csharp
using NexusRpc.Handlers;

[NexusServiceHandler(typeof(IHelloService))]
public class HelloService
{
    [NexusOperationHandler]
    public IOperationHandler<IHelloService.EchoInput, IHelloService.EchoOutput> Echo() =>
        OperationHandler.Sync<IHelloService.EchoInput, IHelloService.EchoOutput>(
            (ctx, input) => new(input.Message));
}
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:153-167 -->

Inside a sync handler, get the Temporal Client that the Worker was initialized with via `NexusOperationExecutionContext.Current.TemporalClient`. Use it to Signal, Query, Update, Signal-With-Start, or Update-With-Start a Workflow. All calls must complete within the Nexus request timeout; Updates should be short-lived to stay within this deadline. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:140-141, 169-178 -->

```csharp
private static string WorkflowIdForUser(string userId) => $"GreetingWorkflow_for_{userId}";

[NexusOperationHandler]
public IOperationHandler<INexusGreetingService.GetLanguagesInput, INexusGreetingService.GetLanguagesOutput> GetLanguages() =>
    OperationHandler.Sync<INexusGreetingService.GetLanguagesInput, INexusGreetingService.GetLanguagesOutput>(
        async (ctx, input) =>
        {
            var client = NexusOperationExecutionContext.Current.TemporalClient;
            var handle = client.GetWorkflowHandle<GreetingWorkflow>(WorkflowIdForUser(input.UserId));
            return await handle.QueryAsync(wf => wf.QueryLanguages(input.IncludeUnsupported));
        });
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:183-195 -->

Handlers should be reliable — the circuit breaker trips after 5 consecutive retryable errors and blocks all Operations from the caller to that Endpoint. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:136, 150 -->

## Asynchronous Operation handler

Use `WorkflowRunOperationHandler.FromHandleFactory` to back an Operation with a Workflow run. Inside the factory, call `context.StartWorkflowAsync` with a lambda invoking the Workflow's `RunAsync` method. Use `context.HandlerContext.RequestId` as the Workflow ID — it is stable across retries of the operation. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:203, 217-228 -->

```csharp
using NexusRpc.Handlers;
using Temporalio.Nexus;

[NexusServiceHandler(typeof(IHelloService))]
public class HelloService
{
    [NexusOperationHandler]
    public IOperationHandler<IHelloService.HelloInput, IHelloService.HelloOutput> SayHello() =>
        WorkflowRunOperationHandler.FromHandleFactory(
            (WorkflowRunOperationContext context, IHelloService.HelloInput input) =>
                context.StartWorkflowAsync(
                    (HelloHandlerWorkflow wf) => wf.RunAsync(input),
                    new() { Id = context.HandlerContext.RequestId }));
}
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:206-229 -->

Workflow IDs should typically be business-meaningful and are used to dedupe Workflow starts. Pass the ID in the Operation input when appropriate. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:231 -->

### Map a Nexus Operation input to multiple Workflow arguments

A Nexus Operation takes only one input parameter. To call a Workflow that takes multiple arguments, pass them through the `RunAsync` lambda: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:241 -->

```csharp
WorkflowRunOperationHandler.FromHandleFactory(
    (WorkflowRunOperationContext context, IHelloService.HelloInput input) =>
        context.StartWorkflowAsync(
            (HelloHandlerWorkflow wf) => wf.RunAsync(input.Language, input.Name),
            new() { Id = context.HandlerContext.RequestId }));
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:252-260 -->

## Register the Service in a Worker

Register a Nexus Service instance via `AddNexusService` on `TemporalWorkerOptions`. A Worker only handles incoming Nexus requests if the Service handler is registered. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:270-288; docs/develop/dotnet/nexus/quickstart.mdx:145 -->

```csharp
using var worker = new TemporalWorker(
    await ConnectClientAsync("nexus-simple-handler-namespace"),
    new TemporalWorkerOptions(taskQueue: "nexus-simple-handler-sample").
        AddNexusService(new HelloService()).
        AddWorkflow<HelloHandlerWorkflow>());
await worker.ExecuteAsync(tokenSource.Token);
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:274-281 -->

## Call a Nexus Operation from a caller Workflow

Inside a Workflow, call `Workflow.CreateNexusWorkflowClient<IService>(EndpointName)` to get a typed client bound to the Endpoint, then `ExecuteNexusOperationAsync` with a lambda invoking the service method. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:298-309 -->

```csharp
using Temporalio.Workflows;

[Workflow]
public class EchoCallerWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(string message)
    {
        var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
            ExecuteNexusOperationAsync(svc => svc.Echo(new(message)));
        return output.Message;
    }
}
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:295-308 -->

The caller depends only on the Service contract (`IHelloService`), not the handler implementation. This decoupling allows the caller and handler to live in separate Namespaces or separate codebases. <!-- docs/develop/dotnet/nexus/quickstart.mdx:182 -->

## Operation timeouts

Nexus Operations support three timeout types that control how long the caller waits at different stages of the lifecycle. Set them in `NexusWorkflowOperationOptions` passed to `ExecuteNexusOperationAsync`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:330-331 -->

### Schedule-to-Close

Limits the total duration from when the Operation is scheduled to when it completes. The Nexus Machinery automatically retries failed requests until this timeout is exceeded. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:335-336 -->

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        ScheduleToCloseTimeout = TimeSpan.FromMinutes(10),
    });
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:339-344 -->

### Schedule-to-Start

Limits how long the caller waits for the Operation to be started by the handler. If not set, no Schedule-to-Start timeout is enforced. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:348-349 -->

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        ScheduleToStartTimeout = TimeSpan.FromMinutes(2),
    });
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:352-357 -->

### Start-to-Close

Limits how long the caller waits for an asynchronous Operation to complete after it has been started. Applies only to asynchronous Operations. If not set, no Start-to-Close timeout is enforced. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:361-363 -->

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        StartToCloseTimeout = TimeSpan.FromMinutes(5),
    });
```

<!-- docs/develop/dotnet/nexus/feature-guide.mdx:366-371 -->

## Cancelling an Operation

To cancel a Nexus Operation from within a Workflow, cancel the cancellation token passed to the operation call. Only asynchronous operations can be cancelled in Nexus, since cancellation is sent using an operation token. The Workflow or other resources backing the operation may choose to ignore the cancellation request; if ignored, the operation may enter a terminal state. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:454-456 -->

Cancellation types control how the caller reacts to cancellation: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:458-463 -->

- `Abandon` — Do not request cancellation of the operation.
- `TryCancel` — Initiate a cancellation request and immediately report cancellation to the caller. Does not guarantee that cancellation is delivered to the operation handler if the caller exits before the delivery is done.
- `WaitCancellationRequested` — Request cancellation of the operation and wait for confirmation that the request was received. Does not wait for actual cancellation.
- `WaitCancellationCompleted` — Wait for operation completion. Operation may or may not complete as cancelled.

The default is `WaitCancellationCompleted`. Set a different option via the `CancellationType` property on `NexusWorkflowOperationOptions` when starting an operation. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:465 -->

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations that are still running. To ensure cancellations are delivered, wait for all pending operations to finish before exiting the Workflow. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:467-469 -->

See the [NexusCancellation sample](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusCancellation) for a reference implementation. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:471 -->

## Creating the Endpoint

Endpoint creation, caller/handler Namespace setup, and Temporal Cloud (`tcld`) configuration are SDK-agnostic. See `references/core/nexus.md` for the full workflow. The endpoint name configured with `temporal operator nexus endpoint create --name` must match the value used in `IHelloService.EndpointName`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:73-82, 104 -->

## Observability

Use `temporal workflow describe -w <ID>` to show pending Nexus Operations in the caller Workflow and attached callbacks on the handler Workflow. Use `temporal workflow show -w <ID>` to view the caller's history including Nexus events. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:554-564 -->

For **synchronous** Nexus Operations the caller's history contains: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:572-575 -->

- `NexusOperationScheduled`
- `NexusOperationCompleted`

For **asynchronous** Nexus Operations the caller's history contains: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:566-570 -->

- `NexusOperationScheduled`
- `NexusOperationStarted`
- `NexusOperationCompleted`

`NexusOperationStarted` is not reported in the caller's history for synchronous operations. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:579 -->

## Samples

- [NexusSimple](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusSimple) — sync `Echo` and async `SayHello` end-to-end. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:40 -->
- [NexusMessaging](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusMessaging) — caller pattern and on-demand pattern using Signals, Queries, Updates through Nexus. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:180, 198 -->
- [NexusCancellation](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusCancellation) — cancellation reference. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:471 -->
- [NexusMultiArg](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusMultiArg) — mapping a Nexus input to multiple Workflow arguments. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:243 -->

## See also

- `references/core/nexus.md` — cross-SDK concepts, Endpoint setup, Temporal Cloud configuration.
- `references/dotnet/error-handling.md` — `ApplicationFailureException`, retry policies, non-retryable errors (apply to Nexus Operations).
- `references/dotnet/observability.md` — logging, metrics, tracing in the .NET SDK.
