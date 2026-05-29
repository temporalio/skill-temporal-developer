# CLI Workflow Commands for Developers

Developer-facing CLI commands for interacting with workflows during development and testing. These commands work identically against a dev server, a self-hosted cluster, or Temporal Cloud -- only the connection descriptor changes.

**IMPORTANT:** In order to make outputs of `temporal` CLI commands easier to read and parse, use the `--output json` flag. The below examples do not show it, for brevity, but generally you should use `--output json`.

## Table of contents

- [Workflow start](#workflow-start)
- [Workflow execute](#workflow-execute)
- [Workflow signal](#workflow-signal)
- [Workflow query](#workflow-query)
- [Workflow update](#workflow-update)
- [Workflow signal-with-start](#workflow-signal-with-start)
- [Workflow result](#workflow-result)
- [Workflow metadata](#workflow-metadata)

## Workflow start

Start a new Workflow Execution asynchronously. Returns the Workflow ID and Run ID.

```bash
temporal workflow start \
    --workflow-id YourWorkflowId \
    --type YourWorkflow \
    --task-queue YourTaskQueue \
    --input '{"some-key": "some-value"}'
```

Required flags: `--type`, `--task-queue`. <!-- docs/cli/workflow.mdx:201,203 --> Optional `--workflow-id` -- the Service generates a UUID if omitted. <!-- docs/cli/workflow.mdx:582 -->

| Flag | Required | Purpose |
|---|---|---|
| `--type` | Yes | Workflow Type name. <!-- docs/cli/workflow.mdx:581 --> |
| `--task-queue`, `-t` | Yes | Workflow Task queue. <!-- docs/cli/workflow.mdx:579 --> |
| `--workflow-id`, `-w` | No | Workflow ID. Service generates a UUID if omitted. <!-- docs/cli/workflow.mdx:582 --> |
| `--input`, `-i` | No | Input value (JSON). Repeatable. Mutually exclusive with `--input-file`. <!-- docs/cli/workflow.mdx:568 --> |
| `--input-file` | No | Read input from file(s). Repeatable. Mutually exclusive with `--input`. <!-- docs/cli/workflow.mdx:570 --> |
| `--input-base64` | No | Decode `--input` as base64 before sending. <!-- docs/cli/workflow.mdx:569 --> |
| `--input-meta` | No | Override payload metadata as `KEY=VALUE` (e.g., `encoding=json/protobuf`). Repeatable. <!-- docs/cli/workflow.mdx:571 --> |
| `--id-reuse-policy` | No | How to reuse a previously-seen Workflow ID. Values: `AllowDuplicate`, `AllowDuplicateFailedOnly`, `RejectDuplicate`, `TerminateIfRunning`. <!-- docs/cli/workflow.mdx:567 --> |
| `--id-conflict-policy` | No | How to resolve conflicts with a running execution sharing the same ID. Values: `Fail`, `UseExisting`, `TerminateExisting`. <!-- docs/cli/workflow.mdx:566 --> |
| `--execution-timeout` | No | Fail a Workflow Execution if it lasts longer than this (duration). Includes retries and ContinueAsNew. <!-- docs/cli/workflow.mdx:561 --> |
| `--run-timeout` | No | Fail a single Workflow Run if it lasts longer than this (duration). <!-- docs/cli/workflow.mdx:574 --> |
| `--task-timeout` | No | Start-to-close timeout for a Workflow Task (duration). <!-- docs/cli/workflow.mdx:580 --> |
| `--search-attribute` | No | Set a search attribute as `KEY=VALUE` (JSON values). Repeatable. <!-- docs/cli/workflow.mdx:575 --> |
| `--memo` | No | Attach unindexed metadata as `KEY="VALUE"` (JSON values). Repeatable. <!-- docs/cli/workflow.mdx:572 --> |
| `--start-delay` | No | Delay before starting (duration). Cannot combine with `--cron`. <!-- docs/cli/workflow.mdx:576 --> |
| `--cron` | No | Legacy cron schedule (prefer `temporal schedule create`). <!-- docs/cli/workflow.mdx:560 --> |
| `--priority-key` | No | Priority 1-5 (default 3). Lower = higher priority. <!-- docs/cli/workflow.mdx:573 --> |
| `--fairness-key` | No | Proportional task dispatch grouping key (string, max 64 bytes). <!-- docs/cli/workflow.mdx:563 --> |
| `--fairness-weight` | No | Weight for this fairness key (0.001-1000). Keys dispatched proportionally. <!-- docs/cli/workflow.mdx:564 --> |
| `--static-summary` | No | Human-readable summary for UIs. Single line. _(Experimental)_ <!-- docs/cli/workflow.mdx:578 --> |
| `--static-details` | No | Human-readable details for UIs. May be multi-line. _(Experimental)_ <!-- docs/cli/workflow.mdx:577 --> |
| `--fail-existing` | No | Fail if the Workflow already exists. <!-- docs/cli/workflow.mdx:562 --> |
| `--headers` | No | Temporal workflow headers as `KEY=VALUE` (JSON). Not gRPC headers. Repeatable. <!-- docs/cli/workflow.mdx:565 --> |

<!-- Sources: docs/cli/workflow.mdx:544-582 -->

## Workflow execute

Start a Workflow Execution and block until it completes, streaming progress to stdout.

```bash
temporal workflow execute \
    --workflow-id YourWorkflowId \
    --type YourWorkflow \
    --task-queue YourTaskQueue \
    --input '{"some-key": "some-value"}'
```

Accepts the same start-time flags as `workflow start`, plus `--detailed` (display events as sections rather than a table; not applied to JSON output). <!-- docs/cli/workflow.mdx:182 --> With `--output json`, the emitted blob includes the full `history` key for the run. <!-- docs/cli/workflow.mdx:175-176 -->

A non-zero exit code means the Workflow failed, was cancelled, terminated, or timed out. Useful for one-shot scripts and smoke tests during development.

<!-- Sources: docs/cli/workflow.mdx:159-204 -->

## Workflow signal

Send an asynchronous signal to a running Workflow Execution.

```bash
temporal workflow signal \
    --workflow-id YourWorkflowId \
    --name YourSignal \
    --input '{"YourInputKey": "YourInputValue"}'
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes (or `--query`) | Workflow ID. <!-- docs/cli/workflow.mdx:473 --> |
| `--name` | Yes | Signal name. <!-- docs/cli/workflow.mdx:468 --> |
| `--input`, `-i` | No | Input value (JSON). Repeatable. <!-- docs/cli/workflow.mdx:464 --> |
| `--run-id`, `-r` | No | Pin to a specific run. Only with `--workflow-id`. <!-- docs/cli/workflow.mdx:472 --> |

For bulk signaling with `--query` (runs as a batch job), see skill-temporal-ops.

<!-- Sources: docs/cli/workflow.mdx:443-474 -->

## Workflow query

Invoke a read-only query handler. Queries do not mutate workflow state and can run on both running and completed workflows.

```bash
temporal workflow query \
    --workflow-id YourWorkflowId \
    --name YourQueryType \
    --input '{"YourInputKey": "YourInputValue"}'
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:365 --> |
| `--name` | Yes | Query Type/Name. <!-- docs/cli/workflow.mdx:362 --> |
| `--input`, `-i` | No | Input value (JSON). Repeatable. <!-- docs/cli/workflow.mdx:358 --> |
| `--run-id`, `-r` | No | Run ID. <!-- docs/cli/workflow.mdx:364 --> |
| `--reject-condition` | No | Reject queries based on Workflow state. Accepted values: `not_open`, `not_completed_cleanly`. <!-- docs/cli/workflow.mdx:363 --> |

<!-- Sources: docs/cli/workflow.mdx:339-365 -->

## Workflow update

Update is a command **group**, not a single command. It has four subcommands: `describe`, `execute`, `result`, `start`.

### `temporal workflow update start`

Initiate an update and wait for the validator to accept or reject it.

```bash
temporal workflow update start \
    --workflow-id YourWorkflowId \
    --name YourUpdate \
    --input '{"some-key": "some-value"}' \
    --wait-for-stage accepted
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:813 --> |
| `--name` | Yes | Handler method name. <!-- docs/cli/workflow.mdx:809 --> |
| `--wait-for-stage` | Yes | Update stage to wait for. The **only** accepted value is `accepted`. Required to allow a future CLI version to choose a default. <!-- docs/cli/workflow.mdx:812 --> |
| `--input`, `-i` | No | Input value (JSON). Repeatable. <!-- docs/cli/workflow.mdx:805 --> |
| `--update-id` | No | Idempotency key. Defaults to a UUID. <!-- docs/cli/workflow.mdx:811 --> |
| `--run-id`, `-r` | No | Run ID. If unset, targets the currently-running execution. <!-- docs/cli/workflow.mdx:810 --> |
| `--first-execution-run-id` | No | Pin the update to the last execution in the chain started with this Run ID. <!-- docs/cli/workflow.mdx:803 --> |

<!-- Sources: docs/cli/workflow.mdx:785-813 -->

### `temporal workflow update execute`

Start an update and wait for it to complete or fail. Can also wait on an existing in-flight update by reusing its Update ID.

```bash
temporal workflow update execute \
    --workflow-id YourWorkflowId \
    --name YourUpdate \
    --input '{"some-key": "some-value"}'
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:764 --> |
| `--name` | Yes | Handler method name. <!-- docs/cli/workflow.mdx:761 --> |
| `--input`, `-i` | No | Input value (JSON). Repeatable. <!-- docs/cli/workflow.mdx:757 --> |
| `--update-id` | No | Idempotency key. Defaults to a UUID. <!-- docs/cli/workflow.mdx:763 --> |
| `--run-id`, `-r` | No | Run ID. If unset, targets the currently-running execution. <!-- docs/cli/workflow.mdx:762 --> |
| `--first-execution-run-id` | No | Pin the update to the last execution in the chain started with this Run ID. <!-- docs/cli/workflow.mdx:755 --> |

<!-- Sources: docs/cli/workflow.mdx:738-764 -->

### `temporal workflow update result`

Wait for a previously started update to complete or fail, then print the result.

```bash
temporal workflow update result \
    --workflow-id YourWorkflowId \
    --update-id YourUpdateId
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:783 --> |
| `--update-id` | Yes | Update ID. Must be unique per Workflow Execution. <!-- docs/cli/workflow.mdx:782 --> |
| `--run-id`, `-r` | No | Run ID. <!-- docs/cli/workflow.mdx:781 --> |

<!-- Sources: docs/cli/workflow.mdx:766-783 -->

### `temporal workflow update describe`

Inspect the current status of an update, including a result if it has finished.

```bash
temporal workflow update describe \
    --workflow-id YourWorkflowId \
    --update-id YourUpdateId
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:736 --> |
| `--update-id` | Yes | Update ID. Must be unique per Workflow Execution. <!-- docs/cli/workflow.mdx:735 --> |
| `--run-id`, `-r` | No | Run ID. <!-- docs/cli/workflow.mdx:734 --> |

<!-- Sources: docs/cli/workflow.mdx:719-736 -->

## Workflow signal-with-start

Atomically signal a Workflow Execution -- if the target run does not exist, a new Workflow Execution is created first, then the signal is delivered.

```bash
temporal workflow signal-with-start \
    --signal-name YourSignal \
    --signal-input '{"some-key": "some-value"}' \
    --workflow-id YourWorkflowId \
    --type YourWorkflowType \
    --task-queue YourTaskQueue \
    --input '{"some-key": "some-value"}'
```

Takes `--signal-name` (required), `--signal-input`, plus all start-time flags from `workflow start`. <!-- docs/cli/workflow.mdx:516,520-522 -->

| Flag | Required | Purpose |
|---|---|---|
| `--signal-name` | Yes | Signal name. <!-- docs/cli/workflow.mdx:516 --> |
| `--signal-input` | No | Signal input value (JSON). Repeatable. <!-- docs/cli/workflow.mdx:512 --> |
| `--type` | Yes | Workflow Type name. <!-- docs/cli/workflow.mdx:522 --> |
| `--task-queue`, `-t` | Yes | Workflow Task queue. <!-- docs/cli/workflow.mdx:520 --> |
| `--workflow-id`, `-w` | No | Workflow ID. Service generates a UUID if omitted. <!-- docs/cli/workflow.mdx:523 --> |

All other start-time flags (`--input`, `--id-reuse-policy`, `--id-conflict-policy`, timeouts, `--search-attribute`, `--memo`, etc.) are accepted. See [Workflow start](#workflow-start) for the full flag table.

<!-- Sources: docs/cli/workflow.mdx:476-523 -->

## Workflow result

Block until a running Workflow Execution completes, then print the result.

```bash
temporal workflow result \
    --workflow-id YourWorkflowId
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:419 --> |
| `--run-id`, `-r` | No | Run ID. <!-- docs/cli/workflow.mdx:418 --> |

<!-- Sources: docs/cli/workflow.mdx:405-419 -->

## Workflow metadata

Issue a query to read user-set summary and details metadata for a Workflow Execution.

```bash
temporal workflow metadata \
    --workflow-id YourWorkflowId
```

| Flag | Required | Purpose |
|---|---|---|
| `--workflow-id`, `-w` | Yes | Workflow ID. <!-- docs/cli/workflow.mdx:324 --> |
| `--run-id`, `-r` | No | Run ID. <!-- docs/cli/workflow.mdx:323 --> |
| `--reject-condition` | No | Reject queries based on Workflow state. Accepted values: `not_open`, `not_completed_cleanly`. <!-- docs/cli/workflow.mdx:322 --> |

<!-- Sources: docs/cli/workflow.mdx:307-324 -->
