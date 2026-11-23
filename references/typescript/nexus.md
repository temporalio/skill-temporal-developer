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

## Signal-with-start and Updates from a handler

To signal a Workflow and start it first if it is not running, call `signalWithStartWorkflow(ctx, workflowTypeOrFunc, options)` from `@temporalio/nexus`. `ctx` is the operation's start context. The options match the client's signal-with-start options (`args`, `workflowId`, `signal`, `signalArgs`, ...), except `taskQueue` is optional and defaults to the handling Worker's Task Queue.

Inside a `TemporalOperationHandler`, use the provided client:

```typescript
import * as temporalNexus from '@temporalio/nexus';

attachContext: new temporalNexus.TemporalOperationHandler({
  async start(_ctx, client, input: AttachInput) {
    await client.signalWithStartWorkflow(sessionWorkflow, {
      args: [],
      workflowId: `session-${input.userId}`,
      signal: attachSignal,
      signalArgs: [input],
    });
    return temporalNexus.TemporalOperationResult.sync(undefined);
  },
}),
```

For a Workflow Update from a Nexus handler, always pass an options object with `waitForStage: 'ACCEPTED'`. It is required and `ACCEPTED` is the only allowed stage, even for an Update with no arguments. Add `args` when the Update takes arguments:

```typescript
const handle = client.getWorkflowHandle(`session-${input.userId}`);
return await handle.update(setLanguageUpdate, { args: [input.language], waitForStage: 'ACCEPTED' });
```

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
