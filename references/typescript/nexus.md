# TypeScript SDK Nexus

Use the [Nexus concepts](../core/nexus.md) to choose an operation and configure its Endpoint. Share the service contract between the caller and handler.

## Define and handle an operation

Declare the contract in a module usable from Workflow code:

```typescript
import { operation, service } from 'nexus-rpc';

export const invoiceService = service('Invoices', {
  generate: operation<string, string>(),
});
```

Connect the contract to its implementation on the handler Worker:

```typescript
import { serviceHandler } from 'nexus-rpc';
import { TemporalOperationHandler } from '@temporalio/nexus';
import { invoiceService } from './invoice-service';
import { generateInvoice } from './workflows';

export const invoiceHandler = serviceHandler(invoiceService, {
  generate: new TemporalOperationHandler<string, string>({
    start: (_ctx, client, invoiceId) =>
      client.startWorkflow(generateInvoice, {
        args: [invoiceId],
        workflowId: `invoice-${invoiceId}`,
      }),
  }),
});
```

Register the handler with `Worker.create({ ..., nexusServices: [invoiceHandler] })`. Register the backing Workflow on the handler Task Queue, which is the default Task Queue for `startWorkflow`. Its return value becomes the operation result. Use a Workflow ID that identifies the business operation so retried starts target the same execution.

For an operation that reliably completes well within 10 seconds, return `TemporalOperationResult.sync(result)` from `start`. To query or signal an existing Workflow, use `client.client.workflow.getHandle(workflowId)` in the handler.

## Call from a Workflow

```typescript
import { createNexusServiceClient } from '@temporalio/workflow';
import { invoiceService } from './invoice-service';

export async function requestInvoice(invoiceId: string): Promise<string> {
  const invoices = createNexusServiceClient({
    service: invoiceService,
    endpoint: 'invoice-service-endpoint',
  });
  return invoices.executeOperation('generate', invoiceId, {
    scheduleToCloseTimeout: '10m',
  });
}
```

The Endpoint must target the handler's Namespace and Task Queue and allow the caller's Namespace.
