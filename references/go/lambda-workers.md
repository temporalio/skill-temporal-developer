# Go SDK Lambda Workers

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:22-29 -->

This reference covers the Go-specific pieces of running a Serverless Worker on AWS Lambda with the `lambdaworker` contrib package. For SDK-agnostic deployment steps (IAM setup, `temporal worker deployment create-version`, setting the current version, verification), see `references/core/lambda-workers.md`.

## Package and entry point

Import the contrib package: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51 -->

```go
import (
    lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
    "go.temporal.io/sdk/worker"
    "go.temporal.io/sdk/workflow"
)
```

Call `lambdaworker.RunWorker` from `main()`, passing a `worker.WorkerDeploymentVersion` and a callback that receives `*lambdaworker.Options`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:40-41 -->

```go
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

`WorkerDeploymentVersion` requires `DeploymentName` and `BuildID`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:58-61 --> Worker Deployment Versioning is always enabled for Serverless Workers. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:78 -->

## Workflow registration and versioning behavior

Every Workflow needs a versioning behavior, either `VersioningBehaviorPinned` or `VersioningBehaviorAutoUpgrade`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:79 --> Set it per-Workflow at registration time, or set a worker-level default with `DefaultVersioningBehavior` in `DeploymentOptions`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:80 -->

```go
opts.RegisterWorkflowWithOptions(MyWorkflow, workflow.RegisterOptions{
    VersioningBehavior: workflow.VersioningBehaviorPinned,
})
```

The `Options` callback exposes the same registration methods as a traditional Worker: `RegisterWorkflow`, `RegisterWorkflowWithOptions`, `RegisterActivity`, `RegisterActivityWithOptions`, and `RegisterNexusService`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->

## Temporal connection configuration

The `lambdaworker` package automatically loads Temporal client configuration from a TOML config file and environment variables. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:86 -->

The config file is resolved in this order: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:88-92 -->

1. The `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:94 -->

## Lambda-tuned defaults

The `lambdaworker` package applies conservative defaults suited to short-lived Lambda invocations. Except for `ShutdownDeadlineBuffer`, these are the same `worker.Options` available to any Temporal Worker, just with lower values. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:100-102 -->

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
| `ShutdownDeadlineBuffer` | 7 seconds (default is `WorkerStopTimeout` + 2 seconds) |

<!-- Sources: docs/develop/go/workers/serverless-workers/aws-lambda.mdx:104-116, 123 -->

`DisableEagerActivities` is always true and cannot be overridden. Eager Activities require a persistent connection, which Lambda invocations don't maintain. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:118-119 -->

## `ShutdownDeadlineBuffer`

`ShutdownDeadlineBuffer` is specific to the `lambdaworker` package and is not part of the standard `worker.Options`. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:102, 121 --> It controls how much time before the Lambda invocation deadline the Worker begins its graceful shutdown. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:122 --> The default is `WorkerStopTimeout` + 2 seconds. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:123 -->

For Workers handling long-running Activities, raise `WorkerStopTimeout`, `ShutdownDeadlineBuffer`, and the Lambda invocation deadline (`--timeout`) together. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:125 -->

## OpenTelemetry sub-package

The `lambdaworker/otel` sub-package provides OpenTelemetry integration with defaults configured for the AWS Distro for OpenTelemetry (ADOT) Lambda layer. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:130 -->

```go
import (
    lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
    otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel"
)

func main() {
    lambdaworker.RunWorker(worker.WorkerDeploymentVersion{
        DeploymentName: "my-app",
        BuildID:        "build-1",
    }, func(opts *lambdaworker.Options) error {
        opts.TaskQueue = "my-task-queue"

        if err := otel.ApplyDefaults(opts, &opts.ClientOptions, otel.Options{}); err != nil {
            return err
        }

        opts.RegisterWorkflowWithOptions(MyWorkflow, workflow.RegisterOptions{
            VersioningBehavior: workflow.VersioningBehaviorPinned,
        })
        opts.RegisterActivity(MyActivity)
        return nil
    })
}
```

<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:151-169 -->

`ApplyDefaults` configures both metrics and tracing. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:173 --> By default, telemetry is sent to `localhost:4317`, the ADOT Lambda layer's default collector endpoint. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:174 --> If you only need one signal, use `otel.ApplyMetrics` or `otel.ApplyTracing` individually. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:241 -->

Attach the ADOT Collector layer to your Lambda function to receive telemetry on `localhost:4317` and forward traces to X-Ray and metrics to CloudWatch. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:176-177 --> Go does not need a language-specific ADOT layer because the OTel SDK is compiled into the binary. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:178 -->

## OTel Collector configuration

The default ADOT Collector configuration does not route OTLP data to the traces pipeline. Bundle a custom `otel-collector-config.yaml` in your deployment package. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:180-182 -->

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

<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:186-222 -->

Set the following environment variable on the Lambda function to point the Collector at the bundled config: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:225-227 -->

```
OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml
```

## Enable X-Ray active tracing

Enable X-Ray active tracing on the Lambda function: <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:229 -->

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

The Lambda execution role must have `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` permissions. Without them, the Collector fails silently and no telemetry appears. <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:237-239 -->

## Build and package

Cross-compile for Lambda's Linux runtime: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:192-196 -->

```bash
GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap ./worker
```

Package the binary into a zip: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:200-202 -->

```bash
zip function.zip bootstrap
```

## Deploy

Use `aws lambda create-function` with the `provided.al2023` custom runtime and a handler name of `bootstrap`: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:252-261, 266-267 -->

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

`provided.al2023` is the Amazon Linux custom runtime used for Go binaries, and the handler must be `bootstrap`. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:266-267 -->

Common environment variables (full list under `--environment`): <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:260, 322-327 -->

- `HOME=/tmp` — writable home directory for the runtime.
- `TEMPORAL_ADDRESS` — Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`).
- `TEMPORAL_NAMESPACE` — Temporal Namespace.
- `TEMPORAL_API_KEY` — API key for API key authentication.

To update an existing function with new code: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:338-342 -->

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

## Cross-SDK steps

For the CloudFormation IAM invocation role, `temporal worker deployment create-version`, setting the current version, and verifying the deployment, see `references/core/lambda-workers.md`.

For general Go SDK observability (logging, metrics, tracing outside Lambda), see `references/go/observability.md`.
