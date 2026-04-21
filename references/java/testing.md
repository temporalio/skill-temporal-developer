# Cadence Java Testing

Cadence Java provides `TestWorkflowEnvironment` for workflow tests and `TestActivityEnvironment` for activity tests.

## Workflow Test Environment

The in-memory test service supports automatic time skipping, so timer-heavy workflows can be tested quickly.

Typical flow:

1. Create `TestWorkflowEnvironment`
2. Register workflow and activity implementations
3. Start a worker for the task list
4. Create a workflow stub and execute the workflow
5. Assert results or send signals during the run

## Activity Tests

Use `TestActivityEnvironment` when testing activity logic independently from workflow orchestration.

## Signal Tests

Start the workflow asynchronously, advance test time if needed, then call workflow signal methods on the stub.
