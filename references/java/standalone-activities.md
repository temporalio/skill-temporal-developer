# Java: Standalone Activities

Standalone Activities run independently, without being orchestrated by a Workflow. Instead of starting an Activity from within a Workflow Definition, a Temporal Client starts a Standalone Activity directly using `ActivityClient` <!-- docs/develop/java/activities/standalone-activities.mdx:29-31 -->. The way you write the Activity and register it with a Worker is identical to Workflow Activities — the same Activity can be executed both as a Standalone Activity and as a Workflow Activity <!-- docs/develop/java/activities/standalone-activities.mdx:33-36,135-136 -->.

## Prerequisites

<!-- Sources: docs/develop/java/activities/standalone-activities.mdx:22-27,60-67 -->

- **Java** 8+ <!-- docs/develop/java/activities/standalone-activities.mdx:62 -->
- **Temporal Java SDK** v1.35.0 or higher <!-- docs/develop/java/activities/standalone-activities.mdx:64 -->
- **Temporal CLI** v1.7.0 or higher <!-- docs/develop/java/activities/standalone-activities.mdx:67 -->
- Release stage: Pre-release <!-- docs/develop/java/activities/standalone-activities.mdx:22-27 -->

## Define an Activity

Define a Standalone Activity exactly as you would a Workflow Activity: an interface annotated with `@ActivityInterface` and methods annotated with `@ActivityMethod` <!-- docs/develop/java/activities/standalone-activities.mdx:133-136 -->.

```java
@ActivityInterface
public interface GreetingActivities {

  @ActivityMethod
  String composeGreeting(String greeting, String name);
}
```
<!-- docs/develop/java/activities/standalone-activities.mdx:140-147 -->

Implementation:

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
<!-- docs/develop/java/activities/standalone-activities.mdx:151-162 -->

## Run a Worker

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — create a `WorkerFactory`, register the Activity implementation, and call `factory.start()`. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity <!-- docs/develop/java/activities/standalone-activities.mdx:166-170 -->.

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

## Construct an ActivityClient

Use `ClientConfigProfile.load()` to read connection settings from environment variables or a TOML profile, then build a `WorkflowServiceStubs` and an `ActivityClient` <!-- docs/develop/java/activities/standalone-activities.mdx:175-179,206-209 -->:

```java
ClientConfigProfile profile = ClientConfigProfile.load();
WorkflowServiceStubs service =
    WorkflowServiceStubs.newServiceStubs(profile.toWorkflowServiceStubsOptions());

ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());
```
<!-- docs/develop/java/activities/standalone-activities.mdx:175-179,206-209 -->

## Execute a Standalone Activity

Call `ActivityClient.execute()` to durably enqueue the Standalone Activity, wait for the Worker to run it, and return the typed result <!-- docs/develop/java/activities/standalone-activities.mdx:197-201 -->. Call this from application code, not from inside a Workflow Definition <!-- docs/develop/java/activities/standalone-activities.mdx:199-200 -->.

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
```
<!-- docs/develop/java/activities/standalone-activities.mdx:211-224 -->

The typed `execute()` overload takes the Activity interface class plus an unbound method reference; the SDK infers the Activity type name and result type from the method reference <!-- docs/develop/java/activities/standalone-activities.mdx:228-230 -->. You can also invoke by string type name:

```java
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```
<!-- docs/develop/java/activities/standalone-activities.mdx:233-234 -->

`StartActivityOptions` requires `id`, `taskQueue`, and at least one of `startToCloseTimeout` or `scheduleToCloseTimeout` <!-- docs/develop/java/activities/standalone-activities.mdx:237-238 -->.

## Start without waiting for the result

Use `ActivityClient.start()` to durably enqueue the Standalone Activity and get an `ActivityHandle<R>` back immediately, without blocking on the Worker <!-- docs/develop/java/activities/standalone-activities.mdx:264-269 -->:

```java
ActivityHandle<String> handle =
    client.start(
        GreetingActivities.class,
        GreetingActivities::composeGreeting,
        options,
        "Hello",
        "World");

// Wait for the result later
String result = handle.getResult();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:274-285 -->

## Get a handle to an existing Standalone Activity

Use `client.getHandle()` to create a typed handle to a previously started Standalone Activity. Pass `null` as the run ID to target the latest run of the given Activity ID <!-- docs/develop/java/activities/standalone-activities.mdx:307-317 -->.

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```
<!-- docs/develop/java/activities/standalone-activities.mdx:312-313 -->

The handle can then be used to wait for the result, describe, cancel, or terminate the Activity <!-- docs/develop/java/activities/standalone-activities.mdx:316-317 -->.

## Wait for the result

Under the hood, calling `client.execute()` is equivalent to calling `client.start()` followed by `handle.getResult()` <!-- docs/develop/java/activities/standalone-activities.mdx:321-323 -->.

Blocking:

```java
String result = handle.getResult();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:326 -->

Asynchronous — returns a `CompletableFuture<R>` so the calling thread is not blocked <!-- docs/develop/java/activities/standalone-activities.mdx:329-330 -->:

```java
CompletableFuture<String> future = handle.getResultAsync();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:333 -->

## List Standalone Activities

Use `client.listExecutions()` to list Standalone Activity Executions that match a List Filter query. The result is a `Stream<ActivityExecutionMetadata>` that fetches pages from the server on demand as the stream is consumed <!-- docs/develop/java/activities/standalone-activities.mdx:344-348 -->.

These APIs return ONLY Standalone Activity Executions. Activities running inside Workflows are not included <!-- docs/develop/java/activities/standalone-activities.mdx:350-351 -->.

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:356-362 -->

The query parameter accepts the same List Filter syntax used for Workflow Visibility, for example `ActivityType = 'composeGreeting' AND Status = 'Running'` <!-- docs/develop/java/activities/standalone-activities.mdx:377-378 -->.

## Count Standalone Activities

Use `client.countExecutions()` to count Standalone Activity Executions matching a List Filter query. It returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks <!-- docs/develop/java/activities/standalone-activities.mdx:382-385 -->.

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:391-396 -->

## CLI equivalents

The same operations are available through the Temporal CLI <!-- docs/develop/java/activities/standalone-activities.mdx:251-260,295-305,338-340,373-375,406-409 -->:

```bash
./temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:253-260 -->

```bash
./temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:298-305 -->

```bash
./temporal activity result --activity-id standalone-activity-id
./temporal activity list
./temporal activity count
```
<!-- docs/develop/java/activities/standalone-activities.mdx:339,374,408 -->

## Temporal Cloud

All Java samples use `ClientConfigProfile.load()`, which reads environment variables or a TOML configuration file, so the same code works against a local dev server and Temporal Cloud without changes <!-- docs/develop/java/activities/standalone-activities.mdx:95-101,413-415 -->.

Connect with mTLS — set these environment variables from your Temporal Cloud Namespace settings <!-- docs/develop/java/activities/standalone-activities.mdx:422-430 -->:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:426-429 -->

Connect with an API key — set these environment variables from your Temporal Cloud API key settings <!-- docs/develop/java/activities/standalone-activities.mdx:434-440 -->:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/java/activities/standalone-activities.mdx:437-439 -->

## See also

- `references/core/standalone-activities.md` for cross-language concepts, version compatibility, the full CLI inventory, and feature limitations.
- `references/java/java.md` for general Java SDK setup, dependencies, and Worker/Client patterns.
