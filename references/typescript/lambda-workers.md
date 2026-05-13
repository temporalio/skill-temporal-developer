# Lambda Workers — TypeScript SDK

For shared concepts (WCI, lifecycle, IAM, deployment, troubleshooting), see `references/core/lambda-workers.md`.

## Package

Use `@temporalio/lambda-worker` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:31 --> to run a Temporal Serverless Worker on AWS Lambda. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:31 -->

The package is in **Pre-release** and APIs are experimental — they may change in backwards-incompatible ways. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:24-26 -->

## `runWorker` entry point

`runWorker` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:40 --> returns a Lambda handler that runs a Temporal Worker. Pass a deployment version (`{ deploymentName, buildId }`) <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:51 --> and a configure callback that sets up Workflows and Activities. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:40-41 -->

```ts
import { runWorker } from '@temporalio/lambda-worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:46
// ...
import * as activities from './activities'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:48
import { TASK_QUEUE } from './workflows'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:49

export const handler = runWorker({ deploymentName: 'sdk-demo', buildId: 'v1' }, (config) => { // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:51
  config.workerOptions.taskQueue = TASK_QUEUE; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:52
  config.workerOptions.workflowBundle = { // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:53
    codePath: require.resolve('./workflow-bundle.js'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:54
  };
  config.workerOptions.activities = activities; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:56
// ...
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:45-59 -->

### Configure callback

The configure callback receives a `config` object whose `config.workerOptions` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:52 --> field accepts the standard Worker options. Set at minimum:

- `taskQueue` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:52 -->
- `workflowBundle` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:53 -->
- `activities` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:56 -->

### Deployment versioning

The deployment version is required. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:62 --> Worker Deployment Versioning is always enabled for Serverless Workers. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:63 -->

Each Workflow must declare a versioning behavior — either `AutoUpgrade` or `Pinned`. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:64 -->

The default versioning behavior is `PINNED`. To change it, set `workerDeploymentOptions.defaultVersioningBehavior` in the configure callback. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:65 -->

## Pre-bundle Workflow code

Use `workflowBundle` with pre-bundled code instead of `workflowsPath`. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:69 --> Pre-bundling avoids webpack bundling overhead on every Lambda cold start. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:70 -->

Build the bundle as a separate build step using `bundleWorkflowCode` from `@temporalio/worker`: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:72-75 -->

```typescript
import { bundleWorkflowCode } from '@temporalio/worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:75
import { writeFile } from 'fs/promises'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:76

