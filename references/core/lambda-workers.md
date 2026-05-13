# Lambda Workers (Serverless Workers on AWS Lambda)

Serverless Workers run on ephemeral, on-demand compute rather than long-lived processes. Temporal invokes the Worker when Tasks arrive, and the Worker shuts down when the work is done. The Go, Python, and TypeScript SDKs ship prerelease packages for running a Worker inside AWS Lambda. <!-- docs/develop/typescript/workers/serverless-workers/index.mdx:18-19 -->

> Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/encyclopedia/workers/serverless-workers.mdx:24-26 -->

For SDK-specific package, configuration, and observability details, read the language file alongside this one:

- Go → `references/go/lambda-workers.md`
- Python → `references/python/lambda-workers.md`
- TypeScript → `references/typescript/lambda-workers.md`

Java and .NET do not have Lambda Worker packages. The Supported SDKs are Go, Python, and TypeScript. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:49-50 -->

## When to recommend Serverless Workers

Good fit: <!-- docs/evaluate/development-production-features/serverless-workers/index.mdx:75-86 -->

- Bursty or event-driven workloads (order processing, webhooks, notifications).
- Low or intermittent traffic where always-on Workers spend most of their time idle.
- Teams already standardized on serverless (Lambda, Cloud Run).
- Multi-tenant platforms with infrequent per-tenant workloads.
- Simpler getting-started path: deploy a function instead of provisioning a cluster.

Poor fit: <!-- docs/evaluate/development-production-features/serverless-workers/index.mdx:88-97 -->

- Activities that run longer than the provider's invocation limit and can't be broken into smaller steps. AWS Lambda's hard ceiling is 15 minutes. Long-running *Workflows* are fine — Workflows span multiple invocations. <!-- docs/encyclopedia/workers/serverless-workers.mdx:243 -->
- Sustained high throughput where always-on Workers are more cost-effective.
- Features that require a persistent connection between Worker and Temporal (e.g., Eager Activities, which are not supported). <!-- docs/develop/typescript/workers/serverless-workers/aws-lambda.mdx:118 -->

## Architecture

### Worker Controller Instance (WCI)

The Worker Controller Instance is a system Workflow that scales Serverless Workers based on Task Queue conditions. One WCI Workflow runs per Worker Deployment Version that has a compute provider configured, in the same Namespace as your Worker Deployment. <!-- docs/encyclopedia/workers/serverless-workers.mdx:66-69 -->

The WCI responds to two triggers: <!-- docs/encyclopedia/workers/serverless-workers.mdx:121-134 -->

- **Sync match failure** — primary scaling path. When the Matching Service can't route a Task to an available Worker, it pushes a signal to the WCI, which invokes a new Worker. Push-based, so scaling is responsive.
- **Task Queue backlog** — the WCI also monitors Task Queue metadata. If pending Tasks exist without enough Workers, the WCI invokes additional Workers.

You can list WCI Workflows in a Namespace: <!-- docs/encyclopedia/workers/serverless-workers.mdx:76-82 -->

```bash
temporal workflow list \
  --namespace <NAMESPACE> \
  --query 'TemporalNamespaceDivision = "TemporalWorkerControllerInstance"'
```

WCI Workflow IDs follow the pattern `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`. <!-- docs/encyclopedia/workers/serverless-workers.mdx:84 -->

```bash
temporal workflow show \
  --namespace <NAMESPACE> \
  --workflow-id 'temporal-sys-worker-controller-instance:<DEPLOYMENT_NAME>:<BUILD_ID>'
```

### Invocation flow

<!-- docs/encyclopedia/workers/serverless-workers.mdx:102-114 -->

1. A Task is submitted (for example, `StartWorkflow` or `ScheduleActivity`).
2. The Matching Service attempts to sync-match the Task to an available Worker.
3. If a Worker is available, the Task routes directly.
4. If sync match fails, the Matching Service pushes a signal to the WCI, which invokes the configured compute provider.
5. The Serverless Worker starts, creates a Temporal Client, and polls the Task Queue.
6. The Worker processes available Tasks until it exits.

