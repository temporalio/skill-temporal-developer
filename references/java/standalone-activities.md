# Standalone Activities — Java SDK

Read `references/core/standalone-activities.md` first for the concept, CLI inventory, prerequisites, and Public Preview limitations. This file covers the Java SDK API.

Java SDK support for Standalone Activities is at **Pre-release**.

## Prerequisites

- **Java 8+.**
- **Temporal Java SDK v1.35.0 or higher.**
- **Temporal CLI v1.7.0 or higher.**

Start the dev server:

```
temporal server start-dev
```

The Temporal Server is then on `localhost:7233` and the Web UI on `http://localhost:8233`; the Standalone Activities nav item is in the top-left of the UI.

## Defining the Activity

An Activity in the Java SDK is an interface annotated with `@ActivityInterface`, with methods annotated with `@ActivityMethod`. The way you define a Standalone Activity is identical to how you define an Activity orchestrated by a Workflow — the same Activity can be executed both ways.

```java
@ActivityInterface
public interface GreetingActivities {

  @ActivityMethod
  String composeGreeting(String greeting, String name);
}
```

```java
public class GreetingActivitiesImpl implements GreetingActivities {

  private static final Logger log = LoggerFactory.getLogger(GreetingActivitiesImpl.class);

  @Override
  public String composeGreeting(String greeting, String name) {
    log.info("Composing greeting...");
    return greeting + ", " + name + "!";
  }
}
```

## Running the Worker

Worker setup matches the Workflow-driven case — create a `WorkerFactory`, register the Activity implementation, call `factory.start()`. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

```java
ClientConfigProfile profile = ClientConfigProfile.load();
WorkflowServiceStubs service =
    WorkflowServiceStubs.newServiceStubs(profile.toWorkflowServiceStubsOptions());

WorkflowClient client = WorkflowClient.newInstance(service, profile.toWorkflowClientOptions());
WorkerFactory factory = WorkerFactory.newInstance(client);
Worker worker = factory.newWorker(TASK_QUEUE);
worker.registerActivitiesImplementations(new GreetingActivitiesImpl());
factory.start();
System.out.println("Worker running on task queue: " + TASK_QUEUE);
```

`ClientConfigProfile.load()` reads environment variables and TOML profiles, so the same code works against a local dev server and Temporal Cloud without changes.

## Construct the ActivityClient

Standalone Activities are started through `ActivityClient` (distinct from `WorkflowClient`). Construct it from the same service stubs as the Worker, plus an `ActivityClientOptions` carrying the namespace:

```java
ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());
```

## Execute a Standalone Activity

`ActivityClient.execute()` durably enqueues the Activity, blocks until it completes on a Worker, and returns the typed result. Call this from application code, **not** from inside a Workflow Definition.

```java
StartActivityOptions options =
    StartActivityOptions.newBuilder()
        .setId(ACTIVITY_ID)
        .setTaskQueue(TASK_QUEUE)
        .setStartToCloseTimeout(Duration.ofSeconds(10))
        .build();

String result =
    client.execute(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");
System.out.println("Activity result: " + result);
```

The typed `execute()` API takes the Activity interface class and an unbound method reference. The SDK uses the method reference to infer the Activity type name and result type at runtime.

You can also call Activities by string type name:

```java
// Using a string type name
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```

### `StartActivityOptions` requirements

`StartActivityOptions` requires `id`, `taskQueue`, and at least one of `startToCloseTimeout` or `scheduleToCloseTimeout`.

CLI:

```bash
./temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```

## Start without waiting for the result

`ActivityClient.start()` returns an `ActivityHandle<R>` without waiting for the Activity to complete.

```java
ActivityHandle<String> handle =
    client.start(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");
System.out.println("Started activity ID: " + ACTIVITY_ID);

// Wait for the result later
String result = handle.getResult();
System.out.println("Activity result: " + result);
```

CLI:

```bash
./temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```

## Get a handle to an existing Standalone Activity

`client.getHandle()` creates a typed handle to a previously started Standalone Activity.

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```

**Pass `null` as the run ID to target the latest run of the given Activity ID.**  Use the handle to wait for the result, describe, cancel, or terminate.

## Wait for the result

`client.execute()` is `client.start()` followed by `handle.getResult()`:

```java
String result = handle.getResult();
```

To wait asynchronously without blocking, use `handle.getResultAsync()` which returns a `CompletableFuture<R>`:

```java
CompletableFuture<String> future = handle.getResultAsync();
```

CLI:

```bash
./temporal activity result --activity-id standalone-activity-id
```

## List Standalone Activities

`client.listExecutions()` returns a `Stream<ActivityExecutionMetadata>` that fetches pages from the server on demand. **These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included.**

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```

The query parameter accepts the same [List Filter](/list-filter) syntax used for Workflow Visibility. Example: `ActivityType = 'composeGreeting' AND Status = 'Running'`.

## Count Standalone Activities

`client.countExecutions()` returns the total count of executions (running, completed, failed, etc.) — **not** the number of queued tasks.

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```

## Run with Temporal Cloud

The samples use `ClientConfigProfile.load()`, so the same code works against Temporal Cloud — configure the connection via environment variables or a TOML profile.

mTLS:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```

API key:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```

## Common mistakes

1. **Calling `ActivityClient.execute` / `start` from inside a Workflow Definition.** These are for application code. Inside a Workflow, use `Workflow.newActivityStub` (see `references/java/java.md`).
2. **Using `WorkflowClient` to start a Standalone Activity.** Standalone Activities are started through `ActivityClient`, constructed with `ActivityClient.newInstance(service, ActivityClientOptions...)`.
3. **Omitting `id`, `taskQueue`, or both timeouts on `StartActivityOptions`.** All three constraints are required.
4. **Passing a non-null run ID to `getHandle` to target the "latest" run.** The docs say: pass `null` to target the latest run. A real run ID targets that specific run.
5. **Expecting `listExecutions` / `countExecutions` to include Workflow-driven Activities.** They don't.

