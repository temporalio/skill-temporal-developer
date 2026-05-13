# `@temporalio/lambda-worker` (AWS Lambda Serverless Worker)

## Overview

`@temporalio/lambda-worker` lets you run a Temporal Worker as an AWS Lambda function: deploy your Worker code as a Lambda, and Temporal Cloud invokes it when Tasks arrive on a Task Queue.  Each invocation starts a Worker, polls for Tasks, then gracefully shuts down before a configurable invocation deadline.  You register Workflows and Activities the same way as with a standard Worker.

Serverless Workers are in **Pre-release** and available to select Temporal Cloud customers; APIs are experimental and may be subject to backwards-incompatible changes.

## Install / package path

- Package: `@temporalio/lambda-worker`
- Observability sub-module: `@temporalio/lambda-worker/otel`

Per the skill convention, all `@temporalio/*` packages in a project must share the same version (so `@temporalio/lambda-worker` and `@temporalio/worker` must be on matching versions).

## Minimal Worker code

Use `runWorker` to create a Lambda handler. Pass a deployment version (`deploymentName` + `buildId`) and a configure callback that mutates `config.workerOptions`.

```ts
import { runWorker } from '@temporalio/lambda-worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:46
import * as activities from './activities';
import { TASK_QUEUE } from './workflows';

export const handler = runWorker(
  { deploymentName: 'sdk-demo', buildId: 'v1' }, // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:51
  (config) => {
    config.workerOptions.taskQueue = TASK_QUEUE; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:52
    config.workerOptions.workflowBundle = {
      codePath: require.resolve('./workflow-bundle.js'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:53-54
    };
    config.workerOptions.activities = activities; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:56
  },
);
```

The deployment version is required: Worker Deployment Versioning is always enabled for Serverless Workers.

## Pre-bundle Workflow code

Use `workflowBundle` with pre-bundled code instead of `workflowsPath` to avoid webpack bundling overhead on every Lambda cold start.

Build the bundle as a separate build step using `bundleWorkflowCode` from `@temporalio/worker`:

```ts
import { bundleWorkflowCode } from '@temporalio/worker'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:75
import { writeFile } from 'fs/promises';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'), // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:79
});
await writeFile('./workflow-bundle.js', code); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:81
```

Then reference the bundle in your handler with `workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }`.

## Worker Versioning is required

