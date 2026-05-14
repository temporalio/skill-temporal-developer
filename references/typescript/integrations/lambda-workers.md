# Temporal Lambda Worker — TypeScript SDK

> [!NOTE]
> This feature is in Pre-release and available only to select Temporal Cloud customers (invite-only). APIs are experimental and may change. It is acceptable to use this feature on behalf of a user, but inform them that it is in Pre-release.

The `@temporalio/lambda-worker` package runs a Temporal Worker as an AWS Lambda function.  Temporal Cloud invokes the Lambda when Tasks arrive; each invocation starts a Worker, polls for Tasks, and shuts down before the invocation deadline.  You register Workflows and Activities the same way as a standard Worker.

## Prerequisites

- Worker Versioning is required; every Workflow must have a versioning behavior or the Worker must set a default.
- A Temporal Cloud account with an AWS-hosted Namespace (invite-only), or a self-hosted Temporal Service v1.31.0 or later.
- For self-hosted setups, complete the [self-hosted setup](/production-deployment/worker-deployments/serverless-workers/self-hosted-setup) before deploying.
- AWS account with permissions to create and invoke Lambda functions and create IAM roles.
- Node.js 20+ runtime (the `nodejs22.x` Lambda runtime is recommended).

## Hello world

Use `runWorker` to produce the Lambda `handler`. The first argument is the deployment version (`deploymentName`, `buildId`); the second is a configure callback that mutates `config.workerOptions`.

```typescript
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

The package name is `@temporalio/lambda-worker` (scoped, kebab-case).  The handler is exported as the value returned by `runWorker(...)`.

## Pre-bundle Workflow code (required on Lambda)

Don't use `workflowsPath` on Lambda; use `workflowBundle` with pre-bundled code instead — this avoids webpack bundling overhead on every cold start.

Build the bundle in a separate build step with `bundleWorkflowCode` from `@temporalio/worker`:

```typescript
import { bundleWorkflowCode } from '@temporalio/worker';
import { writeFile } from 'fs/promises';

const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
});
await writeFile('./workflow-bundle.js', code);
```

Reference the bundle in the handler with `workflowBundle: { codePath: require.resolve('./workflow-bundle.js') }`.

## Deployment version and versioning

- `deploymentName` and `buildId` are passed as the first argument to `runWorker`.
- Worker Deployment Versioning is always enabled for Serverless Workers; the deployment version is required.
- Each Workflow must declare a versioning behavior, either `'AUTO_UPGRADE'` or `'PINNED'`.
- The default versioning behavior is `'PINNED'`.
- To change the Worker-level default, set `config.workerOptions.workerDeploymentOptions.defaultVersioningBehavior` in the configure callback.
- To set per-Workflow behavior, use `setWorkflowOptions` in the Workflow file.

Example of overriding the default in the configure callback:

```typescript
config.workerOptions.workerDeploymentOptions!.defaultVersioningBehavior = 'PINNED';
```

## Connection configuration

The package auto-loads Temporal client configuration from a TOML config file and environment variables.  Config file resolution order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used.  Encrypt sensitive values (TLS keys, API keys) at rest.

## Lambda-tuned defaults

The package applies conservative defaults suited to short-lived Lambda invocations.

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

Eager Activities are not supported. Lambda invocations don't maintain persistent connections.

`shutdownDeadlineBufferMs` is specific to `@temporalio/lambda-worker`; it controls how much time before the Lambda deadline the Worker begins graceful shutdown. The default is `shutdownGraceTime` (5s) + 2s.

## Worker lifecycle and tuning

Each invocation has three phases: init (client connect), work (poll and process Tasks), and shutdown (stop polling, drain in-flight Tasks, run shutdown hooks).

For long-running Activities, tune these three values together:

- Worker stop timeout (`shutdownGraceTime`) > longest Activity runtime.
- `shutdownDeadlineBufferMs` > Worker stop timeout + shutdown hook time.
- Lambda `--timeout` > longest Activity runtime + `shutdownDeadlineBufferMs`.

Raising only the buffer makes the Worker stop polling earlier without giving in-flight Tasks more time; raising only the stop timeout risks Lambda terminating the function before the drain completes.  If an Activity may run longer than half the maximum invocation deadline, use [Activity Heartbeats](/encyclopedia/detecting-activity-failures#activity-heartbeat) instead.

## OpenTelemetry

Telemetry support lives in the `@temporalio/lambda-worker/otel` subpath.

Call `applyDefaults(config)` inside the configure callback to register Temporal SDK tracing interceptors and configure OTLP metric export.  Telemetry is sent to `localhost:4317` (the ADOT Lambda layer's default collector endpoint).

```typescript
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

