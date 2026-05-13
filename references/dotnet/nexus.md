# Temporal Nexus — .NET SDK

Temporal .NET SDK support for Nexus is in **Public Preview** <!-- docs/develop/dotnet/nexus/feature-guide.mdx:19-23 -->. Cross-SDK concepts (Nexus Service, Operation, Endpoint, Machinery, timeouts, retries, circuit breaking, observability events) are in `references/core/nexus.md` — this file only covers the .NET SDK surface tokens and example shapes. Minimum versions: Temporal CLI **v1.3.0 or higher** and Temporal .NET SDK **v1.9.0 or higher** <!-- docs/develop/dotnet/nexus/feature-guide.mdx:46-49 -->.

## Namespaces

- `NexusRpc` — contract attributes `[NexusService]` and `[NexusOperation]` on the interface and its methods <!-- docs/develop/dotnet/nexus/feature-guide.mdx:99-110 -->.
- `NexusRpc.Handlers` — handler attributes `[NexusServiceHandler]` and `[NexusOperationHandler]`, plus `IOperationHandler<TIn, TOut>` and the static `OperationHandler.Sync` factory <!-- docs/develop/dotnet/nexus/feature-guide.mdx:154-167 -->.
- `Temporalio.Nexus` — `WorkflowRunOperationHandler.FromHandleFactory`, `WorkflowRunOperationContext`, and `NexusOperationExecutionContext` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:138-144; docs/develop/dotnet/nexus/feature-guide.mdx:208-209 -->.
- `Temporalio.Workflows` — `Workflow.CreateNexusWorkflowClient` and `NexusWorkflowOperationOptions` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:296-307; docs/develop/dotnet/nexus/feature-guide.mdx:330-344 -->.
- `Temporalio.Worker` — `TemporalWorkerOptions.AddNexusService` for handler registration <!-- docs/develop/dotnet/nexus/feature-guide.mdx:273-278 -->.

## Defining the Service contract

`[NexusService]` on the interface declares the contract; `[NexusOperation]` marks each callable method. Nested `record` and `enum` types declare input/output shapes. The `static readonly string EndpointName` field on the contract is a convenient place to keep the Endpoint name with the contract <!-- docs/develop/dotnet/nexus/feature-guide.mdx:99-128 -->.

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

    public enum HelloLanguage
    {
        En,
        Fr,
        De,
        Es,
        Tr,
    }
}
```

## Synchronous Operation handlers

Apply `[NexusServiceHandler(typeof(IService))]` to the implementation class and `[NexusOperationHandler]` to each method that returns an `IOperationHandler<TIn, TOut>`. For a sync handler return `OperationHandler.Sync<TIn, TOut>((ctx, input) => ...)` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:154-167 -->.

```csharp
using NexusRpc.Handlers;

[NexusServiceHandler(typeof(IHelloService))]
public class HelloService
{
    [NexusOperationHandler]
    public IOperationHandler<IHelloService.EchoInput, IHelloService.EchoOutput> Echo() =>
        // This Nexus service operation is a simple sync handler
        OperationHandler.Sync<IHelloService.EchoInput, IHelloService.EchoOutput>(
            (ctx, input) => new(input.Message));

    // ...
}
```

Inside a sync handler, `NexusOperationExecutionContext.Current.TemporalClient` returns the Temporal Client the Worker was initialized with, for Signal/Query/Update calls or other reliable code. All calls must complete within the Nexus request timeout <!-- docs/develop/dotnet/nexus/feature-guide.mdx:140-142; docs/develop/dotnet/nexus/feature-guide.mdx:171-194 -->.

```csharp
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

## Asynchronous Operation handlers (Workflow-Run Operations)

`WorkflowRunOperationHandler.FromHandleFactory(...)` exposes a Workflow as an asynchronous Operation. The factory receives a `WorkflowRunOperationContext` and the typed input, and returns the handle produced by `context.StartWorkflowAsync(...)` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:201-228 -->.

```csharp
using NexusRpc.Handlers;
using Temporalio.Nexus;

[NexusServiceHandler(typeof(IHelloService))]
public class HelloService
{
    // ...

    [NexusOperationHandler]
    public IOperationHandler<IHelloService.HelloInput, IHelloService.HelloOutput> SayHello() =>
        // This Nexus service operation is backed by a workflow run
        WorkflowRunOperationHandler.FromHandleFactory(
            (WorkflowRunOperationContext context, IHelloService.HelloInput input) =>
                context.StartWorkflowAsync(
                    (HelloHandlerWorkflow wf) => wf.RunAsync(input),
                    // Workflow IDs should typically be business meaningful IDs and are used to
                    // dedupe workflow starts. For this example, we're using the request ID
                    // allocated by Temporal when the caller workflow schedules the operation,
                    // this ID is guaranteed to be stable across retries of this operation.
                    new() { Id = context.HandlerContext.RequestId }));
}
```

