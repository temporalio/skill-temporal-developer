# PHP SDK Data Handling

## Overview

The PHP SDK uses data converters to serialize/deserialize Workflow inputs, outputs, and Activity parameters. JSON is the default format.

## Default Data Converter

The default converter handles:
- `null`
- Scalars (`string`, `int`, `float`, `bool`)
- Arrays (JSON-serialized)
- Objects (JSON-serialized via public properties)

**PHP-specific:** Workflow methods are generators. To specify the return type of a Workflow method, use the `#[ReturnType]` attribute on the interface method:

```php
use Temporal\Workflow\ReturnType;

#[WorkflowInterface]
interface OrderWorkflowInterface
{
    #[WorkflowMethod]
    #[ReturnType(OrderResult::class)]
    public function run(OrderInput $input): \Generator;
}
```

Without `#[ReturnType]`, the SDK cannot deserialize the result into the correct class.

## Custom Data Converter

Implement a custom `PayloadConverter` to handle types the default converter does not support:

```php
use Temporal\DataConverter\PayloadConverter;
use Temporal\Api\Common\V1\Payload;

class MyCustomConverter implements PayloadConverter
{
    public function getEncodingType(): string
    {
        return 'json/my-custom';
    }

    public function toPayload($value): ?Payload
    {
        if (!$value instanceof MyCustomType) {
            return null;  // Return null to let other converters handle it
        }

        $payload = new Payload();
        $payload->setMetadata(['encoding' => $this->getEncodingType()]);
        $payload->setData(json_encode($value->toArray()));
        return $payload;
    }

    public function fromPayload(Payload $payload, \ReflectionType $type)
    {
        return MyCustomType::fromArray(json_decode($payload->getData(), true));
    }
}
```

Register the custom converter when creating the `WorkflowClient`:

```php
use Temporal\DataConverter\DataConverter;
use Temporal\DataConverter\JsonPayloadConverter;
use Temporal\DataConverter\NullPayloadConverter;

$dataConverter = new DataConverter(
    new NullPayloadConverter(),
    new JsonPayloadConverter(),
    new MyCustomConverter(),
);

$client = WorkflowClient::create(
    ServiceClient::create('localhost:7233'),
    dataConverter: $dataConverter
);
```

## Payload Encryption

Encrypt sensitive Workflow data using a custom `PayloadCodec`:

```php
use Temporal\DataConverter\PayloadCodecInterface;
use Temporal\Api\Common\V1\Payload;

class EncryptionCodec implements PayloadCodecInterface
{
    public function __construct(private string $key) {}

    public function encode(array $payloads): array
    {
        return array_map(function (Payload $payload) {
            $encrypted = $this->encrypt($payload->serializeToString());
            $result = new Payload();
            $result->setMetadata(['encoding' => 'binary/encrypted']);
            $result->setData($encrypted);
            return $result;
        }, $payloads);
    }

    public function decode(array $payloads): array
    {
        return array_map(function (Payload $payload) {
            if (($payload->getMetadata()['encoding'] ?? null) !== 'binary/encrypted') {
                return $payload;
            }
            $decrypted = $this->decrypt($payload->getData());
            $result = new Payload();
            $result->mergeFromString($decrypted);
            return $result;
        }, $payloads);
    }

    private function encrypt(string $data): string { /* ... */ }
    private function decrypt(string $data): string { /* ... */ }
}
```

Apply the codec via `DataConverter` on the client:

```php
$dataConverter = DataConverter::createDefault()->withCodec(new EncryptionCodec($encryptionKey));

$client = WorkflowClient::create(
    ServiceClient::create('localhost:7233'),
    dataConverter: $dataConverter
);
```

## Search Attributes

Custom searchable fields for Workflow visibility.

Define Search Attribute keys and set them at Workflow start:

```php
use Temporal\Common\SearchAttributeKey;
use Temporal\Common\TypedSearchAttributes;

$orderIdKey = SearchAttributeKey::forKeyword('OrderId');
$orderStatusKey = SearchAttributeKey::forKeyword('OrderStatus');

$workflow = $client->newWorkflowStub(
    OrderWorkflowInterface::class,
    WorkflowOptions::new()
        ->withTaskQueue('orders')
        ->withTypedSearchAttributes(
            TypedSearchAttributes::empty()
                ->withValue($orderIdKey, $order->id)
                ->withValue($orderStatusKey, 'pending')
        )
);
```

Upsert Search Attributes during Workflow execution:

```php
use Temporal\Workflow;
use Temporal\Common\SearchAttributeKey;

class OrderWorkflow implements OrderWorkflowInterface
{
    public function run(array $order): \Generator
    {
        // ... process order ...

        Workflow::upsertTypedSearchAttributes(
            SearchAttributeKey::forKeyword('OrderStatus')->withValue('completed')
        );

        return 'done';
    }
}
```

### Querying Workflows by Search Attributes

```php
$executions = $client->listWorkflowExecutions(
    'OrderStatus = "processing" OR OrderStatus = "pending"'
);

foreach ($executions as $execution) {
    echo "Workflow {$execution->getExecution()->getWorkflowId()} is still processing\n";
}
```

## Workflow Memo

Store arbitrary metadata with Workflows (not searchable).

```php
// Set memo at Workflow start
$workflow = $client->newWorkflowStub(
    OrderWorkflowInterface::class,
    WorkflowOptions::new()
        ->withTaskQueue('orders')
        ->withMemo([
            'customer_name' => $order->customerName,
            'notes' => 'Priority customer',
        ])
);
```

Upsert memo during Workflow execution:

```php
class OrderWorkflow implements OrderWorkflowInterface
{
    public function run(array $order): \Generator
    {
        // ... process order ...

        Workflow::upsertMemo(['status' => 'fraud-checked']);

        return yield $this->activity->processPayment($order);
    }
}
```

## Best Practices

1. Use `#[ReturnType]` on Workflow interface methods to enable correct deserialization
2. Keep payloads small — see `references/core/gotchas.md` for limits
3. Encrypt sensitive data with a `PayloadCodec`
4. Use typed Search Attributes for business-level visibility and querying
