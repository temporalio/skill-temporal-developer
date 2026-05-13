# Go SDK Resource Tuning

## Overview

The Go SDK lets a Worker hand out Task slots dynamically based on live CPU and memory usage, instead of pinning the slot count to a fixed number. The full API lives in the `go.temporal.io/sdk/worker` package; the only contrib import you need is `go.temporal.io/sdk/contrib/sysinfo`, which supplies the system-info reader (gopsutil-based, cgroup-aware in containers). <!-- docs/develop/worker-performance.mdx:60-70; docs/cloud/worker-health.mdx:404 -->

When to reach for this instead of fixed slot counts is a workload question, not a syntax one — see `Choosing a slot supplier` below. The short version: fixed-size is faster when you have profiled the workload, resource-based is "good enough" when you have not. <!-- docs/develop/worker-performance.mdx:388-427 -->

## API surface

| Symbol | Purpose |
|---|---|
| `worker.NewResourceBasedTuner` | One-call constructor that builds a tuner where every slot type (Workflow, Activity, Local Activity, Nexus) is resource-based. <!-- docs/develop/worker-performance.mdx:494 --> |
| `worker.ResourceBasedTunerOptions` | Struct with `TargetMem`, `TargetCpu`, `InfoSupplier`. <!-- docs/develop/worker-performance.mdx:494-498 --> |
| `worker.NewResourceController` | Builds a controller that resource-based slot suppliers share. <!-- docs/develop/worker-performance.mdx:523 --> |
| `worker.DefaultResourceControllerOptions` | Returns a `ResourceControllerOptions` with the SDK defaults; mutate fields before passing it in. <!-- docs/develop/worker-performance.mdx:519 --> |
| `worker.NewFixedSizeSlotSupplier(n)` | Slot supplier that hands out at most `n` slots. <!-- docs/develop/worker-performance.mdx:524 --> |
| `worker.NewResourceBasedSlotSupplier` | Slot supplier driven by a `ResourceController`. <!-- docs/develop/worker-performance.mdx:529 --> |
| `worker.DefaultActivityResourceBasedSlotSupplierOptions` | Default options for resource-based Activity (and Local Activity) slot suppliers. <!-- docs/develop/worker-performance.mdx:529, 533 --> |
| `worker.NewCompositeTuner` | Tuner that wires a distinct slot supplier per slot type. <!-- docs/develop/worker-performance.mdx:542 --> |
| `worker.CompositeTunerOptions` | Struct with `WorkflowSlotSupplier`, `ActivitySlotSupplier`, `LocalActivitySlotSupplier`, `NexusSlotSupplier`. <!-- docs/develop/worker-performance.mdx:542-547 --> |
| `worker.SlotSupplier` | Interface for implementing a custom slot supplier. <!-- docs/develop/worker-performance.mdx:438 --> |
| `worker.SysInfoProvider` (interface) | What the tuner reads CPU/memory from. Implement your own, or use `sysinfo.SysInfoProvider()`. <!-- docs/cloud/worker-health.mdx:417 --> |

The tuner attaches to a Worker via `worker.Options.Tuner`. <!-- docs/develop/worker-performance.mdx:502-504 -->

> Worker tuners supersede the `MaxConcurrentWorkflowTaskExecutionSize` / `MaxConcurrentActivityExecutionSize` / `MaxConcurrentLocalActivityExecutionSize` options. **Setting both on the same Worker errors at initialization time.** <!-- docs/develop/worker-performance.mdx:84-86, 98-101, 226-229 -->

## Resource-based tuner (all slot types)

The simplest path: every slot type uses the resource-based supplier, governed by the same CPU and memory targets.

```go
import (
    "go.temporal.io/sdk/contrib/sysinfo"
    "go.temporal.io/sdk/worker"
)

func resourceBasedTuner() (worker.Options, error) {
    tuner, err := worker.NewResourceBasedTuner(worker.ResourceBasedTunerOptions{
        TargetMem:    0.8,
        TargetCpu:    0.9,
        InfoSupplier: sysinfo.SysInfoProvider(),
    })
    if err != nil {
        return worker.Options{}, err
    }
    return worker.Options{
        Tuner: tuner,
    }, nil
}
```
<!-- docs/develop/worker-performance.mdx:493-507; sample-apps/go/features/worker_tuner/worker_tuner.go:9-21 -->

`TargetMem` and `TargetCpu` are utilization targets in `[0.0, 1.0]`. The tuner aims for those values without overshooting under load — but it cannot guarantee the ceiling, because per-Task resource cost is not known up front. <!-- docs/develop/worker-performance.mdx:60-65, 78-80 -->

## Composite tuner (mix strategies per slot type)

Use a composite tuner when only some slot types should be resource-driven. The Temporal-recommended split is fixed-size for Workflow and Nexus slots (which use little memory) and resource-based for Activity and Local Activity slots. <!-- docs/develop/worker-performance.mdx:393-396, 512-513 -->

