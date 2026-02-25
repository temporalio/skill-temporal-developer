# TypeScript SDK Observability

## Overview

The TypeScript SDK provides replay-aware logging, metrics, and OpenTelemetry integration for production observability.

## Replay-Aware Logging

Temporal's logger automatically suppresses duplicate messages during replay, preventing log spam when workflows recover state.

### Workflow Logging

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

### Activity Logging

```typescript
import * as activity from '@temporalio/activity';

export async function processPayment(orderId: string): Promise<string> {
  const context = activity.Context.current();
  context.log.info('Processing payment', { orderId });

  // Activity logs don't need replay suppression
  // since completed activities aren't re-executed
  return 'payment-id-123';
}
```

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

### OTLP Metrics

```typescript
Runtime.install({
  telemetryOptions: {
    metrics: {
      otel: {
        url: 'http://127.0.0.1:4317',
        metricsExportInterval: '1s',
      },
    },
  },
});
```

## Best Practices

1. Use `log` from `@temporalio/workflow` - never `console.log` in workflows
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Enable OpenTelemetry for distributed tracing across services
5. Monitor Prometheus metrics for worker health
6. Use Event History for debugging workflow issues
