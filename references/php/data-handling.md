# PHP SDK Data Handling

## Overview

The PHP SDK converts arguments and results with a `DataConverter`, which tries a list of payload converters in order. Use small explicit inputs: business IDs, DTOs, cursors and references to large data in external storage.

## Default Payload Converter

`DataConverter::createDefault()` uses these converters in order:

1. `NullConverter` - `null`
2. `BinaryConverter` - `Temporal\DataConverter\Bytes`
3. `ProtoJsonConverter` - Protobuf messages as JSON
4. `ProtoConverter` - Protobuf messages as binary
5. `JsonConverter` - scalars, arrays, objects, DTOs, enums, `DateTimeInterface`, UUIDs

## Typed Inputs and Results

The SDK uses the PHP type declarations of a method to decode its arguments:

```php
final class OrderInput
{
    public function __construct(
        public readonly string $orderId,
        public readonly int $amountCents,
        public readonly ?string $couponCode = null,
    ) {}
}

#[WorkflowInterface]
interface OrderWorkflowInterface
{
    #[WorkflowMethod(name: 'Order')]
    #[ReturnType(OrderResult::class)]
    public function run(OrderInput $input): \Generator;
}
```

A generator method declares `\Generator`, so `#[ReturnType]` gives the result type to typed client and child stubs. For an untyped stub, give the type to `getResult()`:

```php
$stub = $client->newUntypedWorkflowStub('Order', WorkflowOptions::new()->withTaskQueue('orders'));
$client->start($stub, $input);
$result = $stub->getResult(OrderResult::class);
```

Adding a required constructor parameter breaks decoding of old payloads. Add new fields with default values.

## Custom Data Conversion

Implement `Temporal\DataConverter\PayloadConverterInterface` for a custom encoding. Return `null` from `toPayload()` for values that the converter does not handle:

```php
use Temporal\Api\Common\V1\Payload;
use Temporal\DataConverter\PayloadConverterInterface;
use Temporal\DataConverter\Type;

final class MoneyConverter implements PayloadConverterInterface
{
    public function getEncodingType(): string
    {
        return 'json/money';
    }

    public function toPayload($value): ?Payload
    {
        if (!$value instanceof Money) {
            return null;
        }

        return (new Payload())
            ->setMetadata(['encoding' => $this->getEncodingType()])
            ->setData(json_encode(['amount' => $value->amount, 'currency' => $value->currency]));
    }

    public function fromPayload(Payload $payload, Type $type): Money
    {
        $data = json_decode($payload->getData(), true, 512, \JSON_THROW_ON_ERROR);
        return new Money($data['amount'], $data['currency']);
    }
}
```

Put the custom converter before `JsonConverter`, and register the same converter on the client and the worker:

```php
use Temporal\Client\GRPC\ServiceClient;
use Temporal\Client\WorkflowClient;
use Temporal\DataConverter\BinaryConverter;
use Temporal\DataConverter\DataConverter;
use Temporal\DataConverter\JsonConverter;
use Temporal\DataConverter\NullConverter;
use Temporal\DataConverter\ProtoConverter;
use Temporal\DataConverter\ProtoJsonConverter;
use Temporal\WorkerFactory;

$converter = new DataConverter(
    new NullConverter(),
    new BinaryConverter(),
    new ProtoJsonConverter(),
    new ProtoConverter(),
    new MoneyConverter(),
    new JsonConverter(),
);

$client = WorkflowClient::create(ServiceClient::create('127.0.0.1:7233'), converter: $converter);
$factory = WorkerFactory::create(converter: $converter);
```

## Serialization Context

Since SDK 2.20, a payload converter can know which Workflow or Activity it serializes data for. Use it to select an encryption key or to sign payloads per Workflow. Implement `SerializationContextAwareInterface`. The `DataConverter` gives the context to each converter that implements it:

