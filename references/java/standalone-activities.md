<!-- The Java SDK marks this feature as Pre-release in docs/develop/java/activities/standalone-activities.mdx:25; the encyclopedia page marks the cross-SDK feature as Public Preview in docs/encyclopedia/activities/standalone-activity.mdx:23. -->
> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities run independently of any Workflow and are the right tool when you only need to execute a single durable, retryable task rather than orchestrate multiple steps; see the [Standalone Activity encyclopedia page](/standalone-activity) for the cross-SDK concept. <!-- docs/encyclopedia/activities/standalone-activity.mdx:29-32 --> In the Java SDK you start a Standalone Activity directly "from a Temporal Client using `ActivityClient`." <!-- docs/develop/java/activities/standalone-activities.mdx:29-31 --> The Activity interface, implementation, and Worker registration are identical to a Workflow Activity — the same Activity Function can be invoked either way with no code changes. <!-- docs/develop/java/activities/standalone-activities.mdx:33-35 -->

## Hard guardrail: do not call ActivityClient from inside a Workflow

- Don't call `ActivityClient.execute` / `ActivityClient.start` from inside a Workflow Definition — use Workflow-side activity invocation (`Workflow.newActivityStub(...)`) instead. The Java docs are explicit: "Call this from your application code, not from inside a Workflow Definition." <!-- docs/develop/java/activities/standalone-activities.mdx:199-200 -->

## Prerequisites

- **Java** 8+. <!-- docs/develop/java/activities/standalone-activities.mdx:62 -->
- **Temporal Java SDK** v1.35.0 or higher. <!-- docs/develop/java/activities/standalone-activities.mdx:64 -->
- **Temporal CLI** v1.7.0 or higher — see [references/core/install_cli.md](../core/install_cli.md). <!-- docs/develop/java/activities/standalone-activities.mdx:67 -->

## Worker setup

- Worker registration is identical to a Workflow-Activity worker — the Worker doesn't need to know how the Activity will be invoked. <!-- docs/develop/java/activities/standalone-activities.mdx:166-170 -->
- Minimal setup using `WorkerFactory.newInstance(client)`, `factory.newWorker(TASK_QUEUE)`, and `worker.registerActivitiesImplementations(...)`. <!-- docs/develop/java/activities/standalone-activities.mdx:180-183 -->

```java
ClientConfigProfile profile = ClientConfigProfile.load();
WorkflowServiceStubs service =
    WorkflowServiceStubs.newServiceStubs(profile.toWorkflowServiceStubsOptions());

WorkflowClient client = WorkflowClient.newInstance(service, profile.toWorkflowClientOptions());
WorkerFactory factory = WorkerFactory.newInstance(client);
Worker worker = factory.newWorker(TASK_QUEUE);
worker.registerActivitiesImplementations(new GreetingActivitiesImpl());
factory.start();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:175-184 -->

## Hard pre-step: construct the ActivityClient

- You cannot call `execute` / `start` / `getHandle` / `listExecutions` / `countExecutions` without first constructing an `ActivityClient`. <!-- docs/develop/java/activities/standalone-activities.mdx:206-209 -->

```java
ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());
```
<!-- docs/develop/java/activities/standalone-activities.mdx:206-209 -->

## StartActivityOptions — hard constraints

- `StartActivityOptions` **must** set `id`, `taskQueue`, and at least one of `startToCloseTimeout` or `scheduleToCloseTimeout`. <!-- docs/develop/java/activities/standalone-activities.mdx:237-238 -->

```java
StartActivityOptions options =
    StartActivityOptions.newBuilder()
        .setId(ACTIVITY_ID)
        .setTaskQueue(TASK_QUEUE)
        .setStartToCloseTimeout(Duration.ofSeconds(10))
        .build();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:211-216 -->

## Execute and wait for the result — typed method-reference form

- `client.execute(...)` durably enqueues the Standalone Activity, waits for a Worker to run it, and returns the typed result. <!-- docs/develop/java/activities/standalone-activities.mdx:197-201 -->
- The typed form takes the Activity interface class and an unbound method reference; the SDK infers the Activity type name and result type at runtime. <!-- docs/develop/java/activities/standalone-activities.mdx:228-230 -->

```java
String result =
    client.execute(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");
```
<!-- docs/develop/java/activities/standalone-activities.mdx:218-225 -->

## Execute — string-name form

- When you don't have the interface class available, call the Activity by its string type name and pass the result class. <!-- docs/develop/java/activities/standalone-activities.mdx:230-234 -->