```go
import (
    "go.temporal.io/sdk/contrib/sysinfo"
    "go.temporal.io/sdk/worker"
)

func compositeTuner() (worker.Options, error) {
    options := worker.DefaultResourceControllerOptions()
    options.MemTargetPercent = 0.8
    options.CpuTargetPercent = 0.9
    options.InfoSupplier = sysinfo.SysInfoProvider()
    controller := worker.NewResourceController(options)

    wfSS, err := worker.NewFixedSizeSlotSupplier(10)
    if err != nil {
        return worker.Options{}, err
    }
    actSS, err := worker.NewResourceBasedSlotSupplier(controller, worker.DefaultActivityResourceBasedSlotSupplierOptions())
    if err != nil {
        return worker.Options{}, err
    }
    laSS, err := worker.NewResourceBasedSlotSupplier(controller, worker.DefaultActivityResourceBasedSlotSupplierOptions())
    if err != nil {
        return worker.Options{}, err
    }
    nexusSS, err := worker.NewFixedSizeSlotSupplier(10)
    if err != nil {
        return worker.Options{}, err
    }

    compositeTuner, err := worker.NewCompositeTuner(worker.CompositeTunerOptions{
        WorkflowSlotSupplier:      wfSS,
        ActivitySlotSupplier:      actSS,
        LocalActivitySlotSupplier: laSS,
        NexusSlotSupplier:         nexusSS,
    })
    if err != nil {
        return worker.Options{}, err
    }
    return worker.Options{
        Tuner: compositeTuner,
    }, nil
}
```
<!-- docs/develop/worker-performance.mdx:518-557; sample-apps/go/features/worker_tuner/worker_tuner.go:26-67 -->

Notes on this snippet:

- **The same controller is shared** by every resource-based supplier — that's what lets them coordinate CPU/memory budgets. <!-- docs/develop/worker-performance.mdx:523, 529, 533 -->
- **`DefaultActivityResourceBasedSlotSupplierOptions()` is used for both Activity and Local Activity slot suppliers** in the canonical sample. <!-- docs/develop/worker-performance.mdx:529, 533; sample-apps/go/features/worker_tuner/worker_tuner.go:38, 43 -->
- **All four slot suppliers must be supplied** to `CompositeTunerOptions`. The constructor uses named fields, not positional arguments.

### Field-name pitfall: `TargetMem` vs. `MemTargetPercent`

The resource-target fields appear in two different option structs and **the names do not match**:

| Struct | CPU field | Memory field | `sysinfo` field |
|---|---|---|---|
| `worker.ResourceBasedTunerOptions` (single-call tuner) | `TargetCpu` | `TargetMem` | `InfoSupplier` |
| `worker.ResourceControllerOptions` (composite tuner) | `CpuTargetPercent` | `MemTargetPercent` | `InfoSupplier` |

<!-- docs/develop/worker-performance.mdx:494-498 (tuner options); 519-522 (controller options) -->

Cross-pollinating them is a compile error. If you start from `worker.DefaultResourceControllerOptions()` and try to set `TargetCpu`, the field does not exist on that struct.

## The `sysinfo` contrib package

