# TypeScript SDK Error Handling

## Overview

The TypeScript SDK uses `ApplicationFailure` for application errors with support for non-retryable marking.

## Application Failures

```typescript
import { ApplicationFailure } from '@temporalio/workflow';

export async function myWorkflow(): Promise<void> {
  throw ApplicationFailure.create({
    message: 'Invalid input',
    type: 'ValidationError',
    nonRetryable: true,
  });
}
```

## Activity Errors

```typescript
import { ApplicationFailure } from '@temporalio/activity';

export async function validateActivity(input: string): Promise<void> {
  if (!isValid(input)) {
    throw ApplicationFailure.create({
      message: `Invalid input: ${input}`,
      type: 'ValidationError',
      nonRetryable: true,
    });
  }
}
```

## Handling Errors in Workflows

```typescript
import { proxyActivities, ApplicationFailure } from '@temporalio/workflow';
import type * as activities from './activities';

const { riskyActivity } = proxyActivities<typeof activities>({
  startToCloseTimeout: '5 minutes',
});

export async function workflowWithErrorHandling(): Promise<string> {
  try {
    return await riskyActivity();
  } catch (err) {
    if (err instanceof ApplicationFailure) {
      console.log(`Activity failed: ${err.type} - ${err.message}`);
    }
    throw err;
  }
}
```

## Retry Configuration

```typescript
const { myActivity } = proxyActivities<typeof activities>({
  startToCloseTimeout: '10 minutes',
  retry: {
    initialInterval: '1s',
    backoffCoefficient: 2,
    maximumInterval: '1m',
    maximumAttempts: 5,
    nonRetryableErrorTypes: ['ValidationError', 'PaymentError'],
  },
});
```

## Timeout Configuration

```typescript
const { myActivity } = proxyActivities<typeof activities>({
  startToCloseTimeout: '5 minutes',      // Single attempt
  scheduleToCloseTimeout: '30 minutes',  // Including retries
  heartbeatTimeout: '30 seconds',        // Between heartbeats
});
```

## Cancellation Handling in Activities

```typescript
import { CancelledFailure, heartbeat } from '@temporalio/activity';

export async function cancellableActivity(): Promise<void> {
  try {
    while (true) {
      heartbeat();
      await doWork();
    }
  } catch (err) {
    if (err instanceof CancelledFailure) {
      await cleanup();
    }
    throw err;
  }
}
```

## Idempotency Patterns

Activities may be executed more than once due to retries. Design activities to be idempotent to prevent duplicate side effects.

### Why Activities Need Idempotency

Consider this scenario:
1. Worker polls and accepts an Activity Task
2. Activity function completes successfully
3. Worker crashes before notifying the Cluster
4. Cluster retries the Activity (doesn't know it completed)

If the Activity charged a credit card, the customer would be charged twice.

### Using Idempotency Keys

Use the Workflow Run ID + Activity ID as an idempotency key - this is constant across retries but unique across workflow executions:

```typescript
import { info } from '@temporalio/activity';

export async function chargePayment(
  customerId: string,
  amount: number
): Promise<string> {
  // Create idempotency key from workflow context
  const idempotencyKey = `${info().workflowRunId}-${info().activityId}`;

  // Pass to external service (e.g., Stripe, payment processor)
  const result = await paymentService.charge({
    customerId,
    amount,
    idempotencyKey,  // Service ignores duplicate requests with same key
  });

  return result.transactionId;
}
```

**Important**: Use `workflowRunId` (not `workflowId`) because workflow IDs can be reused.

### Granular Activities

Make activities more granular to reduce the scope of potential retries:

```typescript
// BETTER - Three small activities
export async function lookupCustomer(customerId: string): Promise<Customer> {
  return await db.findCustomer(customerId);
}

export async function processPayment(paymentInfo: PaymentInfo): Promise<string> {
  const idempotencyKey = `${info().workflowRunId}-${info().activityId}`;
  return await paymentService.process(paymentInfo, idempotencyKey);
}

export async function sendReceipt(transactionId: string): Promise<void> {
  await emailService.sendReceipt(transactionId);
}

// WORSE - One large activity doing multiple things
export async function processOrder(order: Order): Promise<void> {
  const customer = await db.findCustomer(order.customerId);
  await paymentService.process(order.payment);  // If this fails here...
  await emailService.sendReceipt(order.id);     // ...all three retry
}
```

## Best Practices

1. Use specific error types for different failure modes
2. Set `nonRetryable: true` for permanent failures
3. Configure `nonRetryableErrorTypes` in retry policy
4. Handle `CancelledFailure` in activities that need cleanup
5. Always re-throw errors after handling
6. Use idempotency keys for activities with external side effects
7. Make activities granular to minimize retry scope
