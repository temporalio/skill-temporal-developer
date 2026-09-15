# Patch Activation Callback (Ruby)

First read the cross-SDK concept page: `references/core/patch-activation-callback.md`.

## Overview

On first non-replay with no prior marker, `Temporalio::Workflow.patched` records a patch marker and returns true.  During replay, outcomes follow history (true with matching/earlier marker; false with none).

A patch activation callback (when available) lets a Worker decide whether to activate at that first non-replay call, which can help coordinate rolling deployments.

## Prerequisites

- Ruby Versioning guide: https://docs.temporal.io/develop/ruby/workflows/versioning
- Patching Encyclopedia entry: https://docs.temporal.io/patching

## Configuring the decision hook

Pseudocode sketch only:

```ruby
# PSEUDOCODE — DO NOT COPY AS-IS
require 'temporalio/worker'

on_first_patch_activation = proc do |patch_id, ctx|
  # Decide using stable deployment config; avoid time/random
  ENV['PATCH_GATE_ENABLE'] == '1'
end

worker = Temporalio::Worker.new(
  client: client,
  task_queue: 'my-task-queue',
  # on_first_patch_activation: on_first_patch_activation, # VERIFY API name
)
```

## Usage pattern in workflows

Workflow code remains the same; the decision affects only the first non-replay call with no marker:

```ruby
if Temporalio::Workflow.patched('add-fraud-check') # <!-- docs/develop/ruby/workflows/versioning.mdx -->
  # New path
else
  # Old path
end
```

## Gotchas

- The callback is not consulted during replay; replay follows markers.
- Base decisions on steady, operator-controlled config; avoid wall-clock and randomness.

## See also

- Concept page: `references/core/patch-activation-callback.md`
- Ruby Versioning: https://docs.temporal.io/develop/ruby/workflows/versioning

