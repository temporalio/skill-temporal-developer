# Ruby Workflow Determinism Protection

## Overview

The Ruby SDK uses two mechanisms to enforce workflow determinism:

1. **Illegal Call Tracing** -- `TracePoint`-based interception of forbidden method calls on the workflow fiber.
2. **Durable Fiber Scheduler** -- a custom `Fiber::Scheduler` that makes fiber operations deterministic.

This differs from Python's sandbox (`SandboxedWorkflowRunner`) and TypeScript's V8 isolate sandbox. Ruby's approach is runtime tracing, not code isolation.

## How Illegal Call Tracing Works

A `TracePoint` is installed on the workflow fiber thread. On every `:call` and `:c_call` event, the SDK checks the receiver class and method name against a configurable set of illegal calls.

```ruby
# Internally, the SDK does something like:
TracePoint.new(:call, :c_call) do |tp|
  if illegal?(tp.defined_class, tp.method_id)
    raise Temporalio::Workflow::NondeterminismError,
      "Illegal call: #{tp.defined_class}##{tp.method_id}"
  end
end
```

Key behaviors:

- Raises `Temporalio::Workflow::NondeterminismError` on violation.
- Detects transitive calls -- a gem calling `IO.read` deep in its internals will still be caught.
- Only active on the workflow fiber, not on activity threads or other fibers.

## Forbidden Operations

Default forbidden operations:

- `Kernel.sleep` -- use `Temporalio::Workflow.sleep`
- `Time.now` (no args) -- use `Temporalio::Workflow.now`
- `Thread.new` -- not allowed in workflows
- `IO.*` -- all IO class methods (`IO.read`, `IO.write`, `IO.pipe`, etc.)
- `Socket.*` -- all socket operations
- `Net::HTTP.*` -- all HTTP client calls
- `Random.*` -- use `Temporalio::Workflow.random`
- `SecureRandom.*` -- use `Temporalio::Workflow.uuid` for UUIDs
- `Timeout.timeout` -- use `Temporalio::Workflow.sleep` with cancellation

Note: `Time.new('2000-12-31')` with arguments IS deterministic and allowed. Only `Time.now` (wall-clock) is forbidden.

## Durable Fiber Scheduler

The SDK provides a custom `Fiber::Scheduler` implementation that makes fiber primitives deterministic within the workflow.

- `Kernel.sleep` and `Mutex` technically work under the durable scheduler but are **disabled by default** via illegal call tracing to prevent accidental misuse.
- `Temporalio::Workflow.sleep` and `Temporalio::Workflow.wait_condition` are the correct alternatives.

```ruby
# Correct: deterministic sleep
Temporalio::Workflow.sleep(30)

# Correct: wait for a condition
Temporalio::Workflow.wait_condition { @order_confirmed }
```

## Disabling Illegal Call Tracing

Use `Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled` when third-party code is known safe:

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    # Third-party gem that does harmless Time.now internally
    result = Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled do
      SomeGem.format_data(input)
    end
    result
  end
end
```

The block disables tracing only for its duration. Keep it as narrow as possible.

## Customizing Illegal Calls

Pass `illegal_workflow_calls:` to `Temporalio::Worker.new`:

```ruby
worker = Temporalio::Worker.new(
  client: client,
  task_queue: 'my-queue',
  workflows: [MyWorkflow],
  illegal_workflow_calls: Temporalio::Worker.default_illegal_workflow_calls.merge(
    'MyInternalClass' => :all,
    'AnotherClass' => { dangerous_method: true }
  )
)
```

Default set available via:

```ruby
Temporalio::Worker.default_illegal_workflow_calls
# => { 'Kernel' => { sleep: true }, 'IO' => :all, ... }
```

Hash format:

- `{ 'ClassName' => :all }` -- block all methods on the class.
- `{ 'ClassName' => { method_name: true } }` -- block specific methods.

## Common Issues

### Third-party gems triggering NondeterminismError

Gems that call `IO`, `Time.now`, or `Socket` internally will trigger errors even if you don't call those methods directly.

**Fix 1:** Wrap in `illegal_call_tracing_disabled`:

```ruby
Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled do
  ThirdPartyGem.safe_pure_computation(data)
end
```

**Fix 2:** For code that needs IO (e.g., reading a config file), use `io_enabled`:

```ruby
Temporalio::Workflow::Unsafe.io_enabled do
  config = YAML.load_file('config.yml')
end
```

**Fix 3:** Combine with replay check for side effects:

```ruby
unless Temporalio::Workflow::Unsafe.replaying?
  Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled do
    MetricsClient.increment('workflow.started')
  end
end
```

### Durable scheduler conflicts

If a gem requires its own fiber scheduler behavior, disable the durable scheduler for that block:

```ruby
Temporalio::Workflow::Unsafe.durable_scheduler_disabled do
  some_fiber_aware_gem.call
end
```

## Best Practices

- Use `Temporalio::Workflow.sleep`, `.now`, `.random`, `.uuid`, `.logger` for all workflow-level operations.
- Never perform IO, network calls, or file access in workflow code -- delegate to activities.
- Use `illegal_call_tracing_disabled` sparingly and only when you are certain the code is deterministic.
- Wrap side-effect-only code in `unless Temporalio::Workflow::Unsafe.replaying?` to avoid duplicate emissions during replay.
- Prefer activities over `io_enabled` blocks -- activities have proper retry, timeout, and heartbeat semantics.
