# Lambda Worker (Python `lambda_worker` contrib)

## Overview

The `lambda_worker` contrib package lets you run a Temporal Serverless Worker on AWS Lambda.
You deploy your Worker code as a Lambda function, and Temporal Cloud invokes it when Tasks arrive; each invocation starts a Worker, polls for Tasks, then gracefully shuts down before a configurable invocation deadline.
You register Workflows and Activities the same way you would with a standard Worker.
Serverless Workers are in Pre-release and available to select Temporal Cloud customers; APIs are experimental and may be subject to backwards-incompatible changes.

## Install / package path

The Python import path is `temporalio.contrib.aws.lambda_worker`.
The OpenTelemetry sub-module is `temporalio.contrib.aws.lambda_worker.otel`.

Install the base SDK:

```bash
pip install temporalio
```

To include OpenTelemetry support, install the optional extra:

```bash
pip install 'temporalio[lambda-worker-otel]'
```

## Minimal Worker code

Use `run_worker` to create a Lambda handler.
Pass a `WorkerDeploymentVersion` and a `configure` callback that registers Workflows and Activities through `worker_config`.
The return value of `run_worker` is the Lambda handler — name it `lambda_handler`.

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

The `WorkerDeploymentVersion` identifies the Worker Deployment and Build ID for this Worker; the deployment name groups related Workers across versions, and the Build Id identifies a specific release of your Worker code.
The `configure` callback receives a `LambdaWorkerConfig` dataclass with fields pre-populated with Lambda-appropriate defaults; set the Task Queue, Workflows, and Activities through `worker_config`, which accepts the same keyword arguments as the `Worker` constructor.

## Worker Versioning is required

Worker Versioning is required for Serverless Workers.
Each Workflow must have a versioning behavior of either `PINNED` or `AUTO_UPGRADE`; set it per-Workflow in the `@workflow.defn` decorator, or set a worker-level default with `default_versioning_behavior` in the worker config.

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

The `lambda_worker` package automatically loads Temporal client configuration from a TOML config file and environment variables.
See the Environment Configuration documentation (`docs/develop/environment-configuration`) for the full list of supported environment variables and config file format.

The config file is resolved in this order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional. If absent, only environment variables are used.

Encrypt sensitive values like TLS keys or API keys; see the AWS documentation on Lambda env var encryption for options.

## Lambda-tuned defaults

The `lambda_worker` package applies conservative defaults suited to short-lived Lambda invocations; these differ from standard Worker defaults to avoid overcommitting resources.

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

`disable_eager_activity_execution` is always `True` and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain.

`shutdown_deadline_buffer` is specific to the `lambda_worker` package; it controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `graceful_shutdown_timeout` + 2 seconds.

## Tuning for long-running Activities

If your Worker handles long-running Activities, set these three values together:

- **Worker stop timeout > longest Activity runtime.** Gives in-flight Activities enough time to finish after polling stops.
- **Shutdown deadline buffer > Worker stop timeout + shutdown hook time.** Ensures the drain and any shutdown hooks complete before the compute provider terminates the environment.
- **Invocation deadline > longest Activity runtime + shutdown deadline buffer.** Set on the compute provider to give each invocation enough total runtime.

If your longest-running Activity runs longer than half the maximum invocation deadline, this constraint may be difficult or impossible to meet — in that case, use Activity Heartbeats to record state so the next retry can pick up where it left off.

Raising only the shutdown deadline buffer makes the Worker stop polling earlier, but does not give in-flight Tasks any more time to complete.
Raising only the Worker stop timeout does not make the Worker stop polling earlier, so the compute provider may terminate the Worker before the full stop timeout completes.

For deeper background on the three-phase lifecycle (init / work / shutdown) and how these knobs interact, see `docs/encyclopedia/workers/serverless-workers.mdx` (Worker lifecycle and Tuning for long-running Activities).

## Observability with OpenTelemetry

The `lambda_worker.otel` module provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer.
With this enabled, the Worker emits SDK metrics and distributed traces for Workflow and Activity executions.

Call `apply_defaults(config)` inside the `configure` callback:

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

