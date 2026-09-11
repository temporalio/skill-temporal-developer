# Temporal Spring Boot Integration

## Overview

`io.temporal:temporal-spring-boot-starter`  auto-configures Workers, registers Workflow / Activity / Nexus Service implementations, and exposes `WorkflowClient` as a Spring bean. This eliminates the manual `WorkflowServiceStubs` to `WorkflowClient` to `WorkerFactory` setup required without Spring.

Temporal's Spring Boot integration supports Spring Boot 2.x, 3.x, and 4.x .

## Dependency Setup

Maven :
```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-boot-starter</artifactId>
    <version>1.31.0</version>
</dependency>
```

Gradle :
```groovy
implementation 'io.temporal:temporal-spring-boot-starter:1.31.0'
```

The starter transitively includes `temporal-sdk` and the autoconfigure module.

## Minimal Configuration

The minimum to autowire a `WorkflowClient` is a `connection.target` :

```yaml
spring.temporal:
  connection:
    target: local # shorthand for localhost:7233; use host:port for remote
```

To set a non-default Namespace, add `spring.temporal.namespace` :

```yaml
spring.temporal:
  connection:
    target: local
  namespace: my-namespace
```

### Temporal Cloud with API key

```yaml
spring.temporal:
  connection:
    target: <region>.<account>.tmprl.cloud:7233
    apiKey: <API key>
  namespace: <namespace>
```

### Temporal Cloud with mTLS

```yaml
spring.temporal:
  connection:
    mtls:
      target: <region>.<account>.tmprl.cloud:7233
      key-file: /path/to/key.key
      cert-chain-file: /path/to/cert.pem
  namespace: <namespace>
```

`cert-chain-file` may be omitted when the `key-file` is a PKCS12 bundle that already contains the certificate chain .

## Interface Design and Spring Annotation Layering

Temporal SDK annotations go on **interfaces**, Spring Boot autoconfigure annotations go on **implementation classes**. The interface side is identical to non-Spring usage.

### Workflow interface

```java
package greetingapp;

import io.temporal.workflow.WorkflowInterface;
import io.temporal.workflow.WorkflowMethod;

@WorkflowInterface
public interface GreetingWorkflow {
    @WorkflowMethod
    String greet(String name);
}
```

### Workflow implementation

`io.temporal.spring.boot.WorkflowImpl`  replaces the manual `worker.registerWorkflowImplementationTypes()` call. The `workers` member  names the Worker(s) this class registers with.

```java
package greetingapp;

import io.temporal.activity.ActivityOptions;
import io.temporal.spring.boot.WorkflowImpl;
import io.temporal.workflow.Workflow;

import java.time.Duration;

// No @Component — Temporal creates a new instance per execution.
@WorkflowImpl(workers = "greeting-worker")
public class GreetingWorkflowImpl implements GreetingWorkflow {

    private final GreetActivities activities = Workflow.newActivityStub(
        GreetActivities.class,
        ActivityOptions.newBuilder()
            .setStartToCloseTimeout(Duration.ofSeconds(30))
            .setTaskQueue("greeting-queue")
            .build()
    );

    @Override
    public String greet(String name) {
        return activities.greet(name);
    }
}
```

### Activity interface

```java
package greetingapp;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

@ActivityInterface
public interface GreetActivities {
    @ActivityMethod
    String greet(String name);
}
```

### Activity implementation

`io.temporal.spring.boot.ActivityImpl`  must be applied to a Spring bean; the documented way is to add `@Component` .

```java
package greetingapp;

import io.temporal.spring.boot.ActivityImpl;
import org.springframework.stereotype.Component;

@Component
@ActivityImpl(workers = "greeting-worker") // docs/develop/java/integrations/spring-boot.mdx:157
public class GreetActivitiesImpl implements GreetActivities {

    private final GreetingService greetingService;

    public GreetActivitiesImpl(GreetingService greetingService) {
        this.greetingService = greetingService;
    }

    @Override
    public String greet(String name) {
        return greetingService.composeGreeting(name);
    }
}
```

