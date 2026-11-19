# .NET SDK Nexus

Use the [Nexus concepts](../core/nexus.md) to choose an operation and configure its Endpoint. Share the service interface between the caller and handler.

## Define and handle an operation

Use a Workflow-backed operation when the handler should start a Workflow and return its result. This example assumes `GenerateInvoiceWorkflow` has a `Task<string> RunAsync(string invoiceId)` Workflow Run method.

```csharp
using NexusRpc;
using NexusRpc.Handlers;
using Temporalio.Nexus;

[NexusService]
public interface IInvoiceService
{
    [NexusOperation]
    string Generate(string invoiceId);
}

[NexusServiceHandler(typeof(IInvoiceService))]
public class InvoiceService
{
    [NexusOperationHandler]
    public IOperationHandler<string, string> Generate() =>
        WorkflowRunOperationHandler.FromHandleFactory(
            (WorkflowRunOperationContext context, string invoiceId) =>
                context.StartWorkflowAsync(
                    (GenerateInvoiceWorkflow workflow) => workflow.RunAsync(invoiceId),
                    new() { Id = $"generate-invoice-{context.HandlerContext.RequestId}" }));
}
```

Deriving the Workflow ID from the Nexus request ID keeps it stable across retries of that request. Register the handler with `TemporalWorkerOptions.AddNexusService(new InvoiceService())` and the backing Workflow with `AddWorkflow<GenerateInvoiceWorkflow>()` on the handler Task Queue. The backing Workflow runs on that queue by default.

For an operation that reliably finishes well within the 10-second handler deadline, use `OperationHandler.Sync<TInput, TResult>`.

## Call from a Workflow

```csharp
using Temporalio.Workflows;

[Workflow]
public class RequestInvoiceWorkflow
{
    [WorkflowRun]
    public Task<string> RunAsync(string invoiceId)
    {
        var invoices = Workflow.CreateNexusWorkflowClient<IInvoiceService>(
            "invoice-service-endpoint");
        return invoices.ExecuteNexusOperationAsync(
            svc => svc.Generate(invoiceId),
            new() { ScheduleToCloseTimeout = TimeSpan.FromMinutes(10) });
    }
}
```

Configure the Endpoint to target the handler's Namespace and Task Queue. In Temporal Cloud, allow the caller's Namespace on the Endpoint.