When pre-bundling Workflow code with OTel, pass the plugin from `makeOtelPlugin()` so Workflow interceptor modules are included in the bundle:

```typescript
import { bundleWorkflowCode } from '@temporalio/worker';
import { makeOtelPlugin } from '@temporalio/lambda-worker/otel';

const { plugin } = makeOtelPlugin();
const { code } = await bundleWorkflowCode({
  workflowsPath: require.resolve('./workflows'),
  plugins: [plugin],
});
```

Attach two ADOT Lambda layers:

1. The ADOT JavaScript layer for Node.js auto-instrumentation and trace export.
2. The ADOT Collector layer (`aws-otel-collector-amd64`) — runs the OTel Collector as a Lambda extension, receiving OTLP on `localhost:4317` and forwarding traces to X-Ray and metrics to CloudWatch.

Provide a custom Collector configuration that routes OTLP to both traces and metrics pipelines (default config does not).  Set this env var on the Lambda: `OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml`.

Enable X-Ray active tracing on the function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role needs `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData`. Without these, the Collector fails silently.

## Deploy

### Build and package

```bash
npx ts-node src/scripts/build-workflow-bundle.ts
npx tsc
npm install --omit=dev
zip -r function.zip lib/ node_modules/ workflow-bundle.js
```

### Create the Lambda function

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

`--runtime` is `nodejs22.x` or another supported Node.js version (20+); `--handler` is in `module.export` format and must point to the handler exported by `runWorker`.

### Common Lambda environment variables

| Variable | Purpose |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`). |
| `TEMPORAL_NAMESPACE` | Temporal Namespace. |
| `TEMPORAL_TASK_QUEUE` | Task Queue name; overrides the value set in code. |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | TLS client certificate path for mTLS. |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | TLS client key path for mTLS. |
| `TEMPORAL_API_KEY` | API key for API key authentication. |

For the full list of supported environment variables and TOML profile format, see [Environment configuration](/develop/environment-configuration).

### Redeploy code

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

Maintain a 1-to-1 mapping between each build ID in Worker code and a Lambda function version. Don't change the build ID in code without also creating a new Worker Deployment Version.

### IAM for Temporal invocation

Temporal Cloud assumes an IAM role in your AWS account to call `lambda:InvokeFunction`.  Deploy the [CloudFormation template](/production-deployment/worker-deployments/serverless-workers/aws-lambda#configure-iam) with `AssumeRoleExternalId`, `LambdaFunctionARNs`, and `RoleName`.

### Create the Worker Deployment Version (CLI)

```bash
temporal worker deployment create \
  --namespace <YOUR_NAMESPACE> \
  --name my-app

temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

`--deployment-name` and `--build-id` must match the values in the Worker code.  `--aws-lambda-assume-role-arn` is the `RoleARN` output from the CloudFormation stack (not the Lambda execution role).

### Set the version as current

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

Without this step, Tasks on the Task Queue won't route to the version.  When the version is created via the UI, it is set as current automatically.

## Constraints

| Constraint | Detail |
|---|---|
| Activity duration | Must complete within the Lambda invocation limit minus `shutdownDeadlineBufferMs`. Lambda's hard maximum is 15 minutes.  |
| Workflow duration | No limit; a Workflow runs across as many invocations as needed.  |
| Versioning | Worker Versioning is required.  |
| Persistent connections | Not maintained across invocations; features requiring persistent connections are unavailable.   |
| Eager Activities | Not supported. Lambda invocations don't maintain persistent connections.  |

## Troubleshooting

- **Invocation loop with no Workflow progress.** Deployment name and build ID in code must exactly match the Worker Deployment Version. A mismatch causes the WCI to repeatedly invoke without ever processing the Task. Fix by aligning the values and redeploying.
- **Lambda never invoked / no Task Queue binding.** A failed first invocation prevents the Task Queue binding from being created. Invoke the Lambda manually from the AWS Console to surface the error directly.
- **Lambda never invoked / version not current.** If created via CLI, run `temporal worker deployment set-current-version`.
- **Validate Connection action.** In the Temporal UI under **Workers > Deployments**, the version's **Actions > Validate Connection** confirms IAM role assume and Lambda reachability.
- **Listing WCI Workflows.** WCI Workflow IDs follow `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>` and can be listed with `--query 'TemporalNamespaceDivision = "TemporalWorkerControllerInstance"'`.
- **Connection / TLS / auth errors.** Check `TEMPORAL_ADDRESS`, `TEMPORAL_API_KEY`, TLS certificate/key validity, and (self-hosted) network reachability.
- **Lambda timeout abandoning Activities.** If Activities run past the Lambda deadline, AWS terminates the invocation. Increase `--timeout`, `shutdownGraceTime`, and `shutdownDeadlineBufferMs` together.