const { code } = await bundleWorkflowCode({ // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:78
  workflowsPath: require.resolve('./workflows'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:79
});
await writeFile('./workflow-bundle.js', code); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:81
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:74-82 -->

Then reference the bundle in your handler with `workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }`. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:84 -->

## Connection configuration

The `@temporalio/lambda-worker` package automatically loads Temporal client configuration from a TOML config file and environment variables. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:88 -->

The config file is resolved in this order: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:90 -->

1. `TEMPORAL_CONFIG_FILE` environment variable, if set. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:92 -->
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`). <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:93 -->
3. `temporal.toml` in the current working directory. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:94 -->

The file is optional. If absent, only environment variables are used. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:96 -->

Encrypt sensitive values like TLS keys or API keys. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:98 -->

## Lambda-tuned defaults

The `@temporalio/lambda-worker` package applies conservative defaults suited to short-lived Lambda invocations. These differ from standard Worker defaults to avoid overcommitting resources in a constrained environment. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:102-103 -->

| Setting | Lambda default |
|---|---|
| `maxConcurrentActivityTaskExecutions` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:107 --> | 2 |
| `maxConcurrentWorkflowTaskExecutions` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:108 --> | 10 |
| `maxConcurrentLocalActivityExecutions` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:109 --> | 2 |
| `maxConcurrentNexusTaskExecutions` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:110 --> | 5 |
| `workflowTaskPollerBehavior` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:111 --> | `SimpleMaximum(2)` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:111 --> |
| `activityTaskPollerBehavior` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:112 --> | `SimpleMaximum(1)` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:112 --> |
| `nexusTaskPollerBehavior` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:113 --> | `SimpleMaximum(1)` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:113 --> |
| `shutdownGraceTime` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:114 --> | 5 seconds |
| `maxCachedWorkflows` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:115 --> | 30 |
| `shutdownDeadlineBufferMs` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:116 --> | 7000 |

Eager Activities are not supported. Lambda invocations don't maintain persistent connections. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:118 -->

`shutdownDeadlineBufferMs` is specific to the `@temporalio/lambda-worker` package. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:120 --> It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:121 --> The default is `shutdownGraceTime` (5s) + 2s. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:122 -->

For long-running Activities, increase `shutdownGraceTime`, `shutdownDeadlineBufferMs`, and the Lambda invocation deadline (`--timeout`) together. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:124 -->

## OpenTelemetry observability

The `@temporalio/lambda-worker/otel` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:129 --> sub-module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layers. With this enabled, the Worker emits SDK metrics and distributed traces for Workflow and Activity executions. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:129-130 -->

### `applyDefaults`

Call `applyDefaults(config)` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:139 --> inside the configure callback to register Temporal SDK interceptors for tracing and configure the Core SDK to export metrics via OpenTelemetry Protocol (OTLP). <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:154 -->

```ts
import { runWorker } from '@temporalio/lambda-worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:138
import { applyDefaults } from '@temporalio/lambda-worker/otel'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:139
import * as activities from './activities'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:140
import { TASK_QUEUE } from './workflows'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:141

export const handler = runWorker({ deploymentName: 'sdk-demo', buildId: 'v1' }, (config) => { // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:143
  config.workerOptions.taskQueue = TASK_QUEUE; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:144
  config.workerOptions.workflowBundle = { // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:145
    codePath: require.resolve('./workflow-bundle.js'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:146
  };
  config.workerOptions.activities = activities; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:148
  applyDefaults(config); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:149
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:137-151 -->

By default, telemetry is sent to `localhost:4317`, which is the ADOT Lambda layer's default collector endpoint. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:155 -->

### `makeOtelPlugin` with pre-bundling

When pre-bundling Workflow code, pass the plugin from `makeOtelPlugin()` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:223 --> so that Workflow interceptor modules are included in the bundle: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:223 -->

```typescript
import { bundleWorkflowCode } from '@temporalio/worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:226
import { makeOtelPlugin } from '@temporalio/lambda-worker/otel'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:227

const { plugin } = makeOtelPlugin(); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:229
const { code } = await bundleWorkflowCode({ // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:230
  workflowsPath: require.resolve('./workflows'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:231
  plugins: [plugin], // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:232
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:225-234 -->

### ADOT Lambda layers

Attach two ADOT Lambda layers to collect telemetry: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:157 -->

1. The **ADOT JavaScript layer** for Node.js-side auto-instrumentation and trace export. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:159 -->
2. The **ADOT Collector layer** (`aws-otel-collector-amd64`) <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:160 --> to run the OTel Collector as a Lambda extension, receiving telemetry via OTLP on `localhost:4317` and forwarding traces to X-Ray and metrics to CloudWatch. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:160 -->

The default Collector configuration does not route OTLP data to the traces pipeline. You must provide a custom Collector configuration that wires the OTLP receiver to both the traces and metrics pipelines. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:162-163 -->

### Collector config environment variable

Set on the Lambda function: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:207 -->

- `OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:209 -->

Enable X-Ray active tracing on the Lambda function. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:211 -->

### IAM permissions

The Lambda execution role must have permissions to write to X-Ray and CloudWatch. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:219 --> Add the following to the execution role: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:220 -->

- `xray:PutTraceSegments` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:220 -->
- `xray:PutTelemetryRecords` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:220 -->
- `cloudwatch:PutMetricData` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:220 -->

Without these permissions, the Collector fails silently and no telemetry appears. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:221 -->
