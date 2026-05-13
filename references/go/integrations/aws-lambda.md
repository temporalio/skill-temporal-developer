# Temporal Go SDK on AWS Lambda (`lambdaworker`)

## Overview

The `lambdaworker` contrib package runs a Temporal Worker inside an AWS Lambda function. Temporal Cloud's Worker Controller Instance invokes the Lambda when Tasks arrive on a Task Queue; the function starts a Worker, polls for Tasks, then shuts down gracefully before the invocation deadline <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:31-34 -->. Workflow and Activity registration is the same as for a long-lived Worker.

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. Request access through a support ticket. APIs are experimental and subject to backwards-incompatible changes <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:22-28 -->.

Conceptual background (WCI, lifecycle phases, autoscaling, constraints) lives on the canonical [Serverless Workers](/serverless-workers) page. This file is the Go-SDK-specific reference; pair it with the end-to-end [Deploy a Serverless Worker on AWS Lambda](/production-deployment/worker-deployments/serverless-workers/aws-lambda) guide for full deployment steps.

## Package and imports

```go
import (
    lambdaworker "go.temporal.io/sdk/contrib/aws/lambdaworker"
    otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel" // optional, observability
    "go.temporal.io/sdk/worker"
    "go.temporal.io/sdk/workflow"
)
```

The package path is `go.temporal.io/sdk/contrib/aws/lambdaworker` (under `contrib/aws`, not at the SDK root) <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51 -->. The OpenTelemetry sub-package is `go.temporal.io/sdk/contrib/aws/lambdaworker/otel` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:146 -->.

