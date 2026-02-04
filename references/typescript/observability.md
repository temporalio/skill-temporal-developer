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

## OpenTelemetry Integration

The `@temporalio/interceptors-opentelemetry` package provides tracing for workflows and activities.

### Setup

```typescript
// instrumentation.ts - require before other imports
import { NodeSDK } from '@opentelemetry/sdk-node';
import { ConsoleSpanExporter } from '@opentelemetry/sdk-trace-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { Resource } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

export const resource = new Resource({
  [ATTR_SERVICE_NAME]: 'my-temporal-service',
});

// Use OTLP exporter for production
export const traceExporter = new OTLPTraceExporter({
  url: 'http://127.0.0.1:4317',
  timeoutMillis: 1000,
});

export const otelSdk = new NodeSDK({
  resource,
  traceExporter,
});

otelSdk.start();
```

### Worker Configuration

```typescript
import { Worker } from '@temporalio/worker';
import {
  OpenTelemetryActivityInboundInterceptor,
  OpenTelemetryActivityOutboundInterceptor,
  makeWorkflowExporter,
} from '@temporalio/interceptors-opentelemetry/lib/worker';
import { resource, traceExporter } from './instrumentation';
import * as activities from './activities';

const worker = await Worker.create({
  workflowsPath: require.resolve('./workflows'),
  activities,
  taskQueue: 'my-queue',

  // OpenTelemetry sinks and interceptors
  sinks: {
    exporter: makeWorkflowExporter(traceExporter, resource),
  },
  interceptors: {
    workflowModules: [require.resolve('./workflows')],
    activity: [
      (ctx) => ({
        inbound: new OpenTelemetryActivityInboundInterceptor(ctx),
        outbound: new OpenTelemetryActivityOutboundInterceptor(ctx),
      }),
    ],
  },
});
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

## Debugging with Event History

### Viewing Event History

Use the Temporal CLI or Web UI to inspect workflow execution history:

```bash
# CLI
temporal workflow show --workflow-id my-workflow

# Get history as JSON
temporal workflow show --workflow-id my-workflow --output json
```

### Key Events to Look For

| Event | Indicates |
|-------|-----------|
| `ActivityTaskScheduled` | Activity was requested |
| `ActivityTaskStarted` | Worker started executing activity |
| `ActivityTaskCompleted` | Activity completed successfully |
| `ActivityTaskFailed` | Activity threw an error |
| `ActivityTaskTimedOut` | Activity exceeded timeout |
| `TimerStarted` | `sleep()` called |
| `TimerFired` | Sleep completed |
| `WorkflowTaskFailed` | Non-deterministic error or workflow bug |

### Debugging Non-Determinism

If you see `WorkflowTaskFailed` with a non-determinism error:

1. Export the history: `temporal workflow show -w <id> -o json > history.json`
2. Run replay test to reproduce:

```typescript
import { Worker } from '@temporalio/worker';

await Worker.runReplayHistory(
  { workflowsPath: require.resolve('./workflows') },
  history
);
```

## Best Practices

1. Use `log` from `@temporalio/workflow` - never `console.log` in workflows
2. Include correlation IDs (orderId, customerId) in log messages
3. Configure Winston or similar for production log aggregation
4. Enable OpenTelemetry for distributed tracing across services
5. Monitor Prometheus metrics for worker health
6. Use Event History for debugging workflow issues
