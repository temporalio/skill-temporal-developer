# Task Queue Priority and Fairness

## Overview

Priority and Fairness control how Tasks are distributed within a Task Queue. Priority determines execution order. Fairness prevents one group of Tasks from starving others. They can be used independently or together.

Priority is enabled by default in Temporal Cloud and self-hosted Temporal. Fairness must be enabled separately and is a paid feature in Temporal Cloud.

This file covers cross-SDK concepts and Task Queue configuration. For SDK-specific APIs and examples, read `references/{your_language}/priority-fairness.md`.

## Priority

Priority lets you control execution order within a single Task Queue by assigning a priority key (integer 1-5, lower = higher priority). Each priority level acts as a sub-queue. All priority-1 Tasks dispatch before priority-2, and so on. Tasks at the same priority level dispatch in FIFO order.

Default priority is 3. Activities and Child Workflows inherit their parent Workflow's priority unless explicitly overridden.

Priority is enforced within each Task Queue partition. Because Tasks are distributed across partitions, ordering across the whole Task Queue is close to Priority order but can deviate when partitions are imbalanced.

### When to use Priority

Use Priority to differentiate execution order between types of work sharing a single Task Queue and Worker pool. For example, process payment-related Tasks before less time-sensitive inventory management Tasks, or ensure real-time Tasks run ahead of batch Tasks. You can also use it to run urgent Tasks immediately by assigning them priority 1.

### CLI

```
temporal workflow start \
  --type ChargeCustomer \
  --task-queue my-task-queue \
  --workflow-id my-workflow-id \
  --input '{"customerId":"12345"}' \
  --priority-key 1
```

For SDK examples, see `references/{your_language}/priority-fairness.md`.

## Fairness

Fairness prevents one group of Tasks from monopolizing Worker capacity. Each fairness key creates a "virtual queue" within the Task Queue. The server uses weighted, probabilistic dispatch across virtual queues so no single key can block others, even with a much larger backlog.

### When to use Fairness

Fairness solves the multi-tenant starvation problem. Without it, Tasks dispatch FIFO: if tenant-big enqueues 100k Tasks, tenant-small's 10 Tasks sit behind the entire backlog. With Fairness, each tenant gets its own virtual queue and Tasks are interleaved.

Common scenarios:

- **Multi-tenant applications** where large tenants should not block small ones.
- **Tiered capacity bands** where you want weighted distribution (e.g., 80% premium, 20% free) without limiting overall throughput when one band is empty.
- **Batch jobs** where some jobs run far more frequently than others.
- **Multi-vendor processing** where a few vendors generate the majority of work.

If all your Tasks can be dispatched immediately (no backlog), you don't need Fairness.

Fairness applies at Task dispatch time and considers each Task as having equal cost until dispatch. It does not account for Tasks currently being processed by Workers. So if you look at Tasks being processed by Workers, you might not see "fairness" across tenants — for example, if tenant-big already has Tasks being processed when tenant-small's Tasks are dispatched, it may still appear that tenant-big is using the most resources.

### Fairness keys and weights

A fairness key is a string, typically a tenant ID or workload category. Each unique key creates a virtual queue. Fairness keys are limited to 64 bytes.

A fairness weight (float, default 1.0) controls how often a key's Tasks are dispatched relative to others. A key with weight 2.0 dispatches approximately twice as often as keys with weight 1.0. Weights must be in the range 0.001-1000, and a key should use one consistent weight within a Task Queue.

Example with three tiers:

| Fairness Key | Weight | Share of Dispatches |
| -- | -- | -- |
| premium-tier | 5.0 | 50% |
| basic-tier | 3.0 | 30% |
| free-tier | 2.0 | 20% |

Tasks without a fairness key are grouped under an implicit empty-string key with weight 1.0. Adoption is incremental: unkeyed Tasks participate in weighted dispatch alongside keyed Tasks.

### Using Fairness with Priority

When combined, Priority determines which sub-queue Tasks go into (priority 1 before 2, etc.), and Fairness applies within each priority level. Tasks sharing both a priority level and fairness key dispatch in FIFO order.

### SDK examples

Use the CLI to start a Workflow with both Priority and Fairness:

```
temporal workflow start \
  --type ChargeCustomer \
  --task-queue my-task-queue \
  --workflow-id my-workflow-id \
  --input '{"customerId":"12345"}' \
  --priority-key 1 \
  --fairness-key tenant-123 \
  --fairness-weight 2.0
```

For Workflow, Activity, and Child Workflow SDK examples, see `references/{your_language}/priority-fairness.md`.

Each Priority field is resolved independently. Activities and Child Workflows inherit unset fields from their parent Workflow and can override individual fields. Continue-As-New inherits the current values unless replacements are provided. Task Queue weight overrides take precedence over SDK-supplied `fairness_weight` values.

### Rate limiting

Two rate-limiting controls work alongside Fairness:

- **`queue-rps-limit`** — overall dispatch rate for the entire Task Queue.
- **`fairness-key-rps-limit-default`** — per-key rate limit, scaled by weight. If the default is 10 rps and a key has weight 2.5, that key's effective limit is 25 rps.

```
temporal task-queue config set \
    --task-queue my-task-queue \
    --task-queue-type activity \
    --namespace my-namespace \
    --queue-rps-limit 500 \
    --queue-rps-limit-reason "overall limit" \
    --fairness-key-rps-limit-default 33.3 \
    --fairness-key-rps-limit-reason "per-key limit"
```

If both limits are set, the more restrictive one applies.

### Fairness weight overrides

You can override the weights of up to 1000 keys through the config API. When an override is set for a key, the SDK-supplied weight is ignored. Overrides are per Task Queue and type (Workflow vs. Activity), so set them for both if needed.

```
temporal task-queue config set \
    --task-queue my-task-queue \
    --task-queue-type activity \
    --namespace my-namespace \
    --fairness-key-weight premium=5.0 \
    --fairness-key-weight basic=1.0
```

Use `key=default` to remove one override or `--fairness-key-weight-clear-all` to remove all overrides for that Task Queue and type.

### Enabling Fairness

When Fairness is enabled with an active backlog, existing queued Tasks are processed before new Fairness-mode Tasks. Disabling Fairness likewise drains the existing Fairness-ordered backlog before returning to Priority and FIFO ordering.

**Temporal Cloud**: enable Fairness for the Namespace from its Overview page. Billing applies while Fairness is enabled, even if individual Tasks do not use fairness keys.

**Self-hosted**: set the `matching.enableFairness` dynamic configuration setting to `true` for the relevant Namespace, Task Queue, or globally. Priority uses the new matcher by default; setting `matching.useNewMatcher` to `false` disables it for the selected scope.

### Limitations

- Accuracy can degrade with a very large number of distinct fairness keys.
- Task Queue partitioning can interfere with fairness distribution. Contact Temporal Support to set a Task Queue to a single partition if needed.
- Weights apply at schedule time, not dispatch time. Changing a weight does not reorder already-backlogged Tasks.
- Fairness is not guaranteed across different Worker versions when using Worker Versioning.
- After server restarts, less-active keys may briefly dispatch new Tasks ahead of their existing backlog until ordering normalizes.
