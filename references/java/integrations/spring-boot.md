# Temporal Spring Boot Integration

## Overview

`temporal-spring-boot-starter` auto-configures workers, registers workflow/activity implementations, and exposes `WorkflowClient` as a Spring bean. This eliminates the manual `WorkflowServiceStubs` → `WorkflowClient` → `WorkerFactory` setup required without Spring.

## Dependency Setup

Maven:

```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-boot-starter</artifactId>
    <version>1.40.0</version>
</dependency>
```

Gradle:

```groovy
implementation 'io.temporal:temporal-spring-boot-starter:1.40.0'
```

The starter transitively includes `temporal-sdk` and the autoconfigure module. You can declare both `temporal-sdk` and `temporal-spring-boot-starter` explicitly, but the starter alone is sufficient.

Spring Boot 3 and Spring Boot 4 are supported; Boot 4 / Jackson 3 support requires Java SDK 1.34+. Keep Temporal dependencies aligned. Spring AI integrations have separate Boot 3 / AI 1 and Boot 4 / AI 2 coordinates; see [Spring AI](spring-ai.md).

## Minimal Configuration

`application.properties`:

```properties
spring.temporal.connection.target=local
spring.temporal.start-workers=true
spring.temporal.workers-auto-discovery.enabled=true
spring.temporal.workers-auto-discovery.workflow-packages=greetingapp
```

`application.yml` equivalent:

```yaml
spring:
  temporal:
    connection:
      target: local  # shorthand for localhost:7233
    start-workers: true
    workers-auto-discovery:
      enabled: true
      workflow-packages:
        - greetingapp
    workers:
      - task-queue: greeting-queue
        name: greeting-worker
```

For self-hosted Temporal, replace `local` with the server address:

```properties
spring.temporal.connection.target=temporal.internal:7233
```

## Interface Design + Spring Annotation Layering

The key concept: Temporal SDK annotations go on **interfaces**, Spring Boot autoconfigure annotations go on **implementation classes**. This is identical to non-Spring usage at the interface level.

### Workflow Interface (unchanged from non-Spring)

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

### Workflow Implementation

```java
package greetingapp;

import io.temporal.activity.ActivityOptions;
import io.temporal.spring.boot.WorkflowImpl;
import io.temporal.workflow.Workflow;

import java.time.Duration;

// @WorkflowImpl replaces manual worker.registerWorkflowImplementationTypes()
// No @Component — workflows are NOT Spring beans; Temporal creates a new instance per execution
@WorkflowImpl(taskQueues = "greeting-queue")
public class GreetingWorkflowImpl implements GreetingWorkflow {

    // Activity stubs created via Workflow.newActivityStub() as usual
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

### Activity Interface (unchanged from non-Spring)

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

### Activity Implementation

```java
package greetingapp;

import io.temporal.spring.boot.ActivityImpl;
import org.springframework.stereotype.Component;

// @Component makes this a Spring bean — dependencies can be injected normally
// @ActivityImpl replaces manual worker.registerActivitiesImplementations()
@Component
@ActivityImpl(taskQueues = "greeting-queue")
public class GreetActivitiesImpl implements GreetActivities {

    private final GreetingService greetingService;

    // Constructor injection works because this is a Spring bean
    public GreetActivitiesImpl(GreetingService greetingService) {
        this.greetingService = greetingService;
    }

    @Override
    public String greet(String name) {
        return greetingService.composeGreeting(name);
    }
}
```

## Auto-Discovery

Set `spring.temporal.workers-auto-discovery.enabled=true` to register Spring beans annotated with `@ActivityImpl`, `@NexusServiceImpl`, or `@WorkflowImpl`. For Workflow classes such as the example above that live outside the Spring context, also set `spring.temporal.workers-auto-discovery.workflow-packages` to their package names.

Use `taskQueues = "greeting-queue"` to register an implementation by Task Queue. Auto-discovery creates a Worker with default options if the Task Queue has no configured Worker. Use `workers = "greeting-worker"` to register by name when the Worker is already configured. An unknown Worker name causes startup to fail.

**Important:** `@ActivityImpl(taskQueues = "greeting-queue")` only registers the activity bean with that worker. It does not route individual activity task executions. Activity stubs default to the Task Queue the Workflow was started on. Set `ActivityOptions.setTaskQueue(...)` only to route Activities to a different queue.

### Comparison: Auto-Discovery vs Explicit YAML Registration

Auto-discovery via annotations:

```properties
spring.temporal.workers-auto-discovery.enabled=true
spring.temporal.workers-auto-discovery.workflow-packages=greetingapp
```

```java
@Component
@ActivityImpl(taskQueues = "greeting-queue")
public class GreetActivitiesImpl implements GreetActivities { ... }
```

Explicit YAML registration (alternative):

```yaml
spring:
  temporal:
    workers:
      - task-queue: greeting-queue
        name: greeting-worker
        activity-beans:
          - greetActivitiesImpl
        workflow-classes:
          - greetingapp.GreetingWorkflowImpl
