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
import { startWorkflow, WorkflowRunOperationHandler } from '@temporalio/nexus';
import { invoiceService } from './invoice-service';
import { generateInvoice } from './workflows';

export const invoiceHandler = serviceHandler(invoiceService, {
  generate: new WorkflowRunOperationHandler<string, string>((ctx, invoiceId) =>
    startWorkflow(ctx, generateInvoice, {
      args: [invoiceId],
      workflowId: `invoice-${ctx.requestId}`,
    }),
  ),
});
```

Register the handler with `Worker.create({ ..., nexusServices: [invoiceHandler] })`. Register the backing Workflow on the handler's Task Queue. This is the default Task Queue for `startWorkflow`, and the Workflow's return value becomes the operation result. The request ID stays stable across retries of the operation start, so those retries target the same Workflow ID.

For an operation that reliably completes well within 10 seconds, provide an async function in `serviceHandler` that returns the result directly.

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

Configure the Endpoint to target the handler's Namespace and Task Queue. In Temporal Cloud, include the caller's Namespace in the Endpoint allowlist.
