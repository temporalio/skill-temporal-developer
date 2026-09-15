First-Run Targeting — Go

Summary:
- Capture the first execution Run ID from WorkflowRun and keep Workflow ID.
- Cancel the chain head by calling CancelWorkflow with Workflow ID and empty Run ID.
- Optionally resolve the current Run via Visibility List Filter using WorkflowId and CloseTime = missing.

Notes:
- GetRunID on WorkflowRun returns the initial Run ID (first_execution_run_id), not the latest.
- Chain-targeted update via CLI uses --first-execution-run-id; verify any Go client chain-target APIs before use.
