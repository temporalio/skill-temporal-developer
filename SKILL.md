---
name: temporal-python
description: "Start, stop, debug, and troubleshoot Temporal workflows for Python projects. Use when: starting workers, executing workflows, workflow is stalled/failed, non-determinism errors, checking workflow status, or managing temporal server start-dev lifecycle."
version: 1.1.0
allowed-tools: "Bash(.claude/skills/temporal/scripts/*:*), Read"
---

# Temporal Skill

Manage Temporal workflows using local development server (Python SDK, `temporal server start-dev`).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_TEMPORAL_LOG_DIR` | `/tmp/claude-temporal-logs` | Worker log directory |
| `CLAUDE_TEMPORAL_PID_DIR` | `/tmp/claude-temporal-pids` | Worker PID directory |
| `TEMPORAL_ADDRESS` | `localhost:7233` | Temporal server gRPC address |
| `TEMPORAL_WORKER_CMD` | `uv run worker` | Command to start worker |

---

## Quick Start

```bash
# 1. Start server
./scripts/ensure-server.sh

# 2. Start worker (kills old workers, starts fresh)
./scripts/ensure-worker.sh

# 3. Execute workflow
uv run starter  # Capture workflow_id from output

# 4. Wait for completion
./scripts/wait-for-workflow-status.sh --workflow-id <id> --status COMPLETED

# 5. Get result (verify it's correct, not an error message)
./scripts/get-workflow-result.sh --workflow-id <id>

# 6. CLEANUP: Kill workers when done
./scripts/kill-worker.sh
```

---

## Common Recipes

### Clean Start
```bash
./scripts/kill-all-workers.sh
./scripts/ensure-server.sh
./scripts/ensure-worker.sh
uv run starter
```

### Debug Stalled Workflow
```bash
./scripts/find-stalled-workflows.sh
./scripts/analyze-workflow-error.sh --workflow-id <id>
tail -100 $CLAUDE_TEMPORAL_LOG_DIR/worker-$(basename "$(pwd)").log
# See references/troubleshooting.md for decision tree
```

### Clear Stalled Environment
```bash
./scripts/find-stalled-workflows.sh
./scripts/bulk-cancel-workflows.sh
./scripts/kill-worker.sh
./scripts/ensure-worker.sh
```

### Check Recent Results
```bash
./scripts/list-recent-workflows.sh --minutes 30
./scripts/get-workflow-result.sh --workflow-id <id>
```

---

## Key Scripts

| Script | Purpose |
|--------|---------|
| `ensure-server.sh` | Start dev server if not running |
| `ensure-worker.sh` | Kill old workers, start fresh one |
| `kill-worker.sh` | Kill current project's worker |
| `kill-all-workers.sh` | Kill all workers (`--include-server` option) |
| `find-stalled-workflows.sh` | Detect stalled workflows |
| `analyze-workflow-error.sh` | Extract errors from history |
| `wait-for-workflow-status.sh` | Block until status reached |
| `get-workflow-result.sh` | Get workflow output |

See `references/tool-reference.md` for full details.

---

## References (Load When Needed)

| Reference | When to Read |
|-----------|--------------|
| `references/concepts.md` | Understanding workflow vs activity tasks, component architecture |
| `references/troubleshooting.md` | Workflow stalled, failed, or misbehaving - decision tree and fixes |
| `references/error-reference.md` | Looking up specific error types and recovery steps |
| `references/tool-reference.md` | Script options and worker management details |
| `references/interactive-workflows.md` | Signals, updates, queries for human-in-the-loop workflows |
| `references/logs.md` | Log file locations and search commands |

---

## Critical Rules

1. **Always kill workers when done** - Don't leave stale workers running
2. **One worker instance only** - Multiple workers cause non-determinism
3. **Capture workflow_id** - You need it for all monitoring/troubleshooting
4. **Verify results** - COMPLETED status doesn't mean correct result; check payload
5. **Non-determinism: analyze first** - Use `analyze-workflow-error.sh` to understand the mismatch. If accidental: fix code to match history. If intentional v2 change: terminate and start fresh. See `references/troubleshooting.md`