Each Workflow must declare a [versioning behavior](/worker-versioning#versioning-behaviors), either `AUTO_UPGRADE` or `PINNED`.

Two ways to set it:

- **Per-Workflow:** call `setWorkflowOptions` in the Workflow file.
- **Worker-level default:** set `workerDeploymentOptions.defaultVersioningBehavior` in the configure callback.

```ts
config.workerOptions.workerDeploymentOptions!.defaultVersioningBehavior = 'PINNED'; // docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:166
```

The TypeScript SDK default is `PINNED`.

## Configure the Temporal connection

`@temporalio/lambda-worker` automatically loads Temporal client configuration from a TOML config file and environment variables.

The config file is resolved in this order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional — if absent, only environment variables are used.

Sensitive values (TLS keys, API keys) should be encrypted.

For details on supported environment variables, config file format, and profiles, see the Environment Configuration docs (`docs/develop/environment-configuration`).

## Lambda-tuned defaults

`@temporalio/lambda-worker` applies conservative defaults suited to short-lived Lambda invocations; these differ from standard Worker defaults to avoid overcommitting resources.

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
| `shutdownDeadlineBufferMs` | 7000 |

**Eager Activities are not supported.** Lambda invocations don't maintain persistent connections.

**`shutdownDeadlineBufferMs` is specific to the `@temporalio/lambda-worker` package.** It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `shutdownGraceTime` (5s) + 2s = 7000ms.

## Tuning for long-running Activities

If your Worker handles long-running Activities, increase `shutdownGraceTime`, `shutdownDeadlineBufferMs`, and the Lambda invocation deadline (`--timeout`) together.

Set these three values together:

- **Worker stop timeout (`shutdownGraceTime`) > longest Activity runtime.** Gives in-flight Activities enough time to finish after polling stops.
- **Shutdown deadline buffer (`shutdownDeadlineBufferMs`) > Worker stop timeout + shutdown hook time.** Ensures the drain and any shutdown hooks complete before the compute provider terminates the environment.
- **Invocation deadline (Lambda `--timeout`) > longest Activity runtime + shutdown deadline buffer.** Set on the compute provider to give each invocation enough total runtime.

If your longest-running Activity runs longer than half the maximum invocation deadline, this constraint may be impossible to meet — use Activity Heartbeats so the next retry can pick up where it left off.

Cross-reference: `docs/encyclopedia/workers/serverless-workers.mdx` — section "Tuning for long-running Activities".

## Observability with OpenTelemetry

The `@temporalio/lambda-worker/otel` sub-module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layers. With it enabled, the Worker emits SDK metrics and distributed traces for Workflow and Activity executions.

Call `applyDefaults(config)` inside the configure callback:

```ts
import { runWorker } from '@temporalio/lambda-worker';
import { applyDefaults } from '@temporalio/lambda-worker/otel'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:139
import * as activities from './activities';
import { TASK_QUEUE } from './workflows';

export const handler = runWorker(
  { deploymentName: 'sdk-demo', buildId: 'v1' },
  (config) => {
    config.workerOptions.taskQueue = TASK_QUEUE;
    config.workerOptions.workflowBundle = {
      codePath: require.resolve('./workflow-bundle.js'),
    };
    config.workerOptions.activities = activities;
    applyDefaults(config); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:149
  },
);
```

`applyDefaults` registers Temporal SDK interceptors for tracing and configures the Core SDK to export metrics via OTLP. By default, telemetry is sent to `localhost:4317`, which is the ADOT Lambda layer's default collector endpoint.

Attach two ADOT Lambda layers:

1. The ADOT JavaScript layer for Node.js-side auto-instrumentation and trace export.
2. The ADOT Collector layer (`aws-otel-collector-amd64`) to run the OTel Collector as a Lambda extension, receiving telemetry via OTLP on `localhost:4317` and forwarding traces to X-Ray and metrics to CloudWatch.

The default Collector configuration does **not** route OTLP data to the traces pipeline — you must provide a custom Collector config that wires the OTLP receiver to both the traces and metrics pipelines. Bundle an `otel-collector-config.yaml` in your Lambda deployment package.

Set this environment variable on the Lambda function:

- `OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml`

Enable X-Ray active tracing on the function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must have these IAM permissions or the Collector fails silently and no telemetry appears: `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, `cloudwatch:PutMetricData`.

When pre-bundling Workflow code, pass the plugin from `makeOtelPlugin()` so that Workflow interceptor modules are included in the bundle:

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { makeOtelPlugin } from '@temporalio/lambda-worker/otel'; // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:227

const { plugin } = makeOtelPlugin(); // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:229
const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  plugins: [plugin], // docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:232
});
```

## Deployment recipe

Build the Workflow bundle and compile the project:

```bash
npx ts-node src/scripts/build-workflow-bundle.ts
npx tsc
```

Install production dependencies and zip the package:

```bash
npm install --omit=dev
zip -r function.zip lib/ node_modules/ workflow-bundle.js
```

Create the Lambda function:

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

Notes on the flags:

- `--runtime nodejs22.x` — use `nodejs22.x` or another supported Node.js version (20+).
- `--handler lib/index.handler` — entry point in `module.export` format; must point to the handler exported by `runWorker`.
- `--timeout 600` — invocation deadline in seconds; set high enough for the Worker to start, process Tasks, and shut down gracefully.
- `HOME=/tmp` is included in the example environment variables for the TypeScript runtime.
- Standard `TEMPORAL_*` environment variables: `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`, `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, `TEMPORAL_API_KEY`.

To update an existing function with new code:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

After the function is deployed, create a Worker Deployment Version that points to it via the Temporal CLI:

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

The `--aws-lambda-assume-role-arn` is the IAM role Temporal assumes to invoke the function (not the Lambda execution role).  The `--aws-lambda-assume-role-external-id` is the External ID configured in the IAM role trust policy.

The broader deploy guide covers IAM role setup (CloudFormation templates for the invocation role, the `Validate Connection` action, and `temporal worker deployment set-current-version`). See `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx`. For self-hosted Temporal Service, see `docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx` (requires Temporal Service v1.31.0+, WCI dynamic config, AWS credentials, and an invocation role).

## Constraints

| Constraint | Detail |
|---|---|
| Activity duration | Must complete within the compute provider's invocation limit (minus shutdown deadline buffer). For AWS Lambda, the maximum is **15 minutes**.  |
| Workflow duration | **No limit.** A Workflow runs across as many invocations as needed.  |
| Eager Activities | Not supported (no persistent connection).  |
| Worker Versioning | Required. Each Workflow must declare `AUTO_UPGRADE` or `PINNED`, per-Workflow or as a Worker-level default.  |

## If invocations aren't happening

Short pointers from the troubleshooting page (`docs/troubleshooting/serverless-workers.mdx`):

- **Run "Validate Connection."** Go to Workers > Deployments > select your deployment, open the Actions menu on the version, and click **Validate Connection** to confirm Temporal can assume the IAM role and invoke the function.
- **Version not set as current.** If you created the version via CLI, you must `temporal worker deployment set-current-version` — otherwise Tasks do not route to it.
- **Deployment name / build ID mismatch causes an invocation loop.** WCI invokes the Lambda, the Worker polls with a different version, the Task isn't processed, and WCI invokes again. Ensure `deploymentName` and `buildId` in code exactly match the Worker Deployment Version.
- **First invocation failed, so Task Queue binding was never established.** Invoke the Lambda manually from the AWS Console to see configuration errors directly; once the Worker connects and polls, the binding is created.
- **Lambda timeout.** If Activities run longer than the available execution window, increase the Lambda `--timeout` and the Worker's `shutdownDeadlineBufferMs` / `shutdownGraceTime` together — see Tuning for long-running Activities above.
