# Lambda Workers (Serverless Workers on AWS Lambda)

> **Pre-release.** Serverless Workers are in Pre-release and available to select Temporal Cloud customers. APIs are experimental and may be subject to backwards-incompatible changes. <!-- docs/encyclopedia/workers/serverless-workers.mdx:22-29 -->

This reference is SDK-agnostic. It covers the conceptual model, lifecycle, constraints, deploy flow, CLI invocation, IAM template, self-hosted prerequisites, and troubleshooting for Temporal Serverless Workers running on AWS Lambda. SDK-specific package names, function signatures, runtime strings, defaults, and packaging commands live in sibling files:

- `references/go/lambda-workers.md`
- `references/python/lambda-workers.md`
- `references/typescript/lambda-workers.md`

## Overview

A Serverless Worker is a Temporal Worker that runs on serverless compute instead of a long-lived process. There is no always-on infrastructure to provision or scale. Temporal invokes the Worker when Tasks arrive on a Task Queue, and the Worker shuts down when the work is done. <!-- docs/encyclopedia/workers/serverless-workers.mdx:44-46 -->

A Serverless Worker uses the same Temporal SDKs as a traditional long-lived Worker and registers Workflows and Activities the same way. The difference is the lifecycle: Temporal invokes the Worker on demand, the Worker starts, processes available Tasks, and then shuts down. <!-- docs/encyclopedia/workers/serverless-workers.mdx:48-50 -->

| | Long-lived Worker | Serverless Worker |
|---|---|---|
| Lifecycle | Long-lived process that runs continuously. | Invoked on demand. Starts and stops per invocation. |
| Scaling | You manage scaling (Kubernetes HPA, instance count, etc.). | Temporal invokes additional instances as needed, within the compute provider's concurrency limits. |
| Connection | Persistent connection to Temporal. | Fresh connection on each invocation. |
<!-- Sources: docs/evaluate/development-production-features/serverless-workers/index.mdx:101-105 -->

Serverless Workers require [Worker Versioning](/worker-versioning). Each Serverless Worker must be associated with a Worker Deployment Version that has a compute provider configured. <!-- docs/encyclopedia/workers/serverless-workers.mdx:52-53 -->

A compute provider is the configuration that tells Temporal how to invoke a Serverless Worker. It is set on a Worker Deployment Version and specifies the provider type, invocation target, and credentials Temporal needs to trigger the invocation. For AWS Lambda, this includes the Lambda function ARN and the IAM role Temporal assumes to invoke the function. <!-- docs/encyclopedia/workers/serverless-workers.mdx:250-255 -->

## Worker Controller Instance

The Worker Controller Instance (WCI) is a system Workflow that scales Serverless Workers based on Task Queue conditions. One WCI Workflow runs per Worker Deployment Version that has a compute provider configured. The WCI runs in the same Namespace as your Worker Deployment. <!-- docs/encyclopedia/workers/serverless-workers.mdx:67-69 -->

WCI Workflow IDs follow the pattern `temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`. <!-- docs/encyclopedia/workers/serverless-workers.mdx:84 -->

The WCI responds to two triggers:

- **Sync match failure** (primary path). When a Task is submitted, the Matching Service attempts to route it directly to an available Worker. If no Worker is available, the sync match fails and the Matching Service pushes a signal to the WCI. The WCI then invokes a new Worker. Because match failures are pushed rather than polled on a timer, latency stays low and scaling is responsive. <!-- docs/encyclopedia/workers/serverless-workers.mdx:123-129 -->
- **Task Queue backlog.** The WCI monitors Task Queue metadata to determine whether pending Tasks exist without enough Workers, and invokes additional Workers when needed. <!-- docs/encyclopedia/workers/serverless-workers.mdx:131-134 -->

### Invocation flow

1. A Task is submitted (for example, `StartWorkflow` or `ScheduleActivity`).
2. The Matching Service attempts to route the Task directly to an available Worker (a sync match).
3. If a Worker is available, the Task is routed to that Worker.
4. If no Worker is available (sync match fails), the Matching Service pushes a signal to the WCI, and the WCI invokes the configured compute provider.
5. The Serverless Worker starts, creates a Temporal Client, and begins polling the Task Queue.
6. The Worker processes available Tasks until it exits.
<!-- Sources: docs/encyclopedia/workers/serverless-workers.mdx:102-111 -->

