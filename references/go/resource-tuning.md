# Go SDK Resource Tuning

This reference covers **resource-based worker tuning** in the Temporal Go SDK: letting the worker decide how many concurrent Workflow / Activity / Local Activity / Nexus Tasks to run based on live CPU and memory utilization, instead of using fixed `MaxConcurrent*` slot counts.

For the fixed-slot knobs (`MaxConcurrentActivityExecutionSize`, etc.) and the Sessions feature, see `references/go/advanced-features.md`. The two styles are mutually exclusive — see [Constraints](#constraints).

## Where the APIs live

The tuner / slot-supplier types live in the main worker package:

```go
import "go.temporal.io/sdk/worker"
```

The system-info implementation that reads host CPU and memory lives in a separate contrib package and is not pulled in unless you import it explicitly:

```go
import "go.temporal.io/sdk/contrib/sysinfo"
```

`sysinfo.SysInfoProvider()` returns an implementation of the `worker.SysInfoProvider` interface.  It is described as a [gopsutil](https://github.com/shirou/gopsutil)-based implementation that supports cgroup metrics in containerized Linux environments.  Available since **Go SDK v1.41.0**.

You can also implement `worker.SysInfoProvider` yourself to feed in custom metrics — for example, when running on a platform `gopsutil` does not handle.

## Concepts (one paragraph each)

**Worker Task Slot.** Capacity to execute a single concurrent Task. When a Worker starts processing a Task, it occupies one slot.

**Slot Supplier.** Strategy that hands out slots. Each supplier manages one slot type. There are slot types for Activity, Workflow, Nexus, or Local Activity Tasks.

**Worker Tuner.** A per-Worker instance that assigns slot suppliers to the four slot types. A tuner can mix kinds — e.g., fixed-size for Workflow and Nexus, resource-based for Activity and Local Activity.

**Three supplier kinds:** Fixed Size, Resource-Based, Custom.

## Choosing a strategy

Use the docs' framing verbatim:

- **Workflow Tasks make minimal demands on CPU and normally don't consume much memory — they are well served by fixed-sized suppliers.**
- **For very low Task completion latency and maximum throughput, avoid resource-based auto-tuning.**
- **Reserve resource-based suppliers for workloads whose resource usage patterns you don't fully understand and don't care to profile.**
- **For variable or very high per-task resource needs, prefer fixed-size with manual tuning.** A resource-based tuner with appropriate fixed numbers can never beat that.
- Resource-based suppliers are a fit when (a) you want acceptable performance with minimum effort, (b) workloads fluctuate and per-Task consumption is low (HTTP calls, blocking I/O), or (c) you need protection against OOM when per-task consumption is unpredictable.

Resource-based suppliers in containerized environments **account for cgroup limits** for both CPU and memory.

## Resource-based tuner — all four slot types resource-based

The simplest setup: one tuner, every slot type driven by the same CPU/memory targets.

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

Field notes:

- `TargetMem` and `TargetCpu` are fractions in `[0.0, 1.0]` representing the **target utilization** the supplier tries to reach without exceeding under load.
- `InfoSupplier` is the source of live CPU/memory readings. `sysinfo.SysInfoProvider()` is the contrib implementation; you can pass any `worker.SysInfoProvider` you wrote yourself.
- The targets are *aspirational* — the supplier may exceed them. **You cannot guarantee that resource-based targets won't ever be exceeded; resources consumed during a task can't be known ahead of time.**

## Composite tuner — mix fixed and resource-based

A **composite tuner lets you mix different slot supplier strategies for each Task type**. The canonical example: fixed-size for Workflow and Nexus, resource-based for Activity and Local Activity.

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

Watch the field-name shift: the **tuner** option struct uses `TargetMem` / `TargetCpu`, but the **controller** option struct uses `MemTargetPercent` / `CpuTargetPercent`. Both structs carry an `InfoSupplier` field of the same type.

Note the example wires the **same** `DefaultActivityResourceBasedSlotSupplierOptions()` into both the Activity supplier and the Local Activity supplier.  The docs do not advertise a separate `DefaultLocalActivity…` helper, so transcribe what the sample uses unless you've grepped the SDK and found one.

All four slot suppliers are populated; `CompositeTunerOptions` is a closed shape with exactly these four fields.

## Wiring the tuner into the Worker

```go
w := worker.New(c, "my-task-queue", workerOpts) // workerOpts.Tuner = tuner
```

`Tuner` is one field on `worker.Options`. By default it is unset, in which case the Worker uses the fixed `MaxConcurrent*ExecutionSize` knobs — for the Go SDK those defaults are 1,000 for Workflow, Activity, and Local Activity.

## Slot supplier throttling (rampThrottle)

Resource-based suppliers expose a **slot throttle**: a minimum wait between handing out new slots after the minimum-slots threshold has been crossed. The docs call this `rampThrottle`.

> Slot throttling is a mechanism to control the rate at which new slots for concurrent tasks are made available for processing. By waiting a brief period between making slots available, the Worker can assess how resource usage has changed since the last task began processing.

**Higher `rampThrottle` trades performance for safety.** Example from the docs: with no throttle, a just-started worker facing a backlog might immediately accept 100 Tasks at once; if each allocates 1 GiB of RAM, the Worker OOMs.

The docs treat `rampThrottle` as a conceptual name common to all SDKs; the exact Go field setter sits on the slot-supplier options structs (`worker.DefaultActivityResourceBasedSlotSupplierOptions()` and friends).

## Constraints

Three hard rules from the docs:

1. **Tuners and the `MaxConcurrent*` knobs are mutually exclusive.** "Worker tuners supersede the existing `maxConcurrentXXXTask` style Worker options. Using both styles will cause an error at Worker initialization time."
2. **Resource targets are aspirational, not guarantees.** "You cannot guarantee that the targets for resource-based suppliers won't ever be exceeded. Resources consumed during a task can't be known ahead of time."
3. **`worker_task_slots_available` only works with fixed-size suppliers.** With resource-based suppliers, use `worker_task_slots_used` instead.

## SysInfoProvider on `worker.Options` (heartbeat reporting, separate use)

The same `sysinfo.SysInfoProvider()` function returns the same kind of value used by **two different fields**, and they are not the same thing:

| Field | Where | Purpose |
|---|---|---|
| `worker.Options.SysInfoProvider` | Top-level Worker options | Enables host CPU/memory in Worker **heartbeats** to the Server (default reports `0`).  |
| `ResourceBasedTunerOptions.InfoSupplier` / `ResourceControllerOptions.InfoSupplier` | Tuner / controller options | Feeds live CPU/memory readings to the **resource-based slot supplier**.  |

```go
w := worker.New(c, "my-task-queue", worker.Options{
    SysInfoProvider: sysinfo.SysInfoProvider(),
})
```

If you want both Server-visible host metrics **and** a resource-based tuner, you set both fields. Sharing the same `sysinfo.SysInfoProvider()` value is fine.

## Custom slot suppliers

If neither fixed-size nor resource-based fits, implement [`worker.SlotSupplier`](https://pkg.go.dev/go.temporal.io/sdk/worker#SlotSupplier) directly. The docs list four required functions, consistent across SDKs:

- `reserveSlot` — called before polling for new tasks; may block; returns a Slot Permit when it decides to accept work.
- `tryReserveSlot` — called for slot reservations in cases like eager activity processing; must not block.
- `markSlotUsed` — called when a slot is about to be used for a task; provides task info.
- `releaseSlot` — called when a slot is no longer needed, whether or not it was used.

The exact Go method names and `SlotPermit` shape live in the SDK godoc — link readers there rather than transcribing.

## Where it fits in the broader tuning story

Resource tuning is one knob on the worker. The other tuning surfaces that interact with it:

- **Fixed-slot `MaxConcurrent*` options** — the legacy alternative; mutually exclusive with a `Tuner`. Documented in `references/go/advanced-features.md` §"Worker Tuning".
- **Poller autoscaling** — orthogonal: chooses how many pollers run, not how many concurrent Tasks execute. Set via `WorkflowTaskPollerBehavior` / `ActivityTaskPollerBehavior` / `NexusTaskPollerBehavior` on `worker.Options` with `worker.NewPollerBehaviorAutoscaling(...)`.
- **Sticky workflow cache** — host-shared cache; set with `worker.SetStickyWorkflowCacheSize`. Default 10,000.
- **Worker heartbeating** — `client.Options.WorkerHeartbeatInterval` controls cadence; `worker.Options.SysInfoProvider` controls *what* is reported.

## Quick metric pointers when tuning

From the worker-tuning quick reference (use these to know whether tuning is working):

- Compute: `worker_task_slots_available` (fixed-size suppliers only), `worker_task_slots_used`, `workflow_task_execution_latency`.
- Memory: `sticky_cache_size`, `sticky_cache_total_forced_eviction`, `sticky_cache_hit`, `sticky_cache_miss`.
- IO: `num_pollers`, `request_latency`.

## Related references

- `references/go/advanced-features.md` — fixed-slot `worker.Options` (`MaxConcurrentActivityExecutionSize`, `MaxConcurrentWorkflowTaskExecutionSize`, `MaxConcurrentActivityTaskPollers`, `MaxConcurrentWorkflowTaskPollers`), Sessions.
- `references/go/observability.md` — metrics emission and Prometheus setup.
- `references/core/dev-management.md` — running and managing workers across environments.
