# Temporal Serverless Workers on AWS Lambda (Python)

## Overview

The `lambda_worker` contrib package lets you run a Temporal Serverless Worker inside an AWS Lambda function <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:31 -->. Each Lambda invocation starts a Worker, polls for Tasks, then gracefully shuts down before the invocation deadline <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:33 -->. Workflow and Activity registration is identical to a long-lived Worker; only the lifecycle differs.

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. Request access via a support ticket. APIs are experimental and may change in backwards-incompatible ways <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:22-29 -->.

For conceptual background (Worker Controller Instance, autoscaling, lifecycle, constraints), see the [Serverless Workers concept page](https://docs.temporal.io/serverless-workers) <!-- docs/encyclopedia/workers/serverless-workers.mdx:1-265 -->. For the full deployment walkthrough, see [Deploy a Serverless Worker on AWS Lambda](https://docs.temporal.io/production-deployment/worker-deployments/serverless-workers/aws-lambda) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:1-602 -->.

## Package and imports

```python
from temporalio.common import WorkerDeploymentVersion, VersioningBehavior
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
# Optional, for observability:
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:46-49 docs/develop/python/workers/serverless-workers/aws-lambda.mdx:79-80 docs/develop/python/workers/serverless-workers/aws-lambda.mdx:145-148 -->

- The package is `temporalio.contrib.aws.lambda_worker` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 -->.
- The OTel module is `temporalio.contrib.aws.lambda_worker.otel` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:148 -->.
- `WorkerDeploymentVersion` and `VersioningBehavior` live in `temporalio.common` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:47 docs/develop/python/workers/serverless-workers/aws-lambda.mdx:80 -->.

## Minimum Worker code

`run_worker` takes a `WorkerDeploymentVersion` and a `configure` callback, and returns a Lambda handler <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:67 -->. Bind that handler to a module-level name (typically `lambda_handler`) so AWS can invoke it.

```python
# lambda_function.py
from activities import hello_activity
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
from workflows import TASK_QUEUE, SampleWorkflow


def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = TASK_QUEUE
    config.worker_config["workflows"] = [SampleWorkflow]
    config.worker_config["activities"] = [hello_activity]


lambda_handler = run_worker(
    WorkerDeploymentVersion(deployment_name="my-app", build_id="build-1"),
    configure,
)
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:43-65 -->

`LambdaWorkerConfig` is a dataclass whose `worker_config` field accepts the same keyword arguments as the `Worker` constructor <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:72-73 -->. The `deployment_name` groups related Workers across versions; the `build_id` identifies a specific release of your Worker code <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:68-69 -->. Worker Versioning is required for Serverless Workers <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:70 -->.

### Versioning behavior

Every Workflow must declare a versioning behavior — either `PINNED` or `AUTO_UPGRADE` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:75 -->. Set it per-Workflow in the decorator, or set a Worker-level default with `default_versioning_behavior` in `worker_config` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:76 -->.

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior


@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class MyWorkflow:
    @workflow.run
    async def run(self, input: str) -> str:
        ...
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:78-88 -->

## Connection configuration

`lambda_worker` automatically loads Temporal client configuration from a TOML config file and environment variables <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:92 -->. The config file is resolved in this order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional — if absent, only environment variables are used <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:94-100 -->.

Common env vars used by Lambda Workers (also documented under the deployment guide's env-var table) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:316-327 -->:

| Variable | Purpose |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g. `<namespace>.<account>.tmprl.cloud:7233`) |
| `TEMPORAL_NAMESPACE` | Temporal Namespace |
| `TEMPORAL_API_KEY` | API key authentication |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | TLS client cert for mTLS |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | TLS client key for mTLS |
| `TEMPORAL_TASK_QUEUE` | Overrides the Task Queue set in code |

For the full env-var list, file format, and profiles, see the [Environment configuration](https://docs.temporal.io/develop/environment-configuration) page <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:329-331 -->. Encrypt sensitive values (TLS keys, API keys) at rest using [Lambda envvar encryption](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html) <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:102 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:333-334 -->.

## Lambda-tuned defaults

`lambda_worker` pre-populates `LambdaWorkerConfig` with conservative defaults suited to short-lived Lambda invocations <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:106-107 -->:

| Setting | Lambda default |
|---|---|
| `max_concurrent_activities` | 2 |
| `max_concurrent_workflow_tasks` | 10 |
| `max_concurrent_local_activities` | 2 |
| `max_concurrent_nexus_tasks` | 5 |
| `workflow_task_poller_behavior` | `SimpleMaximum(2)` |
| `activity_task_poller_behavior` | `SimpleMaximum(1)` |
| `nexus_task_poller_behavior` | `SimpleMaximum(1)` |
| `graceful_shutdown_timeout` | 5 seconds |
| `max_cached_workflows` | 30 |
| `disable_eager_activity_execution` | Always `True` |
| `shutdown_deadline_buffer` | 7 seconds |

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:109-121 -->

- `disable_eager_activity_execution` is always `True` and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:123-124 -->.
- `shutdown_deadline_buffer` is specific to the `lambda_worker` package. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `graceful_shutdown_timeout` + 2 seconds (5 + 2 = 7) <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:126-128 -->.

### Tuning for long-running Activities

If a Worker handles long-running Activities, raise `graceful_shutdown_timeout`, `shutdown_deadline_buffer`, and the Lambda invocation deadline (`--timeout`) together <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:130 -->. The encyclopedia's [Tuning for long-running Activities](https://docs.temporal.io/serverless-workers#tuning-for-long-running-activities) section explains the relationship between these three values <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:131 docs/encyclopedia/workers/serverless-workers.mdx:170-202 -->.

## Build and package

Install dependencies into a local directory using `--platform` to fetch Linux-compatible wheels for the Lambda runtime <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:207-208 -->:

```bash
pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: temporalio
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:210-212 -->

To include OpenTelemetry support, install the `lambda-worker-otel` extra instead:

```bash
pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: 'temporalio[lambda-worker-otel]'
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:214-215 -->

Zip the dependencies together with your application code:

```bash
cd package && zip -r ../function.zip . && cd ..
zip function.zip lambda_function.py my_workflows.py my_activities.py
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:219-222 -->

## Deploy with `aws lambda create-function`

```bash
aws lambda create-function \
  --function-name my-temporal-worker \
  --runtime python3.13 \
  --handler lambda_function.lambda_handler \
  --role <EXECUTION_ROLE_ARN> \
  --zip-file fileb://function.zip \
  --timeout 600 \
  --memory-size 256 \
  --environment '{"Variables":{"TEMPORAL_ADDRESS":"<your-temporal-address>:7233","TEMPORAL_NAMESPACE":"<your-namespace>","TEMPORAL_API_KEY":"<your-api-key>"}}'
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:272-282 -->

- `--runtime`: use `python3.13` or another supported Python version <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:287 -->.
- `--handler`: in `module.function` format. It must point to the handler returned by `run_worker` (above example: `lambda_function.lambda_handler`) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:288 -->.
- `--timeout`: invocation deadline in seconds. Set high enough for the Worker to start, process Tasks, and shut down gracefully <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:320 -->.
- `--role`: the Lambda **execution role**. This is a separate role from the IAM **invocation role** Temporal assumes (see next section). The execution role must have at least `AWSLambdaBasicExecutionRole` attached <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 -->.

To redeploy after a code change:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:338-342 -->

> **Lambda versioning.** Maintain a 1-to-1 mapping between each build ID in your Worker code and a Lambda function version. If using an unversioned Lambda, do not change the build ID in your Worker code without also creating a new Worker Deployment Version <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:344-351 -->.

## IAM for Temporal invocation (Cloud)

For Temporal Cloud, Temporal needs permission to invoke your Lambda function. The Temporal server assumes an IAM role in your AWS account to call `lambda:InvokeFunction`. The trust policy on that role uses an External ID condition to prevent confused-deputy attacks <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:359-361 -->.

Deploy the CloudFormation template from the deployment guide to create the invocation role <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:363-364 -->. Parameters:

| Parameter | Purpose |
|---|---|
| `AssumeRoleExternalId` | Any string you choose; pass the same value when creating the Worker Deployment Version |
| `LambdaFunctionARNs` | Comma-separated Lambda function ARNs the role may invoke |
| `RoleName` | Base name for the created IAM role (defaults to `Temporal-Cloud-Serverless-Worker`) |

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:366-370 -->

After deploying the CloudFormation stack, retrieve the role ARN from its outputs and use it when configuring the Worker Deployment Version below <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:491-497 -->.

> **Two roles, one job each.** The Lambda **execution role** (passed via `aws lambda create-function --role`) is the role Lambda assumes when running your function. The **invocation role** (created by the CloudFormation template, passed via `--aws-lambda-assume-role-arn`) is the role Temporal Cloud assumes to call `lambda:InvokeFunction`. They are not interchangeable <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:518-520 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:558 -->.

For self-hosted Temporal Service deployments, see the self-hosted setup guide for a different CloudFormation template <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:355-357 -->.

## Create the Worker Deployment Version

A Worker Deployment Version with a compute provider tells Temporal how to invoke your Worker. The deployment name and build ID must match the values in your Worker code <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:501-504 -->.

### Via the Temporal UI

The UI flow creates the version and **automatically sets it as current** <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:524-525 -->. In the Namespace, open **Workers > Create Worker Deployment**, fill in Name, Build ID, Lambda ARN, IAM Role ARN (the invocation role ARN), and External ID, then **Save** <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:511-522 -->.

### Via the Temporal CLI

First create the deployment if it doesn't exist:

```bash
temporal worker deployment create \
  --namespace <YOUR_NAMESPACE> \
  --name my-app
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:535-539 -->

Then create the version with the compute provider configuration:

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:543-551 -->

| Flag | Purpose |
|---|---|
| `--deployment-name` | Must match `deployment_name` in `WorkerDeploymentVersion` in your code |
| `--build-id` | Must match `build_id` in `WorkerDeploymentVersion` in your code |
| `--aws-lambda-function-arn` | ARN of the Lambda function Temporal invokes for this version |
| `--aws-lambda-assume-role-arn` | The invocation role ARN (CloudFormation `RoleARN` output) — **not** the Lambda execution role |
| `--aws-lambda-assume-role-external-id` | Same External ID passed to the CloudFormation template |

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:553-559 -->

When using the CLI you must also **set the version as current** in a separate step (the UI does this automatically) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:530-531 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:568-573 -->:

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:575-579 -->

To verify Temporal can reach the Lambda, use **Workers > Deployments > select your deployment > Actions > Validate Connection** <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:564-566 -->.

## OpenTelemetry observability

The `temporalio.contrib.aws.lambda_worker.otel` module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:135 -->. When enabled, the Worker emits SDK metrics and distributed traces for Workflow and Activity executions; the ADOT layer forwards traces to AWS X-Ray and metrics to Amazon CloudWatch <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:136-137 -->.

The simplest entry point is `apply_defaults(config)`, which configures both metrics and tracing <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:166 -->. If you only need one or the other, use `build_metrics_telemetry_config` or `apply_tracing` individually <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:233 -->.

```python
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults
from workflows import TASK_QUEUE, SampleWorkflow
from activities import hello_activity


def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = TASK_QUEUE
    config.worker_config["workflows"] = [SampleWorkflow]
    config.worker_config["activities"] = [hello_activity]
    apply_defaults(config)


lambda_handler = run_worker(
    WorkerDeploymentVersion(deployment_name="my-app", build_id="build-1"),
    configure,
)
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:142-164 -->

By default telemetry is sent to `localhost:4317`, which is the ADOT Lambda layer's collector endpoint <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:167 -->. Attach the ADOT Python Lambda layer to the function to receive telemetry on that endpoint — the layer bundles both auto-instrumentation and an OpenTelemetry Collector that forwards to AWS X-Ray and CloudWatch <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:169-170 -->.

### Custom Collector config

The ADOT layer's default Collector config does not route OTLP data into the traces pipeline. Bundle a custom `otel-collector-config.yaml` in the deployment package that wires the OTLP receiver to both the traces and metrics pipelines <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:172-174 -->:

```yaml
receivers:
    otlp:
        protocols:
            grpc:
                endpoint: "localhost:4317"
            http:
                endpoint: "localhost:4318"

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
            level: debug
        metrics:
            address: localhost:8888
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:178-214 -->

Set the env var on the Lambda function:

```
OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/otel-collector-config.yaml
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:219 -->

> The Python env var is `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` (`_FILE`, pointing to an absolute filesystem path). This is a Python-specific spelling — other Temporal SDKs use a `_URI` variant.

### Enable X-Ray active tracing

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:223-227 -->

### Required IAM permissions for OTel

The Lambda **execution role** must have permissions to write to X-Ray and CloudWatch. Either attach the `AWSXRayDaemonWriteAccess` managed policy, or add `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` individually <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:229-230 -->. Without these permissions, the Collector fails silently and no telemetry appears <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:231 -->.

## Common pitfalls

- **Deployment name / build ID mismatch.** The values in `WorkerDeploymentVersion(...)` in your code must exactly match `--deployment-name` and `--build-id` on the Worker Deployment Version. A mismatch causes an invocation loop: WCI invokes the Lambda, the Worker polls with a different version than expected, the Task isn't processed, and WCI invokes again <!-- docs/troubleshooting/serverless-workers.mdx:154-168 -->.
- **Forgetting `set-current-version`.** When creating the version via CLI, you must run `temporal worker deployment set-current-version`; otherwise Tasks don't route to the version and the Lambda is never invoked. The UI does this automatically <!-- docs/troubleshooting/serverless-workers.mdx:86-92 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:568-573 -->.
- **Conflating execution role with invocation role.** The role on `aws lambda create-function --role` (execution role) is **not** the role passed to `--aws-lambda-assume-role-arn` (invocation role). Reusing the wrong ARN is a frequent cause of connection-validation failures <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:558 -->.
- **Manually invoking the Lambda before creating the Worker Deployment Version with a compute provider.** Polling registers the version on the server, but if no compute provider is configured, no WCI Workflow is created and the Lambda is never automatically invoked thereafter. Fix it by creating or updating the Worker Deployment Version with the `--aws-lambda-*` flags <!-- docs/troubleshooting/serverless-workers.mdx:78-84 -->.
- **First-invocation failure prevents Task Queue binding.** When a version is created, the WCI runs a validation invocation. If that fails (missing env vars, bad TLS config, missing dependencies), no Task Queue binding is established. Invoke the Lambda manually from the AWS Console to surface the error <!-- docs/troubleshooting/serverless-workers.mdx:113-121 -->.
- **Wrong OTel env var name.** Python uses `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` (filesystem path). Don't substitute the `_URI` variant from other SDKs <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:219 -->.
- **Trying to override `disable_eager_activity_execution`.** It is forced to `True` by the package and cannot be changed <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:120 docs/develop/python/workers/serverless-workers/aws-lambda.mdx:123-124 -->.

## See also

- [Deploy a Serverless Worker on AWS Lambda](https://docs.temporal.io/production-deployment/worker-deployments/serverless-workers/aws-lambda) — end-to-end deployment walkthrough.
- [Serverless Workers (concept)](https://docs.temporal.io/serverless-workers) — Worker Controller Instance, autoscaling, lifecycle, constraints.
- [Troubleshoot Serverless Workers](https://docs.temporal.io/troubleshooting/serverless-workers) — diagnostic flow from "is the Lambda being invoked?" through Task Queue binding and version-mismatch loops.
