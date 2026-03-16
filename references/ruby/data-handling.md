# Ruby SDK Data Handling

## Overview

Data converters serialize and deserialize workflow/activity inputs and outputs. The `Temporalio::Converters` module provides the conversion pipeline.

## Default Data Converter

The default converter handles types in this order:

1. `nil` - null payload
2. Bytes - `String` with `ASCII_8BIT` encoding
3. Protobuf - objects implementing `Google::Protobuf::MessageExts`
4. JSON - everything else, via Ruby's `JSON` module

Note: symbol keys become strings on deserialization. `create_additions: true` by default.

## ActiveModel Integration

Use the `ActiveModelJSONSupport` mixin for custom model classes:

```ruby
module ActiveModelJSONSupport
  def as_json(_options = {})
    { JSON.create_id => self.class.name }.merge(instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.delete('@')] = instance_variable_get(var)
    end)
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def self.included(base)
    base.define_method(:json_create) do |hash|
      obj = base.new
      hash.each do |key, value|
        next if key == JSON.create_id
        obj.instance_variable_set("@#{key}", value)
      end
      obj
    end
  end
end

class MyModel
  include ActiveModelJSONSupport
  attr_accessor :name, :value

  def initialize(name: nil, value: nil)
    @name = name
    @value = value
  end
end
```

## Custom Data Converter

```ruby
converter = Temporalio::Converters::DataConverter.new(
  payload_converter: my_payload_converter,
  payload_codec: my_payload_codec,
  failure_converter: my_failure_converter
)

client = Temporalio::Client.connect(
  'localhost:7233',
  'default',
  data_converter: converter
)
```

## Converter Hints

Ruby-specific feature for guiding deserialization to the correct type:

```ruby
class MyWorkflow
  workflow_arg_hint MyClass
  workflow_result_hint MyClass

  workflow_update :my_update, arg_hints: [MyClass]

  def execute(input)
    # input is deserialized as MyClass
  end
end
```

Custom converters use these hints to know the target deserialization type.

## Payload Encryption

Implement a `PayloadCodec` with `encode` and `decode`:

```ruby
class EncryptionCodec
  def encode(payloads)
    payloads.map { |p| encrypt(p) }
  end

  def decode(payloads)
    payloads.map { |p| decrypt(p) }
  end

  private

  def encrypt(payload)
    # encryption logic
  end

  def decrypt(payload)
    # decryption logic
  end
end

converter = Temporalio::Converters::DataConverter.new(
  payload_codec: EncryptionCodec.new
)
```

## Search Attributes

Define a search attribute key:

```ruby
key = Temporalio::SearchAttributes::Key.new(
  'CustomerId',
  Temporalio::SearchAttributes::IndexedValueType::KEYWORD
)
```

Set at workflow start:

```ruby
client.start_workflow(
  MyWorkflow,
  'arg',
  id: 'wf-1',
  task_queue: 'my-queue',
  search_attributes: Temporalio::SearchAttributes.new({ key => 'customer-123' })
)
```

Upsert from a workflow:

```ruby
Temporalio::Workflow.upsert_search_attributes({ key => 'new-value' })
```

Query workflows:

```ruby
client.list_workflows(filter: "CustomerId = 'customer-123'")
```

## Workflow Memo

Set at workflow start:

```ruby
client.start_workflow(
  MyWorkflow,
  'arg',
  id: 'wf-1',
  task_queue: 'my-queue',
  memo: { 'region' => 'us-east', 'priority' => 'high' }
)
```

Read from within a workflow:

```ruby
region = Temporalio::Workflow.memo['region']
```

## Deterministic APIs for Values

Use these instead of standard Ruby equivalents inside workflows:

```ruby
Temporalio::Workflow.uuid       # deterministic UUID
Temporalio::Workflow.random     # deterministic random number
Temporalio::Workflow.now        # deterministic current time
```

## Best Practices

- Use dedicated model classes for Temporal data, not ActiveRecord models.
- Keep payloads small; store large data externally and pass references.
- Encrypt sensitive data with a `PayloadCodec`.
- Use `Temporalio::Workflow.uuid`, `.random`, and `.now` inside workflows for determinism.
