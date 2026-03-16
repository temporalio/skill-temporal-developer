# Ruby SDK Advanced Features

## Schedules

Create recurring workflow executions with `Temporalio::Client::Schedule`.

```ruby
require 'temporalio/client'

# Create a schedule
schedule_id = 'daily-report'
client.create_schedule(
  schedule_id,
  Temporalio::Client::Schedule.new(
    action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
      DailyReportWorkflow,
      id: 'daily-report',
      task_queue: 'reports'
    ),
    spec: Temporalio::Client::Schedule::Spec.new(
      intervals: [
        Temporalio::Client::Schedule::Spec::Interval.new(every: 86_400) # 1 day in seconds
      ]
    )
  )
)

# Manage schedules
handle = client.schedule_handle(schedule_id)
handle.pause(note: 'Maintenance window')
handle.unpause
handle.trigger
handle.delete
```

## Async Activity Completion

For activities that complete asynchronously (e.g., human tasks, external callbacks).

```ruby
class RequestApproval < Temporalio::Activity::Definition
  def execute(request_id)
    # Get task token for async completion
    task_token = Temporalio::Activity::Context.current.info.task_token

    # Store task token for later completion (e.g., in database)
    store_task_token(request_id, task_token)

    # Signal that this activity completes asynchronously
    Temporalio::Activity::Context.current.raise_complete_async
  end
end

# Later, complete the activity from another process
client = Temporalio::Client.connect('localhost:7233')
task_token = get_task_token(request_id)
handle = client.async_activity_handle(task_token: task_token)

if approved
  handle.complete('approved')
else
  handle.fail(Temporalio::Error::ApplicationError.new('Rejected'))
end
```

If you configure a `heartbeat_timeout:` on the activity, the external completer is responsible for sending heartbeats via the async handle. If you do NOT set a `heartbeat_timeout`, no heartbeats are required.

## Worker Tuning

Configure worker performance settings.

```ruby
worker = Temporalio::Worker.new(
  client: client,
  task_queue: 'my-queue',
  workflows: [MyWorkflow],
  activities: [MyActivity],
  max_concurrent_workflow_tasks: 100,
  max_concurrent_activities: 100
)
worker.run
```

## Workflow Failure Exception Types

Control which exceptions cause workflow failure vs workflow task failure (which Temporal retries automatically).

### Per-Workflow Configuration

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  # Class method approach
  def self.workflow_failure_exception_type
    MyCustomError
  end

  def execute
    raise MyCustomError, 'This fails the workflow, not just the task'
  end
end
```

### Worker-Level Configuration

```ruby
Temporalio::Worker.new(
  client: client,
  task_queue: 'my-queue',
  workflows: [MyWorkflow],
  workflow_failure_exception_types: [MyCustomError]
)
```

**Tips:**
- Set to `[Exception]` in tests so any unhandled exception fails the workflow immediately rather than retrying the workflow task forever. Surfaces bugs faster.
- Include `Temporalio::Workflow::NondeterminismError` to fail the workflow instead of leaving it in a retrying state on non-determinism errors.

## Activity Concurrency and Executors

Ruby uses `Temporalio::Worker::ActivityExecutor::ThreadPool` by default. Activities run in a thread pool.

```ruby
# Default: activities run in thread pool
worker = Temporalio::Worker.new(
  client: client,
  task_queue: 'my-queue',
  workflows: [MyWorkflow],
  activities: [MyActivity],
  activity_executors: {
    default: Temporalio::Worker::ActivityExecutor::ThreadPool.new(max_threads: 20)
  }
)
```

Fiber-based execution is also possible for IO-bound activities using Ruby's fiber scheduler.

## Rails Integration

### ActiveRecord Considerations

Never pass ActiveRecord models directly to Temporal workflows or activities. Serialize to plain data structures.

```ruby
# BAD - Passing AR model
client.execute_workflow(
  ProcessOrderWorkflow,
  Order.find(42),  # Don't pass AR objects!
  id: 'order-42',
  task_queue: 'orders'
)

# GOOD - Pass serializable data
client.execute_workflow(
  ProcessOrderWorkflow,
  { id: 42, total: order.total, status: order.status },
  id: 'order-42',
  task_queue: 'orders'
)
```

### Zeitwerk and Autoloading

Rails uses Zeitwerk for autoloading. Workflow and activity classes must be loadable by Zeitwerk or explicitly required.

```ruby
# In config/initializers/temporal.rb or similar
# Eager load Temporal classes so they're available to the worker
Rails.application.config.after_initialize do
  Dir[Rails.root.join('app/workflows/**/*.rb')].each { |f| require f }
  Dir[Rails.root.join('app/activities/**/*.rb')].each { |f| require f }
end
```

### Forking Considerations

If using a forking server (Puma, Unicorn), workers must be created **after** the fork. Connections established before fork are not safe to share across processes.

```ruby
# In Puma config (puma.rb)
on_worker_boot do
  # Create Temporal client and worker AFTER fork
  client = Temporalio::Client.connect('localhost:7233')
  worker = Temporalio::Worker.new(
    client: client,
    task_queue: 'my-queue',
    workflows: [MyWorkflow],
    activities: [MyActivity]
  )
  Thread.new { worker.run }
end
```