```java
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```
<!-- docs/develop/java/activities/standalone-activities.mdx:234 -->

## Start without waiting — ActivityHandle

- `client.start(...)` returns an `ActivityHandle<R>` after the Activity is durably enqueued; the call does not wait for the Worker to run it. <!-- docs/develop/java/activities/standalone-activities.mdx:264-269 -->
- Block for the result later by calling `handle.getResult()`. <!-- docs/develop/java/activities/standalone-activities.mdx:283-285 -->

```java
ActivityHandle<String> handle =
    client.start(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");

String result = handle.getResult();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:274-285 -->

## Get a handle to an existing Standalone Activity

- Use `client.getHandle(...)` to attach a typed handle to a previously started Standalone Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:309 -->
- Passing `null` as the run ID targets the latest run of that Activity ID; the handle can then wait for the result, describe, cancel, or terminate. <!-- docs/develop/java/activities/standalone-activities.mdx:316-317 -->

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```
<!-- docs/develop/java/activities/standalone-activities.mdx:312-313 -->

## Await result later

- `handle.getResult()` blocks until the Activity completes and returns the typed result. <!-- docs/develop/java/activities/standalone-activities.mdx:321-326 -->
- `handle.getResultAsync()` returns a `CompletableFuture<R>` for non-blocking waits. <!-- docs/develop/java/activities/standalone-activities.mdx:329-330 -->

```java
String result = handle.getResult();
CompletableFuture<String> future = handle.getResultAsync();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:326-333 -->

## List Standalone Activity Executions

- `client.listExecutions(query)` returns a `Stream<ActivityExecutionMetadata>` that fetches pages from the server on demand as the stream is consumed. <!-- docs/develop/java/activities/standalone-activities.mdx:345-348 -->
- Only Standalone Activity Executions are returned; Activities running inside Workflows are not included. <!-- docs/develop/java/activities/standalone-activities.mdx:350-351 -->
- The query parameter accepts the same List Filter syntax used for Workflow Visibility, for example `ActivityType = 'composeGreeting' AND Status = 'Running'`. <!-- docs/develop/java/activities/standalone-activities.mdx:377-378 -->

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:356-363 -->

## Count Standalone Activity Executions

- `client.countExecutions(query)` returns an `ActivityExecutionCount` exposing `getCount()` and `getGroups()`. <!-- docs/develop/java/activities/standalone-activities.mdx:382-385 -->
- Each group exposes `getGroupValues()` and `getCount()`. <!-- docs/develop/java/activities/standalone-activities.mdx:393-396 -->
- This is the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. <!-- docs/develop/java/activities/standalone-activities.mdx:384-386 -->

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:391-397 -->

## Temporal CLI mirror

Equivalent CLI invocations use kebab-case flags. <!-- docs/develop/java/activities/standalone-activities.mdx:253-260 -->

Execute and wait:
```bash
temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:253-260 -->

Start without waiting:
```bash
temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:298-305 -->

Wait for result by Activity ID:
```bash
temporal activity result --activity-id standalone-activity-id
```
<!-- docs/develop/java/activities/standalone-activities.mdx:339 -->

List:
```bash
temporal activity list
```
<!-- docs/develop/java/activities/standalone-activities.mdx:374 -->

Count:
```bash
temporal activity count
```
<!-- docs/develop/java/activities/standalone-activities.mdx:408 -->

## Temporal Cloud

- The same code runs against Temporal Cloud because `ClientConfigProfile.load()` reads TOML profiles and environment variables; no code changes are required. <!-- docs/develop/java/activities/standalone-activities.mdx:413-415 --> See the doc's "Connect with mTLS" and "Connect with an API key" sections for the exact `TEMPORAL_ADDRESS` / `TEMPORAL_NAMESPACE` / `TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH` / `TEMPORAL_API_KEY` env-var blocks. <!-- docs/develop/java/activities/standalone-activities.mdx:421-440 -->

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview. <!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy are not supported yet. <!-- docs/encyclopedia/activities/standalone-activity.mdx:111 -->

## Activity context inside a Standalone Activity

<!-- VERIFY: Which `io.temporal.activity.ActivityExecutionContext` / `ActivityInfo` fields, and which `io.temporal.common.converter.DataConverter` / payload-converter serialization-context fields, change nullability when the Activity runs as a Standalone Activity (no parent Workflow)? Docs are silent in `docs/encyclopedia/activities/standalone-activity.mdx` and `docs/develop/java/activities/standalone-activities.mdx` as of this authoring pass. -->
