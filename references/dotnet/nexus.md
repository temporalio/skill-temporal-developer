# .NET SDK Nexus

Use the [Nexus concepts](../core/nexus.md) to choose an operation and configure its Endpoint. Share the service interface between the caller and handler.

## Define and handle an operation

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
    [TemporalOperation]
    public Task<TemporalOperationResult<string>> Generate(
        TemporalOperationStartContext context,
        ITemporalNexusClient client,
        string invoiceId) =>
        client.StartWorkflowAsync(
            (GenerateInvoiceWorkflow workflow) => workflow.RunAsync(invoiceId),
            new() { Id = $"invoice-{invoiceId}" });
}
```

Register the handler with `TemporalWorkerOptions.AddNexusService(new InvoiceService())`. Register the backing Workflow with `AddWorkflow<GenerateInvoiceWorkflow>()` on the handler Task Queue. By default, the Workflow runs on that Task Queue. Its return value becomes the operation result. Use a Workflow ID that identifies the business operation so retried starts target the same execution.

For an operation that reliably completes well within 10 seconds, return `TemporalOperationResult<string>.SyncResult(result)` from the handler. Use `client.TemporalClient` to get a handle when you need to query or signal an existing Workflow.

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

The Endpoint must target the handler's Namespace and Task Queue and allow the caller's Namespace.