`apply_defaults` configures both metrics and tracing. By default, telemetry is sent to `localhost:4317`, which is the ADOT Lambda layer's default collector endpoint.

To collect this telemetry, attach the ADOT Python Lambda layer to your Lambda function.
The default Collector configuration does not route OTLP data to the traces pipeline; you must provide a custom Collector configuration that wires the OTLP receiver to both the traces and metrics pipelines.
Bundle an `otel-collector-config.yaml` in your Lambda deployment package; the docs include a reference config with OTLP receivers on `localhost:4317`/`localhost:4318` and `awsxray` / `awsemf` exporters.

Set the following environment variable on the Lambda function:

```
OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/otel-collector-config.yaml
```

Enable X-Ray active tracing on the Lambda function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must have permissions to write to X-Ray and CloudWatch. Attach the `AWSXRayDaemonWriteAccess` managed policy, or add `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without these permissions, the Collector fails silently and no telemetry appears.

If you only need metrics or tracing, use `build_metrics_telemetry_config` or `apply_tracing` individually.

## Deployment recipe

Install dependencies into a local directory for packaging; use `--platform` to fetch Linux-compatible binaries for the Lambda runtime:

```bash
pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: temporalio
```

Package dependencies and application code into a zip:

```bash
cd package && zip -r ../function.zip . && cd ..
zip function.zip lambda_function.py my_workflows.py my_activities.py
```

Create the Lambda function:

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

Notes on key flags:

- `--runtime python3.13` (or another supported Python version).
- `--handler lambda_function.lambda_handler` must point to the handler returned by `run_worker`.
- `--timeout` is the invocation deadline in seconds — set it high enough for the Worker to start, process Tasks, and shut down gracefully.
- Supported `TEMPORAL_*` env vars include `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`, `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, and `TEMPORAL_API_KEY`.

To update an existing function with new code:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

After the Lambda exists, register a Worker Deployment Version that points to it:

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

The IAM invocation role and CloudFormation steps live in the broader deploy guide (`docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx`); self-hosted setup (Temporal Service v1.31.0+, WCI dynamic config keys, server AWS credentials) is documented in `docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx`.

## Constraints

- **Activity duration:** must complete within the compute provider's invocation limit (minus shutdown deadline buffer). For AWS Lambda, the maximum is 15 minutes.
- **Workflow duration:** no limit. Workflows of any duration work, regardless of the invocation timeout; a Workflow runs across as many invocations as needed.
- **Eager Activities:** not supported — `disable_eager_activity_execution` is always `True` because Eager Activities require a persistent connection that Lambda invocations don't maintain.
- **Worker Versioning:** required. Each Workflow must have an `AUTO_UPGRADE` or `PINNED` behavior, set per-Workflow or as a Worker-level default.

## If invocations aren't happening

Start from the Lambda function's CloudWatch metrics or invocation logs to determine whether the Lambda is being invoked at all, then narrow down.

- **Validate the connection.** In the Temporal UI, go to **Workers > Deployments > select your deployment**, open **Actions** on the version, and click **Validate Connection** — this confirms Temporal can assume the invocation role and invoke the function.
- **Check that the version is set as current.** If you created the version via CLI, run `temporal worker deployment set-current-version` — without this, new Tasks won't route to the version.
- **First invocation failed, so binding never established.** When you create a Worker Deployment Version, the WCI invokes the Lambda to validate; if that first invocation fails (missing env vars, bad TLS, missing deps), the Worker never polls and no Task Queue binding is created. Diagnose by invoking the Lambda manually from the AWS Console.
- **Deployment name / build ID mismatch invocation loop.** Rapid, repeated invocations with no Workflow progress usually mean the `deployment_name`/`build_id` in your Lambda code don't match the Worker Deployment Version; compare against the WCI Workflow ID (`temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`) and `temporal worker deployment describe`.
- **Lambda timeout.** If the function hits its configured timeout before the Worker finishes, AWS terminates the invocation and Activities are abandoned mid-execution and retried; raise the Lambda `--timeout` and the Worker's shutdown buffer together per the tuning rules above.
