# Cadence Go SDK Reference

## Overview

The Cadence Go SDK is `go.uber.org/cadence`. Workflow code is ordinary Go code written against deterministic Cadence workflow APIs.

## Quick Start

Add the SDK:

```bash
go get go.uber.org/cadence
```

Workflow definition:

```go
package workflows

import (
	"time"

	"go.uber.org/cadence/workflow"
)

func GreetingWorkflow(ctx workflow.Context, name string) (string, error) {
	ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute}
	ctx = workflow.WithActivityOptions(ctx, ao)

	var result string
	err := workflow.ExecuteActivity(ctx, "Greet", name).Get(ctx, &result)
	return result, err
}
```

Activity definition:

```go
package activities

import (
	"context"
	"fmt"
)

type Activities struct{}

func (a *Activities) Greet(ctx context.Context, name string) (string, error) {
	return fmt.Sprintf("Hello, %s!", name), nil
}
```

Worker:

```go
package main

import (
	"log"

	"go.uber.org/cadence/client"
	"go.uber.org/cadence/worker"

	"yourmodule/activities"
	"yourmodule/workflows"
)

func main() {
	c, err := client.NewClient(client.Options{})
	if err != nil {
		log.Fatalln(err)
	}
	defer c.Close()

	w := worker.New(c, "greeting-task-list", worker.Options{})
	w.RegisterWorkflow(workflows.GreetingWorkflow)
	w.RegisterActivity(&activities.Activities{})

	log.Fatal(w.Run())
}
```

## Key Concepts

- Workflows use `workflow.Context`
- Activities use `context.Context`
- Workers poll task lists
- Workflow code must be deterministic
- Signals and queries are the primary interactive mechanisms

## Important Cadence Terms

- Domain: logical boundary for workflows
- Task list: worker polling queue
- Decision task: workflow task processed by workflow code

## Read Next

- `references/go/determinism.md`
- `references/go/patterns.md`
- `references/go/error-handling.md`
- `references/go/testing.md`
- `references/go/versioning.md`
