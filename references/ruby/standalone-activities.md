> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

Standalone Activities are Activities run independently of any Workflow, started directly from a Temporal Client — useful when you need a single durable, retryable task (job-queue style) and not multi-step orchestration. The same Activity class can be executed both as a Standalone Activity and as a Workflow Activity with no code changes.

Standalone Activities are conceptually the same across all SDKs. Read the [cross-SDK concept file](references/core/standalone-activities.md) if you have not already, and then see below for the Ruby SDK specific APIs for calling Standalone Activities.

## Prerequisites

- Ruby 3.3 or higher.
- Temporal Ruby SDK (`temporalio` gem) v1.5.0 or higher.
- Temporal CLI v1.7.0 or higher — see [Temporal CLI install instructions](references/core/install_cli.md) if needed. Dev server includes Standalone Activities support.
- For production, Temporal Server v1.31.0 or higher (or Temporal Cloud).

## Hosting Activities on a Worker

The Activity is defined just as activities normally are in Temporal — a `Temporalio::Activity::Definition` subclass with an `execute` method. Worker registration is also the same.

```ruby
require 'temporalio/activity'

class ComposeGreeting < Temporalio::Activity::Definition
  def execute(greeting, name)
    "#{greeting}, #{name}!"
  end
end
```

```ruby
require 'temporalio/client'
require 'temporalio/envconfig'
require 'temporalio/worker'

args, kwargs = Temporalio::EnvConfig::ClientConfig.load_client_connect_options
args[0] ||= 'localhost:7233'
args[1] ||= 'default'

client = Temporalio::Client.connect(*args, **kwargs)

worker = Temporalio::Worker.new(
  client:,
  task_queue: 'standalone-activity-sample',
  activities: [ComposeGreeting] # register whatever your activity(ies) is/are
)

worker.run(shutdown_signals: ['SIGINT'])
```

## Calling and managing Standalone Activities

Start and manage Standalone Activities from your application code using the Temporal Client.

### Do not call from inside a Workflow

Don't call `client.execute_activity` / `client.start_activity` or any other Standalone Activity APIs from inside a Workflow Definition — use Workflow-side activity invocation (`Temporalio::Workflow.execute_activity`) instead.

### Connect a Client

The Standalone Activity operations are methods on a connected `Temporalio::Client`. The examples below assume this `client`.

```ruby
require 'temporalio/client'
require 'temporalio/envconfig'

args, kwargs = Temporalio::EnvConfig::ClientConfig.load_client_connect_options
args[0] ||= 'localhost:7233'
args[1] ||= 'default'

client = Temporalio::Client.connect(*args, **kwargs)
```

### Execute (wait for result)

Use `client.execute_activity(...)` to durably enqueue the Activity, wait for it to run on a Worker, and return the result. The first argument is the Activity; positional arguments after it are passed to the Activity's `execute` method. Required keyword arguments: `id`, `task_queue`, and at least one of `start_to_close_timeout` or `schedule_to_close_timeout` (durations are in seconds).

#### With type checking

Use when activity definitions are available in this language. Pass the `Temporalio::Activity::Definition` subclass (or an instance of one).

```ruby
# In practice, use a meaningful business identifier, like customer or transaction identifier
activity_id = 'send-welcome-email:user-42'

result = client.execute_activity(
  ComposeGreeting,
  'Hello', 'World',
  id: activity_id,
  task_queue: 'standalone-activity-sample',
  start_to_close_timeout: 10
)
```

#### Without type checking

Use when activity definitions are unavailable in this language (i.e. you can't require them). Pass the activity type name as a string or symbol.

```ruby
result = client.execute_activity(
  'ComposeGreeting',
  'Hello', 'World',
  id: activity_id,
  task_queue: 'standalone-activity-sample',
  start_to_close_timeout: 10
)
```

### Start (do not wait for result)

Use `client.start_activity(...)` to durably enqueue the Activity and get back a handle without waiting for completion. This takes the **exact same arguments as `execute_activity`**.

```ruby
handle = client.start_activity(
  ComposeGreeting,
  'Hello', 'World',
  id: activity_id,
  task_queue: 'standalone-activity-sample',
  start_to_close_timeout: 10
)
puts "Started Activity with id=#{handle.id} run_id=#{handle.run_id}"
```

### Get a handle to an existing Activity execution

Use `client.activity_handle(...)` to attach a handle to a previously started Standalone Activity. Passing no run ID (the default) targets the latest run of that Activity ID; pass `activity_run_id:` to target a specific run.

```ruby
handle = client.activity_handle('send-welcome-email:user-42')
```

The handle also exposes `describe`, `cancel`, and `terminate`:

```ruby
handle.describe    # status, timestamps, attempt, last failure, etc.
handle.cancel      # request cooperative cancellation
handle.terminate   # force-close the activity
```

### Wait for the result of a handle

```ruby
result = handle.result
```

Calling `execute_activity` is equivalent to `start_activity` followed by `handle.result`.

### List Standalone Activities

`client.list_activities(query)` returns an `Enumerator` of `ActivityExecution` values that fetches pages from the server on demand as it is consumed.

```ruby
client.list_activities("TaskQueue = 'standalone-activity-sample'").each do |execution|
  puts "ActivityID: #{execution.activity_id}, Type: #{execution.activity_type}, Status: #{execution.status}"
end
```

Only Standalone Activity Executions are returned; Activities running inside Workflows are not included.

### Count Standalone Activities

Use `client.count_activities(query)` to count matching executions; this takes the **exact same arguments as `list_activities`**.

```ruby
result = client.count_activities("TaskQueue = 'standalone-activity-sample'")
puts "Total activities: #{result.count}"
result.groups.each do |group|
  puts "  #{group.group_values.join(',')} => #{group.count}"
end
```