```php
use Temporal\DataConverter\HasWorkflowSerializationContext;
use Temporal\DataConverter\PayloadConverterInterface;
use Temporal\DataConverter\SerializationContext;
use Temporal\DataConverter\SerializationContextAwareInterface;

final class TenantKeyConverter implements PayloadConverterInterface, SerializationContextAwareInterface
{
    private ?SerializationContext $context = null;

    public function getSerializationContext(): ?SerializationContext
    {
        return $this->context;
    }

    public function withSerializationContext(?SerializationContext $context): static
    {
        $clone = clone $this;
        $clone->context = $context;
        return $clone;
    }

    private function keyId(): string
    {
        return $this->context instanceof HasWorkflowSerializationContext
            ? $this->context->getNamespace() . '/' . $this->context->getWorkflowId()
            : 'default';
    }

    // getEncodingType(), toPayload() and fromPayload() use $this->keyId().
}
```

Context types:

- `WorkflowSerializationContext` - `namespace`, `workflowId`
- `ActivitySerializationContext` - `namespace`, `activityType`, `taskQueue`, `workflowId`, `workflowType`, `isLocal`

Both implement `HasWorkflowSerializationContext`. The SDK applies the context on the client and the worker to Workflow and Activity inputs and results, Signals, Queries, Updates, Memo, child Workflows, Continue-As-New, external Signals and failures. `ActivityCompletionClient` applies no context by default: call `withContext(ActivitySerializationContext $context)` on it to set one.

## Payload Encryption

The PHP SDK has no `PayloadCodec` interface and no codec chain. To encrypt payloads, implement a payload converter (or a `DataConverterInterface` decorator) that encrypts the result of the inner converter and marks it with its own `encoding` metadata. Use the [serialization context](#serialization-context) to select a key per Workflow. To see decrypted payloads in the Web UI and CLI, run a separate codec server.

## Payload Size Limits

Since SDK 2.20, the client logs a `[TMPRL1103]` warning when a request carries a payload above 512 KiB or a Memo above 2 KiB. The limits are configurable:

```php
use Temporal\Client\ClientOptions;
use Temporal\Common\PayloadLimitOptions;

$options = (new ClientOptions())->withPayloadLimits(
    PayloadLimitOptions::new()->withPayloadSizeWarning(1024 * 1024),
);

$client = WorkflowClient::create(ServiceClient::create('127.0.0.1:7233'), $options);
```

Use `PayloadLimitOptions::disabled()` to turn the warnings off. On the worker, a payload above the namespace limit fails the Workflow Task with `PAYLOADS_TOO_LARGE`. `WorkerOptions::new()->withDisablePayloadErrorLimit()` turns off this check. Store large data outside Temporal and pass a reference instead.

## Search Attributes

Register custom Search Attributes in the namespace before use. Set them when the Workflow starts:

```php
use Temporal\Client\WorkflowOptions;
use Temporal\Common\SearchAttributes\SearchAttributeKey;
use Temporal\Common\TypedSearchAttributes;

$options = WorkflowOptions::new()
    ->withTaskQueue('orders')
    ->withTypedSearchAttributes(
        TypedSearchAttributes::empty()
            ->withValue(SearchAttributeKey::forKeyword('OrderId'), 'order-123')
            ->withValue(SearchAttributeKey::forKeyword('OrderStatus'), 'pending'),
    );
```

Change them from the Workflow:

```php
Workflow::upsertTypedSearchAttributes(
    SearchAttributeKey::forKeyword('OrderStatus')->valueSet('completed'),
);
```

Find Workflows by Search Attributes from a client:

```php
foreach ($client->listWorkflowExecutions('OrderStatus = "pending"') as $execution) {
    echo $execution->execution->getID(), PHP_EOL;
}
```

## Workflow Memo

Memo is metadata that is not indexed:

```php
$options = WorkflowOptions::new()->withMemo(['source' => 'checkout']);

// Inside the workflow
Workflow::upsertMemo(['phase' => 'fulfilled']);
```

## Deterministic APIs for Values

Use these in Workflow code:

```php
$now = Workflow::now();
$id = yield Workflow::uuid7();
$random = yield Workflow::sideEffect(fn() => random_int(1, 100));
```

## Best Practices

1. Use typed DTOs with `readonly` properties for inputs and results.
2. Register the same converter on clients, workers and replayers.
3. Keep payloads small. Store large data externally and pass references.
4. Do not put secrets or personal data in Search Attributes or Memo.
5. Add new DTO fields with defaults to keep old payloads decodable.
