# Troubleshooting Temporal Workflows

## Step 1: Identify the Problem

```bash
# Check workflow status
temporal workflow describe --workflow-id <id>

# Check for stalled workflows (workflows stuck in RUNNING)
./scripts/find-stalled-workflows.sh

# Analyze specific workflow errors
./scripts/analyze-workflow-error.sh --workflow-id <id>
```

## Step 2: Diagnose Using This Decision Tree

```
Workflow not behaving as expected?
│
├── Status: RUNNING but no progress (STALLED)
│   │
│   ├── Is it an interactive workflow waiting for signal/update?
│   │   └── YES → Send the required interaction
│   │
│   └── NO → Run: ./scripts/find-stalled-workflows.sh
│       │
│       ├── WorkflowTaskFailed detected
│       │   │
│       │   ├── Non-determinism error (history mismatch)?
│       │   │   └── See: "Fixing Non-Determinism Errors" below
│       │   │
│       │   └── Other workflow task error (code bug, missing registration)?
│       │       └── See: "Fixing Other Workflow Task Errors" below
│       │
│       └── ActivityTaskFailed (excessive retries)
│           └── Activity is retrying. Fix activity code, restart worker.
│               Workflow will auto-retry with new code.
│
├── Status: COMPLETED but wrong result
│   └── Check result: ./scripts/get-workflow-result.sh --workflow-id <id>
│       Is result an error message? → Fix workflow/activity logic
│
├── Status: FAILED
│   └── Run: ./scripts/analyze-workflow-error.sh --workflow-id <id>
│       Fix code → ./scripts/ensure-worker.sh → Start NEW workflow
│
├── Status: TIMED_OUT
│   └── Increase timeouts → ./scripts/ensure-worker.sh → Start NEW workflow
│
└── Workflow never starts
    └── Check: Worker running? Task queue matches? Workflow registered?
```

---

## Fixing Workflow Task Errors

**Workflow task errors STALL the workflow** - it stops making progress entirely until the issue is fixed.

### Fixing Non-Determinism Errors

Non-determinism occurs when workflow code produces different commands during replay than what's recorded in history.

**Symptoms**:
- `WorkflowTaskFailed` events in history
- "Non-deterministic error" or "history mismatch" in logs/error message

**CRITICAL: First understand the error**:
```bash
# 1. ALWAYS analyze the error first - understand what mismatched
./scripts/analyze-workflow-error.sh --workflow-id <id>

# Look for details like:
# - "expected ActivityTaskScheduled but got TimerStarted"
# - "activity type mismatch: expected X got Y"
# - "timer ID mismatch"
```

**Report the error to user** - They need to know what changed and why.

**Recovery options** (choose based on intent):

**Option A: Fix code to match history (accidental change / bug)**
```bash
# Use when: You accidentally broke compatibility and want to recover the workflow
# 1. Understand what commands the history expects
# 2. Fix workflow code to produce those same commands during replay
# 3. Restart worker
./scripts/ensure-worker.sh
# 4. Workflow task retries automatically and continues
```

**Option B: Terminate and restart fresh (intentional v2 change)**
```bash
# Use when: You intentionally deployed breaking changes (v1→v2) and want new behavior
# The old workflow was started on v1; you want v2 going forward
temporal workflow terminate --workflow-id <id>
./scripts/ensure-worker.sh
uv run starter  # Start fresh workflow with v2 code
```

**Common non-determinism causes**:
- Changed activity order or added/removed activities mid-execution
- Changed activity names or signatures
- Added/removed timers or signals
- Conditional logic that depends on external state (time, random, etc.)

**Key insight**: Non-determinism means "replay doesn't match history."
- **Accidental?** → Fix code to match history, workflow recovers
- **Intentional v2 change?** → Terminate old workflow, start fresh with new code

### Fixing Other Workflow Task Errors

For workflow task errors that are NOT non-determinism (code bugs, missing registration, etc.):

**Symptoms**:
- `WorkflowTaskFailed` events
- Error is NOT "history mismatch" or "non-deterministic"

**Fix procedure**:
```bash
# 1. Identify the error
./scripts/analyze-workflow-error.sh --workflow-id <id>

# 2. Fix the root cause (code bug, worker config, etc.)

# 3. Kill and restart worker with fixed code
./scripts/ensure-worker.sh

# 4. NO NEED TO TERMINATE - the workflow will automatically resume
#    The new worker picks up where it left off and continues execution
```

**Key point**: Unlike non-determinism, the workflow can recover once you fix the code.

---

## Fixing Activity Task Errors

**Activity task errors cause retries**, not immediate workflow failure.

### Workflow Stalling Due to Retries

Workflows can appear stalled because an activity keeps failing and retrying.

**Diagnosis**:
```bash
# Check for excessive activity retries
./scripts/find-stalled-workflows.sh

# Look for ActivityTaskFailed count
# Check worker logs for retry messages
tail -100 $CLAUDE_TEMPORAL_LOG_DIR/worker-$(basename "$(pwd)").log
```

**Fix procedure**:
```bash
# 1. Fix the activity code

# 2. Restart worker with fixed code
./scripts/ensure-worker.sh

# 3. Worker auto-retries with new code
#    No need to terminate or restart workflow
```

### Activity Failure (Retries Exhausted)

When all retries are exhausted, the activity fails permanently.

**Fix procedure**:
```bash
# 1. Analyze the error
./scripts/analyze-workflow-error.sh --workflow-id <id>

# 2. Fix activity code

# 3. Restart worker
./scripts/ensure-worker.sh

# 4. Start NEW workflow (old one has failed)
uv run starter
```
