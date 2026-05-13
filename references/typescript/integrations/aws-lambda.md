# Temporal Serverless Workers on AWS Lambda - TypeScript SDK

## Overview

`@temporalio/lambda-worker` lets you run a Temporal Worker inside an AWS Lambda function <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:31 -->. Temporal Cloud invokes the Lambda when Tasks arrive; each invocation starts a Worker, polls the Task Queue, and gracefully shuts down before the Lambda deadline <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:32-33 -->. Workflows and Activities are registered the same way as for a standard Worker <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:34 -->.

**Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. Request access via a support ticket or your account team <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:22-29 -->.

For the conceptual model (WCI, sync match, autoscaling, worker lifecycle, constraints) see the Serverless Workers encyclopedia page <!-- docs/encyclopedia/workers/serverless-workers.mdx:42-57 -->. For an end-to-end deployment walkthrough including IAM and verification, see the deployment guide <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:25 -->.

## Package and imports

```ts
import { runWorker } from '@temporalio/lambda-worker';
import { applyDefaults, makeOtelPlugin } from '@temporalio/lambda-worker/otel'; // optional, for OTel
import { bundleWorkflowCode } from '@temporalio/worker'; // for the pre-bundle build step
```

The package is `@temporalio/lambda-worker` and the OpenTelemetry helpers live under `@temporalio/lambda-worker/otel` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:31,129,138-139,227 -->.

## Minimum Worker code

`runWorker` takes a deployment version (`deploymentName` + `buildId`) and a configure callback that mutates the supplied `config` object. It returns a value suitable to `export` as your Lambda handler <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:40-58 -->.

```ts
// src/index.ts
import { runWorker } from '@temporalio/lambda-worker';
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
  },
);
```

The deployment version is required: Worker Deployment Versioning is always enabled for Serverless Workers <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:62-63 -->. Each Workflow must declare a versioning behavior (`AutoUpgrade` or `Pinned`); the Worker-wide default is `PINNED` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:64-65 -->.

To override the default versioning behavior for all Workflows on this Worker, set it in the configure callback <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:166-167 -->:

```ts
config.workerOptions.workerDeploymentOptions!.defaultVersioningBehavior = 'PINNED';
// or 'AUTO_UPGRADE'
```

The accepted string literals are `'PINNED'` and `'AUTO_UPGRADE'` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:166,173-175 -->. To set the behavior per-Workflow, use `setWorkflowOptions` in the Workflow file <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:173-175 -->.

## Pre-bundle Workflow code

**Always use `workflowBundle` with pre-bundled code, not `workflowsPath`.** Pre-bundling avoids webpack bundling overhead on every Lambda cold start <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:69-70 --><!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:170-171 -->.

Run `bundleWorkflowCode` as a separate build step and write the result to a `.js` file shipped in the deployment zip <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:72-82 -->:

```ts
// src/scripts/build-workflow-bundle.ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
});
await writeFile('./workflow-bundle.js', code);
```

Reference the bundle from the handler via `workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:84 -->.

## Configure the Temporal connection

`@temporalio/lambda-worker` automatically loads Temporal client configuration from a TOML config file and environment variables; see the Environment Configuration doc for the full schema and supported variables <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:88 --><!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:329-331 -->.

Config-file resolution order <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:90-96 -->:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:96 -->. Encrypt sensitive values such as TLS keys and API keys at rest <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:98 -->.

## Lambda-tuned defaults

`@temporalio/lambda-worker` applies conservative defaults suited to short-lived invocations <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:100-103 -->:

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

<!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:105-116 -->

**Eager Activities are not supported** — Lambda invocations don't maintain persistent connections <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:118 -->.

`shutdownDeadlineBufferMs` is specific to `@temporalio/lambda-worker` and expressed in **milliseconds**. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default `7000` is `shutdownGraceTime` (5s) + 2s <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:120-122 -->.

For long-running Activities, increase `shutdownGraceTime`, `shutdownDeadlineBufferMs`, and the Lambda invocation deadline (`--timeout`) together. See the encyclopedia's "Tuning for long-running Activities" for how these values relate <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:124-125 --><!-- docs/encyclopedia/workers/serverless-workers.mdx:170-202 -->.

## Build and package

Build the Workflow bundle, compile TypeScript, install production dependencies, and zip <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:229-239 -->:

```bash
npx ts-node src/scripts/build-workflow-bundle.ts
npx tsc

