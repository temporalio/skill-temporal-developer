# Tool Reference

## Lifecycle Scripts

| Tool | Description | Key Options |
|------|-------------|-------------|
| `ensure-server.sh` | Start dev server if not running | - |
| `ensure-worker.sh` | Kill old workers, start fresh one | Uses `$TEMPORAL_WORKER_CMD` |
| `kill-worker.sh` | Kill current project's worker | - |
| `kill-all-workers.sh` | Kill all workers | `--include-server` |
| `list-workers.sh` | List running workers | - |

## Monitoring Scripts

| Tool | Description | Key Options |
|------|-------------|-------------|
| `list-recent-workflows.sh` | Show recent executions | `--minutes N` (default: 5) |
| `find-stalled-workflows.sh` | Detect stalled workflows | `--query "..."` |
| `monitor-worker-health.sh` | Check worker status | - |
| `wait-for-workflow-status.sh` | Block until status | `--workflow-id`, `--status`, `--timeout` |

## Debugging Scripts

| Tool | Description | Key Options |
|------|-------------|-------------|
| `analyze-workflow-error.sh` | Extract errors from history | `--workflow-id`, `--run-id` |
| `get-workflow-result.sh` | Get workflow output | `--workflow-id`, `--raw` |
| `bulk-cancel-workflows.sh` | Mass cancellation | `--pattern "..."` |

## Worker Management Details

### The Golden Rule

**Ensure no old workers are running.** Stale workers with outdated code cause:
- Non-determinism errors (history mismatch)
- Executing old buggy code
- Confusing behavior

**Best practice**: Run only ONE worker instance with the latest code.

### Starting Workers

```bash
# PREFERRED: Smart restart (kills old, starts fresh)
./scripts/ensure-worker.sh
```

This command:
1. Finds ALL existing workers for the project
2. Kills them
3. Starts a new worker with fresh code
4. Waits for worker to be ready

### Verifying Workers

```bash
# List all running workers
./scripts/list-workers.sh

# Check specific worker health
./scripts/monitor-worker-health.sh

# View worker logs
tail -f $CLAUDE_TEMPORAL_LOG_DIR/worker-$(basename "$(pwd)").log
```

**What to look for in logs**:
- `Worker started, listening on task queue: ...` → Worker is ready
- `Worker process died during startup` → Startup failure, check logs for error

### Cleanup (REQUIRED)

**Always kill workers when done.** Don't leave workers running.

```bash
# Kill current project's worker
./scripts/kill-worker.sh

# Kill ALL workers (full cleanup)
./scripts/kill-all-workers.sh

# Kill all workers AND server
./scripts/kill-all-workers.sh --include-server
```
