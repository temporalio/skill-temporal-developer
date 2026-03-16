# PHP Determinism Protection

## Overview

The PHP SDK does NOT have a sandbox. Unlike Python (exec-based sandbox) and TypeScript (V8 isolates), PHP relies entirely on runtime command-ordering checks and developer discipline.

The `WorkflowPanicPolicy` enum controls what happens when non-determinism is detected at runtime:

```php
use Temporal\Worker\WorkerOptions;
use Temporal\Worker\WorkflowPanicPolicy;

// In worker setup
$worker = $factory->newWorker('task-queue', WorkerOptions::new()
    ->withWorkflowPanicPolicy(WorkflowPanicPolicy::FailWorkflow)
);
```

## Forbidden Operations

These operations must NOT be used in workflow code:

- No I/O: `fopen()`, `file_get_contents()`, `curl_*`, PDO, etc.
- No `sleep()` — use `yield Workflow::timer()`
- No `time()`, `date()`, `microtime()` — use `Workflow::now()`
- No `rand()`, `random_int()`, `uniqid()` — use `yield Workflow::sideEffect()`
- No blocking SPL functions
- No mutable global variables

## Common Issues

RoadRunner-specific issues to watch for:

- **Worker memory leaks:** PHP workers are long-running processes. Configure `max_jobs` in `.rr.yaml` to restart workers periodically.
- **Shared state between workflow executions:** Class-level static variables persist across executions in the same worker process. Avoid mutable statics in workflow code.
- **Long-running PHP processes:** Unlike traditional PHP request/response, RoadRunner workers persist — ensure resources are released properly.

## Best Practices

1. Keep workflow code pure — orchestration only, no side effects
2. Use activities for all I/O and external calls
3. Configure `WorkflowPanicPolicy::FailWorkflow` for development to surface non-determinism immediately
4. Use `WorkflowPanicPolicy::BlockWorkflow` (default) for production to allow investigation without data loss