npm install --omit=dev
zip -r function.zip lib/ node_modules/ workflow-bundle.js
```

## Deploy with `aws lambda create-function`

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

Use the `nodejs22.x` runtime (or another supported Node.js 20+ version) and `lib/index.handler` as the handler — the entry point must be in `module.export` format pointing at the handler exported by `runWorker` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:294-309 -->.

The Lambda execution role passed to `--role` must trust `lambda.amazonaws.com` and have at least the `AWSLambdaBasicExecutionRole` managed policy. **This is separate from the IAM role Temporal uses to invoke the function** (see [IAM (Cloud)](#iam-cloud)) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 -->.

`--timeout` is the invocation deadline in seconds: the maximum time each invocation can run before AWS terminates it. Set it high enough for the Worker to start, process Tasks, and shut down gracefully <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:320 -->.

Supported environment variables on the Lambda <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:322-327 -->:

| Variable | Purpose |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`). |
| `TEMPORAL_NAMESPACE` | Temporal Namespace. |
| `TEMPORAL_TASK_QUEUE` | Task Queue name. Overrides the value set in code. |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | Path to the TLS client certificate file for mTLS authentication. |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | Path to the TLS client key file for mTLS authentication. |
| `TEMPORAL_API_KEY` | API key for API key authentication. |

The TypeScript Lambda example also sets `HOME=/tmp` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:302 -->.

To update an existing function with new code <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:338-342 -->:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

Best practice: create a 1-to-1 mapping between each build ID in your Worker code and a Lambda function version. If you use an unversioned Lambda, don't change the build ID without also creating a new Worker Deployment Version <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:344-351 -->.

## IAM (Cloud)

Temporal needs permission to invoke your Lambda function. The Temporal server assumes an IAM role in your AWS account to call `lambda:InvokeFunction`. The trust policy includes an External ID condition to prevent confused-deputy attacks <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:353-361 -->.

Deploy the CloudFormation template provided in the deployment guide; it creates the invocation role and a policy granting `lambda:InvokeFunction` + `lambda:GetFunction` on the configured Lambda ARNs <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:363-476 -->.

Parameters <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:366-370 -->:

- `AssumeRoleExternalId` — any string of your choosing; supply the same value when creating the Worker Deployment Version.
- `LambdaFunctionARNs` — comma-separated list of Lambda function ARNs Temporal may invoke (one role can authorize multiple Worker Lambdas).
- `RoleName` — base name for the created IAM role (defaults to `Temporal-Cloud-Serverless-Worker`).

**Two distinct IAM roles are in play; do not conflate them:**

- The **Lambda execution role** (`--role` on `aws lambda create-function`) grants the function permission to run and write logs. Trust principal: `lambda.amazonaws.com` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 -->.
- The **Temporal invocation role** (the CloudFormation output) is the role Temporal Cloud assumes to call `InvokeFunction`. Trust principals: the Temporal Cloud `wci-lambda-invoke` roles, gated by the External ID condition <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:419-441 -->.

For self-hosted Temporal Service deployments, use the alternate CloudFormation template from the self-hosted setup doc instead <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:355-357 -->.

## Create the Worker Deployment Version

Create a Worker Deployment Version whose compute provider points at your Lambda function. The deployment name and build ID **must match** the values in your Worker code <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:501-504 -->.

### Temporal CLI

First create the deployment if it doesn't already exist <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:533-539 -->:

```bash
temporal worker deployment create \
  --namespace <YOUR_NAMESPACE> \
  --name my-app
```

Then create the version with the compute provider configuration <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:541-551 -->:

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

The relevant flags <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:553-559 -->:

| Flag | Description |
|---|---|
| `--deployment-name` | Must match `deploymentName` in your Worker code. |
| `--build-id` | Must match `buildId` in your Worker code. |
| `--aws-lambda-function-arn` | ARN of the Lambda function Temporal invokes. |
| `--aws-lambda-assume-role-arn` | The invocation role ARN (CloudFormation `RoleARN` output), **not** the execution role and **not** your IAM user. |
| `--aws-lambda-assume-role-external-id` | External ID configured in the role's trust policy. |

**When using the CLI you must set the version as current as a separate step**, otherwise Tasks don't route to it and Temporal won't invoke the Lambda <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:530-531,568-579 -->:

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

### Temporal UI

When you create the version through the UI, it's automatically set as current — you can skip `set-current-version` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:524-525 -->.

To smoke-test reachability, open the deployment version's **Actions** menu in the UI and click **Validate Connection** <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:564-566 -->.

## OpenTelemetry observability

`@temporalio/lambda-worker/otel` provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layers. When enabled, the Worker emits SDK metrics and distributed traces for Workflow and Activity executions <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:127-133 -->.

