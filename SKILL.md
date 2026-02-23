---
name: temporal-developer
description: This skill should be used when the user asks to "create a Temporal workflow", "write a Temporal activity", "debug stuck workflow", "fix non-determinism error", "Temporal Python", "workflow replay", "activity timeout", "signal workflow", "query workflow", "worker not starting", "activity keeps retrying", "Temporal heartbeat", "continue-as-new", "child workflow", "saga pattern", "workflow versioning", "durable execution", "reliable distributed systems", or mentions Temporal SDK development.
version: 1.0.0
---

# Skill: temporal-developer

## Overview

Temporal is a durable execution platform that makes workflows survive failures automatically. This skill provides guidance for building Temporal applications in Python.

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
2. Second, read appropriate `core` and language-specific references for the task at hand.


## Primary References
- **`references/core/determinism.md`** - Why determinism matters, replay mechanics, basic concepts of activities
    + Langauge-specific info at `references/{your_language}/determinism.md`
- **`references/core/patterns.md`** - Conceptual patterns (signals, queries, saga)
    + Langauge-specific info at `references/{your_language}/determinism.md`
- **`references/core/gotchas.md`** - Anti-patterns and common mistakes
    + Langauge-specific info at `references/{your_language}/determinism.md`
- **`references/core/versioning.md`** - Versioning strategies and concepts - how to safely change workflow code while workflows are running
    + Langauge-specific info at `references/{your_language}/determinism.md`
- **`references/core/troubleshooting.md`** - Decision trees, recovery procedures
- **`references/core/error-reference.md`** - Common error types, workflow status reference
- **`references/core/interactive-workflows.md`** - Testing signals, updates, queries
- **`references/core/dev-management.md`** - Dev cycle & management of server and workers
- **`references/core/ai-patterns.md`** - AI/LLM pattern concepts
    + Langauge-specific info at `references/{your_language}/determinism.md`

## Additional Topics
- **`references/{your_langauge}/observability.md`** - See for language-specific implementation guidance on observability in Temporal
- **`references/{your_langauge}/advanced-features.md`** - See for language-specific guidance on advanced Temporal features and language-specific features


## Feedback

If this skill's explanations are unclear, misleading, or missing important information—or if Temporal concepts are proving unexpectedly difficult to work with—draft a GitHub issue body describing the problem encountered and what would have helped, then ask the user to file it at https://github.com/temporalio/skill-temporal-developer/issues/new. Do not file the issue autonomously.
