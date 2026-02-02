# Temporal Concepts

Understanding how Temporal components interact is essential for troubleshooting.

## How Workers, Workflows, and Tasks Relate

```
┌─────────────────────────────────────────────────────────────────┐
│                     TEMPORAL SERVER                              │
│  Stores workflow history, manages task queues, coordinates work │
└─────────────────────────────────────────────────────────────────┘
                              │
                    Task Queue (named queue)
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         WORKER                                   │
│  Long-running process that polls task queue for work            │
│  Contains: Workflow definitions + Activity implementations       │
│                                                                  │
│  When work arrives:                                              │
│    - Workflow Task → Execute workflow code decisions            │
│    - Activity Task → Execute activity code (business logic)     │
└─────────────────────────────────────────────────────────────────┘
```

**Key Insight**: The workflow code runs inside the worker. If worker code is outdated or buggy, workflow execution fails.

## Workflow Task vs Activity Task

| Task Type | What It Does | Where It Runs | On Failure |
|-----------|--------------|---------------|------------|
| **Workflow Task** | Makes workflow decisions (what to do next) | Worker | **Stalls the workflow** until fixed |
| **Activity Task** | Executes business logic | Worker | Retries per retry policy |

**CRITICAL**: Workflow task errors are fundamentally different from activity task errors:
- **Workflow Task Failure** → Workflow **stops making progress entirely**
- **Activity Task Failure** → Workflow **retries the activity** (workflow still progressing)