## Minimum Worker code

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
        opts.TaskQueue = "serverless-task-queue-1"

        opts.RegisterWorkflowWithOptions(SampleWorkflow, workflow.RegisterOptions{
            VersioningBehavior: workflow.VersioningBehaviorPinned,
        })
        opts.RegisterActivity(HelloActivity)

        return nil
    })
}
```

`lambdaworker.RunWorker` takes a `worker.WorkerDeploymentVersion` (required — Worker Deployment Versioning is always enabled for Serverless Workers) and an `Options` callback that registers Workflows and Activities <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:40-41, 77-78 -->.

Every Workflow needs a [versioning behavior](/worker-versioning#versioning-behaviors): either `workflow.VersioningBehaviorPinned` or `workflow.VersioningBehaviorAutoUpgrade`. Set it per-Workflow at registration time (as above), or set a Worker-level default via `DefaultVersioningBehavior` in `DeploymentOptions` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:79-80 -->.

The `Options` callback exposes the same registration methods used with a long-lived Worker: `RegisterWorkflow`, `RegisterWorkflowWithOptions`, `RegisterActivity`, `RegisterActivityWithOptions`, and `RegisterNexusService` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:82 -->.

## Connection configuration

`lambdaworker` automatically loads Temporal client configuration from a TOML config file and environment variables. See [Environment Configuration](/develop/environment-configuration) for the full file format and supported env vars <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:86 -->.

The TOML config file is resolved in this order <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:88-94 -->:

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional — if absent, only environment variables are read.

Sensitive values (TLS keys, API keys) should be encrypted at rest using Lambda environment variable encryption <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:96 -->.

## Lambda-tuned `worker.Options` defaults

`lambdaworker` ships conservative defaults for short-lived invocations. Except for `ShutdownDeadlineBuffer`, these are standard [`worker.Options`](https://pkg.go.dev/go.temporal.io/sdk/worker) tuned down for Lambda's constrained environment <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:100-102 -->.

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

<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:104-116 -->

`DisableEagerActivities` is forced to `true` and **cannot be overridden**. Eager Activities require a persistent connection, which Lambda invocations do not maintain <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:118-119 -->.

`ShutdownDeadlineBuffer` is specific to `lambdaworker`. It controls how much time before the Lambda invocation deadline the Worker begins graceful shutdown (stops polling for new Tasks). Its default is `WorkerStopTimeout` + 2 seconds <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:121-123 -->. `WorkerStopTimeout` then bounds how long the Worker waits for in-flight Tasks to finish after polling stops.

For long-running Activities, raise `WorkerStopTimeout`, `ShutdownDeadlineBuffer`, and the Lambda `--timeout` together. See [Tuning for long-running Activities](/serverless-workers#tuning-for-long-running-activities) for the relationships between these values <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:125-126 -->.

## Build and package

Cross-compile for Lambda's Linux runtime and zip the binary <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:194-202 -->:

```bash
GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap ./worker
zip function.zip bootstrap
```

The output binary **must** be named `bootstrap` to satisfy the `provided.al2023` custom runtime handler requirement.

## Deploy with `aws lambda create-function`

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

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:252-261 -->

Go-specific flags:

- `--runtime provided.al2023` — Lambda runtime for custom Go binaries <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:266 -->.
- `--handler bootstrap` — must be `bootstrap` when using the `provided.al2023` custom runtime <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:267 -->.
- `HOME=/tmp` — required Lambda environment variable in the Go example; `/tmp` is the writable directory on Lambda <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:260 -->.

Shared environment variables (all SDKs) include `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE` (overrides the value set in code), `TEMPORAL_TLS_CLIENT_CERT_PATH`, `TEMPORAL_TLS_CLIENT_KEY_PATH`, and `TEMPORAL_API_KEY` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:322-327 -->.

`--timeout` is the per-invocation deadline in seconds. Set it high enough for the Worker to start, process Tasks, and shut down gracefully <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:320 -->. For AWS Lambda, the maximum Activity duration is bounded by this timeout minus the shutdown deadline buffer, capped at Lambda's 15-minute hard limit <!-- docs/encyclopedia/workers/serverless-workers.mdx:243 -->.

To update an existing function with a new build:

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:339-342 -->

> **Versioning best practice.** Map each `BuildID` in your Worker code 1-to-1 to a [Lambda function version](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html). If you use an unversioned Lambda, never change `BuildID` in code without also creating a new Worker Deployment Version <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:344-350 -->.

## IAM (Temporal Cloud)

Two distinct IAM roles are involved — keep them straight:

1. **Lambda execution role** (`--role` on `aws lambda create-function`) — grants the function permission to run. Trusted principal is `lambda.amazonaws.com`. Needs at least the `AWSLambdaBasicExecutionRole` managed policy <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318 -->.
2. **Invocation role** (the role Temporal Cloud assumes to call `lambda:InvokeFunction`) — created by the [CloudFormation template](/files/temporal-cloud-serverless-worker-role.yaml). Its trust policy requires an External ID condition (a value you choose) to prevent confused-deputy attacks <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:359-365 -->.

The two roles are separate. The Lambda execution role is what your function uses at runtime; the invocation role is what Temporal Cloud uses to call Lambda on your behalf. Do not pass the execution role ARN where the invocation role ARN is expected (or vice versa) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318, 558 -->.

Deploy the template with `aws cloudformation create-stack`, passing `AssumeRoleExternalId`, `LambdaFunctionARNs` (comma-separated, one role can authorize multiple Worker Lambdas), and an optional `RoleName` <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:367-370, 481-489 -->.

## Create Worker Deployment Version

A Worker Deployment Version with a compute provider tells Temporal how to invoke your Worker. The `DeploymentName` and `BuildID` in code must match the version's configuration <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:502-504 -->.

### Via Temporal UI

Create the deployment under **Workers > Create Worker Deployment**, choose **AWS Lambda** as the compute provider, and fill in **Lambda ARN**, **IAM Role ARN** (the invocation role from CloudFormation — *not* the execution role), and **External ID**. The UI automatically sets the new version as current <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:513-525 -->.

### Via Temporal CLI

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

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:536-551 -->

| Flag | Description |
|---|---|
| `--deployment-name` | Must match `DeploymentName` in code <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:555 --> |
| `--build-id` | Must match `BuildID` in code <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:556 --> |
| `--aws-lambda-function-arn` | ARN of the Lambda function Temporal invokes <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:557 --> |
| `--aws-lambda-assume-role-arn` | ARN of the **invocation** role (CloudFormation `RoleARN` output), not the execution role <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:558 --> |
| `--aws-lambda-assume-role-external-id` | External ID configured in the invocation role trust policy <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:559 --> |

When using the CLI, **you must set the version as current as a separate step** (the UI does this automatically) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:530-531, 568-573 -->:

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:576-579 -->

Validate the wiring from **Workers > Deployments > select your deployment > Actions > Validate Connection** before sending real Tasks <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:564-566 -->.

## OpenTelemetry observability

The `lambdaworker/otel` sub-package wires SDK metrics and traces into the [AWS Distro for OpenTelemetry (ADOT)](https://aws-otel.github.io/docs/getting-started/lambda) Lambda layer. The ADOT layer runs a collector sidecar that listens on `localhost:4317` and forwards traces to AWS X-Ray and metrics to CloudWatch <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:130-132, 174-177 -->.

```go
import otel "go.temporal.io/sdk/contrib/aws/lambdaworker/otel"