Wire it up by calling `applyDefaults(config)` inside the configure callback <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:138-151 -->:

```ts
import { runWorker } from '@temporalio/lambda-worker';
import { applyDefaults } from '@temporalio/lambda-worker/otel';
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
    applyDefaults(config);
  },
);
```

`applyDefaults` registers Temporal SDK interceptors for tracing and configures the Core SDK to export metrics via OTLP. By default telemetry is sent to `localhost:4317`, the ADOT Lambda layer's default collector endpoint <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:154-155 -->.

### Two ADOT layers are required

Attach **both** ADOT Lambda layers <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:157-160 -->:

1. The ADOT JavaScript layer — for Node.js-side auto-instrumentation and trace export.
2. The ADOT Collector layer (`aws-otel-collector-amd64`) — runs the OTel Collector as a Lambda extension, receiving telemetry on `localhost:4317` and forwarding traces to X-Ray and metrics to CloudWatch.

The default Collector configuration does **not** route OTLP data to the traces pipeline. Provide a custom Collector configuration that wires the OTLP receiver to both the traces and metrics pipelines, and bundle it in the deployment zip <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:162-205 -->:

```yaml
# otel-collector-config.yaml
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
    namespace: TemporalWorkerMetrics
    log_group_name: /aws/lambda/<your-function-name>
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
      level: info
    metrics:
      address: localhost:8888
```

Set this env var on the Lambda function <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:207-209 -->:

```
OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml
```

Enable X-Ray active tracing on the Lambda function <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:211-217 -->:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The execution role must have `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData`. Without these, the Collector fails silently and no telemetry appears <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:219-221 -->.

### Pre-bundling with OTel

If you pre-bundle Workflow code **and** use OTel, pass the plugin from `makeOtelPlugin()` to `bundleWorkflowCode` so Workflow interceptor modules are included in the bundle <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:223-234 -->:

```ts
import { bundleWorkflowCode } from '@temporalio/worker';
import { makeOtelPlugin } from '@temporalio/lambda-worker/otel';

const { plugin } = makeOtelPlugin();
const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  plugins: [plugin],
});
```

For broader observability concepts and the full SDK metrics list, see the TypeScript Observability doc and the SDK metrics reference <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:132-133 -->.

## Common mistakes

- **Using `workflowsPath` instead of pre-bundled `workflowBundle`.** Forces webpack to run on every cold start; always pre-bundle <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:69-70 -->.
- **Mismatched `deploymentName` / `buildId` between Worker code and the Worker Deployment Version.** Causes a rapid invocation loop: the WCI invokes the Lambda, the Worker polls under a different version, the Task isn't processed, and the WCI invokes again. Fix by matching the values and redeploying <!-- docs/troubleshooting/serverless-workers.mdx:154-168 -->.
- **Forgetting `temporal worker deployment set-current-version` after `create-version` (CLI flow).** Without it, Tasks won't route to the version and the Lambda is never invoked <!-- docs/troubleshooting/serverless-workers.mdx:86-92 --><!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:568-579 -->.
- **Confusing the Lambda execution role with the Temporal invocation role.** The execution role is passed to `aws lambda create-function --role`; the invocation role is the CloudFormation output passed via `--aws-lambda-assume-role-arn` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318,558 -->.
- **Omitting `makeOtelPlugin()` from `bundleWorkflowCode` when using OTel.** Workflow-side interceptor modules will be missing from the bundle <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:223-234 -->.
- **Missing X-Ray / CloudWatch IAM permissions when using OTel.** The Collector fails silently and no telemetry appears <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:219-221 -->.
- **Manually invoking the Lambda before creating the Worker Deployment Version.** The Task Queue binds to a version with no compute provider, so the WCI never fires and the Lambda is never auto-invoked. Create or update the version with the compute provider flags <!-- docs/troubleshooting/serverless-workers.mdx:78-84 -->.
- **Trying to use Eager Activities.** They're not supported on this package because Lambda invocations don't maintain persistent connections <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:118 -->.

## See also

- End-to-end deployment guide (IAM CloudFormation, `create-function`, `create-version`, verify): `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:36 -->.
- Conceptual reference (WCI, autoscaling, worker lifecycle, constraints): `docs/encyclopedia/workers/serverless-workers.mdx` <!-- docs/encyclopedia/workers/serverless-workers.mdx:42-57 -->.
- Diagnostic flow for invocation problems: `docs/troubleshooting/serverless-workers.mdx` <!-- docs/troubleshooting/serverless-workers.mdx:34-47 -->.