Each invocation is independent: a fresh client connection on every invocation, no connection reuse or shared state. <!-- docs/encyclopedia/workers/serverless-workers.mdx:113-114 -->

### Worker lifecycle

A single invocation has three phases: **init**, **work**, **shutdown**. <!-- docs/encyclopedia/workers/serverless-workers.mdx:152-168 -->

- **Init** — Worker initializes and establishes a client connection to Temporal.
- **Work** — Worker polls the Task Queue and processes Tasks.
- **Shutdown** — Worker stops polling, waits for in-flight Tasks to finish, and runs any shutdown hooks (for example, OpenTelemetry flushes). Shutdown begins *before* the invocation deadline so the Worker can exit cleanly before the compute provider terminates the environment.

Two settings interact: <!-- docs/encyclopedia/workers/serverless-workers.mdx:194-202 -->

- **Worker stop timeout** — how long the Worker waits for in-flight Tasks to finish after it stops polling.
- **Shutdown deadline buffer** — how much time before the invocation deadline the Worker stops polling for Tasks.

Raising only the shutdown deadline buffer makes the Worker stop polling earlier but does not give in-flight Tasks more time to complete. Raising only the Worker stop timeout does not make the Worker stop polling earlier, so the provider may terminate the Worker before the stop timeout completes.

### Tuning for long-running Activities

If your Worker handles long-running Activities, set three values together: <!-- docs/encyclopedia/workers/serverless-workers.mdx:171-181 -->

1. **Worker stop timeout > longest Activity runtime** — gives in-flight Activities time to finish after polling stops.
2. **Shutdown deadline buffer > Worker stop timeout + shutdown hook time** — ensures drain and shutdown hooks complete before the provider terminates.
3. **Invocation deadline (Lambda `--timeout`) > longest Activity runtime + shutdown deadline buffer** — gives each invocation enough total runtime.

Example: longest Activity 5 minutes, shutdown hooks 3 seconds → Worker stop timeout > 5 min, shutdown deadline buffer > 303s, Lambda `--timeout` ≥ 10 min 3 s. <!-- docs/encyclopedia/workers/serverless-workers.mdx:190-192 -->

If your longest Activity exceeds half the maximum invocation deadline, use Activity Heartbeats so retries can pick up where the prior attempt left off. <!-- docs/encyclopedia/workers/serverless-workers.mdx:181-188 -->

### Scaling with long-lived Workers

Serverless Workers can share a Task Queue with long-lived Workers. They only fire on sync match failure, so they act as spillover capacity. <!-- docs/encyclopedia/workers/serverless-workers.mdx:136-141 -->

> Do not enable dynamic scaling on the long-lived Workers when they share a Task Queue with Serverless Workers. The two groups cannot coordinate, leading to redundant invocations and unpredictable scaling. <!-- docs/encyclopedia/workers/serverless-workers.mdx:142-148 -->

### Failure handling

<!-- docs/encyclopedia/workers/serverless-workers.mdx:206-237 -->

- **Worker crash** (OOM, unhandled exception): standard Temporal retry semantics. Activity Timeout fires, retry runs on a different invocation, no manual intervention.
- **Provider concurrency limit** (e.g., AWS Lambda account concurrency): further WCI invocations fail; Tasks remain in the Task Queue backlog (no data loss); processing slows until concurrency frees.
- **Resource exhaustion across Activity slots**: by default a single invocation may run multiple Activity slots, so one Activity's crash or OOM can affect others. To isolate: split Workflow and Activity Workers into separate Lambda functions, set Activity slots to 1 per invocation.

## Constraints

<!-- docs/encyclopedia/workers/serverless-workers.mdx:241-246 -->