For AWS Lambda specifically, the Temporal server invokes the Worker by assuming an IAM role and calling `lambda:InvokeFunction` (not an HTTPS push). <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:359-361 -->

Each invocation is independent. The Worker creates a fresh client connection on every invocation. There is no connection reuse or shared state across invocations. <!-- docs/encyclopedia/workers/serverless-workers.mdx:113-114 -->

You can list WCI Workflows in your Namespace with `temporal workflow list --query 'TemporalNamespaceDivision = "TemporalWorkerControllerInstance"'`, and inspect a WCI Workflow's history with `temporal workflow show --workflow-id 'temporal-sys-worker-controller-instance:<DEPLOYMENT_NAME>:<BUILD_ID>'`. <!-- docs/encyclopedia/workers/serverless-workers.mdx:78-91 -->

## Worker lifecycle

A single Serverless Worker invocation has three phases. <!-- docs/encyclopedia/workers/serverless-workers.mdx:153 -->

| Phase | What happens |
|---|---|
| Init | The Worker initializes and establishes a client connection to Temporal. |
| Work | The Worker polls the Task Queue and processes Tasks. |
| Shutdown | The Worker stops polling, waits for in-flight Tasks to finish, and runs any shutdown hooks (for example, OpenTelemetry telemetry flushes). Shutdown begins before the invocation deadline so the Worker can exit cleanly before the compute provider forcibly terminates the execution environment. |
<!-- Sources: docs/encyclopedia/workers/serverless-workers.mdx:162-168 -->

### Tuning for long-running Activities

If your Worker handles long-running Activities, set these three values together:

| Rule | Constraint |
|---|---|
| Worker stop timeout | Greater than longest Activity runtime. Gives in-flight Activities time to finish after polling stops. |
| Shutdown deadline buffer | Greater than (Worker stop timeout + shutdown hook time). Ensures the drain and any shutdown hooks complete before the compute provider terminates the environment. |
| Invocation deadline | Greater than (longest Activity runtime + shutdown deadline buffer). Set on the compute provider to give each invocation enough total runtime. |
<!-- Sources: docs/encyclopedia/workers/serverless-workers.mdx:172-179 -->

If your longest-running Activity runs longer than half the maximum invocation deadline, this constraint may be difficult or impossible to meet. In that case, use Activity Heartbeats to record state so the next retry can resume where it left off. <!-- docs/encyclopedia/workers/serverless-workers.mdx:181-188 -->

The Worker stop timeout controls how long the Worker waits for in-flight Tasks to finish after it stops polling. The shutdown deadline buffer controls how much time before the invocation deadline the Worker stops polling for Tasks. Raising only the shutdown deadline buffer makes the Worker stop polling earlier, but does not give in-flight Tasks any more time to complete. Raising only the Worker stop timeout does not make the Worker stop polling earlier, which means the compute provider might terminate the Worker before the full stop timeout completes. <!-- docs/encyclopedia/workers/serverless-workers.mdx:194-202 -->

## Constraints

| Constraint | Detail |
|---|---|
| Activity duration | Must complete within the compute provider's invocation limit (minus shutdown deadline buffer). For AWS Lambda, the maximum is **15 minutes**. |
| Workflow duration | No limit. Workflows of any duration work, regardless of the invocation timeout. A Workflow runs across as many invocations as needed. |
| Worker code | Same Temporal SDK Worker code, using the serverless Worker package for your SDK. |
| Versioning | Worker Versioning is required. Each Workflow must have an `AutoUpgrade` or `Pinned` behavior, set per-Workflow or as a Worker-level default. |
| Client connection | Fresh client connection on every invocation; no connection reuse or shared state. |
<!-- Sources: docs/encyclopedia/workers/serverless-workers.mdx:241-246, docs/encyclopedia/workers/serverless-workers.mdx:113-114 -->

## Failure handling

Serverless Workers rely on Temporal's standard retry and timeout semantics to recover from failures. <!-- docs/encyclopedia/workers/serverless-workers.mdx:206-207 -->

