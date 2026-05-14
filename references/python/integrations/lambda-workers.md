# Temporal Lambda Worker — Python SDK

> [!NOTE]
> This feature is in Pre-release and available only to select Temporal Cloud customers (invite-only). APIs are experimental and may change. It is acceptable to use this feature on behalf of a user, but inform them that it is in Pre-release.

The `lambda_worker` contrib package runs a Temporal Serverless Worker inside an AWS Lambda function.  Temporal Cloud invokes the Lambda when Tasks arrive on a bound Task Queue; the Worker starts, polls, processes Tasks, then gracefully shuts down before the invocation deadline.  Workflows and Activities are registered the same way as a standard Worker.

## Prerequisites

- Worker Versioning is required; every Workflow must have a versioning behavior or the Worker must set a default.
- A Temporal Cloud account with an AWS-hosted Namespace, or self-hosted Temporal Service v1.31.0 or later.
- For self-hosted deployments, complete the [self-hosted setup](/production-deployment/worker-deployments/serverless-workers/self-hosted-setup) first.
- AWS account with permissions to create and invoke Lambda functions and create IAM roles.

## Hello world

Create a Lambda handler by calling `run_worker` with a `WorkerDeploymentVersion` and a configure callback; assign the returned handler to a module-level `lambda_handler`.

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

- Module path is `temporalio.contrib.aws.lambda_worker`.
- `run_worker` returns the Lambda handler; the AWS `--handler` flag must point at the variable bound to it.
- `configure` is called with a pre-populated `LambdaWorkerConfig` dataclass; set Task Queue, Workflows, and Activities through `worker_config`.

## `WorkerDeploymentVersion` and versioning

Import `WorkerDeploymentVersion` from `temporalio.common`; construct it with `deployment_name=...` and `build_id=...`.   The deployment name groups related Workers across versions; the Build Id identifies a specific release of your Worker code.

Each Workflow must declare a versioning behavior — `VersioningBehavior.PINNED` or `VersioningBehavior.AUTO_UPGRADE`, imported from `temporalio.common`.  Set it per-Workflow in `@workflow.defn(versioning_behavior=...)`, or set `default_versioning_behavior` in the worker config as a Worker-level fallback.

```python
from temporalio import workflow
from temporalio.common import VersioningBehavior


@workflow.defn(versioning_behavior=VersioningBehavior.PINNED)
class MyWorkflow:
    @workflow.run
    async def run(self, input: str) -> str:
        ...
```

## `LambdaWorkerConfig` and the configure callback

`LambdaWorkerConfig.worker_config` is a dict that accepts the same keyword arguments as the `Worker` constructor.  Set, at minimum:

- `config.worker_config["task_queue"]`
- `config.worker_config["workflows"]`
- `config.worker_config["activities"]`

Don't overwrite the entire dict — mutate keys on the dataclass field so Lambda-tuned defaults are preserved.

## Configure the Temporal connection

The `lambda_worker` package automatically loads Temporal client configuration from a TOML config file and environment variables.  See [Environment configuration](/develop/environment-configuration) for the full list of variables and profiles.

Config file resolution order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used.  Encrypt sensitive values like TLS keys and API keys at rest.

## Lambda-tuned defaults

The `lambda_worker` package applies conservative defaults suited to short-lived Lambda invocations.  Transcribed verbatim:

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

- `disable_eager_activity_execution` is always `True` and cannot be overridden — Eager Activities require a persistent connection that Lambda invocations don't maintain.
- `shutdown_deadline_buffer` is specific to `lambda_worker`; it controls how much time before the Lambda deadline the Worker begins graceful shutdown. Default is `graceful_shutdown_timeout` + 2 seconds.

## Worker lifecycle and tuning

Each invocation has three phases: init (initialize and connect to Temporal), work (poll Task Queue and process Tasks), and shutdown (stop polling, drain in-flight Tasks, run shutdown hooks).

For long-running Activities, raise three values together — raising only one breaks the chain:

- **Worker stop timeout > longest Activity runtime** — gives in-flight Activities time to finish after polling stops.
- **`shutdown_deadline_buffer` > Worker stop timeout + shutdown hook time** — ensures drain and shutdown hooks complete before the compute provider terminates the environment.
- **Invocation deadline (`--timeout`) > longest Activity runtime + shutdown deadline buffer** — set on the Lambda function.

