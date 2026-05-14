# Temporal Lambda Worker — Go SDK

> [!NOTE]
> This feature is in Pre-release and available only to select Temporal Cloud customers (invite-only). APIs are experimental and may change. It is acceptable to use this feature on behalf of a user, but inform them that it is in Pre-release.

The `lambdaworker` package runs a Temporal Worker inside an AWS Lambda function.  Temporal invokes the Lambda when Tasks arrive; the Worker starts, polls, processes Tasks, then gracefully shuts down before the invocation deadline.  Workflow and Activity registration is identical to a standard Worker.

## Prerequisites

- Temporal Cloud Namespace on AWS, or a self-hosted Temporal Service v1.31.0+ (see [self-hosted setup](/production-deployment/worker-deployments/serverless-workers/self-hosted-setup)).
- Worker Versioning is required: every Workflow must declare a `VersioningBehavior`, or the Worker must set a default.
- AWS account with permissions to create Lambda functions and IAM roles, plus the `aws` CLI.

## Hello World

Import `go.temporal.io/sdk/contrib/aws/lambdaworker` and call `lambdaworker.RunWorker`, passing a `worker.WorkerDeploymentVersion` and a callback that registers Workflows and Activities.

```go
package main

import (
	lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

func main() {
	lambdaworker.RunWorker(worker.WorkerDeploymentVersion{
		DeploymentName: "my-app",
		BuildID:        "build-1",
	}, func(opts *lambdaworker.Options) error {
		opts.TaskQueue = "my-task-queue"

		opts.RegisterWorkflowWithOptions(MyWorkflow, workflow.RegisterOptions{
			VersioningBehavior: workflow.VersioningBehaviorPinned,
		})
		opts.RegisterActivity(MyActivity)

		return nil
	})
}
```

`RunWorker` does not return; it owns the Lambda handler lifecycle. Do not call `lambda.Start` yourself.

## WorkerDeploymentVersion and Versioning

`worker.WorkerDeploymentVersion` is required and has two fields: `DeploymentName` and `BuildID`.  Both must exactly match the Worker Deployment Version registered with the server.

Each Workflow must declare a versioning behavior, either `workflow.VersioningBehaviorPinned` or `workflow.VersioningBehaviorAutoUpgrade`.  Set it per-Workflow on `workflow.RegisterOptions.VersioningBehavior`, or set a Worker-level default with `DefaultVersioningBehavior` in `DeploymentOptions`.

```go
opts.RegisterWorkflowWithOptions(MyWorkflow, workflow.RegisterOptions{
    VersioningBehavior: workflow.VersioningBehaviorPinned,
})
```

## Options callback

The `*lambdaworker.Options` passed to the callback exposes the standard registration methods: `RegisterWorkflow`, `RegisterWorkflowWithOptions`, `RegisterActivity`, `RegisterActivityWithOptions`, `RegisterNexusService`.  Set the Task Queue on `opts.TaskQueue`.  Configure the client through `opts.ClientOptions`.

## Connection configuration

The package loads Temporal client config from a TOML file and environment variables automatically.  Resolution order:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; environment variables alone are sufficient.  See the Environment Configuration doc for the full variable list.

## Lambda-tuned defaults

These are standard `worker.Options` fields with lower values plus the `lambdaworker`-specific `ShutdownDeadlineBuffer`.

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

`DisableEagerActivities` is always `true` and cannot be overridden; Eager Activities require a persistent connection that Lambda does not maintain.

`ShutdownDeadlineBuffer` defaults to `WorkerStopTimeout + 2 seconds` and controls how much time before the Lambda deadline the Worker begins graceful shutdown.

## Worker lifecycle and tuning

Each invocation has three phases:

- **Init** — establishes the client connection to Temporal.
- **Work** — polls the Task Queue and processes Tasks.
- **Shutdown** — stops polling, waits for in-flight Tasks, runs shutdown hooks (such as OTel flushes).

For long-running Activities, three distinct values must be tuned together — do not conflate them:

- `WorkerStopTimeout` > longest Activity runtime. Controls how long the Worker waits for in-flight Tasks after polling stops.
- `ShutdownDeadlineBuffer` > `WorkerStopTimeout` + shutdown hook time. Controls when polling stops before the invocation deadline.
- Lambda `--timeout` (invocation deadline) > longest Activity runtime + `ShutdownDeadlineBuffer`.

If the longest Activity runs longer than half the maximum invocation deadline, use Activity Heartbeats so retries can resume.

## OpenTelemetry

The `go.temporal.io/sdk/contrib/aws/lambdaworker/otel` sub-package configures OTel metrics and tracing with defaults that target the AWS Distro for OpenTelemetry (ADOT) collector layer at `localhost:4317`.

