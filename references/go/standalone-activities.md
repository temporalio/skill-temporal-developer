> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are conceptually the same across all SDKs. Read the [cross-SDK concept file](references/core/standalone-activities.md) if you have not already, and then see below for the Go SDK specific APIs for calling Standalone Activities.

In Go, you start a Standalone Activity from a Temporal Client with `client.ExecuteActivity()` instead of from inside a Workflow with `workflow.ExecuteActivity()`.  The Activity definition and Worker registration are identical to regular Activities; only the execution path differs.

## Prerequisites

- Temporal Go SDK v1.41.0 or higher.
- Go 1.22+.
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](references/core/install_cli.md) if needed. The Temporal Dev Server has Standalone Activities enabled by default.
- For production, Temporal Server v1.31.0 or higher (or Temporal Cloud).

## Hosting Activities on a Worker

Running a Worker for Standalone Activities is identical to running a Worker for Workflow-driven Activities — create a Worker, register the Activity, and call `Run()`. The Worker does not need to know whether the Activity will be invoked from a Workflow or as a Standalone Activity.

```go
package main

import (
	"github.com/temporalio/samples-go/standalone-activity/helloworld"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/contrib/envconfig"
	"go.temporal.io/sdk/worker"
	"log"
)

func main() {
	c, err := client.Dial(envconfig.MustLoadDefaultClientOptions())
	if err != nil {
		log.Fatalln("Unable to create client", err)
	}
	defer c.Close()

	w := worker.New(c, "standalone-activity-helloworld", worker.Options{})

	w.RegisterActivity(helloworld.Activity)

	err = w.Run(worker.InterruptCh())
	if err != nil {
		log.Fatalln("Unable to start worker", err)
	}
}
```

## Calling and managing Standalone Activities

All Standalone Activity calls go through the Temporal `Client`. Use the operations below from your application code (for example, a starter program), not from inside a Workflow Definition.

### Do not call from inside a Workflow

Don't call `client.ExecuteActivity` from inside a Workflow Definition — use `workflow.ExecuteActivity(ctx, ...)` instead.

### Connect a Client

Use `envconfig.MustLoadDefaultClientOptions()` so the same code runs against a local dev server and Temporal Cloud with no changes.

```go
import (
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/contrib/envconfig"
)

c, err := client.Dial(envconfig.MustLoadDefaultClientOptions())
if err != nil {
	log.Fatalln("Unable to create client", err)
}
defer c.Close()
```

### Execute (start and get a handle)

`client.ExecuteActivity()` returns an `ActivityHandle` immediately — it does not wait for completion.  To wait for the result, call `handle.Get(ctx, &out)` (see [Wait for the result of a handle](#wait-for-the-result-of-a-handle) below). There is no separate `Start` function in the Go SDK; `ExecuteActivity` is the only entry point.

`client.StartActivityOptions` requires `ID`, `TaskQueue`, and at least one of `ScheduleToCloseTimeout` or `StartToCloseTimeout`.

```go
activityOptions := client.StartActivityOptions{
	ID:                     "send-welcome-email:user-42",
	TaskQueue:              "standalone-activity-helloworld",
	ScheduleToCloseTimeout: 10 * time.Second,
}

handle, err := c.ExecuteActivity(context.Background(), activityOptions, helloworld.Activity, "Temporal")
if err != nil {
	log.Fatalln("Unable to execute activity", err)
}

log.Println("Started", "ActivityID", handle.GetID(), "RunID", handle.GetRunID())
```

#### With type checking

Pass the Activity as a function reference:

```go
handle, err := c.ExecuteActivity(ctx, options, helloworld.Activity, "Temporal")
```

#### Without type checking

Pass the Activity type name as a string — useful when the starter cannot import the Activity package:

```go
handle, err := c.ExecuteActivity(ctx, options, "Activity", "Temporal")
```

### Get a handle to an existing Activity execution

Use `client.GetActivityHandle()` to rebind a handle to a previously started Standalone Activity. Both `ActivityID` and `RunID` are required.

```go
handle := c.GetActivityHandle(client.GetActivityHandleOptions{
	ActivityID: "send-welcome-email:user-42",
	RunID:      "the-run-id",
})
```

### Wait for the result of a handle

Call `handle.Get(ctx, &out)` to block until the Activity completes and deserialize its result into the provided pointer. If the Activity failed, the failure is returned as an error.

```go
var result string
err := handle.Get(context.Background(), &result)
if err != nil {
	log.Fatalln("Activity failed", err)
}
log.Println("Activity result:", result)
```

Calling `ExecuteActivity` and then `handle.Get(ctx, &out)` is the Go equivalent of the synchronous "Execute and wait" pattern that other SDKs offer as a single call.

### List Standalone Activities

Use `client.ListActivities()` with a [List Filter](https://docs.temporal.io/list-filter) query. The result's `Results` field is a range-over-func iterator that yields `(ActivityExecutionInfo, error)` pairs.

```go
resp, err := c.ListActivities(context.Background(), client.ListActivitiesOptions{
	Query: "TaskQueue = 'standalone-activity-helloworld'",
})
if err != nil {
	log.Fatalln("Unable to list activities", err)
}

for info, err := range resp.Results {
	if err != nil {
		log.Fatalln("Error iterating activities", err)
	}
	log.Printf("ActivityID: %s, Type: %s, Status: %v\n",
		info.ActivityID, info.ActivityType, info.Status)
}
```

Only Standalone Activity Executions are returned; Activities running inside Workflows are not included.

### Count Standalone Activities

Use `client.CountActivities()` with the same arguments as `ListActivities`. `resp.Count` is the total count of matching executions (running, completed, failed, etc.) — not the number of queued tasks.

```go
resp, err := c.CountActivities(context.Background(), client.CountActivitiesOptions{
	Query: "TaskQueue = 'standalone-activity-helloworld'",
})
if err != nil {
	log.Fatalln("Unable to count activities", err)
}

log.Println("Total activities:", resp.Count)
```
