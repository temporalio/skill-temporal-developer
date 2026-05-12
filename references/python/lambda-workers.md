# Python SDK Lambda Workers

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:22-29 -->

This reference covers running a Temporal Serverless Worker on AWS Lambda using the Python SDK's `lambda_worker` contrib package. For cross-SDK concepts (Worker Deployment Versions, CloudFormation IAM, `temporal worker deployment create-version`, verification), see `references/core/lambda-workers.md`.

## Package and entry point

The contrib package is `temporalio.contrib.aws.lambda_worker`. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 --> Use `run_worker` to produce a Lambda handler that runs a Temporal Worker. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:40 -->

```python
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
<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:46-64 -->

- `run_worker` takes a `WorkerDeploymentVersion` and a configure callback, and returns a Lambda handler. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:67 -->
- The `configure` callback receives a `LambdaWorkerConfig` dataclass; set the Task Queue, Workflows, and Activities through `worker_config`, which accepts the same keyword arguments as the `Worker` constructor. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:72-73 -->
- `lambda_handler` is just the variable name in the sample — the handler value is whatever `run_worker` returns. Reference it in your Lambda `--handler` flag as `module.handler-variable`.

## Versioning behavior

Worker Versioning is required for Serverless Workers. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:70 --> Every Workflow must declare a versioning behavior of either `PINNED` or `AUTO_UPGRADE`. Set it per-Workflow in the `@workflow.defn` decorator, or set a worker-level default via `default_versioning_behavior` in the worker config. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:75-76 -->

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior


@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class MyWorkflow:
    @workflow.run
    async def run(self, input: str) -> str:
        ...
```
<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:79-88 -->

## Temporal connection configuration

The `lambda_worker` package automatically loads Temporal client configuration from a TOML config file and environment variables. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:92 --> The config file is resolved in this order: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:94 -->

1. The `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:96-98 -->

The file is optional; if absent, only environment variables are used. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:100 -->

## Lambda-tuned defaults

The `lambda_worker` package applies conservative defaults suited to short-lived Lambda invocations. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:106 -->

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

<!-- Sources: docs/develop/python/workers/serverless-workers/aws-lambda.mdx:109-121 -->

`disable_eager_activity_execution` is always `True` and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:123-124 -->

## `shutdown_deadline_buffer`

`shutdown_deadline_buffer` is specific to the `lambda_worker` package. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `graceful_shutdown_timeout + 2 seconds`. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:126-128 -->

If your Worker handles long-running Activities, increase `graceful_shutdown_timeout`, `shutdown_deadline_buffer`, and the Lambda invocation deadline (`--timeout`) together. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:130 -->

## OpenTelemetry integration

The `temporalio.contrib.aws.lambda_worker.otel` module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:135 --> Call `apply_defaults(config)` inside your `configure` callback to wire up both metrics and tracing.

```python
from activities import hello_activity
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults
from workflows import TASK_QUEUE, SampleWorkflow


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
<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:145-163 -->

- `apply_defaults` configures both metrics and tracing. By default, telemetry is sent to `localhost:4317`, the ADOT Lambda layer's default collector endpoint. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:166-167 -->
- If you only need metrics or tracing, use `build_metrics_telemetry_config` or `apply_tracing` individually. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:233 -->
- Attach the ADOT Python Lambda layer to your Lambda function for auto-instrumentation and a bundled OpenTelemetry Collector that receives telemetry on `localhost:4317` and forwards traces to AWS X-Ray and metrics to Amazon CloudWatch. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:169-170 -->

### OTel Collector config

The ADOT layer's default Collector configuration does not route OTLP data to the traces pipeline. You must provide a custom Collector configuration that wires the OTLP receiver to both the traces and metrics pipelines. Bundle the following `otel-collector-config.yaml` in your Lambda deployment package: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:172-174 -->

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
        # AWS EMF exporter for metrics
        # These are example configurations
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

### Collector config env var

Point the ADOT layer at your bundled config by setting this environment variable on the Lambda function: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:217-219 -->

```
OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/otel-collector-config.yaml
```

> Note: Python uses `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` (the `..._FILE` form). The `..._URI` form belongs to other SDKs and is not used here.

### Enable X-Ray active tracing

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```
<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:223-227 -->

The Lambda execution role must have permissions to write to X-Ray and CloudWatch. Attach the `AWSXRayDaemonWriteAccess` managed policy, or add `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without these permissions, the Collector fails silently and no telemetry appears. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:229-231 -->

## Build and package

Install dependencies into a local directory for packaging. Use `--platform` to fetch Linux-compatible binaries for the Lambda runtime: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:207-208 -->

```bash
pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: temporalio
```
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:211 -->

To include OpenTelemetry support, install `temporalio[lambda-worker-otel]` instead. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:214-215 -->

Package the dependencies and your application code into a zip file: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:217 -->

```bash
cd package && zip -r ../function.zip . && cd ..
zip function.zip lambda_function.py my_workflows.py my_activities.py
```
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:220-221 -->

## Deploy

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
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:273-282 -->

- `--runtime`: use `python3.13` or another supported Python version. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:287 -->
- `--handler`: entry point in `module.function` format. Must point to the handler returned by `run_worker` — for example, `lambda_function.lambda_handler` matches the `lambda_handler` variable in `lambda_function.py`. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:288 -->
- Environment variables for connection: `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_API_KEY`. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:281 -->

To update an existing function with new code:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```
<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:339-342 -->

## Cross-SDK steps

For CloudFormation IAM setup (the role Temporal assumes to invoke your Lambda), creating the Worker Deployment Version with `temporal worker deployment create-version`, setting the version as current, and verifying the deployment, see `references/core/lambda-workers.md`.

For general Python observability concepts (metrics, tracing, logging), see `references/python/observability.md`.
