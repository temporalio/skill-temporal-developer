# Lambda Worker (Go SDK `lambdaworker` contrib package)

## Overview

The `lambdaworker` package lets you run a Temporal Serverless Worker as an AWS Lambda function.  You deploy your Worker code as a Lambda; Temporal Cloud invokes it when Tasks arrive, the Worker polls for Tasks, processes them, then gracefully shuts down before the invocation deadline.  Workflows and Activities are registered the same way as with a standard long-lived Worker.  Serverless Workers are in Pre-release and available to select Temporal Cloud customers; APIs are experimental and may be subject to backwards-incompatible changes.

## Install / package path

Import the package from:

```go
import lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker" // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51
```

The OpenTelemetry helpers live in a sub-package:

```go
import otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel" // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:146
```

## Minimal worker code

Use `RunWorker`, passing a `worker.WorkerDeploymentVersion` and an `Options` callback that registers your Workflows and Activities.

```go
package main

import (
	greeting "github.com/temporalio/samples-go/lambda-worker/greeting"

	lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

func main() {
	lambdaworker.RunWorker(worker.WorkerDeploymentVersion{
		DeploymentName: "my-app",
		BuildID:        "build-1",
	}, func(opts *lambdaworker.Options) error {
		opts.TaskQueue = "serverless-task-queue-1"

		opts.RegisterWorkflowWithOptions(greeting.SampleWorkflow, workflow.RegisterOptions{
			VersioningBehavior: workflow.VersioningBehaviorPinned,
		})
		opts.RegisterActivity(greeting.HelloActivity)

		return nil
	})
}
```

The `Options` callback exposes the same registration methods you use on a traditional Worker: `RegisterWorkflow`, `RegisterWorkflowWithOptions`, `RegisterActivity`, `RegisterActivityWithOptions`, and `RegisterNexusService`.

## Worker Versioning is required

`WorkerDeploymentVersion` is required; Worker Deployment Versioning is always enabled for Serverless Workers.  Each Workflow must have a versioning behavior of either `workflow.VersioningBehaviorPinned` or `workflow.VersioningBehaviorAutoUpgrade`.  Set it per-Workflow at registration time (via `workflow.RegisterOptions{VersioningBehavior: ...}`), or set a Worker-level default with `DefaultVersioningBehavior` in `DeploymentOptions`.

## Configure the Temporal connection

The `lambdaworker` package automatically loads client configuration from a TOML config file and environment variables.  See the Environment Configuration docs for the full list of supported environment variables, config file format, and profiles.

The config file is resolved in this order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used.  Encrypt sensitive values like TLS keys or API keys.

## Lambda-tuned defaults

`lambdaworker` applies conservative defaults suited to short-lived Lambda invocations. Except for `ShutdownDeadlineBuffer`, these are the same `worker.Options` fields available to any Temporal Worker, just with lower values for Lambda's constrained environment.

| Setting | Lambda default |
|---|---|
| `MaxConcurrentActivityExecutionSize` | 2 |
| `MaxConcurrentWorkflowTaskExecutionSize` | 10 |
| `MaxConcurrentLocalActivityExecutionSize` | 2 |
| `MaxConcurrentNexusTaskExecutionSize` | 5 |
| `MaxConcurrentActivityTaskPollers` | 1 |
| `MaxConcurrentWorkflowTaskPollers` | 2 |
| `MaxConcurrentNexusTaskPollers` | 1 |
| `WorkerStopTimeout` | 5 seconds |
| `DisableEagerActivities` | Always true |
| Sticky cache size | 100 |
| `ShutdownDeadlineBuffer` | 7 seconds |

`DisableEagerActivities` is always true and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain.

`ShutdownDeadlineBuffer` is specific to the `lambdaworker` package. It controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `WorkerStopTimeout + 2 seconds`.

## Tuning for long-running Activities

If your Worker handles long-running Activities, set these three values together:

- **Worker stop timeout > longest Activity runtime.** Gives in-flight Activities enough time to finish after polling stops.
- **Shutdown deadline buffer > Worker stop timeout + shutdown hook time.** Ensures the drain and any shutdown hooks complete before the compute provider terminates the environment.
- **Invocation deadline > longest Activity runtime + shutdown deadline buffer.** Set on the compute provider (the Lambda `--timeout` flag) to give each invocation enough total runtime.

If your longest-running Activity exceeds half the maximum invocation deadline, this constraint may be impossible to meet; use Activity Heartbeats so the next retry can pick up where it left off.

Raising only the shutdown deadline buffer makes the Worker stop polling earlier but does not give in-flight Tasks more time to complete. Raising only `WorkerStopTimeout` does not make the Worker stop polling earlier, so the compute provider might terminate the Worker before the full stop timeout completes.

For the encyclopedia-level explanation of these values, see `docs/encyclopedia/workers/serverless-workers.mdx` (Tuning for long-running Activities section).

## Observability with OpenTelemetry

The `lambdaworker/otel` sub-package provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer.  The Worker emits SDK metrics and distributed traces for Workflow and Activity executions; the ADOT layer can forward traces to AWS X-Ray and metrics to Amazon CloudWatch.

