# Cadence Go Testing

Cadence Go provides `testsuite.WorkflowTestSuite` and `testsuite.TestWorkflowEnvironment` for unit tests.

## Basic Structure

```go
type WorkflowSuite struct {
	suite.Suite
	testsuite.WorkflowTestSuite
	env *testsuite.TestWorkflowEnvironment
}

func (s *WorkflowSuite) SetupTest() {
	s.env = s.NewTestWorkflowEnvironment()
}
```

## Execute Workflow

```go
s.env.ExecuteWorkflow(MyWorkflow, input)
s.True(s.env.IsWorkflowCompleted())
s.NoError(s.env.GetWorkflowError())
```

## Mock Activities

```go
s.env.OnActivity(MyActivity, mock.Anything, mock.Anything).Return("ok", nil)
```

## Test Signals

Register delayed callbacks before running the workflow:

```go
s.env.RegisterDelayedCallback(func() {
	s.env.SignalWorkflow("approve", true)
}, time.Minute)
```

The test environment advances logical time automatically.
