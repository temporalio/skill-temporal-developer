# Python SDK Serverless Workers

## Overview

Historically, Temporal Cloud hosts only the control plane and persistence — **you run your own workers** (Fargate, Cloud Run, Kubernetes, VMs). As of `temporalio` 1.25.0, the SDK ships a first-party **AWS Lambda worker** package that lets the Temporal Service invoke a Lambda function on demand to process Workflow, Activity, and Nexus tasks.

Status: **Pre-release / experimental.** Requires coordinated server-side support — check the release notes for current availability. Other serverless runtimes (Cloudflare Workers, Vercel, Supabase Edge Functions) are not supported.

## AWS Lambda Worker Quick Start

Package: `temporalio.contrib.aws.lambda_worker`. A single `run_worker` call handles the full per-invocation lifecycle: connect to the Temporal Service, create a worker with Lambda-tuned defaults, poll for tasks, and gracefully shut down before the invocation deadline.

```python
# handler.py
from temporalio.common import WorkerDeploymentVersion
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker

from my_workflows import MyWorkflow
from my_activities import my_activity


def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = "my-task-queue"
    config.worker_config["workflows"] = [MyWorkflow]
    config.worker_config["activities"] = [my_activity]


lambda_handler = run_worker(
    WorkerDeploymentVersion(
        deployment_name="my-service",
        build_id="v1.0",
    ),
    configure,
)
```

Set `handler.lambda_handler` as your Lambda function's handler entry point.

## Configuration

Client connection (address, namespace, TLS, API key) is loaded automatically via `temporalio.envconfig` from:

1. The file named by `TEMPORAL_CONFIG_FILE` env var, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional — environment variables alone are sufficient. `task_queue` in `worker_config` is pre-populated from `TEMPORAL_TASK_QUEUE` if set.

**In production, pull secrets from AWS Secrets Manager / SSM**, not from the TOML file bundled into the deployment package.

## Lambda-Tuned Defaults

`run_worker` applies conservative limits appropriate for Lambda resource constraints. Override any field in the `configure` callback.

| Setting | Default |
| --- | --- |
| `max_concurrent_activities` | 2 |
| `max_concurrent_workflow_tasks` | 10 |
| `max_concurrent_local_activities` | 2 |
| `max_concurrent_nexus_tasks` | 5 |
| `workflow_task_poller_behavior` | `SimpleMaximum(2)` |
| `activity_task_poller_behavior` | `SimpleMaximum(1)` |
| `nexus_task_poller_behavior` | `SimpleMaximum(1)` |
| `graceful_shutdown_timeout` | 5 seconds |
| `max_cached_workflows` | 100 |
| `disable_eager_activity_execution` | always `True` |

**Worker Deployment Versioning is always enabled** — the `WorkerDeploymentVersion` argument is required.

## Lambda Timeout

Set the Lambda function timeout long enough for the worker to pick up a task, execute it, and shut down gracefully. At minimum: `longest expected activity StartToClose timeout + graceful_shutdown_timeout (default 5s)`. **1 minute is the recommended floor.** If timeout is too short, the worker may be terminated before finishing in-flight tasks.

## Observability

Metrics and tracing are opt-in. The `otel` submodule provides helpers for AWS Distro for OpenTelemetry (ADOT):

```python
from temporalio.contrib.aws.lambda_worker import LambdaWorkerConfig, run_worker
from temporalio.contrib.aws.lambda_worker.otel import apply_defaults, OtelOptions

def configure(config: LambdaWorkerConfig) -> None:
    config.worker_config["task_queue"] = "my-task-queue"
    config.worker_config["workflows"] = [MyWorkflow]
    config.worker_config["activities"] = [my_activity]
    apply_defaults(config, OtelOptions())

lambda_handler = run_worker(
    WorkerDeploymentVersion(deployment_name="my-service", build_id="v1.0"),
    configure,
)
```

`apply_metrics` and `apply_tracing` are available individually. Pair with the ADOT Lambda layer for automatic integration with AWS observability.

## When to Use Lambda Workers

**Good fit:**
- Bursty or low-volume task queues where a full-time worker fleet is wasteful.
- Scenarios where ops overhead (scaling, patching, restart) of a long-running worker fleet is the main cost concern.
- Workloads where per-invocation worker state is acceptable (no warm caches between invocations).

**Poor fit:**
- Sustained high-QPS activity processing — per-invocation dial + poll cost and concurrency caps dominate.
- Activities that need warm, expensive in-process state (model weights, DB connection pools). Each invocation reconnects.
- Workflows or activities that routinely exceed Lambda's max execution time (15 min).

## Gotchas

- Every invocation re-establishes the Temporal client connection and re-warms the worker cache. Prefer long-lived workers on Fargate / Cloud Run / EKS if that cost matters.
- `disable_eager_activity_execution` is always true — activities always flow through the task queue rather than being optimistically dispatched to the current worker.
- All four concurrency defaults are very low. Raise them in `configure` only after confirming your Lambda memory size supports it.

## References

- Package docs: [`temporalio.contrib.aws.lambda_worker`](https://python.temporal.io/temporalio.contrib.aws.lambda_worker.html)
- Source: [sdk-python/temporalio/contrib/aws/lambda_worker](https://github.com/temporalio/sdk-python/tree/main/temporalio/contrib/aws/lambda_worker)
- Release notes: [sdk-python 1.25.0](https://github.com/temporalio/sdk-python/releases/tag/1.25.0)