Workflow IDs should typically be business-meaningful IDs and are used to dedupe Workflow starts; the sample uses `context.HandlerContext.RequestId` because it is stable across retries of the Operation <!-- docs/develop/dotnet/nexus/feature-guide.mdx:222-231 -->.

## Multi-argument Workflows

A Nexus Operation accepts only one input parameter. To start a Workflow that takes multiple arguments, unpack the fields in the call to `RunAsync` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:239-262 -->.

```csharp
[NexusServiceHandler(typeof(IHelloService))]
public class HelloService
{
    [NexusOperationHandler]
    public IOperationHandler<IHelloService.HelloInput, IHelloService.HelloOutput> SayHello() =>
        WorkflowRunOperationHandler.FromHandleFactory(
            (WorkflowRunOperationContext context, IHelloService.HelloInput input) =>
                context.StartWorkflowAsync(
                    (HelloHandlerWorkflow wf) => wf.RunAsync(input.Language, input.Name),
                    new() { Id = context.HandlerContext.RequestId }));
}
```

## Registering Nexus Services on a Worker

Chain `.AddNexusService(handler)` off `TemporalWorkerOptions`, alongside `.AddWorkflow<T>()` and activity registrations <!-- docs/develop/dotnet/nexus/feature-guide.mdx:268-288 -->.

```csharp
using var worker = new TemporalWorker(
    await ConnectClientAsync("nexus-simple-handler-namespace"),
    new TemporalWorkerOptions(taskQueue: "nexus-simple-handler-sample").
        AddNexusService(new HelloService()).
        AddWorkflow<HelloHandlerWorkflow>());
```

## Calling Nexus Operations from a Workflow

In a caller Workflow, `Workflow.CreateNexusWorkflowClient<TService>(endpointName)` returns a typed client; `.ExecuteNexusOperationAsync(svc => svc.Method(...))` schedules the Operation and awaits its result <!-- docs/develop/dotnet/nexus/feature-guide.mdx:294-309 -->.

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

## Setting per-Operation timeouts

`NexusWorkflowOperationOptions` carries three `TimeSpan` fields — `ScheduleToCloseTimeout`, `ScheduleToStartTimeout`, and `StartToCloseTimeout` — passed as the second argument to `ExecuteNexusOperationAsync` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:328-371 -->. See `references/core/nexus.md` for the semantics of each.

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        ScheduleToCloseTimeout = TimeSpan.FromMinutes(10),
        ScheduleToStartTimeout = TimeSpan.FromMinutes(2),
        StartToCloseTimeout = TimeSpan.FromMinutes(5),
    });
```

## Cancellation

To cancel a Nexus Operation, cancel the cancellation token passed to the operation call. Only asynchronous Operations can be canceled; the handler may choose to ignore the request <!-- docs/develop/dotnet/nexus/feature-guide.mdx:452-456 -->. Cancellation types are set on `CancellationType` in `NexusWorkflowOperationOptions` <!-- docs/develop/dotnet/nexus/feature-guide.mdx:458-465 -->:

- `Abandon` — do not request cancellation of the operation.
- `TryCancel` — initiate a cancellation request and immediately report cancellation to the caller; delivery is not guaranteed if the caller exits before delivery completes.
- `WaitCancellationRequested` — request cancellation and wait for confirmation the request was received; does not wait for actual cancellation.
- `WaitCancellationCompleted` — wait for operation completion; operation may or may not complete as cancelled. **This is the default.**

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        CancellationType = NexusOperationCancellationType.TryCancel, // <!-- VERIFY --> enum type name not in docs
    });
```

Once the caller Workflow completes, the caller's Nexus Machinery will not make any further attempts to cancel operations still running; wait for pending Operations to finish before exiting the Workflow if cancellations must be delivered <!-- docs/develop/dotnet/nexus/feature-guide.mdx:467-469 -->.

## Worker development against a local server

Start the dev server, create the handler/caller Namespaces, and create the Endpoint <!-- docs/develop/dotnet/nexus/feature-guide.mdx:53-82 -->:

```bash
temporal server start-dev
temporal operator namespace create --namespace nexus-simple-handler-namespace
temporal operator namespace create --namespace nexus-simple-caller-namespace
temporal operator nexus endpoint create \
  --name nexus-simple-endpoint \
  --target-namespace nexus-simple-handler-namespace \
  --target-task-queue nexus-simple-handler-sample
```

## See also

- `references/core/nexus.md` — cross-SDK Nexus concepts, lifecycle, timeouts, retries, circuit breaking, observability.
- .NET Nexus sample: <https://github.com/temporalio/samples-dotnet/tree/main/src/NexusSimple> <!-- docs/develop/dotnet/nexus/feature-guide.mdx:40 -->.
