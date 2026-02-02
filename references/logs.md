# Log Files

| Log | Location | Content |
|-----|----------|---------|
| Worker logs | `$CLAUDE_TEMPORAL_LOG_DIR/worker-{project}.log` | Worker output, activity logs, errors |

Default log directory: `/tmp/claude-temporal-logs`

## Useful Log Searches

```bash
# Find errors
grep -i "error" $CLAUDE_TEMPORAL_LOG_DIR/worker-*.log

# Check worker startup
grep -i "started" $CLAUDE_TEMPORAL_LOG_DIR/worker-*.log

# Find activity issues
grep -i "activity" $CLAUDE_TEMPORAL_LOG_DIR/worker-*.log

# Tail live logs
tail -f $CLAUDE_TEMPORAL_LOG_DIR/worker-$(basename "$(pwd)").log
```
