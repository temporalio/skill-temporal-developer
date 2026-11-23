# Ruby SDK Observability

## Overview

Temporal Ruby SDK provides logging, metrics, tracing, and visibility for monitoring workflows and activities.

## Logging

### Workflow Logging (Replay-Safe)

```ruby
Temporalio::Workflow.logger.info("Processing order")
Temporalio::Workflow.logger.warn("Retrying with fallback")
Temporalio::Workflow.logger.error("Order failed: #{reason}")
```

### Activity Logging

```ruby
Temporalio::Activity::Context.current.logger.info("Sending email")
Temporalio::Activity::Context.current.logger.warn("Slow response: #{elapsed}s")
```

Do not use `puts` or `print` in workflows. They are not replay-safe and produce duplicate output on replay.

### Customizing Logger Configuration

```ruby
require 'logger'

# The logger set on the client is used by Temporalio::Workflow.logger and
# Temporalio::Activity::Context.current.logger. Defaults to stdout at WARN.
client = Temporalio::Client.connect(
  'localhost:7233', 'my-namespace',
  logger: Logger.new($stdout, level: Logger::INFO)
)
```

### Core Log Format

Core (the Rust engine under the SDK) writes its own logs to the console as compact (default), pretty, or JSON:

```ruby
logging = Temporalio::Runtime::LoggingOptions.new(log_format: Temporalio::Runtime::ConsoleLogFormat::JSON)
runtime = Temporalio::Runtime.new(telemetry: Temporalio::Runtime::TelemetryOptions.new(logging:))
```

## Metrics

### Enabling SDK Metrics

Configure telemetry via `Temporalio::Runtime`:

```ruby
prometheus_options = Temporalio::Runtime::PrometheusMetricsOptions.new(
  bind_address: '0.0.0.0:9000'
)

metrics_options = Temporalio::Runtime::MetricsOptions.new(
  prometheus: prometheus_options
)

telemetry_options = Temporalio::Runtime::TelemetryOptions.new(
  metrics: metrics_options
)

runtime = Temporalio::Runtime.new(telemetry: telemetry_options)
Temporalio::Runtime.default = runtime
```

Set the default runtime **before** creating any clients or workers.

### Key SDK Metrics

- `temporal_workflow_completed` - workflow completions
- `temporal_workflow_failed` - workflow failures
- `temporal_activity_execution_latency` - activity duration
- `temporal_sticky_cache_hit` - workflow cache hits
- `temporal_workflow_task_execution_latency` - workflow task duration

## Worker Heartbeating

A running Worker sends a heartbeat to the Temporal Service every 60 seconds by default. `temporal worker list` and `temporal worker describe` show what the heartbeats report, including Worker configuration, host load, SDK runtime, and OS. Set the interval between 1 and 60 seconds. Keep heartbeats enabled unless the user asks otherwise, because disabling them leaves those commands with missing or inaccurate Workers.

```ruby
runtime = Temporalio::Runtime.new(
  worker_heartbeat_interval: 30,   # seconds; nil disables heartbeats
  disable_environment_info: true   # omit runtime, hosting, and platform info
)
```

## Search Attributes (Visibility)

Define a search attribute key:

```ruby
key = Temporalio::SearchAttributes::Key.new(
  'CustomerId',
  Temporalio::SearchAttributes::IndexedValueType::KEYWORD
)
```

Set at Workflow start:

```ruby
client.start_workflow(
  MyWorkflow,
  'arg',
  id: 'wf-1',
  task_queue: 'my-queue',
  search_attributes: Temporalio::SearchAttributes.new({ key => 'customer-123' })
)
```

Upsert from a Workflow:

```ruby
Temporalio::Workflow.upsert_search_attributes(key.value_set('new-value'))
```

### Querying Workflows by Search Attributes

```ruby
client.list_workflows("CustomerId = 'customer-123'")
```

## Best Practices

- Use `Temporalio::Workflow.logger` in workflows, `Temporalio::Activity::Context.current.logger` in activities.
- Configure Prometheus metrics for production deployments.
- Use Search Attributes for workflow visibility and filtering.
- Never use `puts` or `print` in workflow code.
