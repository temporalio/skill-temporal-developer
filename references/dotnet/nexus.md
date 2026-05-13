# Temporal Nexus — .NET SDK

> See `references/core/nexus.md` for cross-SDK concepts (lifecycle, retries, circuit breaker, timeout semantics, cancellation semantics, observability events). This file documents .NET (C#) SDK identifiers only.

**Support stage: Public Preview** (not GA). <!-- docs/develop/dotnet/nexus/feature-guide.mdx:21 -->

Recommended versions: Temporal CLI v1.3.0+, Temporal .NET SDK v1.9.0+. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:48-49 -->

## Namespaces

- `NexusRpc` — `[NexusService]`, `[NexusOperation]` attributes for interface definitions. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:99-110 -->
- `NexusRpc.Handlers` — `[NexusServiceHandler(typeof(...))]`, `[NexusOperationHandler]`, `OperationHandler.Sync<,>`, `IOperationHandler<,>`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:154-163 -->
- `Temporalio.Nexus` — `WorkflowRunOperationHandler.FromHandleFactory`, `WorkflowRunOperationContext`, `NexusOperationExecutionContext.Current.TemporalClient`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:138-142 -->
- `Temporalio.Workflows` — `Workflow.CreateNexusWorkflowClient<IInterface>(endpointName)`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:296-304 -->

## Define a Service contract

Apply `[NexusService]` to an interface and `[NexusOperation]` to each operation method. Nested records/enums define input/output payload shapes. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:99-128 -->

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

The default data converter encodes payloads as Null, Byte array, Protobuf JSON, then JSON; .NET classes are serialized to JSON. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:92-95 -->

## Develop operation handlers

A handler class is marked with `[NexusServiceHandler(typeof(IInterface))]`. Each method returning `IOperationHandler<TInput, TOutput>` is annotated with `[NexusOperationHandler]`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:156-167 -->

### Synchronous operation

Use `OperationHandler.Sync<TInput, TOutput>` for simple RPC-style handlers. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:148-163 -->

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

Inside a sync handler, get the Worker's Temporal Client via `NexusOperationExecutionContext.Current.TemporalClient` for Signals, Queries, Updates, Signal-With-Start, or Update-With-Start. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:140-141 --> <!-- docs/develop/dotnet/nexus/feature-guide.mdx:169-194 -->

```csharp
var client = NexusOperationExecutionContext.Current.TemporalClient;
var handle = client.GetWorkflowHandle<GreetingWorkflow>(WorkflowIdForUser(input.UserId));
return await handle.QueryAsync(wf => wf.QueryLanguages(input.IncludeUnsupported));
```
<!-- docs/develop/dotnet/nexus/feature-guide.mdx:191-193 -->

Sync handlers must complete within the Nexus request timeout (see `references/core/nexus.md`). <!-- docs/develop/dotnet/nexus/feature-guide.mdx:173 -->

### Asynchronous workflow-run operation

Use `WorkflowRunOperationHandler.FromHandleFactory` to expose a Workflow as the backing async operation. The factory receives a `WorkflowRunOperationContext` and the operation input, and returns the start handle from `context.StartWorkflowAsync(...)`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:203-228 -->

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

`context.HandlerContext.RequestId` is the request ID allocated by Temporal when the caller Workflow scheduled the operation; it is guaranteed to be stable across retries, making it a safe default workflow ID. In general, prefer a business-meaningful ID passed through the operation input. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:223-231 -->

### Map a Nexus operation input to multiple Workflow arguments

A Nexus Operation takes a single input parameter; to start a Workflow with multiple positional arguments, pass them to `RunAsync` inside the `StartWorkflowAsync` lambda. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:239-262 -->

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

## Register a Nexus Service in a Worker

Use `TemporalWorkerOptions.AddNexusService(...)` alongside `AddWorkflow<T>()`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:269-288 -->

```csharp
using var worker = new TemporalWorker(
    await ConnectClientAsync("nexus-simple-handler-namespace"),
    new TemporalWorkerOptions(taskQueue: "nexus-simple-handler-sample").
        AddNexusService(new HelloService()).
        AddWorkflow<HelloHandlerWorkflow>());
```

## Caller-side: invoke an operation

From inside a Workflow, build a typed proxy with `Workflow.CreateNexusWorkflowClient<IInterface>(endpointName)` and call the operation via `ExecuteNexusOperationAsync(svc => svc.Op(...))`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:294-309 -->

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

```csharp
[Workflow]
public class HelloCallerWorkflow
{
    [WorkflowRun]
    public async Task<string> RunAsync(string name, IHelloService.HelloLanguage language)
    {
        var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
            ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)));
        return output.Message;
    }
}
```
<!-- docs/develop/dotnet/nexus/feature-guide.mdx:311-326 -->

## Timeouts

Set Nexus operation timeouts via `NexusWorkflowOperationOptions` passed as the second argument to `ExecuteNexusOperationAsync`. All three properties are `TimeSpan`. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:330-371 -->

- `ScheduleToCloseTimeout` — total duration from schedule to completion; the Nexus Machinery retries failed requests until this fires. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:335-344 -->
- `ScheduleToStartTimeout` — how long the caller waits for the operation to be started by the handler; not enforced if unset. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:348-357 -->
- `StartToCloseTimeout` — how long the caller waits for an async operation to complete after start; applies only to async operations; not enforced if unset. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:361-371 -->

```csharp
var output = await Workflow.CreateNexusWorkflowClient<IHelloService>(IHelloService.EndpointName).
    ExecuteNexusOperationAsync(svc => svc.SayHello(new(name, language)), new NexusWorkflowOperationOptions
    {
        ScheduleToCloseTimeout = TimeSpan.FromMinutes(10),
    });
```

## Cancellation

To cancel a Nexus Operation from within a caller Workflow, cancel the cancellation token passed to the operation call. Only asynchronous operations can be canceled in Nexus, since cancellation is delivered using an operation token. The handler may choose to ignore the cancellation request. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:453-456 -->

Set the cancellation type via `CancellationType` on `NexusWorkflowOperationOptions`: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:465 -->

- `Abandon` — do not request cancellation of the operation. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:460 -->
- `TryCancel` — initiate a cancellation request and immediately report cancellation to the caller; delivery to the handler is not guaranteed if the caller exits before delivery completes. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:461 -->
- `WaitCancellationRequested` — request cancellation and wait for confirmation the request was received; does not wait for actual cancellation. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:462 -->
- `WaitCancellationCompleted` (default) — wait for operation completion; the operation may or may not complete as cancelled. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:463-465 -->

Once the caller Workflow completes, the caller's Nexus Machinery makes no further cancellation attempts on operations still running. To ensure delivery, await all pending operations before exiting the Workflow. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:467-469 -->

## CLI setup

Create the routing Nexus Endpoint:

```
temporal operator nexus endpoint create \
  --name nexus-simple-endpoint \
  --target-namespace nexus-simple-handler-namespace \
  --target-task-queue nexus-simple-handler-sample
```
<!-- docs/develop/dotnet/nexus/feature-guide.mdx:78-82 -->

Create caller/handler Namespaces beforehand: <!-- docs/develop/dotnet/nexus/feature-guide.mdx:66-67 -->

```
temporal operator namespace create --namespace nexus-simple-handler-namespace
temporal operator namespace create --namespace nexus-simple-caller-namespace
```

For Temporal Cloud, use `tcld nexus endpoint create` with `--allow-namespace` to allowlist caller Namespaces. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:521-530 -->

## Samples

- [NexusSimple](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusSimple) — sync `Echo` and async `SayHello` operations. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:40 -->
- [NexusMessaging](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusMessaging) — caller-pattern and on-demand-pattern Signals/Queries/Updates through Nexus. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:175 --> <!-- docs/develop/dotnet/nexus/feature-guide.mdx:198 -->
- [NexusMultiArg](https://github.com/temporalio/samples-dotnet/blob/main/src/NexusMultiArg/Handler/HelloService.cs) — operation input mapped to multiple Workflow arguments. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:243 -->
- [NexusCancellation](https://github.com/temporalio/samples-dotnet/tree/main/src/NexusCancellation) — cancellation patterns. <!-- docs/develop/dotnet/nexus/feature-guide.mdx:471 -->
