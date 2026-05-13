# Nexus — .NET SDK

This reference covers the .NET SDK programming model for Nexus. For cross-cutting concepts (lifecycle semantics, timeout meanings, retry behavior, circuit breaking, cancellation vs termination, deployment patterns, security, debugging, metrics) see `references/core/nexus.md`.

## Support status

Temporal .NET SDK support for Nexus is in **Public Preview** — it is **not** GA.

Recommended baseline versions from the feature-guide prereqs:

- Temporal CLI v1.3.0 or higher
- Temporal .NET SDK v1.9.0 or higher

The two namespaces that contain .NET Nexus APIs are `NexusRpc` / `NexusRpc.Handlers` (contract + handler primitives) and `Temporalio.Nexus` (Temporal-backed handlers and context).

## Defining the Service contract

The Service contract is a C# **interface** decorated with the `[NexusService]` attribute. Each operation is a method on the interface decorated with `[NexusOperation]`. Inputs and outputs are typically inner `record` types, and inner `enum` types are allowed. A `static readonly string EndpointName` constant lives on the interface so caller and handler share a single source of truth for the Endpoint name.

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

A Nexus Operation has exactly **one input parameter**. To pass multiple workflow arguments through, model the input as a record and unpack it inside the handler.

## Handler basics

A handler is a plain class annotated with `[NexusServiceHandler(typeof(IHelloService))]`. Each handler method is annotated with `[NexusOperationHandler]` and returns an `IOperationHandler<TIn, TOut>`.

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

The handler method itself is a factory: it is called once at registration time and returns the `IOperationHandler` value that processes incoming operation requests.

## Synchronous Operation handler

`OperationHandler.Sync<TIn, TOut>((ctx, input) => ...)` produces a synchronous handler that returns its result inline.  Sync handlers must finish within the Nexus request deadline (10 seconds) — see the core reference for the precise meaning of this deadline.

## Using the Temporal Client from a sync handler

A common pattern is to drive Signals, Queries, and Updates from a sync handler. `NexusOperationExecutionContext.Current.TemporalClient` returns the `ITemporalClient` the Worker was initialized with.

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

Use `client.GetWorkflowHandle<TWorkflow>(workflowId)` to obtain a typed workflow handle, then `QueryAsync`, `SignalAsync`, `ExecuteUpdateAsync`, or Signal-With-Start / Update-With-Start to interact with the Workflow. All work driven from a sync handler must complete inside the request deadline.

## Asynchronous Workflow-Run Operation

To back an Operation by a long-running Workflow, return a `WorkflowRunOperationHandler.FromHandleFactory(...)` instead of a sync handler. The factory receives a `WorkflowRunOperationContext` and the deserialized input, and must call `context.StartWorkflowAsync(...)`.

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

`context.HandlerContext.RequestId` is the Temporal-allocated request ID that is stable across retries of this operation, which makes it a safe deduplication key for the Workflow ID.  For production use, a business-meaningful Workflow ID is preferred — pass it through on the Service contract input.

## Multiple Workflow arguments

A Nexus Operation accepts a single input parameter, but the started Workflow can take any number of arguments. Unpack the record inside the call to `RunAsync`:

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

## Registering with a Worker

Register the handler instance via `AddNexusService` on `TemporalWorkerOptions`. The handler Worker also registers the Workflow type it will run.

```csharp
using var worker = new TemporalWorker(
    await ConnectClientAsync("nexus-simple-handler-namespace"),
    new TemporalWorkerOptions(taskQueue: "nexus-simple-handler-sample")
        .AddNexusService(new HelloService())
        .AddWorkflow<HelloHandlerWorkflow>());

await worker.ExecuteAsync(tokenSource.Token);
```

Like `AddActivity`, `AddNexusService` takes a concrete instance — the Worker dispatches incoming Nexus tasks to that object. A Worker only handles Nexus traffic for services it has registered.

The caller Worker registers only the caller Workflows; it does not need the handler class.

```csharp
using var worker = new TemporalWorker(
    await ConnectClientAsync("nexus-simple-caller-namespace"),
    new TemporalWorkerOptions(taskQueue: "nexus-simple-caller-sample")
        .AddWorkflow<EchoCallerWorkflow>()
        .AddWorkflow<HelloCallerWorkflow>());

await worker.ExecuteAsync(tokenSource.Token);
```

## Caller Workflow

From inside a Workflow, build a typed Nexus client with `Workflow.CreateNexusWorkflowClient<TService>(endpointName)` and invoke an operation through `ExecuteNexusOperationAsync`.

```csharp
using Temporalio.Workflows;

[Workflow]
public class HelloCallerWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(string name, IHelloService.HelloLanguage language)
    {
        var output = await Workflow
            .CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName)
            .ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)));
        return output.Message;
    }
}
```

