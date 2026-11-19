# Go SDK Nexus

Use the [Nexus concepts](../core/nexus.md) to choose an operation and configure its Endpoint. Share the service name, operation name, input type, and result type between the caller and handler.

## Define and handle an operation

This example exposes an existing `GenerateInvoice(workflow.Context, string) (string, error)` Workflow as the `generate` operation on the `Invoices` service. The operation takes an invoice ID and returns the Workflow result.

```go
import (
	"context"

	"github.com/nexus-rpc/sdk-go/nexus"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/temporalnexus"
	"go.temporal.io/sdk/worker"
)

const invoiceService = "Invoices"
const generateInvoiceOperation = "generate"

var invoiceOperation = temporalnexus.NewWorkflowRunOperation(
	generateInvoiceOperation,
	GenerateInvoice,
	func(_ context.Context, _ string, opts nexus.StartOperationOptions) (client.StartWorkflowOptions, error) {
		return client.StartWorkflowOptions{ID: "invoice-" + opts.RequestID}, nil
	},
)

func registerInvoiceService(w worker.Worker) error {
	service := nexus.NewService(invoiceService)
	if err := service.Register(invoiceOperation); err != nil {
		return err
	}
	w.RegisterNexusService(service)
	w.RegisterWorkflow(GenerateInvoice)
	return nil
}
```

Call `registerInvoiceService` before running the handler Worker. The backing Workflow starts on the handler's Task Queue by default. The request ID stays stable across retries of the operation start, so those retries target the same Workflow ID.

## Call from a Workflow

```go
import (
	"time"

	"go.temporal.io/sdk/workflow"
)

func RequestInvoice(ctx workflow.Context, invoiceID string) (string, error) {
	invoices := workflow.NewNexusClient("invoice-service-endpoint", invoiceService)
	future := invoices.ExecuteOperation(ctx, generateInvoiceOperation, invoiceID, workflow.NexusOperationOptions{
		ScheduleToCloseTimeout: 10 * time.Minute,
	})
	var result string
	if err := future.Get(ctx, &result); err != nil {
		return "", err
	}
	return result, nil
}
```

Register `RequestInvoice` on the caller Worker. Configure `invoice-service-endpoint` to target the handler Worker's Namespace and Task Queue. In Temporal Cloud, include the caller's Namespace in the Endpoint allowlist.
