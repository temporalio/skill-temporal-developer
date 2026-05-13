# Standalone Activities — Java SDK

## Overview

Standalone Activities are Activities that run independently, without being
orchestrated by a Workflow. <!-- docs/develop/java/activities/standalone-activities.mdx:29 -->
You define a Standalone Activity exactly the same way you define a Workflow
Activity — an interface annotated with `@ActivityInterface` whose methods are
annotated with `@ActivityMethod`. <!-- docs/develop/java/activities/standalone-activities.mdx:133 -->
The key Java idiosyncrasy is the **invocation surface**: a Standalone Activity is
started directly from a Temporal Client via `ActivityClient`, not from a
Workflow Definition and not via `WorkflowClient`. <!-- docs/develop/java/activities/standalone-activities.mdx:31 -->
The same Activity can be executed both as a Standalone Activity and as a
Workflow Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:135 -->

## Support stage and minimum SDK version

- Temporal Java SDK support for Standalone Activities is at
  **Pre-release**. <!-- docs/develop/java/activities/standalone-activities.mdx:24 -->
- **Temporal Java SDK** v1.35.0 or higher. <!-- docs/develop/java/activities/standalone-activities.mdx:64 -->
- **Java** 8+. <!-- docs/develop/java/activities/standalone-activities.mdx:62 -->
- **Temporal CLI** v1.7.0 or higher (for the CLI parity commands shown below). <!-- docs/develop/java/activities/standalone-activities.mdx:67 -->

## Define the Activity

An Activity is an interface annotated with `@ActivityInterface`, with methods
annotated with `@ActivityMethod`. <!-- docs/develop/java/activities/standalone-activities.mdx:133 -->
The interface and implementation are identical to a Workflow Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:134 -->

```java
@ActivityInterface
public interface GreetingActivities {

  @ActivityMethod
  String composeGreeting(String greeting, String name);
}
```
<!-- docs/develop/java/activities/standalone-activities.mdx:141 -->

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
<!-- docs/develop/java/activities/standalone-activities.mdx:152 -->

## Run a Worker with the Activity registered

Running a Worker for Standalone Activities is the same as running a Worker for
Workflow Activities — create a `WorkerFactory`, register the Activity
implementation, and call `factory.start()`. The Worker doesn't need to know
whether the Activity will be invoked from a Workflow or as a Standalone
Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:166 -->

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

Note that the Worker is wired up via `WorkflowClient` /
`WorkerFactory.newInstance(client)` even though it processes a Standalone
Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:179 -->

## Construct an `ActivityClient`

To invoke a Standalone Activity from application code, construct an
`ActivityClient` against the same `WorkflowServiceStubs`. The Namespace is
sourced from the loaded `ClientConfigProfile`.

```java
ActivityClient client =
    ActivityClient.newInstance(
        service,
        ActivityClientOptions.newBuilder().setNamespace(profile.getNamespace()).build());
```
<!-- docs/develop/java/activities/standalone-activities.mdx:206 -->

## Execute a Standalone Activity (typed)

`ActivityClient.execute()` durably enqueues the Standalone Activity on the
Temporal Server, waits for it to be picked up by a Worker, and returns the
typed result. Call it from application code, **not** from inside a Workflow
Definition. <!-- docs/develop/java/activities/standalone-activities.mdx:197 -->

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
<!-- docs/develop/java/activities/standalone-activities.mdx:211 -->

The typed `execute()` overload takes the Activity interface class and an
unbound method reference. The SDK uses the method reference to infer the
Activity type name and result type at runtime. <!-- docs/develop/java/activities/standalone-activities.mdx:228 -->

## Execute by string type name

You can also call Activities by string type name when you do not have the
interface available on the classpath:

```java
// Using a string type name
String result = client.execute("ComposeGreeting", String.class, options, "Hello", "World");
```
<!-- docs/develop/java/activities/standalone-activities.mdx:233 -->

## `StartActivityOptions` required fields

`StartActivityOptions` requires:

- `id`
- `taskQueue`
- at least one of `startToCloseTimeout` or `scheduleToCloseTimeout`

<!-- docs/develop/java/activities/standalone-activities.mdx:237 -->

## Start a Standalone Activity without waiting for the result

Starting (as opposed to executing) sends the request to the Temporal Server
to durably enqueue the Activity job, but does **not** block waiting for the
Worker to run it. <!-- docs/develop/java/activities/standalone-activities.mdx:264 -->
`ActivityClient.start()` returns an `ActivityHandle<R>` parameterized on the
result type. <!-- docs/develop/java/activities/standalone-activities.mdx:267 -->

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

## Get a handle to an existing Standalone Activity

`client.getHandle()` returns a typed `ActivityHandle<R>` for a previously
started Standalone Activity. Pass `null` as the run ID to target the latest
run of the given Activity ID. <!-- docs/develop/java/activities/standalone-activities.mdx:316 -->