```

Use auto-discovery when implementations are colocated in a single package tree (most apps). Use explicit YAML when you need fine-grained control, want to exclude specific classes, or are registering beans defined elsewhere.

### Migrating legacy configuration

If your configuration uses `spring.temporal.workers-auto-discovery.packages`, remove it before setting `enabled` or `workflow-packages`. The starter rejects configurations that combine the legacy property with either setting.

## Customize Worker Options

Register a Spring bean implementing `WorkerOptionsCustomizer` when an option depends on the Worker name or Task Queue. Spring calls it after applying the properties for each Worker. Return the builder with any overrides.

```java
import io.temporal.spring.boot.WorkerOptionsCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class TemporalWorkerConfiguration {
    @Bean
    WorkerOptionsCustomizer workerOptions() {
        return (builder, workerName, taskQueue) -> {
            if ("greeting-queue".equals(taskQueue)) {
                builder.setMaxConcurrentActivityExecutionSize(16);
            }
            return builder;
        };
    }
}
```

## WorkflowClient Injection

`WorkflowClient` is automatically registered as a Spring bean by the autoconfigure. Inject it into any `@Service` or `@RestController`:

```java
package greetingapp;

import io.temporal.client.WorkflowClient;
import io.temporal.client.WorkflowOptions;
import org.springframework.stereotype.Service;

import java.util.UUID;

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
                .setTaskQueue("greeting-queue")  // must match the worker's task queue
                .build()
        );
        // Synchronous — blocks until workflow completes
        return stub.greet(name);
    }

    public void startGreetingAsync(String name) {
        var stub = client.newWorkflowStub(
            GreetingWorkflow.class,
            WorkflowOptions.newBuilder()
                .setWorkflowId(UUID.randomUUID().toString())
                .setTaskQueue("greeting-queue")
                .build()
        );
        // Fire-and-forget — returns immediately
        WorkflowClient.start(stub::greet, name);
    }
}
```

## Worker Lifecycle

Workers start on `ApplicationReadyEvent` — after the full Spring context is initialized (DB migrations run, all beans wired). This means activity beans are fully ready before any workflow tasks are processed.

To run a client-only app (one that submits workflows but does not execute them):

```properties
spring.temporal.start-workers=false
```

## Testing Strategies

See [Java testing guide](../testing.md) for full details on both approaches.

**Spring integration tests** — uses an embedded Temporal test server wired into the Spring context:

```properties
# src/test/resources/application-test.properties
spring.temporal.test-server.enabled=true
```

```java
@SpringBootTest
@ActiveProfiles("test")
class GreetingIntegrationTest {
    @Autowired WorkflowClient client;  // points at the embedded test server

    @Test
    void testWorkflowThroughSpringContext() { ... }
}
```

**Unit tests without Spring** — use `TestWorkflowEnvironment` or `TestWorkflowExtension` directly. No Spring context, faster startup, full time-skipping support:

```java
@RegisterExtension
static final TestWorkflowExtension testWorkflow = TestWorkflowExtension.newBuilder()
    .setWorkflowTypes(GreetingWorkflowImpl.class)
    .setDoNotStart(true)
    .build();
```

Do not mix approaches in the same test class — choose one or the other.

## Spring-Specific Gotchas

**Workflow impls must not have `@Component`**
Temporal creates a new workflow instance per execution via `beanFactory.createBean()` (not `getBean()`). Adding `@Component` means Spring also registers it as a singleton bean, which can cause confusing lifecycle behavior. Leave `@WorkflowImpl` classes as plain classes with no Spring annotations.

**Activity beans are Spring singletons**
Temporal may invoke activity methods concurrently across many workflow executions. Keep activity implementations stateless — no mutable instance fields. Use injected services (which are themselves stateless or thread-safe) for all state.

**The Worker starts without an expected implementation**
Check that the implementation has the matching Spring annotation and Task Queue or Worker name. For non-bean Workflow implementations, check that `workflow-packages` includes their package.

**Activity stubs inherit the Workflow Task Queue**
`@ActivityImpl(taskQueues = "greeting-queue")` registers the activity bean with the worker — it does not set the default task queue for activity execution. An Activity stub defaults to the Task Queue the Workflow was started on; set `.setTaskQueue(...)` when the Activity Worker polls a different queue.

**Multiple `DataConverter` beans**
If you define more than one `DataConverter` bean (e.g., a custom JSON converter and a default), the autoconfigure fails with an ambiguity error. Name one of them `mainDataConverter` to designate it as the primary.
