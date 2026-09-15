# First-Run Targeting (Workflow Chains)

Target the current execution in a Workflow Execution Chain using the chains first execution Run ID.

- The first execution Run ID (first_execution_run_id) identifies the chain created by Continue-As-New, Retry, Cron, or Reset.

- CLI Update subcommands accept --first-execution-run-id to pin an update to the last execution in the chain that started with that Run ID.

## When to use it
- Your workflows roll over via Continue-As-New or Retry and you need a stable chain handle.
- External callers should not care which specific Run is current at the moment of an operation.

## Go-specific overview
- The Go WorkflowRun returned from ExecuteWorkflow exposes GetRunID(), which returns the initial runs Run ID (the chains first_execution_run_id), and GetWorkflowID().

- For client-initiated cancellation or termination, target the current run of the chain using the Workflow ID and an empty Run ID (SDK or server resolves the current run).

## Notes and cautions
- Do not confuse the initial Run ID (first_execution_run_id) with the latest Run ID. They differ whenever a chain rolls over.

- Chain targeting by first-execution-run-id exists for CLI Update. For Cancel or Terminate, prefer workflowID plus empty runID or resolve the current Run ID first (see Go reference for a pattern). Any Go SDK API that claims to accept a first-execution-run-id directly must be verified in current SDK docs.