Nexus Service implementations follow the same pattern using `io.temporal.spring.boot.NexusServiceImpl` ; the impl must be a Spring bean.

## Configure Workers

The integration supports two configuration methods for Workers: explicit configuration and auto-discovery . They compose: auto-discovery is applied **after and on top of** explicit configuration .

### Explicit configuration

The `workers:` block lists Workers and their members :

```yaml
spring.temporal:
  workers:
    - task-queue: greeting-queue
      name: greeting-worker # if omitted, the Task Queue name is used as the Worker name
      workflow-classes:
        - greetingapp.GreetingWorkflowImpl
      activity-beans:
        - greetActivitiesImpl
```

- `task-queue` is the Task Queue the Worker polls.
- `name` is the unique Worker name; it defaults to the Task Queue when omitted .
- `workflow-classes` lists fully qualified Workflow implementation class names .
- `activity-beans` lists Spring bean names of Activity implementations .

### Auto-discovery

Auto-discovery lets you skip listing Workflow classes, Activity beans, and Nexus Service beans by referencing Worker Task Queue names or Worker names on the implementations themselves .

```yaml
spring.temporal:
  workers-auto-discovery:
    packages:
      - greetingapp # docs/develop/java/integrations/spring-boot.mdx:138-142
```

#### Auto-discovery scope

Auto-discovery picks up exactly the following :

- Workflow implementation classes annotated with `io.temporal.spring.boot.WorkflowImpl` .
- Activity beans present in the Spring context whose implementations are annotated with `io.temporal.spring.boot.ActivityImpl` .
- Nexus Service beans present in the Spring context whose implementations are annotated with `io.temporal.spring.boot.NexusServiceImpl` .
- Workers themselves — if a Task Queue or Worker name is referenced by one of the annotations but not explicitly configured, a Worker is created with default options .

Auto-discovered Workflow classes, Activity beans, and Nexus Service beans are registered with configured Workers if not already registered .

`ActivityImpl` and `NexusServiceImpl` only work when the implementation is a Spring bean (for example, annotated with `@Component`) .

### Explicit vs auto-discovery, side by side

Auto-discovery via annotations:

```yaml
spring.temporal:
  workers-auto-discovery:
    packages:
      - greetingapp
```
```java
@Component
@ActivityImpl(workers = "greeting-worker")
public class GreetActivitiesImpl implements GreetActivities { }
```

Explicit registration:

```yaml
spring.temporal:
  workers:
    - task-queue: greeting-queue
      name: greeting-worker
      workflow-classes:
        - greetingapp.GreetingWorkflowImpl
      activity-beans:
        - greetActivitiesImpl
```

Use auto-discovery when implementations are colocated in a package tree (most apps). Use explicit configuration when registering beans defined outside scanned packages, or when you want the YAML to be the single source of truth.

## WorkflowClient Injection

`WorkflowClient` is autowired by the integration . Inject it into any `@Service` or `@RestController`:

```java
@Service
public class GreetingStarter {

    private final WorkflowClient client;

    public GreetingStarter(WorkflowClient client) {
        this.client = client;
    }

    public String startGreeting(String name) {
        var stub = client.newWorkflowStub(
            GreetingWorkflow.class,
            WorkflowOptions.newBuilder()
                .setWorkflowId(UUID.randomUUID().toString())
                .setTaskQueue("greeting-queue") // must match the Worker's Task Queue
                .build()
        );
        return stub.greet(name);
    }
}
```

## Interceptors

Create beans implementing one of `io.temporal.common.interceptors.WorkflowClientInterceptor`, `io.temporal.common.interceptors.ScheduleClientInterceptor`, or `io.temporal.common.interceptors.WorkerInterceptor` . Registration order is controlled by Spring's `org.springframework.core.annotation.Order`  annotation on each bean — lower values run first.

```java
import io.temporal.common.interceptors.WorkerInterceptor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

@Component
@Order(10)
public class TracingWorkerInterceptor implements WorkerInterceptor {
    // ...
}
```

