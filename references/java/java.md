# Cadence Java SDK Reference

## Overview

The Cadence Java SDK uses `com.uber.cadence`. Workflows are typically expressed as annotated interfaces plus implementation classes.

## Dependency

Maven:

```xml
<dependency>
  <groupId>com.uber.cadence</groupId>
  <artifactId>cadence-client</artifactId>
  <version>LATEST.RELEASE.VERSION</version>
</dependency>
```

## Quick Start

Workflow interface:

```java
public interface GreetingWorkflow {
  @WorkflowMethod
  String run(String name);
}
```

Workflow implementation:

```java
public class GreetingWorkflowImpl implements GreetingWorkflow {
  private final GreetingActivities activities =
      Workflow.newActivityStub(
          GreetingActivities.class,
          new ActivityOptions.Builder()
              .setStartToCloseTimeout(Duration.ofMinutes(1))
              .build());

  @Override
  public String run(String name) {
    return activities.greet(name);
  }
}
```

Activity interface and implementation:

```java
public interface GreetingActivities {
  String greet(String name);
}

public class GreetingActivitiesImpl implements GreetingActivities {
  @Override
  public String greet(String name) {
    return "Hello, " + name + "!";
  }
}
```

## Key Concepts

- One `@WorkflowMethod` per workflow interface
- Optional `@SignalMethod` and `@QueryMethod`
- Workers poll task lists
- Workflow code must stay deterministic

## Read Next

- `references/java/determinism.md`
- `references/java/patterns.md`
- `references/java/error-handling.md`
- `references/java/testing.md`
- `references/java/versioning.md`
