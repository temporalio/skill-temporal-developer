# Lambda Workers — Python SDK

The `lambda_worker` contrib package <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:31 --> runs a Temporal Serverless Worker on AWS Lambda. Each invocation starts a Worker, polls for Tasks, then gracefully shuts down before the invocation deadline. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:33 -->

Serverless Workers are in Pre-release; APIs are experimental and may change. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:24-26 -->

For shared concepts (WCI, lifecycle, IAM, deployment, troubleshooting), see `references/core/lambda-workers.md`.

## Package and entry point

Import path: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:48 -->

```python
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
```

`run_worker` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:40 --> takes a `WorkerDeploymentVersion` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:41 --> and a configure callback, and returns a Lambda handler. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:67 -->

The `WorkerDeploymentVersion` identifies the Worker Deployment and Build ID for this Worker. Worker Versioning is required for Serverless Workers. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:68-70 -->

### Canonical example

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:45-64 -->

```py
from activities import hello_activity
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
# ...
from workflows import TASK_QUEUE, SampleWorkflow


def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = TASK_QUEUE
    config.worker_config["workflows"] = [SampleWorkflow]
    config.worker_config["activities"] = [hello_activity]
# ...


lambda_handler = run_worker(
    WorkerDeploymentVersion(deployment_name="my-app", build_id="build-1"),
    configure,
)
```

## The configure callback

The `configure` callback receives a `LambdaWorkerConfig` dataclass with fields pre-populated with Lambda-appropriate defaults. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:72 --> Set the Task Queue, Workflows, and Activities through `worker_config`, which accepts the same keyword arguments as the `Worker` constructor. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:73 -->

Keys used in the canonical example: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:54-56 -->

- `config.worker_config["task_queue"]`
- `config.worker_config["workflows"]`
- `config.worker_config["activities"]`

## Versioning behavior

Each Workflow must have a versioning behavior, either `PINNED` or `AUTO_UPGRADE`. Set it per-Workflow in the `@workflow.defn` decorator, or set a worker-level default with `default_versioning_behavior` in the worker config. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:75-76 -->

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:78-88 -->

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior


@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class MyWorkflow:
    @workflow.run
    async def run(self, input: str) -> str:
        ...
```

## Configure the Temporal connection

The `lambda_worker` package automatically loads Temporal client configuration from a TOML config file and environment variables. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:92 -->

Config file resolution order: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:94-98 -->

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional. If absent, only environment variables are used. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:100 --> Encrypt sensitive values like TLS keys or API keys. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:102 -->

## Lambda-tuned defaults

The `lambda_worker` package applies conservative defaults suited to short-lived Lambda invocations. These differ from standard Worker defaults to avoid overcommitting resources in a constrained environment. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:106-107 -->

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:109-121 -->

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

`disable_eager_activity_execution` is always `True` and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:123-124 -->

`shutdown_deadline_buffer` is specific to the `lambda_worker` package. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `graceful_shutdown_timeout` + 2 seconds. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:126-128 -->

For long-running Activities, increase `graceful_shutdown_timeout`, `shutdown_deadline_buffer`, and the Lambda invocation deadline (`--timeout`) together. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:130 -->

## OpenTelemetry

The `lambda_worker.otel` module <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:135 --> provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer. The Worker emits SDK metrics and distributed traces for Workflow and Activity executions. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:135-137 -->

Import: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:148 -->

```python
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults
```

### Canonical OTel sample

<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:144-163 -->

```py
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

`apply_defaults` configures both metrics and tracing. By default, telemetry is sent to `localhost:4317`, which is the ADOT Lambda layer's default collector endpoint. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:166-167 -->

If you only need metrics or tracing, use `build_metrics_telemetry_config` or `apply_tracing` individually. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:233 -->

### Collector configuration

Attach the [ADOT Python Lambda layer](https://aws-otel.github.io/docs/getting-started/lambda/lambda-python) to your Lambda function. The layer includes auto-instrumentation and an OpenTelemetry Collector that receives telemetry on `localhost:4317` and forwards traces to AWS X-Ray and metrics to Amazon CloudWatch. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:169-170 -->

The default Collector configuration does not route OTLP data to the traces pipeline. You must provide a custom Collector configuration that wires the OTLP receiver to both the traces and metrics pipelines. Bundle an `otel-collector-config.yaml` in your Lambda deployment package. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:172-174 -->

Set the following environment variable on the Lambda function: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:217 -->

- `OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/otel-collector-config.yaml` <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:219 -->

Note: Python uses `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` (a file path), not a URI variant.

Enable X-Ray active tracing: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:221 -->

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```
<!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:224-227 -->

### IAM permissions for telemetry

The Lambda execution role must have permissions to write to X-Ray and CloudWatch. Attach the `AWSXRayDaemonWriteAccess` managed policy, or add `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without these permissions, the Collector fails silently and no telemetry appears. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:229-231 -->
