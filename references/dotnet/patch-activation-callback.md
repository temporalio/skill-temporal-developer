# Patch Activation Callback (.NET)

First read the cross-SDK concept page: `references/core/patch-activation-callback.md`.

## Overview

By default, on first non-replay with no prior marker, `patched()` (Patched) records a marker and returns true.  During replay, outcomes follow recorded markers (true with matching/earlier marker, false with none).

The patch activation callback, when available, lets a Worker decide whether to activate a patch at that moment (record marker, return true) or defer (return false) to better coordinate rolling deployments.

## Prerequisites

- Understand .NET versioning/patching: https://docs.temporal.io/develop/dotnet/workflows/versioning
- Review patching semantics: https://docs.temporal.io/patching

## Configuring the decision hook

Pseudocode sketch only:

```csharp
// PSEUDOCODE — DO NOT COPY AS-IS
var worker = new TemporalWorker(client, new TemporalWorkerOptions("my-task-queue")
    .OnFirstPatchActivation((string patchId, PatchContext ctx) =>
    {
        // Decide using stable deployment config; avoid time/random
        return Env.GetBool("PATCH_GATE_ENABLE") == true;
    }));
```

## Usage pattern in workflows

Workflow code remains the same; the decision affects only the first non-replay call with no marker:

```csharp
// Normal usage — the callback only influences the first non-replay activation
if (Workflow.Patched("add-fraud-check")) // <!-- docs/develop/dotnet/workflows/versioning.mdx -->
{
    // New code path
}
else
{
    // Old code path
}
```

## Gotchas

- The callback is not consulted during replay; replay follows history markers.
- Base decisions on stable, operator-controlled config (e.g., env var, deployment metadata), not wall-clock time or randomness.

## See also

- Concept page: `references/core/patch-activation-callback.md`
- .NET Versioning guide: https://docs.temporal.io/develop/dotnet/workflows/versioning