| Failure | Behavior | Mitigation |
|---|---|---|
| Worker crash (OOM, unhandled exception, etc.) | Activity Timeout fires after the configured duration; Temporal retries the Activity on a different Worker invocation. No manual intervention required. | Standard retry/timeout configuration. |
| Provider concurrency limit reached (e.g., AWS Lambda account concurrency) | Further invocations from the WCI fail; Tasks remain in the Task Queue backlog (no data loss); processing slows until concurrency frees up. | Raise provider concurrency, or shape traffic. |
| Resource exhaustion across Activity slots within one invocation | A crash or resource exhaustion in one Activity (e.g., OOM from a memory-intensive op) can affect other Activities running in the same invocation, because a single Worker invocation may run multiple Activity slots by default. | Split Workflow and Activity Workers into separate compute functions, and/or set Activity slots to 1 per invocation so each Activity gets a dedicated execution environment. |
<!-- Sources: docs/encyclopedia/workers/serverless-workers.mdx:209-237 -->

## Deploy flow

The end-to-end deploy flow for AWS Lambda has six steps. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:61-602 -->

1. **Write Worker code.** Author a Worker that runs inside a Lambda function. The Worker handles the per-invocation lifecycle: connecting to Temporal, polling for tasks, and gracefully shutting down before the invocation deadline. SDK-specific package usage lives in the SDK sibling files. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:61-64 -->
2. **Build and package, then deploy the Lambda function** with `aws lambda create-function` (or equivalent). SDK-specific runtime and handler strings live in the SDK sibling files. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:183-242 -->
3. **Configure IAM for Temporal invocation (Cloud).** Deploy the Temporal-provided CloudFormation template to create the IAM role Temporal assumes to call `lambda:InvokeFunction`. The trust policy includes an External ID condition to prevent confused-deputy attacks. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:353-498 -->
4. **Create the Worker Deployment Version** with a compute provider that points to your Lambda function. The deployment name and build ID must match the values in your Worker code. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:499-562 -->
5. **Set the version as current** with `temporal worker deployment set-current-version`. Without this step, Tasks on the Task Queue will not route to the version and Temporal will not invoke the Lambda. (Versions created in the Temporal UI are set current automatically.) <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:568-579 -->
6. **Verify the deployment.** Start a Workflow on the Task Queue and confirm the Lambda is invoked, the Worker connects, picks up the Task, and processes it. Cross-check the Temporal UI event history and the Lambda function's CloudWatch log group. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:581-601 -->

To update existing Lambda code, use `aws lambda update-function-code --function-name <NAME> --zip-file fileb://function.zip`. Best practice is a 1-to-1 mapping between each build ID in your Worker code and a Lambda function version. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:336-351 -->

## Temporal CLI flags

Create the Worker Deployment if it does not already exist, then create the version with compute provider configuration. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:530-551 -->

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

| Flag | Description |
|---|---|
| `--deployment-name` | Worker Deployment name. Must match `DeploymentName` in your Worker code. |
| `--build-id` | Worker Deployment Version build ID. Must match `BuildID` in your Worker code. |
| `--aws-lambda-function-arn` | ARN of the Lambda function Temporal invokes for this version. |
| `--aws-lambda-assume-role-arn` | IAM role Temporal assumes to invoke the function. This is the `RoleARN` output from the CloudFormation stack created in step 3. **Not** the Lambda execution role from step 2 and **not** your own IAM user/role. |
| `--aws-lambda-assume-role-external-id` | External ID configured in the IAM role trust policy. |
<!-- Sources: docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:553-559 -->

After creating the version with the CLI, set it as current: <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:572-579 -->

```bash
temporal worker deployment set-current-version \
  --deployment-name my-app \
  --build-id build-1
```

To verify Temporal can reach your Lambda function, in the Temporal UI go to **Workers > Deployments**, select the deployment, open the **Actions** menu on the version, and click **Validate Connection**. This checks that Temporal can assume the IAM role and invoke the function. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:564-566 -->

## CloudFormation IAM (Temporal Cloud)

The Cloud CloudFormation template (`temporal-cloud-serverless-worker-role.yaml`) creates an IAM role that Temporal Cloud can assume to invoke one or more Lambda functions, plus the `Temporal-Cloud-Lambda-Invoke-Permissions` policy that grants `lambda:InvokeFunction` and `lambda:GetFunction` on the configured Lambda ARNs. The trust policy includes an External ID condition. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:363-476 -->

