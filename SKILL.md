---
name: Temporal Development
description: This skill should be used when the user asks to "create a Temporal workflow", "write a Temporal activity", "debug stuck workflow", "fix non-determinism error", "Temporal Python", "Temporal TypeScript", "workflow replay", "activity timeout", "signal workflow", "query workflow", "worker not starting", "activity keeps retrying", "Temporal heartbeat", "continue-as-new", "child workflow", "saga pattern", "workflow versioning", "durable execution", "reliable distributed systems", or mentions Temporal SDK development. Provides multi-language guidance for Python and TypeScript with operational scripts.
version: 1.0.0
---

# Temporal Development

## Overview

Temporal is a durable execution platform that makes workflows survive failures automatically. This skill provides guidance for building Temporal applications in Python and TypeScript.

## Core Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Temporal Cluster                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │  Event History  │  │   Task Queues   │  │   Visibility   │  │
│  │  (Durable Log)  │  │  (Work Router)  │  │   (Search)     │  │
│  └─────────────────┘  └─────────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Poll / Complete
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Worker                                   │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐  │
│  │   Workflow Definitions  │  │   Activity Implementations   │  │
│  │   (Deterministic)       │  │   (Non-deterministic OK)     │  │
│  └─────────────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Components:**
- **Workflows** - Durable, deterministic functions that orchestrate activities
- **Activities** - Non-deterministic operations (API calls, I/O) that can fail and retry
- **Workers** - Long-running processes that poll task queues and execute code
- **Task Queues** - Named queues connecting clients to workers

## History Replay: Why Determinism Matters

Temporal achieves durability through **history replay**:

1. **Initial Execution** - Worker runs workflow, generates Commands, stored as Events in history
2. **Recovery** - On restart/failure, Worker re-executes workflow from beginning
3. **Matching** - SDK compares generated Commands against stored Events
4. **Restoration** - Uses stored Activity results instead of re-executing

**If Commands don't match Events = Non-determinism Error = Workflow blocked**

| Workflow Code | Command | Event |
|--------------|---------|-------|
| Execute activity | `ScheduleActivityTask` | `ActivityTaskScheduled` |
| Sleep/timer | `StartTimer` | `TimerStarted` |
| Child workflow | `StartChildWorkflowExecution` | `ChildWorkflowExecutionStarted` |

See `references/core/determinism.md` for detailed explanation.

## Determinism Quick Reference

| Forbidden | Python | TypeScript |
|-----------|--------|------------|
| Current time | `workflow.now()` | `Date.now()` (auto-replaced) |
| Random | `workflow.random()` | `Math.random()` (auto-replaced) |
| UUID | `workflow.uuid4()` | `uuid4()` from workflow |
| Sleep | `asyncio.sleep()` | `sleep()` from workflow |

**Python sandbox**: Explicit protection, use `workflow.unsafe.imports_passed_through()` for libraries
**TypeScript sandbox**: V8 isolation, automatic replacements, use type-only imports for activities

## Language Selection

### Python
- Decorators: `@workflow.defn`, `@workflow.run`, `@activity.defn`
- Async/await throughout
- Explicit sandbox with pass-through pattern
- **Critical**: Separate workflow and activity files for performance
- See `references/python/python.md`

### TypeScript
- Functions exported from workflow file
- `proxyActivities()` with type-only imports
- V8 sandbox with automatic replacements
- Webpack bundling for workflows
- See `references/typescript/typescript.md`

## Pattern Index

| Pattern | Use Case | Python | TypeScript |
|---------|----------|--------|------------|
| **Signals** | Fire-and-forget events to running workflow | `references/python/patterns.md` | `references/typescript/patterns.md` |
| **Queries** | Read-only state inspection | `references/python/patterns.md` | `references/typescript/patterns.md` |
| **Updates** | Synchronous state modification with response | `references/python/patterns.md` | `references/typescript/patterns.md` |
| **Child Workflows** | Break down large workflows, isolate failures | `references/python/patterns.md` | `references/typescript/patterns.md` |
| **Continue-as-New** | Prevent unbounded history growth | `references/python/advanced-features.md` | `references/typescript/advanced-features.md` |
| **Saga** | Distributed transactions with compensation | `references/python/patterns.md` | `references/typescript/patterns.md` |

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| Workflow stuck (RUNNING but no progress) | Worker not running or wrong task queue | Check worker, verify task queue name |
| `NondeterminismError` | Code changed mid-execution | Use patching API or reset workflow |
| Activity keeps retrying | Activity throwing errors | Check activity logs, fix root cause |
| Workflow FAILED | Unhandled exception in workflow | Check workflow error, fix code |
| Timeout errors | Timeout too short or activity stuck | Increase timeout or add heartbeats |