Pass `NexusWorkflowOperationOptions` as a second argument to `ExecuteNexusOperationAsync` when you need to configure timeouts or the cancellation type:

```csharp
var output = await Workflow
    .CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName)
    .ExecuteNexusOperationAsync(
        svc => svc.SayHello(new(name, language)),
        new NexusWorkflowOperationOptions
        {
            ScheduleToCloseTimeout = TimeSpan.FromMinutes(10),
        });
```

The caller depends only on the Service interface, not on the handler class — that is what allows the two sides to live in separate Namespaces or even separate codebases.

## Setting timeouts

Set timeouts via `NexusWorkflowOperationOptions` when calling `ExecuteNexusOperationAsync`.  See `references/core/nexus.md` for what each timeout means and when to use it.

**Schedule-to-Close** — total wall-clock budget for the operation:

```csharp
new NexusWorkflowOperationOptions
{
    ScheduleToCloseTimeout = TimeSpan.FromMinutes(10),
}
```

**Schedule-to-Start** — how long the caller will wait for the handler to start the operation. If not set, no Schedule-to-Start timeout is enforced.

```csharp
new NexusWorkflowOperationOptions
{
    ScheduleToStartTimeout = TimeSpan.FromMinutes(2),
}
```

**Start-to-Close** — how long an already-started **asynchronous** operation has to complete. Applies only to asynchronous operations. If not set, no Start-to-Close timeout is enforced.

```csharp
new NexusWorkflowOperationOptions
{
    StartToCloseTimeout = TimeSpan.FromMinutes(5),
}
```

## Cancellation

To cancel a Nexus Operation from a caller Workflow, cancel the cancellation token passed to the operation call. Only **asynchronous** operations can be canceled — cancellation is delivered using an operation token, which sync operations do not produce. The Workflow or other resource backing the operation may choose to ignore the request; if ignored, the operation may still reach a terminal state.

The cancellation type controls how the caller reacts after issuing the cancel. .NET uses **Pascal-case** names (note: `WaitCancellationRequested` and `WaitCancellationCompleted`, with the `Cancellation` substring in the middle):

- `Abandon` — Do not request cancellation of the operation.
- `TryCancel` — Initiate a cancellation request and immediately report cancellation to the caller. Does not guarantee delivery to the handler if the caller exits first.
- `WaitCancellationRequested` — Request cancellation and wait for confirmation that the request was received. Does not wait for actual cancellation.
- `WaitCancellationCompleted` — Wait for operation completion. The operation may or may not complete as canceled.

The default is `WaitCancellationCompleted`. Override it via `CancellationType` on `NexusWorkflowOperationOptions`.

```csharp
var output = await Workflow
    .CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName)
    .ExecuteNexusOperationAsync(
        svc => svc.SayHello(new(name, language)),
        new NexusWorkflowOperationOptions
        {
            CancellationType = NexusOperationCancellationType.TryCancel, // <!-- VERIFY: exact enum type name for CancellationType property (feature guide names the values but not the enclosing enum) -->
        });
```

Once the caller Workflow completes, the caller's Nexus machinery makes no further cancellation attempts on still-running operations. To guarantee cancellation delivery, await all pending operations before letting the Workflow exit.

## Quick recipe pointer

End-to-end flow against a local dev server:

1. `temporal server start-dev` — start the dev server with Nexus enabled.
2. `temporal operator namespace create --namespace nexus-simple-handler-namespace`
3. `temporal operator namespace create --namespace nexus-simple-caller-namespace`
4. ```
   temporal operator nexus endpoint create \
     --name nexus-simple-endpoint \
     --target-namespace nexus-simple-handler-namespace \
     --target-task-queue nexus-simple-handler-sample
   ```
5. `dotnet run handler-worker` — run the handler Worker.
6. `dotnet run caller-worker` — run the caller Worker in a second terminal.
7. `dotnet run caller-workflow` — start the caller Workflow.

The full Cloud setup (mTLS cert generation, `tcld namespace create`, `tcld nexus endpoint create`) is in the feature guide.

## Cross-Namespace in Temporal Cloud

In Temporal Cloud the Nexus Endpoint is created with `tcld nexus endpoint create`. The `--allow-namespace` flag builds the allowlist of caller Namespaces permitted to use the Endpoint, as described in Runtime Access Control.

```
tcld nexus endpoint create \
  --name nexus-simple-endpoint \
  --target-task-queue nexus-simple-handler-sample \
  --target-namespace <your-handler-namespace.account> \
  --allow-namespace <your-caller-namespace.account> \
  --description-file endpoint_description.md
```

Creating the Endpoint requires the Developer account role or higher and NamespaceAdmin permission on the `--target-namespace`. See `references/core/nexus.md` for the security model and the full feature guide for the mTLS bootstrap details.
