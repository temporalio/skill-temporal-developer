# TypeScript SDK Lambda Workers

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:22-29 -->

The `@temporalio/lambda-worker` package runs a Temporal Serverless Worker on AWS Lambda. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:31 --> Each invocation starts a Worker, polls for Tasks, then gracefully shuts down before a configurable invocation deadline. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:33 -->

For SDK-agnostic concepts (lifecycle, CloudFormation IAM, `temporal worker deployment create-version`), see `references/core/lambda-workers.md`.

## Package and entry point

Import `runWorker` from `@temporalio/lambda-worker` and export the returned handler. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:40-46 -->

```ts
import { runWorker } from '@temporalio/lambda-worker';
import * as activities from './activities';
import { TASK_QUEUE } from './workflows';

export const handler = runWorker({ deploymentName: 'sdk-demo', buildId: 'v1' }, (config) => {
  config.workerOptions.taskQueue = TASK_QUEUE;
  config.workerOptions.workflowBundle = {
    codePath: require.resolve('./workflow-bundle.js'),
  };
  config.workerOptions.activities = activities;
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:46-58 -->

The deployment version (`deploymentName` + `buildId`) is required; Worker Deployment Versioning is always enabled for Serverless Workers. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:62-63 -->

## Pre-bundle Workflow code

Use `workflowBundle` with pre-bundled code instead of `workflowsPath`. Pre-bundling avoids webpack bundling overhead on every Lambda cold start. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:69-70 -->

Build the bundle as a separate build step with `bundleWorkflowCode` from `@temporalio/worker`: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:72-82 -->

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
});
await writeFile('./workflow-bundle.js', code);
```

Then reference the output in the handler with `workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }`. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:84 -->

## Versioning behavior

Each Workflow must declare a versioning behavior, either `'AUTO_UPGRADE'` or `'PINNED'` (string literals). <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:64 --> <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:173-174 --> The default versioning behavior is `PINNED`. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:65 -->

Change the Worker-level default in the configure callback:

```ts
config.workerOptions.workerDeploymentOptions!.defaultVersioningBehavior = 'PINNED';
```
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:166 -->

Set per-Workflow behavior with `setWorkflowOptions` in the Workflow file. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:174 -->

## Temporal connection config

`@temporalio/lambda-worker` automatically loads Temporal client configuration from a TOML config file and environment variables. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:88 -->

The config file is resolved in this order: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:90-94 -->

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional. If absent, only environment variables are used. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:96 --> Encrypt sensitive values like TLS keys or API keys. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:98 -->

## Lambda-tuned defaults

`@temporalio/lambda-worker` applies conservative defaults suited to short-lived Lambda invocations.

| Setting | Lambda default |
|---|---|
| `maxConcurrentActivityTaskExecutions` | 2 |
| `maxConcurrentWorkflowTaskExecutions` | 10 |
| `maxConcurrentLocalActivityExecutions` | 2 |
| `maxConcurrentNexusTaskExecutions` | 5 |
| `workflowTaskPollerBehavior` | `SimpleMaximum(2)` |
| `activityTaskPollerBehavior` | `SimpleMaximum(1)` |
| `nexusTaskPollerBehavior` | `SimpleMaximum(1)` |
| `shutdownGraceTime` | 5 seconds |
| `maxCachedWorkflows` | 30 |
| `shutdownDeadlineBufferMs` | 7000 (default is `shutdownGraceTime` (5s) + 2s) |

<!-- Sources: docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:105-122 -->

Eager Activities are not supported because Lambda invocations don't maintain persistent connections. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:118 -->

## `shutdownDeadlineBufferMs`

`shutdownDeadlineBufferMs` is specific to `@temporalio/lambda-worker`. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:120-121 --> Its value is in **milliseconds** (the default `7000` is 7000 ms, i.e. 7 seconds).

If your Worker handles long-running Activities, increase `shutdownGraceTime`, `shutdownDeadlineBufferMs`, and the Lambda invocation deadline (`--timeout`) together. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:124 -->

## OpenTelemetry

The `@temporalio/lambda-worker/otel` module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layers. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:129 -->

