# Java SDK Nexus

Use the [Nexus concepts](../core/nexus.md) to choose an operation and configure its Endpoint. Share the service interface between the caller and handler.

## Define and handle an operation

Declare the service contract with `@Service` and mark its callable methods with `@Operation`:

```java
import io.nexusrpc.Operation;
import io.nexusrpc.Service;

@Service
public interface InvoiceService {
    @Operation
    String generate(String invoiceId);
}
```

Use `WorkflowRunOperation.fromWorkflowMethod` when the operation should start a Workflow and return its result. This example assumes an existing `GenerateInvoiceWorkflow` with a `String run(String invoiceId)` Workflow method.

```java
import io.nexusrpc.handler.OperationHandler;
import io.nexusrpc.handler.OperationImpl;
import io.nexusrpc.handler.ServiceImpl;
import io.temporal.client.WorkflowOptions;
import io.temporal.nexus.Nexus;
import io.temporal.nexus.WorkflowRunOperation;

@ServiceImpl(service = InvoiceService.class)
public class InvoiceServiceImpl {
    @OperationImpl
    public OperationHandler<String, String> generate() {
        return WorkflowRunOperation.fromWorkflowMethod((context, details, invoiceId) -> {
            var options = WorkflowOptions.newBuilder()
                .setWorkflowId("generate-invoice-" + details.getRequestId())
                .build();
            var workflow = Nexus.getOperationContext().getWorkflowClient()
                .newWorkflowStub(GenerateInvoiceWorkflow.class, options);
            return workflow::run;
        });
    }
}
```

The request ID keeps the backing Workflow ID consistent across retries of the same Nexus request. Before starting the handler Worker, register both the backing Workflow implementation and the Nexus service:

```java
handlerWorker.registerWorkflowImplementationTypes(GenerateInvoiceWorkflowImpl.class);
handlerWorker.registerNexusServiceImplementation(new InvoiceServiceImpl());
```

For an operation that reliably finishes well within 10 seconds, implement it with `OperationHandler.sync((context, details, input) -> result)`.

## Call from a Workflow

Create a typed stub inside the caller Workflow and invoke the service method. The following method body returns the operation result:

```java
import io.temporal.workflow.NexusOperationOptions;
import io.temporal.workflow.NexusServiceOptions;
import io.temporal.workflow.Workflow;
import java.time.Duration;
```

```java
var invoices = Workflow.newNexusServiceStub(
    InvoiceService.class,
    NexusServiceOptions.newBuilder()
        .setEndpoint("invoice-service-endpoint")
        .setOperationOptions(NexusOperationOptions.newBuilder()
            .setScheduleToCloseTimeout(Duration.ofMinutes(10))
            .build())
        .build());
return invoices.generate(invoiceId);
```

Configure the Endpoint to target the handler's Namespace and Task Queue. In Temporal Cloud, allow the caller's Namespace on the Endpoint.
