# Java Determinism Protection

## Overview

The Java SDK has **no sandbox** and **no static analyzer**. Unlike the Python SDK (which uses a sandbox that blocks non-deterministic operations at runtime) or the TypeScript SDK (which uses V8 isolation to replace non-deterministic functions with deterministic variants), Java relies entirely on developer conventions and runtime replay detection to enforce determinism.

## Forbidden Operations

```java
// BAD: Non-deterministic operations in workflow code
Thread.sleep(1000);
UUID id = UUID.randomUUID();
double val = Math.random();
long now = System.currentTimeMillis();
new Thread(() -> doWork()).start();
CompletableFuture.supplyAsync(() -> compute());

// GOOD: Deterministic Workflow.* alternatives
Workflow.sleep(Duration.ofSeconds(1));
String id = Workflow.randomUUID().toString();
int val = Workflow.newRandom().nextInt();
long now = Workflow.currentTimeMillis();
Promise<Void> promise = Async.procedure(() -> doWork());
CompletablePromise<String> promise = Workflow.newPromise();
```

## Convention-Based Enforcement

Java workflow code runs in a cooperative threading model where only one workflow thread executes at a time under a global lock. The SDK does not intercept or block non-deterministic calls. Instead, non-determinism is detected at **replay time**: if replayed code produces results that differ from the recorded history, the SDK throws a `NonDeterministicException`.

Because Java has no proactive protection, use the `WorkflowReplayer` class to test replay compatibility before deploying workflow code changes.

## Best Practices

1. Always use `Workflow.*` APIs instead of standard Java equivalents for time, randomness, UUIDs, sleeping, and threading
2. Test all workflow code changes with `WorkflowReplayer` against recorded histories
3. Keep workflows focused on orchestration logic; move all I/O and side effects into activities
4. Avoid mutable static state shared across workflow instances
