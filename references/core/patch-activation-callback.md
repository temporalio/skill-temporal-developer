# Patch Activation Callback (Concepts)

This document explains how to control whether a patch activates on the first non-replay call, to make rolling deployments safer. For SDK-specific pages, see `references/{your_language}/patch-activation-callback.md`.

## Overview

By default, when a Workflow execution is not replaying and it encounters a `patched()` call with no prior marker for that patch ID, the SDK records a patch marker in history and returns `true`.  This “first non-replay activation” means new executions will normally take the new code path immediately.

During replay, `patched()` behavior differs: with a matching or earlier marker, it returns `true` without modifying history; with no marker, it returns `false` and does not add a marker.   Because of replay boundaries, a Workflow does not always run the newest code.

In rolling deployments, you may want to delay this first activation to avoid uneven cutovers while a subset of Workers is on the new build. Blue/green or rainbow deployments are the recommended alternative (via Worker Versioning); rolling deployments are explicitly incompatible with Worker Versioning, in which case patching remains the fallback.

The “patch activation callback” is a Worker-scoped decision point that runs exactly when `patched()` would first activate (non-replay, no prior marker). It decides whether to activate now (record marker, return true) or defer (return false).

## When to use

- You deploy with rolling updates and need to coordinate patch activation across a mixed fleet until a safe threshold is met.
- You cannot yet adopt Worker Versioning’s blue/green or rainbow strategies; patching is your safety tool.

Prefer Worker Versioning when possible; it avoids patch branching in many cases.

## Behavior and constraints

- Scope: The decision applies only to the first non-replay call with no prior marker for a given patch ID in a run. Subsequent outcomes follow history (presence/absence of the marker) per normal `patched()` semantics.
- Replay safety: The callback is not consulted during replay; replay behavior remains governed by recorded patch markers.
- Determinism discipline: Base the decision on stable deployment configuration (for example, a fleet-wide gate) rather than wall-clock time or per-pod randomness, to avoid inconsistent cutovers across Workers.

## Recommended activation policies

These are deployment patterns, not SDK APIs. Implement them only if/when your SDK exposes a patch-activation decision hook.

- Fleet gate: Activate only if a deployment-controlled flag (environment/config) is set for the new build. Flip the flag when a sufficient portion of the fleet is updated.
- Version threshold: Activate only on Workers whose deployment version is in a pre-approved set (e.g., “ramping” or “current”).
- Staggered cohorts: Activate for a small cohort first (e.g., canary or a subset of Task Queues), then expand. Coordinate via config, not randomness.

## Limitations and cautions

- Not a server-side routing control. It is a Worker-local decision at the moment `patched()` would first activate.
- Do not attempt to encode business-time windows (e.g., “after 5pm”) in activation logic; this leads to inconsistent activation and surprises during reprocessing. Prefer explicit operator flips.
- Activation policies do not change replay outcomes for in-flight runs with existing history.

## See also

- Patching Encyclopedia entry (deep semantics): https://docs.temporal.io/patching
- Versioning concepts: `references/core/versioning.md`
- Worker Versioning (deployments): https://docs.temporal.io/production-deployment/worker-deployments/worker-versioning

