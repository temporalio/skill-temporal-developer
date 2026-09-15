# Patch Activation Callback (Python)

First read the cross-SDK concept page: `references/core/patch-activation-callback.md`.

## Overview

On first non-replay with no prior marker, `workflow.patched()` records a patch marker and returns `True`.  During replay, outcomes follow history (true with matching/earlier marker; false with none).

The patch activation callback (when available) lets a Worker decide whether to activate at that first non-replay call, useful for coordinating rolling deployments.

## Prerequisites

- Python Versioning guide: https://docs.temporal.io/develop/python/workflows/versioning
- Patching Encyclopedia entry: https://docs.temporal.io/patching

## Configuring the decision hook

Pseudocode sketch only:

```python
# PSEUDOCODE — DO NOT COPY AS-IS
from temporalio.worker import Worker, WorkerOptions  # <-- names illustrative only

def on_first_patch_activation(patch_id: str, ctx) -> bool:
    # Decide using stable deployment config; avoid time/random
    return os.getenv("PATCH_GATE_ENABLE") == "1"

worker = Worker(
    client,
    task_queue="my-task-queue",
    # on_first_patch_activation=on_first_patch_activation,  # VERIFY API name
)
```

## Usage pattern in workflows

Workflow code remains the same; the decision affects only the first non-replay call with no marker:

```python
from temporalio import workflow

if workflow.patched("add-fraud-check"):  # <!-- docs/develop/python/workflows/versioning.mdx -->
    # New path
    ...
else:
    # Old path
    ...
```

## Gotchas

- The callback is not consulted during replay; replay follows markers.
- Use operator-controlled config or deployment metadata; avoid time-of-day or instance randomness.

## See also

- Concept page: `references/core/patch-activation-callback.md`
- Python Versioning: https://docs.temporal.io/develop/python/workflows/versioning