These three interceptor interfaces are the only ordering hook the integration documents — there is no Temporal-specific ordering API. For broader extension (registering Workflow / Activity / Nexus types, modifying Worker or Client options across the SDK), see the [Temporal Plugin system](https://docs.temporal.io/develop/plugins-guide).

## Customization of Options

Create a bean implementing `io.temporal.spring.boot.TemporalOptionsCustomizer<OptionsBuilderType>`  to programmatically adjust options after the YAML/property values are applied. The supported builder types are :

- `WorkflowServiceStubsOptions.Builder`
- `WorkflowClientOptions.Builder`
- `WorkerFactoryOptions.Builder`
- `WorkerOptions.Builder`
- `WorkflowImplementationOptions.Builder`
- `TestEnvironmentOptions.Builder`

For per-Task-Queue or per-Worker-name customization of `WorkerOptions`, use `io.temporal.spring.boot.WorkerOptionsCustomizer` instead of the generic form . For per-Workflow-Type customization of `WorkflowImplementationOptions`, use `io.temporal.spring.boot.WorkflowImplementationOptionsCustomizer` .

## Integrations (metrics and tracing)

The integration picks up a `io.micrometer.core.instrument.MeterRegistry` bean (for example, from Spring Boot Actuator) and reports Temporal metrics through it .

For tracing, the integration picks up the OpenTelemetry bean configured by `spring-cloud-sleuth-otel-autoconfigure`, or a custom `io.opentelemetry.api.OpenTelemetry` / `io.opentracing.Tracer` bean in the application context .

The Spring AI integration (`io.temporal:temporal-spring-ai`) builds on this Spring Boot integration: when on the classpath, its `SpringAiPlugin` auto-registers `ChatModelActivity` with all Temporal Workers created by the Spring Boot integration .

## Testing

Switch the client to an in-memory `io.temporal.testing.TestWorkflowEnvironment` by enabling the test server :

```yaml
spring.temporal:
  test-server:
    enabled: true
```

When `spring.temporal.test-server.enabled: true` is set, the `spring.temporal.connection` block is ignored . You can then autowire the `TestWorkflowEnvironment` alongside `WorkflowClient`:

```java
@SpringBootTest(classes = Test.Configuration.class)
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class Test {
    @Autowired ConfigurableApplicationContext applicationContext;
    @Autowired TestWorkflowEnvironment testWorkflowEnvironment;
    @Autowired WorkflowClient workflowClient;

    @BeforeEach
    void setUp() {
        applicationContext.start();
    }

    @ComponentScan // discovers @Component-annotated Activity beans
    public static class Configuration {}
}
```

For unit tests without Spring, use `TestWorkflowExtension` or `TestWorkflowEnvironment` directly; see [Java SDK test frameworks](https://docs.temporal.io/develop/java/best-practices/testing-suite#test-frameworks). Don't mix Spring integration tests and direct `TestWorkflowExtension` tests in the same test class — pick one.

## Spring-Specific Gotchas

**Workflow impls must not have `@Component`.** Temporal creates a new Workflow instance per execution. Adding `@Component` makes Spring also manage it as a singleton bean, causing confusing lifecycle behavior. Leave `@WorkflowImpl` classes as plain classes with no Spring stereotype.

**Activity beans are Spring singletons.** Temporal may invoke Activity methods concurrently across many Workflow executions. Don't keep mutable instance state on Activity beans — use injected stateless or thread-safe services instead.

**`@WorkflowImpl` / `@ActivityImpl` without `workers-auto-discovery.packages` is silently ignored.** Without the packages list, nothing scans the annotations and nothing registers. Verify in the Temporal UI that the Worker reports the expected Workflow and Activity types.

**`ActivityOptions.setTaskQueue(...)` is still required on Activity stubs.** `@ActivityImpl(workers = "...")`  only binds the Activity bean to a Worker; it doesn't route Activity Task execution. Inside Workflow code, set `.setTaskQueue(...)` on `ActivityOptions` to direct Activity Tasks to the right queue.

**Multiple `DataConverter` beans cause ambiguity.** If you declare more than one `DataConverter` bean, designate the primary by naming one of them `mainDataConverter`.
