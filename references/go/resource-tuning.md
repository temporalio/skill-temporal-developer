# Go SDK Resource Tuning

This reference covers the Go SDK's **resource-based Worker tuning** API — how to let a Worker hand out task slots based on live CPU and memory utilization instead of fixed counts, and how the API and its host-info collector are split across two packages.

For the orthogonal fixed-count knobs (`MaxConcurrentActivityExecutionSize`, `MaxConcurrentWorkflowTaskExecutionSize`, etc.), see `references/go/advanced-features.md` → "Worker Tuning". For SDK-wide defaults and metric mappings, see [Worker tuning quick reference](../../../documentation/docs/develop/worker-tuning-reference.mdx).

## Where the API lives now

The resource-tuning constructors and option structs live in the core worker package:

```go
import "go.temporal.io/sdk/worker"
```

The host-info collector that resource-based tuners need is shipped separately in a contrib package:

```go
import "go.temporal.io/sdk/contrib/sysinfo"
```

`sysinfo` is a [gopsutil](https://github.com/shirou/gopsutil)-based implementation that supports cgroup metrics in containerized Linux environments. <!-- docs/cloud/worker-health.mdx:404 -->

> **Migration note.** Earlier releases shipped this surface under `go.temporal.io/sdk/contrib/resourcetuner`. The constructors (`NewResourceBasedTuner`, `NewResourceController`, `NewFixedSizeSlotSupplier`, `NewResourceBasedSlotSupplier`, `NewCompositeTuner`) and option structs (`ResourceBasedTunerOptions`, `CompositeTunerOptions`) now live on the `worker` package. <!-- docs/develop/worker-performance.mdx:494,518–547 --> The CPU/memory collector moved to its own `contrib/sysinfo` package and is supplied via the `worker.SysInfoProvider` interface. <!-- docs/cloud/worker-health.mdx:403,417 -->

## Choosing a tuner type

The Go SDK exposes three slot supplier strategies. Each Worker uses one tuner; a tuner assigns one supplier to each task type (Workflow, Activity, Local Activity, Nexus). <!-- docs/develop/worker-performance.mdx:42–46,92–94 -->

- **Fixed Size Slot Suppliers** hand out slots up to a preset limit. Best when you have a concrete idea of per-task resource consumption and can compute a safe upper bound from hardware/environment characteristics — lowest overhead, best performance under known load. <!-- docs/develop/worker-performance.mdx:52–58 -->
- **Resource-Based Slot Suppliers** hand out slots based on real-time CPU and memory usage, targeting thresholds you set. They account for cgroup limits in containers and dynamically adjust slots across task types. Best for "acceptable performance with minimum effort," fluctuating workloads with low per-task consumption, or protection against unpredictable per-task allocations. <!-- docs/develop/worker-performance.mdx:60–64,407–420 -->
- **Custom Slot Suppliers** issue `SlotPermit`s under logic you implement (`reserveSlot`, `tryReserveSlot`, `markSlotUsed`, `releaseSlot`). Use when fixed and resource-based don't fit. <!-- docs/develop/worker-performance.mdx:72–75,444–456 -->

Guardrails from the docs:

- Resource-based targets are *not* guaranteed — task resource use can't be known ahead of time. <!-- docs/develop/worker-performance.mdx:78–81 -->
- Workflow Tasks normally use minimal CPU/memory and are well-served by fixed-size suppliers; resource-based tuning is most useful for Activities. <!-- docs/develop/worker-performance.mdx:393–395 -->
- For very-low-latency, maximum-throughput workloads, avoid resource-based auto-tuning. <!-- docs/develop/worker-performance.mdx:396–397 -->
- The `worker_task_slots_available` gauge only works with fixed-size suppliers — it is not emitted for resource-based suppliers. Use `worker_task_slots_used` instead when you need a gauge that covers both. <!-- docs/develop/worker-performance.mdx:198–202 -->

## Tuners and `MaxConcurrentXXX` cannot be combined

Setting a `Tuner` on `worker.Options` *and* any `maxConcurrentXXXTask` option in the same `worker.Options` causes an **error at Worker initialization**. Pick one style or the other. <!-- docs/develop/worker-performance.mdx:83–87,97–101,224–229 -->

## Recipe 1 — resource-based tuner (single call)

Use `worker.NewResourceBasedTuner` when you want resource-based suppliers for *every* task type with one constructor call.

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

<!-- docs/develop/worker-performance.mdx:493–505 -->

Field notes:

- `TargetMem` and `TargetCpu` are fractions in `[0, 1]` representing the system utilization the supplier aims for (the doc snippet uses `0.8` and `0.9`). <!-- docs/develop/worker-performance.mdx:495–496 -->
- `InfoSupplier` accepts an implementation of `worker.SysInfoProvider`. `sysinfo.SysInfoProvider()` (from `go.temporal.io/sdk/contrib/sysinfo`) is the default gopsutil/cgroup-aware implementation. <!-- docs/develop/worker-performance.mdx:497, docs/cloud/worker-health.mdx:404,413 -->

## Recipe 2 — composite tuner (mix strategies per task type)

Use `worker.NewCompositeTuner` when different task types want different suppliers — for example, fixed-size for Workflow and Nexus Tasks, resource-based for Activity and Local Activity Tasks. <!-- docs/develop/worker-performance.mdx:512–513 -->

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

<!-- docs/develop/worker-performance.mdx:518–554 -->

Field notes:

- The controller options struct returned by `worker.DefaultResourceControllerOptions()` exposes `MemTargetPercent`, `CpuTargetPercent`, and `InfoSupplier` — note these names differ from `ResourceBasedTunerOptions`' `TargetMem` / `TargetCpu` / `InfoSupplier`. <!-- docs/develop/worker-performance.mdx:519–522 -->
- One `*worker.ResourceController` is shared across all resource-based slot suppliers so they coordinate against the same targets. <!-- docs/develop/worker-performance.mdx:523 -->
- The composite tuner snippet reuses `worker.DefaultActivityResourceBasedSlotSupplierOptions()` for both the Activity and Local Activity slot suppliers — there is no separate `DefaultLocalActivity...Options` helper shown in the docs. <!-- docs/develop/worker-performance.mdx:529,533 -->
- `worker.CompositeTunerOptions` has four slot-supplier fields: `WorkflowSlotSupplier`, `ActivitySlotSupplier`, `LocalActivitySlotSupplier`, `NexusSlotSupplier`. <!-- docs/develop/worker-performance.mdx:543–546 -->

## Slot supplier throttling (`rampThrottle`)

Resource-based suppliers have a `rampThrottle` option that defines the minimum time the Worker waits between handing out new slots after the minimum-slots count has been passed. <!-- docs/develop/worker-performance.mdx:468–470 -->

> **A higher `rampThrottle` trades off performance for safety.** <!-- docs/develop/worker-performance.mdx:471 -->

Example from the docs: a freshly started Worker with no throttle facing a backlog might accept 100 tasks at once. If each task allocates 1 GB of RAM, the Worker likely OOMs. The throttle forces a wait between slot grants so newly consumed resources are visible before more slots open. <!-- docs/develop/worker-performance.mdx:473–477 -->

<!-- VERIFY: docs/develop/worker-performance.mdx mentions `rampThrottle` as an SDK option but does not show the exact Go field name on `worker.DefaultActivityResourceBasedSlotSupplierOptions()`. Read the worker package godoc before pinning the field. -->

## Reporting host CPU/memory in Worker heartbeats

`worker.Options.SysInfoProvider` is a *separate* knob from the tuner's `InfoSupplier` field. It controls whether the Worker reports host CPU/memory usage in its 60-second heartbeat to the Temporal Service — used by the UI and `temporal worker describe`/`list` for fleet visibility. <!-- docs/cloud/worker-health.mdx:382–389,400–403 -->

By default the Go SDK reports `0` for CPU and memory. To enable real values: <!-- docs/cloud/worker-health.mdx:402–403 -->

```go
import (
    "go.temporal.io/sdk/contrib/sysinfo"
    "go.temporal.io/sdk/worker"
)

w := worker.New(c, "my-task-queue", worker.Options{
    SysInfoProvider: sysinfo.SysInfoProvider(),
})
```

<!-- docs/cloud/worker-health.mdx:406–415 -->

You can also implement the `worker.SysInfoProvider` interface to supply your own resource metrics. <!-- docs/cloud/worker-health.mdx:417 -->

If you want both behaviors — resource-based slot suppliers *and* host resource reporting in heartbeats — set both `worker.Options.SysInfoProvider` and the tuner's `InfoSupplier` (typically to the same `sysinfo.SysInfoProvider()` value).

## Cgroup behavior

When running in a containerized environment, all SDKs use cgroups for both CPU and memory; CPU is accounted for at the container level. <!-- docs/develop/worker-performance.mdx:66–70 --> The `sysinfo` contrib package's gopsutil implementation supports cgroup metrics in containerized Linux environments. <!-- docs/cloud/worker-health.mdx:404 -->

## Defaults table (for context)

These are the fixed defaults a Worker uses when no tuner is set: <!-- docs/develop/worker-tuning-reference.mdx:70–76,97–103,122–128 -->

| Knob | Go default |
|---|---|
| `MaxConcurrentWorkflowTaskExecutionSize` | 1,000 |
| `MaxConcurrentActivityTaskExecutionSize` | 1,000 |
| `MaxConcurrentLocalActivityTaskExecutionSize` | 1,000 |
| `StickyWorkflowCacheSize` | 10,000 |
| `MaxConcurrentWorkflowTaskPollers` | 2 |
| `MaxConcurrentActivityTaskPollers` | 2 |

Configuring a `Tuner` replaces the three `MaxConcurrent*TaskExecutionSize` rows above; setting both raises a Worker-init error (see "Tuners and `MaxConcurrentXXX` cannot be combined" above). The cache size and poller counts are unaffected by tuner choice.

## Field-name traps (read before writing code)

| Where you set it | Field name | Notes |
|---|---|---|
| `worker.ResourceBasedTunerOptions` | `TargetMem`, `TargetCpu`, `InfoSupplier` | Used by `worker.NewResourceBasedTuner`. <!-- docs/develop/worker-performance.mdx:494–498 --> |
| `worker.ResourceControllerOptions` (from `DefaultResourceControllerOptions()`) | `MemTargetPercent`, `CpuTargetPercent`, `InfoSupplier` | Used by `worker.NewResourceController`. Note the differing names. <!-- docs/develop/worker-performance.mdx:519–522 --> |
| `worker.Options` | `SysInfoProvider` | Enables host-resource heartbeating. Different field name from the tuner options above, same interface type. <!-- docs/cloud/worker-health.mdx:403,413 --> |

## Related references

- `references/go/advanced-features.md` — fixed-count `MaxConcurrentXXX` knobs, sessions, schedules, async activity completion.
- `references/go/observability.md` — slot/cache/latency metrics the Worker emits.
- [Worker performance](../../../documentation/docs/develop/worker-performance.mdx) — comprehensive tuning guide (all SDKs).
- [Worker tuning quick reference](../../../documentation/docs/develop/worker-tuning-reference.mdx) — SDK defaults and metrics-by-resource tables.
- [Manage Worker Heartbeating](../../../documentation/docs/cloud/worker-health.mdx) — heartbeat interval and host resource reporting.
