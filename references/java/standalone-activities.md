# Standalone Activities — Java SDK

Standalone Activities run independently, without being orchestrated by a Workflow. You start them directly from a Temporal Client using `ActivityClient`. The Activity definition and Worker registration are identical to a Workflow Activity — the same Activity Function can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.
<!-- docs/develop/java/activities/standalone-activities.mdx:29 -->
<!-- docs/develop/java/activities/standalone-activities.mdx:33 -->

Java SDK support for Standalone Activities is at Pre-release; the underlying feature is in Public Preview.
<!-- docs/develop/java/activities/standalone-activities.mdx:22 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:21 -->

## 1. Prerequisites

- Java 8+
- Temporal Java SDK v1.35.0 or higher
- Temporal CLI v1.7.0 or higher
- Temporal Server v1.31.0 or higher
<!-- docs/develop/java/activities/standalone-activities.mdx:60 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:114 -->

Install the CLI with Homebrew:

```bash
brew install temporal
```

Start the local development server (Standalone Activities are enabled by default):

```bash
temporal server start-dev
```
<!-- docs/develop/java/activities/standalone-activities.mdx:71 -->
<!-- docs/develop/java/activities/standalone-activities.mdx:86 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:138 -->

The server listens on `localhost:7233`; the Web UI is at `http://localhost:8233` and exposes a Standalone Activities nav item.
<!-- docs/develop/java/activities/standalone-activities.mdx:105 -->

### Public Preview limitations

- Pause, reset, and update options are not supported in Public Preview but scheduled for GA.
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy is not supported yet.
<!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->

## 2. Define your Activity

An Activity in the Java SDK is an interface annotated with `@ActivityInterface`, with methods annotated with `@ActivityMethod`. The way you define a Standalone Activity is identical to how you define an Activity orchestrated by a Workflow. The same Activity can be executed as a Standalone Activity and as a Workflow Activity.
<!-- docs/develop/java/activities/standalone-activities.mdx:133 -->

```java
@ActivityInterface
public interface GreetingActivities {

  @ActivityMethod
  String composeGreeting(String greeting, String name);
}
```
<!-- docs/develop/java/activities/standalone-activities.mdx:140 -->

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
<!-- docs/develop/java/activities/standalone-activities.mdx:151 -->

## 3. Run a Worker with the Activity registered

Running a Worker for Standalone Activities is the same as running a Worker for Workflow Activities — you create a `WorkerFactory`, register the Activity implementation, and call `factory.start()`. The Worker doesn't need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.
<!-- docs/develop/java/activities/standalone-activities.mdx:166 -->

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
<!-- docs/develop/java/activities/standalone-activities.mdx:174 -->

`ClientConfigProfile.load()` reads environment variables and TOML configuration files, so the same code works against a local dev server and Temporal Cloud.
<!-- docs/develop/java/activities/standalone-activities.mdx:95 -->

## 4. Execute a Standalone Activity (wait for result)

Use `ActivityClient.execute()` to execute a Standalone Activity and block until it completes. Call this from your application code, not from inside a Workflow Definition. This durably enqueues the Standalone Activity in the Temporal Server, waits for it to be executed on your Worker, and then returns the typed result.
<!-- docs/develop/java/activities/standalone-activities.mdx:197 -->

