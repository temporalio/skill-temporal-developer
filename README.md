# Temporal Development Skill

A comprehensive skill for building Temporal applications in Python and TypeScript.

## Overview

This skill provides multi-language guidance for Temporal development, combining:
- **Core concepts** shared across languages (determinism, patterns, versioning)
- **Language-specific references** for Python and TypeScript
- **AI/LLM integration patterns** for building durable AI applications

## Structure

```
temporal-dev/
├── SKILL.md                    # Core architecture, quick references (always loaded)
├── references/
│   ├── core/                   # Language-agnostic concepts
│   │   ├── determinism.md      # Why determinism matters, replay mechanics
│   │   ├── patterns.md         # Signals, queries, saga, child workflows
│   │   ├── versioning.md       # Patching, workflow types, worker versioning
│   │   ├── troubleshooting.md  # Decision trees, recovery procedures
│   │   ├── error-reference.md  # Common error types, workflow status
│   │   ├── interactive-workflows.md # Testing signals, updates, queries
│   │   ├── dev-management.md   # Dev cycle & management of server and workers
│   │   ├── logs.md             # Log file locations, search patterns
│   │   └── ai-integration.md   # AI/LLM integration concepts
│   ├── python/                 # Python SDK references
│   │   ├── python.md           # SDK overview, quick start
│   │   ├── sandbox.md          # Python sandbox mechanics
│   │   ├── sync-vs-async.md    # Activity type selection
│   │   ├── patterns.md         # Python implementations
│   │   ├── testing.md          # WorkflowEnvironment, mocking
│   │   ├── error-handling.md   # ApplicationError, retries
│   │   ├── data-handling.md    # Pydantic, encryption
│   │   ├── observability.md    # Logging, metrics
│   │   ├── versioning.md       # Python patching API
│   │   ├── advanced-features.md # Continue-as-new, updates, schedules, dynamic workflows, and more
│   │   └── ai-patterns.md      # Python AI Cookbook patterns
│   └── typescript/             # TypeScript SDK references
│       ├── typescript.md       # SDK overview, quick start
│       ├── patterns.md         # TypeScript implementations
│       ├── testing.md          # TestWorkflowEnvironment
│       ├── error-handling.md   # ApplicationFailure
│       ├── data-handling.md    # Data converters
│       ├── observability.md    # Sinks, logging
│       ├── versioning.md       # TypeScript patching API
│       └── advanced-features.md # Sinks, updates, schedules and more
```

## Progressive Disclosure

The skill uses progressive loading to manage context efficiently:

1. **SKILL.md** - Always loaded when skill triggers
   - Core architecture diagram
   - Determinism quick reference
   - Pattern index with links
   - Troubleshooting quick reference

2. **Core references** - Loaded when discussing concepts
   - Language-agnostic theory and patterns
   - Versioning strategies
   - Troubleshooting decision trees

3. **Language references** - Loaded when working in that language
   - SDK-specific implementations
   - Language-specific gotchas
   - Testing patterns

## Trigger Phrases

The skill activates on phrases like:
- "create a Temporal workflow"
- "write a Temporal activity"
- "debug workflow stuck"
- "fix non-determinism error"
- "Temporal Python" / "Temporal TypeScript"
- "workflow replay"
- "activity timeout"
- "signal workflow" / "query workflow"
- "worker not starting"
- "activity keeps retrying"
- "Temporal heartbeat"
- "continue-as-new"
- "child workflow"
- "saga pattern"
- "workflow versioning"
