---
name: cadence-developer
description: Develop, debug, and manage Cadence applications with the official Cadence Go and Java SDKs. Use when the user is building workflows, activities, workers, signals, queries, child workflows, retries, continue-as-new flows, search attributes, or replay-safe workflow versioning with Cadence.
version: 0.4.0
---

# Skill: cadence-developer

## Overview

Cadence is a durable execution platform for long-running workflows. This skill provides Cadence guidance for the official Cadence scope used in this repository:

- Core Cadence concepts
- Go SDK
- Java SDK

This skill does not attempt to preserve Temporal-only APIs or non-official Cadence SDK surfaces. For unsupported material, read `references/non-compatible/README.md`.

## Core Architecture

The Cadence service is the orchestration backend. At a high level it stores workflow event history, routes work through task lists, and exposes visibility APIs for listing and searching workflows.

Important Cadence terms:

- **Domain**: A namespace-like isolation boundary in Cadence.
- **Task List**: A named queue that workers poll.
- **Decision Task**: A workflow task delivered to workflow code during replay or progress.
- **Activity Task**: A task delivered to activity workers.

Workers are long-running processes that you run and manage. Each worker polls a task list, executes workflow or activity code, and reports the result back to Cadence.

## Why Determinism Matters

Cadence restores workflow state by replaying event history. Workflow code must therefore be deterministic: on replay it must issue the same commands in the same order for the same history.

If workflow code changes incompatibly, replay can fail with a non-deterministic error and the workflow stops making progress until the code is fixed or the execution is recovered.

See `references/core/determinism.md` and `references/core/versioning.md`.

## Getting Started

### Ensure Cadence CLI is installed

Use the Cadence CLI, not the Temporal CLI.

#### macOS

```bash
brew install cadence-workflow
```

#### Docker

```bash
docker run -it --rm ubercadence/cli:master --help
```

#### Build From Source

Follow the Cadence server repository instructions if you need a locally built CLI.

## Read Relevant References

1. Start with the language guide you are working in:
   - Go -> `references/go/go.md`
   - Java -> `references/java/java.md`
2. Then read the matching `core` and language-specific references for the task at hand.

## Primary References

- `references/core/determinism.md`
- `references/core/patterns.md`
- `references/core/gotchas.md`
- `references/core/versioning.md`
- `references/core/troubleshooting.md`
- `references/core/error-reference.md`
- `references/core/interactive-workflows.md`
- `references/core/dev-management.md`

## Language References

- `references/go/*.md`
- `references/java/*.md`

## Unsupported Material

For Temporal-only capabilities or unsupported SDK surfaces in this repository, see:

- `references/non-compatible/README.md`
- `references/typescript/README.md`
- `references/python/README.md`
- `references/dotnet/README.md`
