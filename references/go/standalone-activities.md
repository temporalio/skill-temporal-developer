# Standalone Activities — Go SDK Reference

Standalone Activities are Activity Executions that run independently, without
being orchestrated by a Workflow. Instead of starting an Activity from inside a
Workflow Definition with `workflow.ExecuteActivity()`, you start a Standalone
Activity directly from a Temporal Client using `client.ExecuteActivity()`.
<!-- docs/develop/go/activities/standalone-activities.mdx:29 -->

The Activity Definition and Worker registration are identical to regular
(Workflow) Activities — only the execution path differs. The same Activity
Function can be executed as a Standalone Activity and as a Workflow Activity
with no code changes.
<!-- docs/develop/go/activities/standalone-activities.mdx:33 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:56 -->

> Public Preview: Go SDK support for Standalone Activities is at Public
> Preview. `TerminateExisting` conflict policy / `TerminateIfRunning` reuse
> policy is not supported yet, and pause / reset / update options are not
> supported in Public Preview but are scheduled for GA.
<!-- docs/develop/go/activities/standalone-activities.mdx:22 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:109 -->

---

## 1. Prerequisites

- **Go** 1.22+
- **Temporal Go SDK** v1.41.0 or higher
- **Temporal CLI** v1.7.0 or higher
- **Temporal Server** v1.31.0 or higher (Standalone Activities require this)
<!-- docs/develop/go/activities/standalone-activities.mdx:57 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:23 -->

Install the CLI with Homebrew:

```bash
brew install temporal
```
<!-- docs/develop/go/activities/standalone-activities.mdx:67 -->

Verify:

```bash
temporal --version
```
<!-- docs/develop/go/activities/standalone-activities.mdx:75 -->

Start the local development server (the Temporal Dev Server has Standalone
Activities enabled by default):

```
temporal server start-dev
```
<!-- docs/develop/go/activities/standalone-activities.mdx:81 -->

The server listens on `localhost:7233` and the Web UI is at
`http://localhost:8233`. Standalone Activities are accessible from the nav bar
in the Web UI.
<!-- docs/develop/go/activities/standalone-activities.mdx:101 -->

---

## 2. Writing an Activity Function

Define your Activity in a shared file so both the Worker and the starter can
reference it. The signature and body are identical to a Workflow Activity — no
Standalone-specific code is required.
<!-- docs/develop/go/activities/standalone-activities.mdx:127 -->

```go
package helloworld

import (
	"context"
	"go.temporal.io/sdk/activity"
)

func Activity(ctx context.Context, name string) (string, error) {
	logger := activity.GetLogger(ctx)
	logger.Info("Activity", "name", name)
	return "Hello " + name + "!", nil
}
```
<!-- docs/develop/go/activities/standalone-activities.mdx:131 -->

---

## 3. Running a Worker with the Activity registered

Running a Worker for Standalone Activities is the same as running a Worker for
Workflow-driven Activities — create a Worker, register the Activity, and call
`Run()`. The Worker doesn't need to know whether the Activity will be invoked
from a Workflow or as a Standalone Activity.
<!-- docs/develop/go/activities/standalone-activities.mdx:148 -->

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
<!-- docs/develop/go/activities/standalone-activities.mdx:157 -->

Run the Worker:

```
go run standalone-activity/helloworld/worker/main.go
```
<!-- docs/develop/go/activities/standalone-activities.mdx:188 -->

---

## 4. Executing a Standalone Activity (wait-for-result)