```java
ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());

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
<!-- docs/develop/java/activities/standalone-activities.mdx:205 -->

The typed `execute()` API takes the Activity interface class and an unbound method reference. The SDK uses the method reference to infer the Activity type name and result type at runtime. You can also call Activities by string type name:
<!-- docs/develop/java/activities/standalone-activities.mdx:228 -->

```java
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```
<!-- docs/develop/java/activities/standalone-activities.mdx:233 -->

`StartActivityOptions` requires `id`, `taskQueue`, and at least one of `startToCloseTimeout` or `scheduleToCloseTimeout`.
<!-- docs/develop/java/activities/standalone-activities.mdx:237 -->

## 5. Start a Standalone Activity without waiting for the result

Starting a Standalone Activity sends a request to the Temporal Server to durably enqueue your Activity job, without waiting for it to be executed by your Worker. Use `ActivityClient.start()` to start a Standalone Activity and get a handle:
<!-- docs/develop/java/activities/standalone-activities.mdx:264 -->

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
<!-- docs/develop/java/activities/standalone-activities.mdx:273 -->

### Conflict policy and reuse policy

Standalone Activities support deduplication via a conflict policy (for example `USE_EXISTING`) and a reuse policy (for example `REJECT_DUPLICATES`). The `TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are not supported in Public Preview.
<!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

<!-- VERIFY: The Java doc does not show builder methods on `StartActivityOptions` for setting conflict policy or reuse policy; only the encyclopedia lists the policy values. The exact Java setter names are not in the doc, so they are not shown here. -->

## 6. Get a handle to an existing Standalone Activity

Use `client.getHandle()` to create a typed handle to a previously started Standalone Activity:
<!-- docs/develop/java/activities/standalone-activities.mdx:308 -->

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```
<!-- docs/develop/java/activities/standalone-activities.mdx:311 -->

Pass `null` as the run ID to target the latest run of the given activity ID. You can then use the handle to wait for the result, describe, cancel, or terminate the Activity.
<!-- docs/develop/java/activities/standalone-activities.mdx:316 -->

## 7. Wait for the result of a Standalone Activity

Calling `client.execute()` is equivalent to calling `client.start()` to durably enqueue the Standalone Activity, then calling `handle.getResult()` to block until the Activity completes and return the result:
<!-- docs/develop/java/activities/standalone-activities.mdx:321 -->

```java
String result = handle.getResult();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:325 -->

To wait asynchronously without blocking the calling thread, use `handle.getResultAsync()`, which returns a `CompletableFuture<R>`:
<!-- docs/develop/java/activities/standalone-activities.mdx:329 -->

```java
CompletableFuture<String> future = handle.getResultAsync();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:332 -->

You can also wait for a result by Activity ID with the CLI:

```bash
./temporal activity result --activity-id standalone-activity-id
```
<!-- docs/develop/java/activities/standalone-activities.mdx:338 -->

## 8. List Standalone Activities

Use `client.listExecutions()` to list Standalone Activity Executions that match a List Filter query. The result is a `Stream<ActivityExecutionMetadata>` that fetches pages from the server on demand as the stream is consumed. These APIs return only Standalone Activity Executions — Activities running inside Workflows are not included.
<!-- docs/develop/java/activities/standalone-activities.mdx:344 -->

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:355 -->

The query parameter accepts the same List Filter syntax used for Workflow Visibility, for example `ActivityType = 'composeGreeting' AND Status = 'Running'`.
<!-- docs/develop/java/activities/standalone-activities.mdx:377 -->

## 9. Count Standalone Activities

Use `client.countExecutions()` to count Standalone Activity Executions matching a List Filter query. This returns the total count of executions (running, completed, failed, etc.) — not the number of queued tasks. It works the same way as counting Workflow Executions.
<!-- docs/develop/java/activities/standalone-activities.mdx:382 -->

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:390 -->

## 10. Run with Temporal Cloud

The code samples on this page use `ClientConfigProfile.load()`, so the same code works against Temporal Cloud — just configure the connection via environment variables or a TOML profile. No code changes are needed.
<!-- docs/develop/java/activities/standalone-activities.mdx:413 -->

### Connect with mTLS

Set these environment variables with values from your Temporal Cloud Namespace settings:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:421 -->

### Connect with an API key

Set these environment variables with values from your Temporal Cloud API key settings:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/java/activities/standalone-activities.mdx:433 -->

Then run the Worker and starter code as shown in the earlier sections.
<!-- docs/develop/java/activities/standalone-activities.mdx:442 -->