```go
package main

import (
	greeting "github.com/temporalio/samples-go/lambda-worker/greeting"

	lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
	otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

func main() {
	lambdaworker.RunWorker(worker.WorkerDeploymentVersion{
		DeploymentName: "my-app",
		BuildID:        "build-1",
	}, func(opts *lambdaworker.Options) error {
		opts.TaskQueue = "serverless-task-queue-1"

		if err := otel.ApplyDefaults(opts, &opts.ClientOptions, otel.Options{}); err != nil {
			return err
		}

		opts.RegisterWorkflowWithOptions(greeting.SampleWorkflow, workflow.RegisterOptions{
			VersioningBehavior: workflow.VersioningBehaviorPinned,
		})
		opts.RegisterActivity(greeting.HelloActivity)

		return nil
	})
}
```

`ApplyDefaults` configures both metrics and tracing.  By default, telemetry is sent to `localhost:4317`, the ADOT Lambda layer's default collector endpoint.  Go does not need a language-specific ADOT layer because the OTel SDK is compiled into the binary.

The default ADOT Collector configuration does not route OTLP data to the traces pipeline; you must bundle a custom `otel-collector-config.yaml` in your Lambda deployment package that wires the OTLP receiver to both the traces and metrics pipelines.

Point the Collector at the bundled config with the following environment variable:

- `OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml`

Enable X-Ray active tracing on the Lambda function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must have `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without these, the Collector fails silently and no telemetry appears.

If you only need metrics or tracing, use `otel.ApplyMetrics` or `otel.ApplyTracing` individually instead of `ApplyDefaults`.

## Deployment recipe

Cross-compile for Lambda's Linux runtime:

```bash
GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap ./worker
```

Package the binary into a zip:

```bash
zip function.zip bootstrap
```

Create the Lambda function:

```bash
aws lambda create-function \
  --function-name my-temporal-worker \
  --runtime provided.al2023 \
  --handler bootstrap \
  --role <EXECUTION_ROLE_ARN> \
  --zip-file fileb://function.zip \
  --timeout 600 \
  --memory-size 256 \
  --environment '{"Variables":{"HOME":"/tmp","TEMPORAL_ADDRESS":"<your-temporal-address>:7233","TEMPORAL_NAMESPACE":"<your-namespace>","TEMPORAL_API_KEY":"<your-api-key>"}}'
```

Use `--runtime provided.al2023` for custom Go binaries; the `--handler` must be `bootstrap` when using the `provided.al2023` custom runtime.  `--timeout` is the invocation deadline (seconds); set it high enough for the Worker to start, process Tasks, and shut down gracefully.  Set `HOME=/tmp` in the function's environment along with the `TEMPORAL_*` variables.

Common env vars: `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`, `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, `TEMPORAL_API_KEY`.

To update an existing function with new code:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

The IAM/role step (Temporal Cloud invocation role + External ID CloudFormation template) lives in the broader deploy guide; see `docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx` ("Configure IAM for Temporal invocation").  For self-hosted Temporal Service v1.31.0+, see `docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx` for dynamic config keys (`workercontroller.enabled`, `workercontroller.compute_providers.enabled`, `workercontroller.scaling_algorithms.enabled`), AWS credentials, and the self-hosted invocation role.

Create the Worker Deployment Version with the Temporal CLI:

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

`--deployment-name` and `--build-id` must match `DeploymentName` and `BuildID` in your Worker code.  `--aws-lambda-assume-role-arn` is the `RoleARN` output from the CloudFormation stack (not the Lambda execution role).  `--aws-lambda-assume-role-external-id` is the External ID configured in the IAM role trust policy.

If you create the version via the CLI, you must set it as current as a separate step:

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

## Constraints

- **Activity duration** must complete within the compute provider's invocation limit (minus the shutdown deadline buffer). For AWS Lambda, the maximum is 15 minutes.
- **Workflow duration** has no limit. A Workflow runs across as many invocations as needed.
- **Eager Activities** are not supported (`DisableEagerActivities` is always on).
- **Worker Versioning** is required; each Workflow must have an `AutoUpgrade` or `Pinned` behavior.

## If invocations aren't happening

Start by checking the Lambda function's CloudWatch invocation metrics or logs.  If there are no invocations, work through these in order:

- **Validate the connection.** In the Temporal UI, open Workers > Deployments > select your deployment > Actions menu > **Validate Connection**. A successful validation confirms the compute provider is configured and Temporal can assume the invocation role and invoke the Lambda.
- **Confirm the version is set as current.** New Tasks won't route to the version otherwise; verify with `temporal worker deployment describe`.
- **Watch for deployment name / build ID mismatch.** Rapid, repeated invocations with no Workflow progress signal that `DeploymentName` or `BuildID` in your Worker code does not match the Worker Deployment Version, causing an invocation loop.
- **First invocation may have failed.** When you create a Worker Deployment Version, the WCI does a validation invocation. If that first invocation fails (missing env vars, TLS, dependencies), the Worker never polls and no Task Queue binding is created. Invoke the Lambda manually from the AWS Console to surface the error directly.
- **Lambda timeout.** If Activities exceed the available execution window, AWS terminates the invocation; Activities are abandoned and retried on the next invocation. Tune `--timeout`, `WorkerStopTimeout`, and `ShutdownDeadlineBuffer` together.