| Constraint | Detail |
|---|---|
| Activity duration | Must complete within the provider's invocation limit minus the shutdown deadline buffer. AWS Lambda max = 15 minutes. |
| Workflow duration | No limit. Workflows span as many invocations as needed. |
| Worker code | Same SDK Worker code, using the serverless Worker package for your SDK. |
| Versioning | Worker Versioning is required. Each Workflow must have `AutoUpgrade` or `Pinned` behavior, set per-Workflow or as a Worker-level default. |

## Worker Deployment Versioning is required

Each Serverless Worker must be associated with a Worker Deployment Version that has a compute provider configured. <!-- docs/encyclopedia/workers/serverless-workers.mdx:52-53 -->

The Worker code passes the deployment name and build ID; these must match the values used when creating the Worker Deployment Version. The deployment name groups related Workers across versions; the build ID identifies a specific release. <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:67-70 -->

Every Workflow must declare a [versioning behavior](https://docs.temporal.io/worker-versioning#versioning-behaviors) — either `AutoUpgrade`/`AUTO_UPGRADE` or `Pinned`/`PINNED` — or the Worker must set a worker-level default. The SDK enum names differ; see the language file for the exact form. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:43-44 -->

## Deployment overview

The end-to-end path is the same across SDKs (only the package and packaging steps differ): <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:25-60 -->

1. Write Worker code that uses the SDK's lambda-worker package.
2. Build and package for Lambda, then run `aws lambda create-function`.
3. (Temporal Cloud only) Configure IAM so Temporal can invoke your Lambda — deploy the [CloudFormation template](https://docs.temporal.io/files/temporal-cloud-serverless-worker-role.yaml) which creates the role and `lambda:InvokeFunction` / `lambda:GetFunction` policy.
4. Create the Worker Deployment Version (Temporal UI or CLI) with the compute provider configuration.
5. Set the version as current (UI does this automatically; CLI requires an explicit step).
6. Start a Workflow on the matching Task Queue to verify the invocation.

### `aws lambda create-function` parameters

These parameters apply to all SDKs: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:314-327 -->

| Parameter | Description |
|---|---|
| `--role` | ARN of the Lambda execution role. Trusted principal must be `lambda.amazonaws.com`. **Separate from** the role Temporal assumes to invoke the function. Must have at least the `AWSLambdaBasicExecutionRole` managed policy. |
| `--zip-file` | Path to your packaged deployment zip. |
| `--timeout` | Invocation deadline in seconds. Maximum time each Lambda invocation can run before AWS terminates. Set high enough for the Worker to start, process Tasks, and shut down gracefully. |
| `--memory-size` | Memory in MB allocated to each invocation. |

Per-SDK runtime and handler values:

| SDK | `--runtime` | `--handler` |
|---|---|---|
| Go | `provided.al2023` (custom runtime for Go binaries) | `bootstrap` (handler must equal binary name) |
| Python | `python3.13` or another supported Python version | `module.function`, e.g. `lambda_function.lambda_handler` |
| TypeScript | `nodejs22.x` or another supported Node.js version (20+) | `module.export`, e.g. `lib/index.handler` |

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:252-311 -->

### Temporal connection environment variables

The serverless packages read environment variables and TOML config files automatically at startup. Set on the Lambda function: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:322-331 -->

| Variable | Description |
|---|---|
| `TEMPORAL_ADDRESS` | Temporal frontend address (e.g., `<namespace>.<account>.tmprl.cloud:7233`). |
| `TEMPORAL_NAMESPACE` | Temporal Namespace. |
| `TEMPORAL_TASK_QUEUE` | Task Queue name. Overrides the value set in code. |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | Path to the TLS client certificate file (mTLS). |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | Path to the TLS client key file (mTLS). |
| `TEMPORAL_API_KEY` | API key for API key authentication. |

For the full environment variable list and config-file format, see [Environment Configuration](https://docs.temporal.io/develop/environment-configuration). <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:329-331 -->

Sensitive values (TLS keys, API keys) should be encrypted at rest via [Lambda environment variable encryption](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html). <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:333-334 -->

### TOML config file resolution order

The lambda-worker packages auto-load a `temporal.toml` config file in this order: <!-- docs/develop/python/workers/serverless-workers/aws-lambda.mdx:92-100 -->

1. `TEMPORAL_CONFIG_FILE` environment variable, if set.
2. `temporal.toml` in `$LAMBDA_TASK_ROOT` (typically `/var/task`).
3. `temporal.toml` in the current working directory.

The file is optional; if absent, only environment variables are used.

### Update an existing function

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:336-342 -->

```bash
aws lambda update-function-code \
  --function-name my-temporal-worker \
  --zip-file fileb://function.zip
```

> **Lambda versioning best practice:** Create a 1-to-1 mapping between each build ID in your Worker code and a Lambda function version. If you use an unversioned Lambda, do not change the Build Id in your Worker code without also creating a new Worker Deployment Version. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:344-351 -->

## IAM: two separate roles

Two distinct IAM roles are involved in a Serverless Worker deployment. Don't confuse them: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:317-318, 553-558 -->

1. **Lambda execution role** — passed via `--role` on `aws lambda create-function`. Grants the function permission to run. Trust principal: `lambda.amazonaws.com`. Must have `AWSLambdaBasicExecutionRole` (and any other permissions your Worker code needs, e.g., for X-Ray + CloudWatch when using OTel).
2. **Temporal invocation role** — created by the CloudFormation template. Trust principal: Temporal Cloud's invoke roles (or your own self-hosted server role). Used by Temporal to call `lambda:InvokeFunction`. The CloudFormation `AssumeRoleExternalId` parameter is a confused-deputy guard — pass the same value when creating the Worker Deployment Version.

### Temporal Cloud invocation role (CloudFormation)

The template is at `/files/temporal-cloud-serverless-worker-role.yaml` on the docs site. Parameters: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:366-370 -->

| Parameter | Description |
|---|---|
| `AssumeRoleExternalId` | A string you choose to prevent confused-deputy attacks. Any value. Use the same value when creating the Worker Deployment Version. |
| `LambdaFunctionARNs` | Comma-separated list of Lambda function ARNs that Temporal may invoke. One role can authorize multiple Worker Lambdas. |
| `RoleName` | Base name for the created IAM role. Defaults to `Temporal-Cloud-Serverless-Worker`. |

Deploy the template and read the role ARN from outputs: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:480-495 -->

```bash
aws cloudformation create-stack \
  --stack-name <STACK_NAME> \
  --template-body file://temporal-cloud-serverless-worker-role.yaml \
  --parameters \
    ParameterKey=AssumeRoleExternalId,ParameterValue=<EXTERNAL_ID> \
    ParameterKey=LambdaFunctionARNs,ParameterValue='"<LAMBDA_FUNCTION_ARN>"' \
  --capabilities CAPABILITY_NAMED_IAM \
  --region <AWS_REGION>

aws cloudformation describe-stacks --stack-name <STACK_NAME> \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleARN`].OutputValue' \
  --output text --region <AWS_REGION>
```

The role grants `lambda:InvokeFunction` and `lambda:GetFunction` on the listed function ARNs. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:453-456 -->

## Creating the Worker Deployment Version

### Temporal UI path

When you create a version through the UI, it is automatically set as current. Skip the "set current" step. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:524-525 -->

1. In the UI, open your Namespace → **Workers** → **Create Worker Deployment**.
2. Under **Configuration**, enter **Name** and **Build ID** — must match `DeploymentName` and `BuildID` in your Worker code.
3. Under **Compute**, select **AWS Lambda** and provide **Lambda ARN**, **IAM Role ARN** (the role ARN from CloudFormation; *not* the Lambda execution role), and **External ID** (the same value you passed to the CloudFormation template).

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:509-522 -->

### Temporal CLI path

First, create the Worker Deployment if it doesn't exist: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:535-539 -->

```bash
temporal worker deployment create \
  --namespace <YOUR_NAMESPACE> \
  --name my-app
```

Then create the version with the compute provider configuration: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:544-551 -->

```bash
temporal worker deployment create-version \
  --namespace <YOUR_NAMESPACE> \
  --deployment-name my-app \
  --build-id build-1 \
  --aws-lambda-function-arn <LAMBDA_FUNCTION_ARN> \
  --aws-lambda-assume-role-arn <INVOCATION_ROLE_ARN> \
  --aws-lambda-assume-role-external-id <EXTERNAL_ID>
```

| Flag | Description |
|---|---|
| `--deployment-name` | Must match `DeploymentName` in Worker code. |
| `--build-id` | Must match `BuildID` in Worker code. |
| `--aws-lambda-function-arn` | ARN of the Lambda function Temporal invokes for this version. |
| `--aws-lambda-assume-role-arn` | IAM role Temporal assumes to invoke the function (the `RoleARN` output from CloudFormation). Not the Lambda execution role. |
| `--aws-lambda-assume-role-external-id` | External ID configured in the IAM role trust policy. |

<!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:553-559 -->

### Set version as current (CLI only)

If you used the CLI, set the version as current. Without this step, Tasks won't route to the version and Temporal won't invoke the Lambda. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:570-579 -->

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

### Validate connection

In the UI: **Workers** → **Deployments** → select your deployment → **Actions** menu on the version → **Validate Connection**. Confirms that Temporal can assume the IAM role and invoke the function. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:564-566 -->

## Verifying the deployment

Start a Workflow on the matching Task Queue: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:583-590 -->

```bash
temporal workflow start \
  --task-queue my-task-queue \
  --type MyWorkflow \
  --input '"Hello, serverless!"'
```

When the Task lands with no active pollers, Temporal invokes the Lambda. Check:

- Temporal UI workflow execution → event history should show task completions.
- AWS CloudWatch Logs at `/aws/lambda/my-temporal-worker` → Worker startup, task processing, graceful shutdown.

## Troubleshooting

Use this decision tree adapted from `docs/troubleshooting/serverless-workers.mdx`. <!-- docs/troubleshooting/serverless-workers.mdx -->

### Is the Lambda being invoked at all?

Check the Lambda function's CloudWatch metrics. AWS Console → **Lambda > Functions > your function > Monitor → Invocations** graph, or **CloudWatch > Log groups > /aws/lambda/<function-name>**. <!-- docs/troubleshooting/serverless-workers.mdx:49-57 -->

### Lambda is not being invoked

Work through these in order. <!-- docs/troubleshooting/serverless-workers.mdx:62-121 -->

1. **Validate the connection** in the UI (Workers → Deployments → Actions → Validate Connection). If validation fails, verify Lambda function ARN, invocation role ARN, and External ID in the Worker Deployment Version configuration match the CloudFormation deployment.

2. **No compute provider configured** — a common cause is manually invoking the Lambda *before* creating the Worker Deployment Version. The Worker's poll registers the version on the server, but with no compute provider attached. Fix: create or update the version with the `--aws-lambda-*` flags.

3. **Check the version is set as current.** Verify with `temporal worker deployment describe`. If you created the version via CLI, you need to explicitly set it current.

4. **Check the WCI is detecting Tasks.** Inspect Task Queues bound to the version and whether there's a backlog:

   ```bash
   temporal worker deployment describe-version \
     --namespace <NAMESPACE> \
     --deployment-name <DEPLOYMENT_NAME> \
     --build-id <BUILD_ID> \
     --report-task-queue-stats
   ```

   If no Task Queues are listed, the binding wasn't established. The server binds a Task Queue only when a Worker with that deployment version successfully connects and polls.

5. **Failed first invocation.** When you create a Worker Deployment Version, the WCI invokes the Lambda to validate the configuration. If that first invocation fails (missing env vars, bad TLS config, missing dependencies), the Worker never polls and the binding is never created. Diagnose by invoking the Lambda manually from the AWS Console — its execution result and errors show directly.

### Lambda is invoked but Tasks aren't completing

<!-- docs/troubleshooting/serverless-workers.mdx:123-168 -->

1. **Check CloudWatch logs** for Worker startup errors. Common categories:
   - **Connection failures** — `TEMPORAL_ADDRESS`, `TEMPORAL_API_KEY` (or `temporal.toml`) set incorrectly. For self-hosted, verify network reachability.
   - **TLS errors** — certificate or key missing, expired, or doesn't match the Namespace.
   - **Authentication errors** — API key invalid or lacks access to the Namespace.

2. **Lambda timeout.** If the function reaches `--timeout` before the Worker finishes, AWS terminates the invocation; in-flight Activities are abandoned and retried on the next invocation. Increase Lambda `--timeout` and the Worker's shutdown buffer together — see [Tuning for long-running Activities](#tuning-for-long-running-activities) above.

3. **Deployment name / build ID mismatch.** Rapid repeated invocations with no Workflow progress indicate the values in code don't match the Worker Deployment Version. Compare against the WCI Workflow ID (`temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`) and `temporal worker deployment describe`. A mismatch causes an invocation loop: WCI invokes → Worker polls with a different version than the WCI expects → Task not processed → WCI invokes again. Fix by updating the code values to match, then redeploy.

## Self-hosted prerequisites

Self-hosted Temporal Service must be **v1.31.0 or later**. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:29 -->

Setup steps: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:33-41 -->

1. Ensure Lambda can reach the Temporal Service frontend (VPC access, peering, etc., if private).
2. Enable the WCI through dynamic configuration.
3. Provide the server with AWS credentials to assume IAM roles.
4. Create the Lambda invocation role in your AWS account.

### Enable the WCI

The WCI is disabled by default. Add to your [dynamic config](https://docs.temporal.io/references/dynamic-configuration) file: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:50-69 -->

```yaml
workercontroller.enabled:
  - value: true

workercontroller.compute_providers.enabled:
  - value:
      - aws-lambda

workercontroller.scaling_algorithms.enabled:
  - value:
      - no-sync
```

To enable WCI per-Namespace instead of globally, add a `constraints` section: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:71-79 -->

```yaml
workercontroller.enabled:
  - value: true
    constraints:
      namespace: 'your-namespace'
```

The server watches the dynamic config file and applies updates without a restart. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:81 -->

### AWS credentials for the server

How you provide credentials depends on where the server runs: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:85-102 -->

- **On AWS infrastructure (EC2, ECS, EKS)** — uses the attached instance/task/pod role automatically. That role must have `sts:AssumeRole` permission for the Lambda invocation role.
- **Outside AWS** — use [IAM Roles Anywhere](https://aws.amazon.com/iam/roles-anywhere/), or set static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` (not recommended).

### Self-hosted CloudFormation template

A separate template (`temporal-self-hosted-serverless-worker-role.yaml`) creates the invocation role, with `TemporalIamRoleArn` as an additional parameter (the ARN of the IAM identity the Temporal Service runs as — find via `aws sts get-caller-identity` in the server's environment). <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:104-131 -->

## Decision pointers

- "Should I use Serverless Workers for this workload?" → See [When to recommend Serverless Workers](#when-to-recommend-serverless-workers).
- "Which SDK package?" → Go: `references/go/lambda-workers.md`. Python: `references/python/lambda-workers.md`. TypeScript: `references/typescript/lambda-workers.md`.
- "How long can an Activity run?" → ≤ 15 minutes (Lambda hard limit) minus shutdown deadline buffer. Use Heartbeats if longer.
- "Do I need Worker Versioning?" → Yes, always. See [Constraints](#constraints).
- "Worker is not invoking" → [Troubleshooting](#troubleshooting).
- "Self-hosted setup" → [Self-hosted prerequisites](#self-hosted-prerequisites).