| Parameter | Description |
|---|---|
| `AssumeRoleExternalId` | A string you choose to prevent confused-deputy attacks. Can be any value. Use the same value when creating the Worker Deployment Version. |
| `LambdaFunctionARNs` | Comma-separated list of Lambda function ARNs that Temporal may invoke. One role can authorize multiple Worker Lambdas. |
| `RoleName` | Base name for the created IAM role. Defaults to `Temporal-Cloud-Serverless-Worker`. |
<!-- Sources: docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:366-370 -->

Deploy the template, then retrieve the role ARN from the stack outputs to use as `--aws-lambda-assume-role-arn`. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:478-497 -->

```bash
aws cloudformation create-stack \
  --stack-name <STACK_NAME> \
  --template-body file://temporal-cloud-serverless-worker-role.yaml \
  --parameters \
    ParameterKey=AssumeRoleExternalId,ParameterValue=<EXTERNAL_ID> \
    ParameterKey=LambdaFunctionARNs,ParameterValue='"<LAMBDA_FUNCTION_ARN>"' \
  --capabilities CAPABILITY_NAMED_IAM \
  --region <AWS_REGION>

aws cloudformation describe-stacks \
  --stack-name <STACK_NAME> \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleARN`].OutputValue' \
  --output text --region <AWS_REGION>
