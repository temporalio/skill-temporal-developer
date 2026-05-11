# Go Resource Tuning

This reference covers Temporal Go SDK Worker tuning: task slots, slot suppliers (fixed-size, resource-based, custom), Worker tuners, and the host-info reporting plumbing used by resource-based tuning. See the conceptual page on [Worker performance](https://docs.temporal.io/develop/worker-performance) and the [Worker tuning quick reference](https://docs.temporal.io/develop/worker-tuning-reference) for the cross-SDK material this document specializes for Go.

## Overview

A Temporal Worker executes Workflow, Activity, Local Activity, and Nexus Tasks. Each running Task occupies a **slot**, and a **slot supplier** decides when a new slot can be handed out. <!-- docs/develop/worker-performance.mdx:34-46 --> A **Worker tuner** binds one supplier per slot type onto a Worker. <!-- docs/develop/worker-performance.mdx:89-94 -->

Current Go API surface for tuning lives in the `go.temporal.io/sdk/worker` package: `worker.NewResourceBasedTuner`, `worker.NewCompositeTuner`, `worker.NewFixedSizeSlotSupplier`, `worker.NewResourceBasedSlotSupplier`, `worker.NewResourceController`. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:9-65 --> Host-resource sampling lives in a separate contrib module, `go.temporal.io/sdk/contrib/sysinfo`. <!-- docs/cloud/worker-health.mdx:404-414 -->

**What changed:** Resource-tuner constructors used to live under `go.temporal.io/sdk/contrib/resourcetuner`. They are now in the `worker` package, and the gopsutil-backed host sampler moved to `go.temporal.io/sdk/contrib/sysinfo`. New code should import from `worker` and `contrib/sysinfo` as shown below.

## Concepts

### Task slots

A Worker Task Slot is the capacity to execute a single concurrent Task. Slots are managed for Workflow, Activity, Local Activity, and Nexus Task types; when a Worker starts a Task it occupies one slot. <!-- docs/develop/worker-performance.mdx:32-46 -->

### Slot suppliers

A Slot Supplier defines a strategy for handing out slots and manages exactly one slot type. <!-- docs/develop/worker-performance.mdx:42-45 --> The Go SDK supports three:

- **Fixed-size slot suppliers** hand out slots up to a preset limit. Best when you have a concrete upper bound on per-task resource usage. <!-- docs/develop/worker-performance.mdx:52-58 -->
- **Resource-based slot suppliers** hand out slots based on real-time CPU and memory utilization, targeting (but not guaranteeing) the thresholds you specify. They honor cgroup limits in containerized environments. <!-- docs/develop/worker-performance.mdx:60-70 -->
- **Custom slot suppliers** let you implement `worker.SlotSupplier` for arbitrary policies. <!-- docs/develop/worker-performance.mdx:72-75, docs/develop/worker-performance.mdx:438 -->

### Worker tuners

A Worker Tuner assigns slot suppliers to the per-Task-type slots on a single Worker. It can mix supplier types — for example, fixed-size for Workflow and Nexus, resource-based for Activity and Local Activity. <!-- docs/develop/worker-performance.mdx:381-386 -->

## Go defaults

Defaults that apply when you do **not** configure a tuner: <!-- docs/develop/worker-tuning-reference.mdx:68-76, docs/develop/worker-tuning-reference.mdx:95-103, docs/develop/worker-tuning-reference.mdx:120-128 -->

| Setting | Go default |
| --- | --- |
| `MaxConcurrentWorkflowTaskExecutionSize` | 1,000 |
| `MaxConcurrentActivityTaskExecutionSize` | 1,000 |
| `MaxConcurrentLocalActivityTaskExecutionSize` | 1,000 |
| `MaxCachedWorkflows` / sticky cache size | 10,000 |
| `MaxConcurrentWorkflowTaskPollers` | 2 |
| `MaxConcurrentActivityTaskPollers` | 2 |
| Namespace APS | 400 |
| `TaskQueueActivitiesPerSecond` | Unlimited |

## The mutual-exclusion warning

> Worker tuners supersede the existing `maxConcurrentXXXTask` style Worker options. Using both styles will cause an error at Worker initialization time. <!-- docs/develop/worker-performance.mdx:84-86, docs/develop/worker-performance.mdx:98-100, docs/develop/worker-performance.mdx:226-228 -->

Once you set `worker.Options{Tuner: ...}` you must not also set `MaxConcurrentWorkflowTaskExecutionSize`, `MaxConcurrentActivityExecutionSize`, `MaxConcurrentLocalActivityExecutionSize`, or any of their siblings on the same `worker.Options`. Pick one style per Worker.

## Recipe: resource-based tuner

A resource-based tuner applies a single resource budget across all slot types on the Worker. Configure target CPU and memory utilization, wire an info supplier that reports current host usage, and pass the tuner to `worker.Options`.

<!-- Sources: docs/develop/worker-performance.mdx:490-507, sample-apps/go/features/worker_tuner/worker_tuner.go:9-21 -->

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

Notes:

- The fields on `worker.ResourceBasedTunerOptions` are `TargetMem`, `TargetCpu`, and `InfoSupplier`. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:10-13 -->
- The `0.8` and `0.9` shown above are illustrative values from the sample, not documented defaults.
- Without `InfoSupplier`, the Go SDK reports `0` for CPU and memory in Worker heartbeats and the tuner has no resource signal to act on. <!-- docs/cloud/worker-health.mdx:402-403 -->

## Recipe: composite tuner

A composite tuner lets you mix supplier strategies per Task type. The example below uses fixed-size suppliers for Workflow and Nexus Tasks and resource-based suppliers (sharing one `ResourceController`) for Activity and Local Activity Tasks. <!-- docs/develop/worker-performance.mdx:510-513 -->

<!-- Sources: docs/develop/worker-performance.mdx:515-557, sample-apps/go/features/worker_tuner/worker_tuner.go:26-65 -->

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

Notes:

- `worker.CompositeTunerOptions` requires **four** suppliers — `WorkflowSlotSupplier`, `ActivitySlotSupplier`, `LocalActivitySlotSupplier`, `NexusSlotSupplier`. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:53-58 -->
- The fields on the **controller** options struct (`worker.DefaultResourceControllerOptions()`) are `MemTargetPercent`, `CpuTargetPercent`, and `InfoSupplier`. Don't confuse these with `ResourceBasedTunerOptions` (`TargetMem`, `TargetCpu`, `InfoSupplier`). <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:27-30 -->
- `worker.NewFixedSizeSlotSupplier(n int)` takes an integer slot count. `worker.NewResourceBasedSlotSupplier(controller, opts)` takes a shared `*ResourceController` and a per-supplier options struct (here `worker.DefaultActivityResourceBasedSlotSupplierOptions()`). <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:33-48 -->
- Both Activity and Local Activity suppliers share the same controller in the sample, so they jointly observe the same resource budget. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:38-45 -->

## Host resource reporting (sysinfo)

The resource-based tuner needs a source of CPU and memory measurements. The Go SDK exposes a `SysInfoProvider` field on [`worker.Options`](https://pkg.go.dev/go.temporal.io/sdk/worker#Options); by default it is unset and the SDK reports `0` for CPU and memory in Worker heartbeats. <!-- docs/cloud/worker-health.mdx:402-403 -->

The `go.temporal.io/sdk/contrib/sysinfo` contrib package supplies a ready-made implementation backed by [gopsutil](https://github.com/shirou/gopsutil) that honors cgroup metrics on containerized Linux. <!-- docs/cloud/worker-health.mdx:404 -->

```go
import (
    "go.temporal.io/sdk/contrib/sysinfo"
    "go.temporal.io/sdk/worker"
)

w := worker.New(c, "my-task-queue", worker.Options{
    SysInfoProvider: sysinfo.SysInfoProvider(),
})
```

<!-- docs/cloud/worker-health.mdx:406-415 -->

Notes:

- Host resource reporting is available from **Go SDK v1.41.0**. <!-- docs/cloud/worker-health.mdx:395 -->
- The same `sysinfo.SysInfoProvider()` value is what you pass to `ResourceBasedTunerOptions.InfoSupplier` and to `worker.ResourceControllerOptions.InfoSupplier` in the recipes above. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:13, sample-apps/go/features/worker_tuner/worker_tuner.go:30 -->
- You can also implement the `worker.SysInfoProvider` interface to surface custom resource metrics. <!-- docs/cloud/worker-health.mdx:417 --> <!-- VERIFY: interface method signatures not enumerated in docs; see go.temporal.io/sdk/worker godoc -->

## Choosing a slot supplier

Guidance from the cross-SDK page, restated for Go: <!-- docs/develop/worker-performance.mdx:393-427 -->

- **Workflow Tasks**: prefer fixed-size suppliers. Workflow Tasks make minimal CPU demands and normally consume little memory, so a fixed slot count plus the sticky workflow cache is the right shape. <!-- docs/develop/worker-performance.mdx:395-396 -->
- **Activities / Local Activities with predictable per-task usage**: prefer fixed-size, sized to your hardware. Fixed-size with good numbers will always outperform resource-based. <!-- docs/develop/worker-performance.mdx:402-405 -->
- **Activities / Local Activities with unpredictable or variable per-task usage**: resource-based is a good match — it protects against OOM and oversubscription without forcing you to profile every workload. <!-- docs/develop/worker-performance.mdx:407-420 -->
- **Custom logic for accepting work**: implement `worker.SlotSupplier` directly when neither fixed nor resource-based fits. <!-- docs/develop/worker-performance.mdx:429-456 -->

The resource-based tuner cannot guarantee its targets; resource consumption per Task is unknown until the Task runs. <!-- docs/develop/worker-performance.mdx:79-80, docs/develop/worker-performance.mdx:420 -->

## `rampThrottle`

Resource-based suppliers expose a `rampThrottle` option that sets the minimum wait between handing out new slots, after the minimum slot count has been reached. The throttle gives the Worker time to observe newly consumed resources before issuing more slots, trading some throughput on a cold start for safety against runaway allocation. <!-- docs/develop/worker-performance.mdx:464-477 -->

A higher `rampThrottle` is safer; a lower one is faster to ramp. The docs describe this qualitatively and do not specify a default unit. <!-- docs/develop/worker-performance.mdx:468-477 -->

## Metrics and observability

The cross-SDK metrics relevant to tuning are documented in the [worker-tuning quick reference](https://docs.temporal.io/develop/worker-tuning-reference#metrics-reference-by-resource-type). Specifically for resource tuning:

- `worker_task_slots_used` — gauge of currently occupied slots; works for both fixed-size and resource-based suppliers. <!-- docs/develop/worker-performance.mdx:195 -->
- `worker_task_slots_available` — gauge of currently available slots; **fixed-size only**. It cannot be used with resource-based slot suppliers. <!-- docs/develop/worker-performance.mdx:200 -->
- Tag both metrics with `worker_type=WorkflowWorker` or `worker_type=ActivityWorker` to scope by slot type. <!-- docs/develop/worker-performance.mdx:196 -->
- Pair these with `workflow_task_schedule_to_start_latency` and `activity_schedule_to_start_latency` to detect Tasks queueing up behind a slot ceiling. <!-- docs/develop/worker-performance.mdx:206-209 -->

If you adopt a resource-based supplier and notice `worker_task_slots_available` going flat, that is expected — fall back to `worker_task_slots_used` plus host CPU/memory observation.

## Common pitfalls

- **Mixing `Tuner` with `MaxConcurrent*` options**: Worker initialization fails with an error if both styles are set on the same `worker.Options`. <!-- docs/develop/worker-performance.mdx:84-86 -->
- **Forgetting to set `InfoSupplier` / `SysInfoProvider`**: without a provider, the Go SDK reports `0` for CPU and memory, so a resource-based tuner has nothing to react to and heartbeats look idle. <!-- docs/cloud/worker-health.mdx:402-403 -->
- **Confusing the two options structs**: `ResourceBasedTunerOptions` uses `TargetMem` / `TargetCpu` / `InfoSupplier`; `DefaultResourceControllerOptions()` produces an options struct with `MemTargetPercent` / `CpuTargetPercent` / `InfoSupplier`. They are not interchangeable. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:10-13, sample-apps/go/features/worker_tuner/worker_tuner.go:27-30 -->
- **Using resource-based suppliers for Workflow Tasks by default**: Workflow Tasks normally have low CPU and memory demands and are best served by fixed-size suppliers. Reach for resource-based on Activity / Local Activity Workers. <!-- docs/develop/worker-performance.mdx:395-405 -->
- **Expecting `worker_task_slots_available` to track resource-based capacity**: it only reports for fixed-size suppliers. Observe host resources and `worker_task_slots_used` instead. <!-- docs/develop/worker-performance.mdx:200 -->
- **Reusing a single `ResourceController`'s budget for too many supplier instances**: in the composite recipe, Activity and Local Activity share one controller intentionally so the budget is jointly enforced. If you want independent budgets, construct separate controllers. <!-- sample-apps/go/features/worker_tuner/worker_tuner.go:31-45 -->