Use [`client.ExecuteActivity()`](https://pkg.go.dev/go.temporal.io/sdk/client#Client)
from application code (not from inside a Workflow Definition) to start a
Standalone Activity Execution. It returns an `ActivityHandle` that you can use
to get the result, describe, cancel, or terminate the Activity.
<!-- docs/develop/go/activities/standalone-activities.mdx:196 -->

`client.StartActivityOptions` requires `ID`, `TaskQueue`, and at least one of
`ScheduleToCloseTimeout` or `StartToCloseTimeout`.
<!-- docs/develop/go/activities/standalone-activities.mdx:282 -->

```go
activityOptions := client.StartActivityOptions{
	ID:                     "standalone_activity_helloworld_ActivityID",
	TaskQueue:              "standalone-activity-helloworld",
	ScheduleToCloseTimeout: 10 * time.Second,
}

handle, err := c.ExecuteActivity(context.Background(), activityOptions, helloworld.Activity, "Temporal")
if err != nil {
	log.Fatalln("Unable to execute activity", err)
}

log.Println("Started standalone activity", "ActivityID", handle.GetID(), "RunID", handle.GetRunID())

var result string
err = handle.Get(context.Background(), &result)
if err != nil {
	log.Fatalln("Unable get standalone activity result", err)
}
log.Println("Activity result:", result)
```
<!-- docs/develop/go/activities/standalone-activities.mdx:226 -->

You can pass the Activity as either a function reference or a string Activity
type name:

```go
handle, err := c.ExecuteActivity(ctx, options, helloworld.Activity, "arg1")

// Using a string type name
handle, err := c.ExecuteActivity(ctx, options, "Activity", "arg1")
```
<!-- docs/develop/go/activities/standalone-activities.mdx:275 -->

Or use the Temporal CLI:

```bash
temporal activity execute \
  --type Activity \
  --activity-id standalone_activity_helloworld_ActivityID \
  --task-queue standalone-activity-helloworld \
  --schedule-to-close-timeout 10s \
  --input '"Temporal"'
```
<!-- docs/develop/go/activities/standalone-activities.mdx:298 -->

---

## 5. Starting a Standalone Activity (without waiting) and dedup policies

`client.ExecuteActivity()` returns an `ActivityHandle` immediately — you do not
have to call `handle.Get()` to wait for the result. You can return the
`ActivityID` / `RunID` to a caller and pick the Activity up later via a handle.
<!-- docs/develop/go/activities/standalone-activities.mdx:199 -->
<!-- docs/develop/go/activities/standalone-activities.mdx:330 -->

For deduplication, Standalone Activities support **conflict policy**
(`USE_EXISTING`, ...) and **reuse policy** (`REJECT_DUPLICATES`, ...).
`TerminateExisting` conflict policy and `TerminateIfRunning` reuse policy are
**not supported** in Public Preview.
<!-- docs/encyclopedia/activities/standalone-activity.mdx:84 -->
<!-- docs/encyclopedia/activities/standalone-activity.mdx:110 -->

See [`StartActivityOptions`](https://pkg.go.dev/go.temporal.io/sdk/client#StartActivityOptions)
in the Go SDK API reference for the full set of options.
<!-- docs/develop/go/activities/standalone-activities.mdx:283 -->

<!-- VERIFY: The Go SDK doc page does not name the specific Go field on
StartActivityOptions for conflict policy / reuse policy. Refer to the
StartActivityOptions godoc linked above for the exact Go field names and enum
constants. -->

---

## 6. Getting a handle to an existing Standalone Activity

Use `client.GetActivityHandle()` to create a handle to a previously started
Standalone Activity. This is analogous to `client.GetWorkflow()` for Workflow
Executions. Both `ActivityID` and `RunID` are required.
<!-- docs/develop/go/activities/standalone-activities.mdx:332 -->

```go
handle := c.GetActivityHandle(client.GetActivityHandleOptions{
	ActivityID: "standalone_activity_helloworld_ActivityID",
	RunID:      "the-run-id",
})

// Use the handle to get the result, describe, cancel, or terminate
var result string
err := handle.Get(context.Background(), &result)
if err != nil {
	log.Fatalln("Unable to get activity result", err)
}
```
<!-- docs/develop/go/activities/standalone-activities.mdx:337 -->

---

## 7. Waiting for the result

Use `ActivityHandle.Get()` to block until the Activity completes and retrieve
its result. This is analogous to calling `Get()` on a `WorkflowRun`. If the
Activity completed successfully the result is deserialized into the provided
pointer; if the Activity failed, the failure is returned as an error.
<!-- docs/develop/go/activities/standalone-activities.mdx:309 -->

```go
var result string
err = handle.Get(context.Background(), &result)
if err != nil {
	log.Fatalln("Activity failed", err)
}
log.Println("Activity result:", result)
```
<!-- docs/develop/go/activities/standalone-activities.mdx:312 -->

Or wait for a result by Activity ID with the CLI:

```bash
temporal activity result --activity-id standalone_activity_helloworld_ActivityID
```
<!-- docs/develop/go/activities/standalone-activities.mdx:326 -->

---

## 8. Listing Standalone Activities

Use [`client.ListActivities()`](https://pkg.go.dev/go.temporal.io/sdk/client#Client)
to list Standalone Activity Executions matching a [List Filter](/list-filter)
query. The result contains an iterator that yields `ActivityExecutionInfo`
entries. These APIs return only Standalone Activity Executions — Activities
running inside Workflows are not included.
<!-- docs/develop/go/activities/standalone-activities.mdx:353 -->

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
<!-- docs/develop/go/activities/standalone-activities.mdx:359 -->

The `Query` field accepts the same List Filter syntax used for Workflow
Visibility, e.g. `"ActivityType = 'Activity' AND Status = 'Running'"`.
<!-- docs/develop/go/activities/standalone-activities.mdx:382 -->

CLI equivalent:

```bash
temporal activity list
```
<!-- docs/develop/go/activities/standalone-activities.mdx:378 -->

---

## 9. Counting Standalone Activities

Use [`client.CountActivities()`](https://pkg.go.dev/go.temporal.io/sdk/client#Client)
to count Standalone Activity Executions matching a List Filter query. This
returns the total count of executions (running, completed, failed, etc.) — not
the number of queued tasks. It works the same way as counting Workflow
Executions.
<!-- docs/develop/go/activities/standalone-activities.mdx:388 -->

```go
resp, err := c.CountActivities(context.Background(), client.CountActivitiesOptions{
	Query: "TaskQueue = 'standalone-activity-helloworld'",
})
if err != nil {
	log.Fatalln("Unable to count activities", err)
}

log.Println("Total activities:", resp.Count)
```
<!-- docs/develop/go/activities/standalone-activities.mdx:392 -->

CLI equivalent:

```bash
temporal activity count
```
<!-- docs/develop/go/activities/standalone-activities.mdx:405 -->

---

## 10. Running with Temporal Cloud

The samples on this page use `envconfig.MustLoadDefaultClientOptions()`, so the
same code works against Temporal Cloud — just configure the connection via
environment variables or a TOML profile. No code changes are needed.
<!-- docs/develop/go/activities/standalone-activities.mdx:411 -->

For a step-by-step guide on connecting to Temporal Cloud (Namespace creation,
certificate generation, authentication setup), see
[Connect to Temporal Cloud](/develop/go/client/temporal-client#connect-to-temporal-cloud).
<!-- docs/develop/go/activities/standalone-activities.mdx:415 -->

### Connect with mTLS

Set these environment variables with values from your Temporal Cloud Namespace
settings:

```
export TEMPORAL_ADDRESS=<your-namespace>.<your-account-id>.tmprl.cloud:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_TLS_CLIENT_CERT_PATH='path/to/your/client.pem'
export TEMPORAL_TLS_CLIENT_KEY_PATH='path/to/your/client.key'
```
<!-- docs/develop/go/activities/standalone-activities.mdx:423 -->

### Connect with an API key

Set these environment variables with values from your Temporal Cloud API key
settings:

```
export TEMPORAL_ADDRESS=<region>.<cloud_provider>.api.temporal.io:7233
export TEMPORAL_NAMESPACE=<your-namespace>.<your-account-id>
export TEMPORAL_API_KEY=<your-api-key>
```
<!-- docs/develop/go/activities/standalone-activities.mdx:434 -->

Then run the Worker and starter code as shown in the earlier sections.
<!-- docs/develop/go/activities/standalone-activities.mdx:440 -->
