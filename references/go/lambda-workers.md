# Lambda Workers — Go SDK

Go-SDK-specific guidance for running a Temporal Serverless Worker on AWS Lambda using the `lambdaworker` package. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:31 -->

For shared concepts (WCI, lifecycle, IAM, deployment, troubleshooting), see `references/core/lambda-workers.md`.

## Package

Import path: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51 -->

```go
lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker" // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51
```

Serverless Workers are in Pre-release; APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:24-26 -->

## Entry point: `RunWorker`

Use `RunWorker` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:40 --> to start a Lambda-based Worker. It takes a `worker.WorkerDeploymentVersion` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:41,58 --> value and a callback `func(opts *lambdaworker.Options) error` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:61 --> that registers Workflows and Activities.

Canonical example (verbatim from the docs): <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:43-75 -->

```go
package main

import (
	greeting "github.com/temporalio/samples-go/lambda-worker/greeting"

	lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
// ...
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

func main() {
	lambdaworker.RunWorker(worker.WorkerDeploymentVersion{
		DeploymentName: "my-app",
		BuildID:        "build-1",
	}, func(opts *lambdaworker.Options) error {
		opts.TaskQueue = "serverless-task-queue-1"

// ...

		opts.RegisterWorkflowWithOptions(greeting.SampleWorkflow, workflow.RegisterOptions{
			VersioningBehavior: workflow.VersioningBehaviorPinned,
		})
		opts.RegisterActivity(greeting.HelloActivity)

		return nil
	})
}
```

`WorkerDeploymentVersion` is required; Worker Deployment Versioning is always enabled for Serverless Workers. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:77-78 -->

## Registration via `Options`

The `Options` callback exposes the same registration methods as a traditional Worker: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->

- `RegisterWorkflow` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->
- `RegisterWorkflowWithOptions` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->
- `RegisterActivity` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->
- `RegisterActivityWithOptions` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->
- `RegisterNexusService` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->

### Versioning behavior

Each Workflow must have a versioning behavior, either `AutoUpgrade` or `Pinned`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:79 --> Set it per-Workflow at registration time via `workflow.RegisterOptions` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:66 -->:

```go
opts.RegisterWorkflowWithOptions(greeting.SampleWorkflow, workflow.RegisterOptions{
	VersioningBehavior: workflow.VersioningBehaviorPinned, // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:66-68
})
```

Or set a worker-level default with `DefaultVersioningBehavior` in `DeploymentOptions`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:80 -->

Constants: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:67 -->

- `workflow.VersioningBehaviorPinned` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:67 -->
- `workflow.VersioningBehaviorAutoUpgrade` <!-- VERIFY: only VersioningBehaviorPinned appears verbatim in the docs file at line 67; AutoUpgrade is referenced only as the English word "AutoUpgrade" on line 79. The constant name follows the same pattern but is not literally shown. -->

## Connection configuration

`lambdaworker` loads Temporal client configuration from a TOML file and environment variables. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:86 --> The config file is resolved in this order: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:88-92 -->

1. `TEMPORAL_CONFIG_FILE` environment variable, if set. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:90 -->
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`). <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:91 -->
3. `temporal.toml` in the current working directory. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:92 -->

The file is optional; if absent, only environment variables are used. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:94 -->

## Lambda-tuned defaults

The `lambdaworker` package applies conservative defaults suited to short-lived Lambda invocations. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:100 --> Except for `ShutdownDeadlineBuffer`, these are the same `worker.Options` available to any Temporal Worker, just with lower values. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:102 -->

| Setting | Lambda default | <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:104-116 -->
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

Notes:

- `DisableEagerActivities` is always true and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:118-119 -->
- `ShutdownDeadlineBuffer` is specific to the `lambdaworker` package and controls how much time before the Lambda deadline the Worker begins its graceful shutdown. The default is `WorkerStopTimeout` + 2 seconds (= 7s). <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:121-123 -->

## OpenTelemetry

Sub-package: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:146 -->

```go
otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel" // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:146
```

Apply defaults (configures both metrics and tracing): <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:158,173 -->

```go
if err := otel.ApplyDefaults(opts, &opts.ClientOptions, otel.Options{}); err != nil { // docs/develop/go/workers/serverless-workers/aws-lambda.mdx:158
	return err
}
```

For partial use: `otel.ApplyMetrics` or `otel.ApplyTracing` individually. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:241 -->

Default collector endpoint: `localhost:4317`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:174 -->

Go does not need a language-specific ADOT layer because the OTel SDK is compiled into the binary. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:178 -->

Set this environment variable on the Lambda function to point the Collector at a bundled config: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:225-227 -->

```
OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml
```
<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:227 -->

IAM permissions required on the Lambda execution role (otherwise the Collector fails silently): <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:237-239 -->

- `xray:PutTraceSegments` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:238 -->
- `xray:PutTelemetryRecords` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:238 -->
- `cloudwatch:PutMetricData` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:238 -->

The underlying metrics and traces are the same ones the Go SDK emits in any environment. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:134 -->

## Build and deploy

For the cross-compile build target, IAM setup, and deployment commands, see `references/core/lambda-workers.md`.
