
> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities run independently of any Workflow and are the right tool when you only need to execute a single durable, retryable task rather than orchestrate multiple steps; see the [Standalone Activity encyclopedia page](/standalone-activity) for the cross-SDK concept.  In the Java SDK you start a Standalone Activity directly "from a Temporal Client using `ActivityClient`."  The Activity interface, implementation, and Worker registration are identical to a Workflow Activity — the same Activity Function can be invoked either way with no code changes.

## Hard guardrail: do not call ActivityClient from inside a Workflow

- Don't call `ActivityClient.execute` / `ActivityClient.start` from inside a Workflow Definition — use Workflow-side activity invocation (`Workflow.newActivityStub(...)`) instead. The Java docs are explicit: "Call this from your application code, not from inside a Workflow Definition."

## Prerequisites

- **Java** 8+.
- **Temporal Java SDK** v1.35.0 or higher.
- **Temporal CLI** v1.7.0 or higher — see [references/core/install_cli.md](../core/install_cli.md).

## Worker setup

- Worker registration is identical to a Workflow-Activity worker — the Worker doesn't need to know how the Activity will be invoked.
- Minimal setup using `WorkerFactory.newInstance(client)`, `factory.newWorker(TASK_QUEUE)`, and `worker.registerActivitiesImplementations(...)`.

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

## Hard pre-step: construct the ActivityClient

- You cannot call `execute` / `start` / `getHandle` / `listExecutions` / `countExecutions` without first constructing an `ActivityClient`.

```java
ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());
```

## StartActivityOptions — hard constraints

- `StartActivityOptions` **must** set `id`, `taskQueue`, and at least one of `startToCloseTimeout` or `scheduleToCloseTimeout`.

```java
StartActivityOptions options =
    StartActivityOptions.newBuilder()
        .setId(ACTIVITY_ID)
        .setTaskQueue(TASK_QUEUE)
        .setStartToCloseTimeout(Duration.ofSeconds(10))
        .build();
```

## Execute and wait for the result — typed method-reference form

- `client.execute(...)` durably enqueues the Standalone Activity, waits for a Worker to run it, and returns the typed result.
- The typed form takes the Activity interface class and an unbound method reference; the SDK infers the Activity type name and result type at runtime.

```java
String result =
    client.execute(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");
```

## Execute — string-name form

- When you don't have the interface class available, call the Activity by its string type name and pass the result class.

```java
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```

## Start without waiting — ActivityHandle

- `client.start(...)` returns an `ActivityHandle<R>` after the Activity is durably enqueued; the call does not wait for the Worker to run it.
- Block for the result later by calling `handle.getResult()`.

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

## Get a handle to an existing Standalone Activity

- Use `client.getHandle(...)` to attach a typed handle to a previously started Standalone Activity.
- Passing `null` as the run ID targets the latest run of that Activity ID; the handle can then wait for the result, describe, cancel, or terminate.

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```

## Await result later

- `handle.getResult()` blocks until the Activity completes and returns the typed result.
- `handle.getResultAsync()` returns a `CompletableFuture<R>` for non-blocking waits.

```java
String result = handle.getResult();
CompletableFuture<String> future = handle.getResultAsync();
```

## List Standalone Activity Executions

- `client.listExecutions(query)` returns a `Stream<ActivityExecutionMetadata>` that fetches pages from the server on demand as the stream is consumed.
- Only Standalone Activity Executions are returned; Activities running inside Workflows are not included.
- The query parameter accepts the same List Filter syntax used for Workflow Visibility, for example `ActivityType = 'composeGreeting' AND Status = 'Running'`.

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```

## Count Standalone Activity Executions

- `client.countExecutions(query)` returns an `ActivityExecutionCount` exposing `getCount()` and `getGroups()`.
- Each group exposes `getGroupValues()` and `getCount()`.
- This is the total count of executions (running, completed, failed, etc.) — not the number of queued tasks.

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```

## Temporal CLI mirror

Equivalent CLI invocations use kebab-case flags.

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

Wait for result by Activity ID:
```bash
temporal activity result --activity-id standalone-activity-id
```

List:
```bash
temporal activity list
```

Count:
```bash
temporal activity count
```

## Temporal Cloud

- The same code runs against Temporal Cloud because `ClientConfigProfile.load()` reads TOML profiles and environment variables; no code changes are required.  See the doc's "Connect with mTLS" and "Connect with an API key" sections for the exact `TEMPORAL_ADDRESS` / `TEMPORAL_NAMESPACE` / `TEMPORAL_TLS_CLIENT_CERT_PATH` / `TEMPORAL_TLS_CLIENT_KEY_PATH` / `TEMPORAL_API_KEY` env-var blocks.

## Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview.
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy are not supported yet.