If the longest Activity runs longer than half the maximum invocation deadline, use [Activity Heartbeats](/encyclopedia/detecting-activity-failures#activity-heartbeat) instead so the next retry resumes from the recorded state.

## OpenTelemetry

The `temporalio.contrib.aws.lambda_worker.otel` module provides OpenTelemetry integration with defaults configured for the [AWS Distro for OpenTelemetry (ADOT)](https://aws-otel.github.io/docs/getting-started/lambda) Lambda layer.  Use it to emit SDK metrics and distributed traces for Workflow and Activity executions.

```python
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults


def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = TASK_QUEUE
    config.worker_config["workflows"] = [SampleWorkflow]
    config.worker_config["activities"] = [hello_activity]
    apply_defaults(config)
```

- `apply_defaults(config)` configures both metrics and tracing; default endpoint is `localhost:4317`, the ADOT Lambda layer's default Collector endpoint.
- If you only need metrics, use `build_metrics_telemetry_config`; for tracing only, use `apply_tracing`.
- Optional install extra: `temporalio[lambda-worker-otel]`.
- Attach the [ADOT Python Lambda layer](https://aws-otel.github.io/docs/getting-started/lambda/lambda-python).
- The default Collector configuration does not route OTLP data to the traces pipeline; bundle a custom `otel-collector-config.yaml` in the deployment package that wires the OTLP receiver to both traces and metrics pipelines.
- Set environment variable `OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/otel-collector-config.yaml` on the Lambda function.
- Enable X-Ray active tracing: `aws lambda update-function-configuration --function-name <name> --tracing-config Mode=Active`.
- The Lambda execution role must have permissions to write to X-Ray and CloudWatch. Attach the `AWSXRayDaemonWriteAccess` managed policy, or add `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData`. Without these, the Collector fails silently and no telemetry appears.

## Deploy

### Build and package

Install dependencies for the Lambda Linux runtime using `--platform` to fetch Linux-compatible binaries:

```bash
pip install --target ./package --platform manylinux2014_x86_64 --only-binary=:all: temporalio
```

For OpenTelemetry support, install `temporalio[lambda-worker-otel]` instead.

Package dependencies and application code into a zip:

```bash
cd package && zip -r ../function.zip . && cd ..
zip function.zip lambda_function.py my_workflows.py my_activities.py
```

### Create the Lambda function

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

- `--runtime python3.13` (or another supported Python version).
- `--handler lambda_function.lambda_handler` — `module.function` format pointing at the handler returned by `run_worker`.
- `--role` is the Lambda execution role (separate from the role Temporal assumes to invoke the function); must have at least `AWSLambdaBasicExecutionRole`.
- `--timeout` is the invocation deadline in seconds; set it high enough for init, work, and graceful shutdown.

### Environment variables

| Variable | Description |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`). |
| `TEMPORAL_NAMESPACE` | Temporal Namespace. |
| `TEMPORAL_TASK_QUEUE` | Task Queue name. Overrides the value set in code. |
| `TEMPORAL_API_KEY` | API key for API key authentication. |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | Path to TLS client certificate for mTLS. |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | Path to TLS client key for mTLS. |

### Redeploy code

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

Create a 1-to-1 mapping between each Build Id in your Worker code and a Lambda function version. If you use an unversioned Lambda, don't change the Build Id without also creating a new Worker Deployment Version.

### Configure IAM for Temporal invocation

Temporal needs permission to invoke your Lambda. Deploy the CloudFormation template from the [deploy guide](/production-deployment/worker-deployments/serverless-workers/aws-lambda#configure-iam) to create the invocation role with an External ID condition.

### Create the Worker Deployment Version

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

- `--deployment-name` and `--build-id` must exactly match the `deployment_name` and `build_id` in your Worker code.
- `--aws-lambda-assume-role-arn` is the role Temporal assumes (from the CloudFormation stack output), not the Lambda execution role.

### Set the version as current

CLI-created versions are not current automatically; set the version as current or Tasks will not route to it.

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

## Constraints

- Activity duration must complete within the Lambda invocation limit minus the shutdown deadline buffer; AWS Lambda's maximum is 15 minutes.
- Workflow duration has no limit — Workflows span as many invocations as needed.
- Worker Versioning is required; every Workflow needs `AUTO_UPGRADE` or `PINNED`.
- Eager Activities are always disabled (`disable_eager_activity_execution=True`); features that require a persistent connection are unavailable.
- Each invocation creates a fresh client connection — no connection reuse or shared state.

## Common mistakes and troubleshooting

- **Rapid invocation loop with no Workflow progress** — the `deployment_name` or `build_id` in your code doesn't match the Worker Deployment Version. The WCI invokes the Lambda, the Worker polls under a different deployment version, the Task isn't processed, the WCI invokes again. Fix the values in code and redeploy.
- **Lambda is invoked but Task Queue never binds** — the first invocation after creating the Worker Deployment Version failed (missing env vars, wrong TLS, missing dependencies). Without a successful poll, no Task Queue binding is created. Invoke the Lambda manually from the AWS Console to see the error directly.
- **Lambda not being invoked at all** — verify the version has a compute provider configured and use **Workers > Deployments > Actions > Validate Connection** to confirm Temporal can assume the role and invoke the function.
- **Version created via CLI but no invocations** — confirm the version is set as current with `temporal worker deployment describe`.
- **List WCI Workflows** in a Namespace: query `TemporalNamespaceDivision = "TemporalWorkerControllerInstance"`. WCI Workflow IDs follow the pattern `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`.
- **Connection/TLS/auth errors during startup** — verify `TEMPORAL_ADDRESS`, `TEMPORAL_API_KEY` (or `temporal.toml`) are correct on the Lambda function.
- **Activities abandoned mid-execution** — the Lambda timeout fired before the Worker finished. Increase Lambda `--timeout` and `shutdown_deadline_buffer` together per the [tuning rules](#worker-lifecycle-and-tuning).