```

The role Temporal assumes (compute-provider invocation role) is **distinct** from the Lambda execution role passed to `aws lambda create-function --role`. The execution role's trusted principal must be `lambda.amazonaws.com` and must have at least the `AWSLambdaBasicExecutionRole` managed policy attached. Do not conflate the two. <!-- docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:318, docs/production-deployment/worker-deployments/serverless-workers/aws-lambda.mdx:516-520 -->

## Self-hosted setup

Self-hosted Serverless Workers require **Temporal Service v1.31.0 or later**. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:29 -->

Self-hosted prerequisites: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:31-41 -->

1. **Network reachability.** The Temporal Service frontend must be reachable from the Lambda execution environment. If the Temporal Service runs on a private network, you may need VPC access for Lambda, VPC peering, or a similar mechanism. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:43-48 -->
2. **Enable the WCI** through dynamic configuration. It is disabled by default. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:50-54 -->
3. **AWS credentials for the server.** On AWS infrastructure (EC2/ECS/EKS), the attached instance/task/pod role is used automatically and must have `sts:AssumeRole` for the invocation role. Outside AWS, use IAM Roles Anywhere, or static credentials in the server's environment (not recommended). <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:83-102 -->
4. **Create the Lambda invocation role** with the self-hosted CloudFormation template. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:104-130 -->

### Dynamic configuration keys

The exact dynamic-config keys are: <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:58-69 -->

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

| Key | Purpose |
|---|---|
| `workercontroller.enabled` | Enables the WCI globally (or per-Namespace with a `constraints.namespace` selector). |
| `workercontroller.compute_providers.enabled` | List of enabled compute providers (e.g., `aws-lambda`). |
| `workercontroller.scaling_algorithms.enabled` | List of enabled scaling algorithms (e.g., `no-sync`). |
<!-- Sources: docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:58-79 -->

The Temporal Service watches the dynamic config file for changes and applies updates without a restart. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:81 -->

### Self-hosted CloudFormation template

The self-hosted template (`temporal-self-hosted-serverless-worker-role.yaml`) differs from the Cloud template by adding a `TemporalIamRoleArn` parameter for the IAM role/user identity that the Temporal Service runs as. <!-- docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:110-131 -->

| Parameter | Description |
|---|---|
| `TemporalIamRoleArn` | ARN of the IAM role/user the Temporal Service runs as. The identity the server uses to call `sts:AssumeRole`. Discover with `aws sts get-caller-identity` in the server's environment. |
| `AssumeRoleExternalId` | Unique string to prevent confused-deputy attacks. Use the same value when creating the Worker Deployment Version. |
| `LambdaFunctionARNs` | Comma-separated list of Lambda function ARNs that Temporal may invoke. |
| `RoleName` | Base name for the created IAM role. Defaults to `Temporal-Serverless-Worker`. |
<!-- Sources: docs/production-deployment/worker-deployments/serverless-workers/self-hosted-setup.mdx:126-131 -->

## Troubleshooting decision tree

When a Workflow is not progressing, start by determining whether the Lambda is being invoked at all, then narrow down. Check the Lambda's CloudWatch metrics (Invocations graph) or CloudWatch Logs (`/aws/lambda/<function-name>`). <!-- docs/troubleshooting/serverless-workers.mdx:47-60 -->

### A. Lambda is **not** being invoked

Work through these checks in order. <!-- docs/troubleshooting/serverless-workers.mdx:62-122 -->

1. **Validate the connection to Lambda.** In the Temporal UI, **Workers > Deployments**, select your deployment, open the **Actions** menu on the version, and click **Validate Connection**. A successful validation confirms the version has a compute provider, that Temporal can assume the invocation role, and that the Lambda is invocable. If validation fails, verify the Lambda function ARN, the invocation role ARN, and that the External ID matches. <!-- docs/troubleshooting/serverless-workers.mdx:66-77 -->
2. **Confirm a compute provider exists on the version.** A common cause of "no WCI" is manually invoking the Lambda before the Worker Deployment Version was created; the Worker polls and registers the version on the server, but the version has no compute provider, so no WCI exists. Fix by creating or updating the version with the compute provider flags. <!-- docs/troubleshooting/serverless-workers.mdx:78-84 -->
3. **Check that the version is set as current.** If you created the version through the CLI, you must run `temporal worker deployment set-current-version`. Verify with `temporal worker deployment describe`. <!-- docs/troubleshooting/serverless-workers.mdx:86-92 -->
4. **Check that the WCI is detecting Tasks.** Inspect Task Queue bindings and backlog with `temporal worker deployment describe-version --report-task-queue-stats`. If no Task Queues are listed, the binding has not been established. The server binds a Task Queue to a Worker Deployment Version only after a Worker with that version successfully connects and polls the Task Queue. A common cause is a failed first invocation (missing env vars, incorrect TLS, missing dependencies); diagnose by invoking the Lambda manually from the AWS Console to surface configuration errors directly. <!-- docs/troubleshooting/serverless-workers.mdx:94-121 -->

### B. Lambda **is** invoked but Tasks are not completing

If CloudWatch shows invocations but Workflows are not progressing, the problem is inside the Worker's execution. <!-- docs/troubleshooting/serverless-workers.mdx:123-127 -->

1. **Check Lambda execution logs** in CloudWatch `/aws/lambda/<function-name>` for errors during Worker startup: <!-- docs/troubleshooting/serverless-workers.mdx:128-141 -->
   - Connection failures: the Worker cannot reach the Temporal Service. Verify `TEMPORAL_ADDRESS` and `TEMPORAL_API_KEY` (or the `temporal.toml` config file). For self-hosted, verify network reachability.
   - TLS errors: the certificate or key is missing, expired, or does not match the Namespace.
   - Authentication errors: the API key is invalid or lacks Namespace access.
2. **Check for Lambda timeout.** If the Lambda reaches its configured timeout before the Worker finishes, AWS terminates the invocation; Activities are abandoned mid-execution and retried on the next invocation. For long-running Activities, raise the Lambda timeout and the Worker's shutdown buffer together (see [Tuning for long-running Activities](#tuning-for-long-running-activities)). <!-- docs/troubleshooting/serverless-workers.mdx:143-152 -->
3. **Check that the deployment name and build ID match.** If CloudWatch shows rapid, repeated invocations with no Workflow progress, the deployment name or build ID in your Worker code may not match the Worker Deployment Version. Compare against the WCI Workflow ID (`temporal-sys-worker-controller-instance:<deployment-name>:<build-id>`) and `temporal worker deployment describe`. A mismatch causes an invocation loop: the WCI invokes the Lambda, the Worker polls with a different version than the WCI expects, the Task is not processed, and the WCI invokes again. Fix by updating the code to match and redeploying. <!-- docs/troubleshooting/serverless-workers.mdx:154-168 -->

## SDK-specific references

For package names, function signatures, default configuration tables, OpenTelemetry setup, Lambda runtime strings, and packaging commands per language, see:

- `references/go/lambda-workers.md`
- `references/python/lambda-workers.md`
- `references/typescript/lambda-workers.md`
