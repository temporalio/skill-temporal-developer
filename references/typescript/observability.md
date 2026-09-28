# TypeScript SDK Observability

## Overview

The TypeScript SDK provides replay-aware logging, metrics, distributed tracing (OpenTelemetry), and visibility (Search Attributes) for production observability.

These pillars are complementary: **logging** (below) captures discrete events, **metrics** capture aggregate worker health, **tracing** stitches a single request across Client/Workflow/Activity/Nexus boundaries, and **Search Attributes** make executions queryable.

## Replay-Aware Logging

Temporal's logger automatically suppresses duplicate messages during replay, preventing log spam when workflows recover state.

### Workflow Logging

Workflows run in a sandboxed environment and cannot use regular Node.js loggers directly. Since SDK 1.8.0, the `@temporalio/workflow` package exports a `log` object that provides replay-aware logging. Internally, it uses Sinks to funnel messages to the Runtime's logger.

```typescript
import { log } from '@temporalio/workflow';

export async function orderWorkflow(orderId: string): Promise<string> {
  log.info('Processing order', { orderId });

  const result = await processPayment(orderId);
  log.debug('Payment processed', { orderId, result });

  return result;
}
```

**Log levels**: `log.debug()`, `log.info()`, `log.warn()`, `log.error()`

The workflow logger automatically suppresses duplicate messages during replay and includes workflow context metadata (workflowId, runId, etc.) on every log entry.

### Activity Logging

```typescript
import { log } from '@temporalio/activity';

export async function processPayment(orderId: string): Promise<string> {
  log.info('Processing payment', { orderId });
  return 'payment-id-123';
}
```

The activity logger adds contextual metadata (activity ID, type, namespace) and funnels messages to the runtime's logger for consistent collection.

## Customizing the Logger

### Basic Configuration

```typescript
import { DefaultLogger, Runtime } from '@temporalio/worker';

const logger = new DefaultLogger('DEBUG', ({ level, message }) => {
  console.log(`Custom logger: ${level} - ${message}`);
});
Runtime.install({ logger });
```

### Winston Integration

```typescript
import winston from 'winston';
import { DefaultLogger, Runtime } from '@temporalio/worker';

const winstonLogger = winston.createLogger({
  level: 'debug',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'temporal.log' })
  ],
});

const logger = new DefaultLogger('DEBUG', (entry) => {
  winstonLogger.log({
    label: entry.meta?.activityId ? 'activity' : entry.meta?.workflowId ? 'workflow' : 'worker',
    level: entry.level.toLowerCase(),
    message: entry.message,
    timestamp: Number(entry.timestampNanos / 1_000_000n),
    ...entry.meta,
  });
});

Runtime.install({ logger });
```

## Metrics

### Prometheus Metrics

```typescript
import { Runtime } from '@temporalio/worker';

Runtime.install({
  telemetryOptions: {
    metrics: {
      prometheus: {
        bindAddress: '127.0.0.1:9091',
      },
    },
  },
});
```

## Distributed Tracing (OpenTelemetry)

See [OpenTelemetry TypeScript integration guide](integrations/opentelemetry.md).

## Search Attributes (Visibility)

Custom searchable fields for workflow visibility.

### Setting Search Attributes at Start

```typescript
import { Client } from '@temporalio/client';
import { defineSearchAttributeKey, SearchAttributeType } from '@temporalio/common';

const client = new Client();

const ORDER_ID = defineSearchAttributeKey('OrderId', SearchAttributeType.KEYWORD);
const CUSTOMER_TYPE = defineSearchAttributeKey('CustomerType', SearchAttributeType.KEYWORD);
const ORDER_TOTAL = defineSearchAttributeKey('OrderTotal', SearchAttributeType.DOUBLE);
const CREATED_AT = defineSearchAttributeKey('CreatedAt', SearchAttributeType.DATETIME);

await client.workflow.start('orderWorkflow', {
  taskQueue: 'orders',
  workflowId: `order-${orderId}`,
  args: [order],
  typedSearchAttributes: [
    { key: ORDER_ID, value: orderId },
    { key: CUSTOMER_TYPE, value: 'premium' },
    { key: ORDER_TOTAL, value: 99.99 },
    { key: CREATED_AT, value: new Date() },
  ],
});
```

### Upserting Search Attributes from Workflow

```typescript
import { defineSearchAttributeKey, SearchAttributeType } from '@temporalio/common';
import { upsertSearchAttributes } from '@temporalio/workflow';

const ORDER_STATUS = defineSearchAttributeKey('OrderStatus', SearchAttributeType.KEYWORD);

export async function orderWorkflow(order: Order): Promise<string> {
  // Update status as workflow progresses
  upsertSearchAttributes([{ key: ORDER_STATUS, value: 'processing' }]);

  await processOrder(order);

  upsertSearchAttributes([{ key: ORDER_STATUS, value: 'completed' }]);

  return 'done';
}
```

### Reading Search Attributes

```typescript
import { defineSearchAttributeKey, SearchAttributeType } from '@temporalio/common';
import { workflowInfo } from '@temporalio/workflow';

const ORDER_ID = defineSearchAttributeKey('OrderId', SearchAttributeType.KEYWORD);

export async function orderWorkflow(): Promise<void> {
  const info = workflowInfo();
  const orderId = info.typedSearchAttributes.get(ORDER_ID);
  // ...
}
```

### Querying Workflows by Search Attributes

```typescript
const client = new Client();

// List workflows using search attributes
for await (const workflow of client.workflow.list({
  query: 'OrderStatus = "processing" AND CustomerType = "premium"',
})) {
  console.log(`Workflow ${workflow.workflowId} is still processing`);
}
```

## Best Practices

1. Use `log` from `@temporalio/workflow` for production observability. For temporary print debugging, `console.log()` is fine—it's direct and immediate, whereas `log` goes through sinks which may lose messages on workflow errors
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Monitor Prometheus metrics for worker health
5. Use Event History for debugging workflow issues
6. Use Search Attributes for business-level visibility and filtering
7. Use the `OpenTelemetryPlugin` for distributed tracing across Client/Workflow/Activity/Nexus boundaries.