// inside the Options callback:
if err := otel.ApplyDefaults(opts, &opts.ClientOptions, otel.Options{}); err != nil {
    return err
}
```

`otel.ApplyDefaults` configures both metrics and tracing with sensible defaults. If you only need one, call `otel.ApplyMetrics` or `otel.ApplyTracing` individually <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:173, 241 -->.

Unlike Python or TypeScript, Go does not need a language-specific ADOT layer — the OTel SDK is compiled into the binary <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:178 -->.

### Required Collector config

The default ADOT collector configuration does not route OTLP data to a traces pipeline. Bundle a custom `otel-collector-config.yaml` in your deployment package that wires the OTLP receiver into both traces and metrics pipelines <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:180-182 -->:

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

<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:186-222 -->

Point the collector at the bundled file with the `OPENTELEMETRY_COLLECTOR_CONFIG_URI` environment variable (note: `_URI`, not `_FILE`) <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:227 -->:

```
OPENTELEMETRY_COLLECTOR_CONFIG_URI=/var/task/otel-collector-config.yaml
```

Enable X-Ray active tracing on the function:

```bash
aws lambda update-function-configuration \
  --function-name <your-function-name> \
  --tracing-config Mode=Active
```

<!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:232-235 -->

The Lambda **execution role** must include these permissions or the collector fails silently with no telemetry surfaced <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:237-239 -->:

- `xray:PutTraceSegments`
- `xray:PutTelemetryRecords`
- `cloudwatch:PutMetricData`

## Common pitfalls

**Wrong package path.** The package is `go.temporal.io/sdk/contrib/aws/lambdaworker`, not `go.temporal.io/sdk/lambdaworker` <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:51 -->.

**Deployment name / build ID mismatch.** If `DeploymentName` or `BuildID` in code does not exactly match the Worker Deployment Version's configuration, the WCI repeatedly invokes the Lambda but the Worker polls under a different version, the Task is never processed, and the WCI invokes again — an invocation loop. Compare your code's values against the WCI Workflow ID (`temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`) and `temporal worker deployment describe` <!-- docs/troubleshooting/serverless-workers.mdx:154-168 -->.

**Forgetting `set-current-version` after CLI create.** A Worker Deployment Version created via the CLI is not current until you run `temporal worker deployment set-current-version`. Without it, Tasks never route to the version and Lambda is never invoked <!-- docs/troubleshooting/serverless-workers.mdx:86-90 -->.

**Conflating execution role and invocation role.** The Lambda execution role (passed to `aws lambda create-function --role`) is *not* the role Temporal Cloud assumes. The invocation role comes from the CloudFormation template output and is passed via `--aws-lambda-assume-role-arn`. The UI and CLI both call this out explicitly <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:518-520, 558 -->.

**Manually invoking the Lambda before creating the Worker Deployment Version.** If you test-invoke the Lambda before the version with a compute provider exists, the Worker connects and registers a Task Queue binding against a version that has no compute provider. No WCI Workflow exists for that version, and Temporal will never automatically invoke the Lambda. Fix by creating or updating the Worker Deployment Version with the compute provider flags <!-- docs/troubleshooting/serverless-workers.mdx:78-84 -->.

**Missing or wrong-named binary.** `provided.al2023` requires the handler binary be named `bootstrap`. Use `-tags lambda.norpc -o bootstrap` on the `go build` invocation <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:195, 267 -->.

**Setting `DisableEagerActivities = false`.** It is forced `true` and cannot be overridden by user code <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:118-119 -->.

**Raising `WorkerStopTimeout` without raising `ShutdownDeadlineBuffer`.** The Worker keeps polling until the buffer-before-deadline boundary; raising stop timeout alone does not give in-flight Activities more time to finish. Raise both together along with the Lambda `--timeout` <!-- docs/encyclopedia/workers/serverless-workers.mdx:194-202 -->.

**Missing OTel IAM permissions.** Without `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and `cloudwatch:PutMetricData` on the execution role, the ADOT collector swallows telemetry silently — no errors, no data <!-- docs/develop/go/workers/serverless-workers/aws-lambda.mdx:237-239 -->.

## Further reading

- End-to-end deployment guide: [Deploy a Serverless Worker on AWS Lambda](/production-deployment/worker-deployments/serverless-workers/aws-lambda).
- Conceptual overview (WCI, lifecycle, autoscaling, constraints): [Serverless Workers](/serverless-workers).
- Diagnostic flow when invocations fail or loop: [Troubleshoot Serverless Workers](/troubleshooting/serverless-workers).
- Client config file + env vars: [Environment Configuration](/develop/environment-configuration).