```java
ActivityHandle<String> handle =
    client.getHandle("standalone-activity-id", null, String.class);
```
<!-- docs/develop/java/activities/standalone-activities.mdx:312 -->

You can then use the handle to wait for the result, describe, cancel, or
terminate the Activity. <!-- docs/develop/java/activities/standalone-activities.mdx:316 -->

## Wait for the result

`client.execute()` is implemented as `client.start()` followed by
`handle.getResult()` — `getResult()` blocks until the Activity completes and
returns the result. <!-- docs/develop/java/activities/standalone-activities.mdx:321 -->

```java
String result = handle.getResult();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:325 -->

To wait asynchronously without blocking the calling thread, use
`handle.getResultAsync()`, which returns a `CompletableFuture<R>`. <!-- docs/develop/java/activities/standalone-activities.mdx:329 -->

```java
CompletableFuture<String> future = handle.getResultAsync();
```
<!-- docs/develop/java/activities/standalone-activities.mdx:332 -->

## List Standalone Activities

`client.listExecutions()` returns a `Stream<ActivityExecutionMetadata>` that
fetches pages from the server on demand as the stream is consumed. The query
parameter is a [List Filter](/list-filter) string. <!-- docs/develop/java/activities/standalone-activities.mdx:344 -->

These APIs return **only** Standalone Activity Executions. Activities running
inside Workflows are not included. <!-- docs/develop/java/activities/standalone-activities.mdx:350 -->

```java
client
    .listExecutions("TaskQueue = '" + TASK_QUEUE + "'")
    .forEach(
        info ->
            System.out.printf(
                "ActivityID: %s, Type: %s, Status: %s%n",
                info.getActivityId(), info.getActivityType(), info.getStatus()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:356 -->

The query parameter accepts the same List Filter syntax used for Workflow
Visibility — for example, `ActivityType = 'composeGreeting' AND Status = 'Running'`. <!-- docs/develop/java/activities/standalone-activities.mdx:377 -->

## Count Standalone Activities

`client.countExecutions()` returns an `ActivityExecutionCount` for the given
List Filter query. The returned count covers running, completed, failed, etc.
executions — not the number of queued tasks. <!-- docs/develop/java/activities/standalone-activities.mdx:382 -->

```java
ActivityExecutionCount resp = client.countExecutions("TaskQueue = '" + TASK_QUEUE + "'");
System.out.println("Total activities: " + resp.getCount());
resp.getGroups()
    .forEach(
        group ->
            System.out.println("Group " + group.getGroupValues() + ": " + group.getCount()));
```
<!-- docs/develop/java/activities/standalone-activities.mdx:390 -->

`ActivityExecutionCount.getCount()` returns the total count.
`ActivityExecutionCount.getGroups()` is iterable; each group exposes
`getGroupValues()` and `getCount()`. <!-- docs/develop/java/activities/standalone-activities.mdx:390 -->

## CLI parity

The Temporal CLI offers Standalone Activity commands that mirror the Java SDK
calls above. The docs file invokes the CLI as `./temporal` (a local binary in
the working directory); the snippets below reproduce that convention exactly.

Execute and block for a result: <!-- docs/develop/java/activities/standalone-activities.mdx:252 -->

```bash
./temporal activity execute \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:253 -->

Start without waiting: <!-- docs/develop/java/activities/standalone-activities.mdx:297 -->

```bash
./temporal activity start \
  --type ComposeGreeting \
  --activity-id standalone-activity-id \
  --task-queue standalone-activity-task-queue \
  --start-to-close-timeout 10s \
  --input '"Hello"' \
  --input '"World"'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:298 -->

Wait for a result by Activity ID: <!-- docs/develop/java/activities/standalone-activities.mdx:336 -->

```bash
./temporal activity result --activity-id standalone-activity-id
```
<!-- docs/develop/java/activities/standalone-activities.mdx:338 -->

List Standalone Activities: <!-- docs/develop/java/activities/standalone-activities.mdx:371 -->

```bash
./temporal activity list
```
<!-- docs/develop/java/activities/standalone-activities.mdx:373 -->

Count Standalone Activities: <!-- docs/develop/java/activities/standalone-activities.mdx:405 -->

```bash
./temporal activity count
```
<!-- docs/develop/java/activities/standalone-activities.mdx:407 -->

## Connect via environment configuration

All code samples on this page use `ClientConfigProfile.load()` to configure
the Temporal Client connection. It responds to environment variables and TOML
configuration files, so the same code works against a local development
server and Temporal Cloud without changes. <!-- docs/develop/java/activities/standalone-activities.mdx:96 -->

For Temporal Cloud connections, no code changes are needed — configure the
connection via environment variables or a TOML profile. <!-- docs/develop/java/activities/standalone-activities.mdx:413 -->

### Connect with mTLS

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/java/activities/standalone-activities.mdx:425 -->

### Connect with an API key

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/java/activities/standalone-activities.mdx:436 -->