`sysinfo.SysInfoProvider()` returns a `worker.SysInfoProvider` implementation backed by [gopsutil](https://github.com/shirou/gopsutil). It reads cgroup metrics in containerized Linux environments, so it sees the container's CPU and memory limits rather than the host's. <!-- docs/cloud/worker-health.mdx:404 -->

```go
import (
    "go.temporal.io/sdk/contrib/sysinfo"
    "go.temporal.io/sdk/worker"
)
```
<!-- docs/cloud/worker-health.mdx:406-410 -->

You can also implement the `worker.SysInfoProvider` interface yourself — e.g., to read from a Prometheus-shaped metric source or a sidecar — and pass that into `InfoSupplier`. <!-- docs/cloud/worker-health.mdx:417 -->

### Two places to plug `sysinfo` in — they do different things

This is the most common point of confusion:

| Field | Lives on | What it does |
|---|---|---|
| `InfoSupplier` | `worker.ResourceBasedTunerOptions` / `worker.ResourceControllerOptions` | Feeds CPU/memory readings to the **resource-based slot supplier** so it can scale slot counts. <!-- docs/develop/worker-performance.mdx:497, 522 --> |
| `SysInfoProvider` | `worker.Options` | Feeds CPU/memory readings into **Worker heartbeats** so the Server (and UI) can report host load. <!-- docs/cloud/worker-health.mdx:402-415 --> |

The same `sysinfo.SysInfoProvider()` value can be used in both. Setting `worker.Options.SysInfoProvider` does **not** wire up resource-based tuning; you still need a tuner. The reverse is also true — using a resource-based tuner does not automatically populate the heartbeat fields. <!-- docs/cloud/worker-health.mdx:402-403 -->

## Slot suppliers

| Supplier | When to use |
|---|---|
| **Fixed-size** (`worker.NewFixedSizeSlotSupplier`) | You know an upper bound that does not OOM the host. Lowest overhead, best peak performance. <!-- docs/develop/worker-performance.mdx:52-58 --> |
| **Resource-based** (`worker.NewResourceBasedSlotSupplier`) | Per-Task resource use is unpredictable; workload is variable; you want OOM protection without profiling. <!-- docs/develop/worker-performance.mdx:60-65, 407-419 --> |
| **Custom** (implement `worker.SlotSupplier`) | You need bespoke admission control beyond CPU/memory. <!-- docs/develop/worker-performance.mdx:72-75, 429-456 --> |

The custom interface is documented under "Implement Custom Slot Suppliers" in the worker-performance page; it issues `SlotPermit`s and must implement `reserveSlot` (may block), `tryReserveSlot` (must not block), `markSlotUsed`, and `releaseSlot`. <!-- docs/develop/worker-performance.mdx:438, 444-454 -->

## Choosing a slot supplier

Pulled verbatim from the docs guidance: <!-- docs/develop/worker-performance.mdx:393-427 -->

- **Workflow Tasks** make minimal CPU/memory demands and are well-served by fixed-size suppliers.
- **For low latency and maximum throughput**, avoid resource-based auto-tuning. A fixed-size supplier with appropriate numbers will always beat a resource-based one on raw performance.
- **Reserve resource-based suppliers** for workloads with resource patterns you do not want to profile, or for fluctuating workloads with low per-Task consumption (HTTP calls, blocking I/O), or for protection against unpredictable per-Task consumption.

Auto-tuning may exceed your requested CPU/memory thresholds. Resources consumed during a Task cannot be known ahead of time. <!-- docs/develop/worker-performance.mdx:78-80, 420 -->

## Ramp throttle

Resource-based slot suppliers expose a `rampThrottle` — the minimum time the Worker waits between handing out new slots after the minimum slot count has been reached. A higher value trades performance for safety; a just-started Worker with no throttle could grab a backlog's worth of Tasks before observing their resource cost. <!-- docs/develop/worker-performance.mdx:467-477 -->

## Go defaults reference

If you do **not** configure a tuner and rely on the legacy `MaxConcurrentXxx` options, the Go SDK defaults are: <!-- docs/develop/worker-tuning-reference.mdx:72, 99, 124 -->

| Option | Default |
|---|---|
| `MaxConcurrentWorkflowTaskExecutionSize` | 1,000 |
| `MaxConcurrentActivityTaskExecutionSize` | 1,000 |
| `MaxConcurrentLocalActivityTaskExecutionSize` | 1,000 |
| `MaxCachedWorkflows` / sticky cache (set via `worker.SetStickyWorkflowCacheSize`) | 10,000 |
| `MaxConcurrentWorkflowTaskPollers` | 2 |
| `MaxConcurrentActivityTaskPollers` | 2 |
| Namespace APS | 400 |

Sticky cache size is process-global in Go; set it via `worker.SetStickyWorkflowCacheSize`. <!-- docs/develop/worker-performance.mdx:363 -->

## Common mistakes

1. **Setting both a `Tuner` and `MaxConcurrentXxxTask` options on the same Worker.** Errors at Worker initialization. <!-- docs/develop/worker-performance.mdx:84-86 -->
2. **Crossing the field names** between `ResourceBasedTunerOptions` (`TargetMem`, `TargetCpu`) and `ResourceControllerOptions` (`MemTargetPercent`, `CpuTargetPercent`). They are separate structs.
3. **Importing `contrib/resourcetuner`.** The current import path is `go.temporal.io/sdk/contrib/sysinfo`; the tuner constructors live in `worker`. <!-- docs/cloud/worker-health.mdx:404, 408 -->
4. **Confusing `worker.Options.SysInfoProvider` with `ResourceBasedTunerOptions.InfoSupplier`.** The first feeds heartbeats; the second feeds slot scaling. Set both if you want both behaviors.
5. **Forgetting one of the four `CompositeTunerOptions` fields.** All four (Workflow, Activity, Local Activity, Nexus) are expected by the constructor. <!-- docs/develop/worker-performance.mdx:542-547 -->
6. **Sharing controllers across Workers.** A `ResourceController` is per-Worker — its target percentages describe what *this* Worker should consume on its host. Sharing one between Workers makes the targets meaningless.
7. **Assuming `targetMem` will never be exceeded.** It is a target, not a ceiling. <!-- docs/develop/worker-performance.mdx:78-80 -->

## Related

- `references/go/advanced-features.md` — `MaxConcurrentXxx` worker options for fixed slot counts.
- `references/go/observability.md` — Worker heartbeat metrics that feed into the Worker view in the UI.
- `docs/develop/worker-performance.mdx` — the canonical concept page (read this first if you are tuning unfamiliar workloads).
- `docs/develop/worker-tuning-reference.mdx` — defaults and metrics cheat-sheet across SDKs.