See `references/core/troubleshooting.md` for decision trees and detailed recovery steps.

## Versioning

To safely change workflow code while workflows are running:

1. **Patching API** - Code-level branching for old vs new paths
2. **Workflow Type Versioning** - New workflow type for incompatible changes
3. **Worker Versioning** - Deployment-level control with Build IDs

See `references/core/versioning.md` for concepts, language-specific files for implementation.

## Scripts (Operational)

Available scripts in `scripts/` for worker and workflow management:

### Server & Worker Lifecycle
| Script | Purpose |
|--------|---------|
| `ensure-server.sh` | Start Temporal dev server if not running |
| `ensure-worker.sh` | Start worker for project (kills existing first) |
| `list-workers.sh` | List running workers |
| `kill-worker.sh` | Stop a specific worker |
| `kill-all-workers.sh` | Stop ALL workers (cleanup) |
| `monitor-worker-health.sh` | Check worker health, uptime, recent errors |

### Workflow Operations
| Script | Purpose |
|--------|---------|
| `list-recent-workflows.sh` | Show recent workflow executions |
| `get-workflow-result.sh` | Get output/result from completed workflow |
| `find-stalled-workflows.sh` | Find workflows not making progress |
| `analyze-workflow-error.sh` | Diagnose workflow failures |
| `bulk-cancel-workflows.sh` | Cancel multiple workflows by ID or pattern |

### Utilities (used by other scripts)
| Script | Purpose |
|--------|---------|
| `wait-for-workflow-status.sh` | Poll until workflow reaches target status |
| `wait-for-worker-ready.sh` | Poll log file for worker startup |
| `find-project-workers.sh` | Helper to find worker PIDs for a project |

## Additional Resources

### Core References (Language-Agnostic)
- **`references/core/determinism.md`** - Why determinism matters, replay mechanics
- **`references/core/patterns.md`** - Conceptual patterns (signals, queries, saga)
- **`references/core/versioning.md`** - Versioning strategies and concepts
- **`references/core/troubleshooting.md`** - Decision trees, recovery procedures
- **`references/core/error-reference.md`** - Common error types, workflow status reference
- **`references/core/interactive-workflows.md`** - Testing signals, updates, queries
- **`references/core/tool-reference.md`** - Script options and worker management details
- **`references/core/logs.md`** - Log file locations and search patterns
- **`references/core/ai-integration.md`** - AI/LLM integration patterns

### Python References
- **`references/python/python.md`** - Python SDK overview, quick start
- **`references/python/sandbox.md`** - Python sandbox mechanics
- **`references/python/sync-vs-async.md`** - Activity type selection, event loop
- **`references/python/patterns.md`** - Python pattern implementations
- **`references/python/testing.md`** - WorkflowEnvironment, mocking
- **`references/python/error-handling.md`** - ApplicationError, retries
- **`references/python/data-handling.md`** - Pydantic, encryption
- **`references/python/observability.md`** - Logging, metrics, tracing
- **`references/python/versioning.md`** - Python patching API
- **`references/python/advanced-features.md`** - Continue-as-new, interceptors
- **`references/python/ai-patterns.md`** - Python AI Cookbook patterns

### TypeScript References
- **`references/typescript/typescript.md`** - TypeScript SDK overview, quick start
- **`references/typescript/patterns.md`** - TypeScript pattern implementations
- **`references/typescript/testing.md`** - TestWorkflowEnvironment
- **`references/typescript/error-handling.md`** - ApplicationFailure, retries
- **`references/typescript/data-handling.md`** - Data converters
- **`references/typescript/observability.md`** - Sinks, logging
- **`references/typescript/versioning.md`** - TypeScript patching API
- **`references/typescript/advanced-features.md`** - Cancellation scopes, interceptors
