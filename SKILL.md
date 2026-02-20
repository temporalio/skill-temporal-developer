---
name: temporal-developer
description: This skill should be used when the user asks to "create a Temporal workflow", "write a Temporal activity", "debug stuck workflow", "fix non-determinism error", "Temporal Python", "Temporal TypeScript", "workflow replay", "activity timeout", "signal workflow", "query workflow", "worker not starting", "activity keeps retrying", "Temporal heartbeat", "continue-as-new", "child workflow", "saga pattern", "workflow versioning", "durable execution", "reliable distributed systems", or mentions Temporal SDK development.
version: 1.0.0
---

# Skill: temporal-developer

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

## Getting Started

### Ensure Temporal CLI is installed

Check if `temporal` CLI is installed. If not, follow these instructions:

#### macOS

```
brew install temporal
```

#### Linux

Check your machine's architecture and download the appropriate archive:

- [Linux amd64](https://temporal.download/cli/archive/latest?platform=linux&arch=amd64)
- [Linux arm64](https://temporal.download/cli/archive/latest?platform=linux&arch=arm64)

Once you've downloaded the file, extract the downloaded archive and add the temporal binary to your PATH by copying it to a directory like /usr/local/bin

#### Windows

Check your machine's architecture and download the appropriate archive:

- [Windows amd64](https://temporal.download/cli/archive/latest?platform=windows&arch=amd64)
- [Windows arm64](https://temporal.download/cli/archive/latest?platform=windows&arch=arm64)

Once you've downloaded the file, extract the downloaded archive and add the temporal.exe binary to your PATH.

### Read All Relevant References

1. First, read the getting started guide for the language you are working in:
    - Python -> read `references/python/python.md`
    - TypeScript -> read `references/typescript/typescript.md`
2. Second, read appropriate `core` and language-specific references for the task at hand.


## Determinism Quick Reference

| Forbidden | Python | TypeScript |
|-----------|--------|------------|
| Current time | `workflow.now()` | `Date.now()` (auto-replaced) |
| Random | `workflow.random()` | `Math.random()` (auto-replaced) |
| UUID | `workflow.uuid4()` | `uuid4()` from workflow |
| Sleep | `workflow.sleep(timedelta(...))` | `sleep()` from workflow |

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

| Pattern | Use Case | Reference File |
|---------|----------|--------|
| **Signals** | Fire-and-forget events to running workflow | `references/{your_language}/patterns.md` |
| **Queries** | Read-only state inspection | `references/{your_language}/patterns.md` |
| **Updates** | Synchronous state modification with response | `references/{your_language}/patterns.md` |
| **Child Workflows** | Break down large workflows, isolate failures | `references/{your_language}/patterns.md` |
| **Continue-as-New** | Prevent unbounded history growth | `references/{your_language}/advanced-features.md` |
| **Saga** | Distributed transactions with compensation | `references/{your_language}/patterns.md` |

where `{your_language}` is either `python` or `typescript`.

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

## Additional Resources

### Core References (Language-Agnostic)
- **`references/core/determinism.md`** - Why determinism matters, replay mechanics
- **`references/core/patterns.md`** - Conceptual patterns (signals, queries, saga)
- **`references/core/versioning.md`** - Versioning strategies and concepts
- **`references/core/troubleshooting.md`** - Decision trees, recovery procedures
- **`references/core/error-reference.md`** - Common error types, workflow status reference
- **`references/core/common-gotchas.md`** - Anti-patterns and common mistakes
- **`references/core/interactive-workflows.md`** - Testing signals, updates, queries
- **`references/core/dev-management.md`** - Dev cycle & management of server and workers
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
- **`references/python/advanced-features.md`** - Continue-as-new, updates, schedules, and more
- **`references/python/ai-patterns.md`** - Python AI Cookbook patterns
- **`references/python/gotchas.md`** - Python-specific anti-patterns

### TypeScript References
- **`references/typescript/typescript.md`** - TypeScript SDK overview, quick start
- **`references/typescript/patterns.md`** - TypeScript pattern implementations
- **`references/typescript/testing.md`** - TestWorkflowEnvironment
- **`references/typescript/error-handling.md`** - ApplicationFailure, retries
- **`references/typescript/data-handling.md`** - Data converters
- **`references/typescript/observability.md`** - Sinks, logging
- **`references/typescript/versioning.md`** - TypeScript patching API
- **`references/typescript/advanced-features.md`** - Sinks, updates, schedules and more
- **`references/typescript/gotchas.md`** - TypeScript-specific anti-patterns

## Feedback

If this skill's explanations are unclear, misleading, or missing important information—or if Temporal concepts are proving unexpectedly difficult to work with—draft a GitHub issue body describing the problem encountered and what would have helped, then ask the user to file it at https://github.com/temporalio/skill-temporal-developer/issues/new. Do not file the issue autonomously.