Apply both metrics and tracing:

```go
import otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel"

if err := otel.ApplyDefaults(opts, &opts.ClientOptions, otel.Options{}); err != nil {
    return err
}
```

For metrics-only or tracing-only, use `otel.ApplyMetrics` or `otel.ApplyTracing`.

Go does not need a language-specific ADOT layer because the OTel SDK is compiled into the binary; attach only the ADOT Collector layer.

The default Collector config does not route OTLP to the traces pipeline. Bundle a custom `otel-collector-config.yaml` in the deployment package and set:

- `OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml`

Enable X-Ray active tracing on the function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must include `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData`; without them the Collector fails silently.

## Deploy

### Build and package

Cross-compile for the Lambda Linux runtime; the output binary must be named `bootstrap`:

```bash
GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap ./worker
zip function.zip bootstrap
```

### Create the Lambda function

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

For Go binaries, `--runtime` must be `provided.al2023` and `--handler` must be `bootstrap`.  Set `HOME=/tmp` so the Go runtime has a writable home directory.

Supported environment variables:

| Variable | Description |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g. `<namespace>.<account>.tmprl.cloud:7233`). |
| `TEMPORAL_NAMESPACE` | Temporal Namespace. |
| `TEMPORAL_TASK_QUEUE` | Task Queue name. Overrides the value set in code. |
| `TEMPORAL_API_KEY` | API key authentication. |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | mTLS client certificate path. |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | mTLS client key path. |

The `--timeout` flag is the Lambda invocation deadline, not `WorkerStopTimeout` or `ShutdownDeadlineBuffer`.

### Redeploy

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

Create a 1-to-1 mapping between each `BuildID` and a Lambda function version; if you use an unversioned Lambda, do not change `BuildID` without also creating a new Worker Deployment Version.

### Configure IAM for Temporal to invoke the Lambda

Deploy the CloudFormation template from the [deployment guide](/production-deployment/worker-deployments/serverless-workers/aws-lambda#configure-iam) to create the invocation role for Temporal Cloud.  For self-hosted, follow the [self-hosted setup](/production-deployment/worker-deployments/serverless-workers/self-hosted-setup#create-invocation-role).  The trust policy uses an External ID condition; pass the same External ID when creating the Worker Deployment Version.

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

`--deployment-name` and `--build-id` must match `DeploymentName` and `BuildID` in the Worker code.  `--aws-lambda-assume-role-arn` is the invocation role from the CloudFormation stack, not the Lambda execution role.

### Set version as current

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

CLI-created versions are not current until this command runs; without it, Tasks do not route to the version.

## Constraints

- Activity duration must complete within the Lambda invocation limit minus `ShutdownDeadlineBuffer`; Lambda's maximum is 15 minutes.
- Workflow duration is unconstrained; a Workflow spans as many invocations as needed.
- Features requiring persistent connections are unavailable.
- `DisableEagerActivities` is always `true`.
- Worker Versioning is required; every Workflow needs `AutoUpgrade` or `Pinned`.

## Troubleshooting

Use the **Validate Connection** action on the deployment version in the Temporal UI to confirm Temporal can assume the IAM role and invoke the Lambda.

Common failure modes:

- **Invocation loop with no Workflow progress.** `DeploymentName` / `BuildID` in code do not match the Worker Deployment Version; the WCI keeps re-invoking. Update the code to match and redeploy.
- **Lambda never invoked, no Task Queue binding.** A failed first invocation prevents the Task Queue from binding to the version. Invoke the Lambda manually from the AWS Console to surface configuration errors directly.
- **No WCI Workflow exists.** The Worker Deployment Version has no compute provider; recreate it with the `--aws-lambda-*` flags.
- **Version not set as current (CLI flow).** Run `temporal worker deployment set-current-version` or verify with `temporal worker deployment describe`.
- **Lambda timeout terminates Activities.** Increase Lambda `--timeout`, `WorkerStopTimeout`, and `ShutdownDeadlineBuffer` together per the tuning rules above.

Inspect WCI state by Workflow ID pattern `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`:

```bash
temporal workflow show \
  --namespace <NAMESPACE> \
  --workflow-id 'temporal-sys-worker-controller-instance:<DEPLOYMENT_NAME>:<BUILD_ID>'
```

Check which Task Queues are bound and whether a backlog exists:

```bash
temporal worker deployment describe-version \
  --namespace <NAMESPACE> \
  --deployment-name <DEPLOYMENT_NAME> \
  --build-id <BUILD_ID> \
  --report-task-queue-stats
```

Worker logs are in CloudWatch under `/aws/lambda/<function-name>`.