```ts
import { runWorker } from '@temporalio/lambda-worker';
import { applyDefaults } from '@temporalio/lambda-worker/otel';
import * as activities from './activities';
import { TASK_QUEUE } from './workflows';

export const handler = runWorker({ deploymentName: 'sdk-demo', buildId: 'v1' }, (config) => {
  config.workerOptions.taskQueue = TASK_QUEUE;
  config.workerOptions.workflowBundle = {
    codePath: require.resolve('./workflow-bundle.js'),
  };
  config.workerOptions.activities = activities;
  applyDefaults(config);
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:138-150 -->

`applyDefaults` registers Temporal SDK interceptors for tracing and configures the Core SDK to export metrics via OTLP. By default, telemetry is sent to `localhost:4317`, the ADOT Lambda layer's default collector endpoint. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:154-155 -->

### ADOT Lambda layers

Attach two ADOT Lambda layers: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:157-160 -->

1. The **ADOT JavaScript layer** for Node.js-side auto-instrumentation and trace export.
2. The **ADOT Collector layer** (`aws-otel-collector-amd64`) to run the OTel Collector as a Lambda extension. It receives telemetry on `localhost:4317` and forwards traces to X-Ray and metrics to CloudWatch.

### OTel Collector configuration

The default Collector configuration does not route OTLP data to the traces pipeline; bundle a custom `otel-collector-config.yaml` in your Lambda deployment package: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:162-164 -->

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 'localhost:4317'
      http:
        endpoint: 'localhost:4318'

exporters:
  debug:
  awsxray:
    region: us-west-2
  awsemf:
    # AWS EMF exporter for metrics
    # These are example configurations
    namespace: TemporalWorkerMetrics
    # log_group_name: /aws/lambda/<your-function-name>
    log_group_name: /aws/lambda/sdk-worker-typescript
    region: us-west-2
    dimension_rollup_option: NoDimensionRollup
    resource_to_telemetry_conversion:
      enabled: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [awsxray, debug]
    metrics:
      receivers: [otlp]
      exporters: [awsemf]
  telemetry:
    logs:
      level: debug
    metrics:
      address: localhost:8888
```
<!-- Sources: docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:168-205 -->

Set this environment variable on the Lambda function: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:208-210 -->

```
OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml
```

(Note the `..._URI` suffix.)

### X-Ray active tracing

Enable X-Ray active tracing on the Lambda function: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:212-218 -->

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must have `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without them, the Collector fails silently and no telemetry appears. <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:220-222 -->

### OTel + Workflow pre-bundle plugin

When pre-bundling Workflow code with OTel enabled, pass the plugin from `makeOtelPlugin()` so that Workflow interceptor modules are included in the bundle: <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:224 -->

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { makeOtelPlugin } from '@temporalio/lambda-worker/otel';

const { plugin } = makeOtelPlugin();
const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  plugins: [plugin],
});
```
<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:226-235 -->

## Build and package

Build the Workflow bundle, compile the project, install production-only dependencies, and zip everything: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:229-239 -->

```bash
npx ts-node src/scripts/build-workflow-bundle.ts
npx tsc

npm install --omit=dev
zip -r function.zip lib/ node_modules/ workflow-bundle.js
```

## Deploy

```bash
aws lambda create-function \
  --function-name my-temporal-worker \
  --runtime nodejs22.x \
  --handler lib/index.handler \
  --role <EXECUTION_ROLE_ARN> \
  --zip-file fileb://function.zip \
  --timeout 600 \
  --memory-size 256 \
  --environment '{"Variables":{"HOME":"/tmp","TEMPORAL_ADDRESS":"<your-temporal-address>:7233","TEMPORAL_NAMESPACE":"<your-namespace>","TEMPORAL_API_KEY":"<your-api-key>"}}'
```
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:293-303 -->

`--runtime` must be `nodejs22.x` or another supported Node.js version (20+). `--handler` is in `module.export` format and points to the handler exported by `runWorker`. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:308-309 -->

Key environment variables: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:302, 322-327 -->

- `HOME=/tmp` — required for SDK files that need a writable home directory.
- `TEMPORAL_ADDRESS` — Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`).
- `TEMPORAL_NAMESPACE` — Temporal Namespace.
- `TEMPORAL_API_KEY` — API key for API key authentication.

## See also

- `references/core/lambda-workers.md` — SDK-agnostic lifecycle, CloudFormation IAM template, and the `temporal worker deployment create-version` step for AWS Lambda Serverless Workers.
- `references/typescript/observability.md` — general TypeScript SDK observability (metrics, tracing, replay-aware logging) outside the Lambda context.
