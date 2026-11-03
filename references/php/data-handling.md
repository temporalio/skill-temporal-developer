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
    // Added in a later version: a property default, not a constructor parameter
    public ?string $couponCode = null;

    public function __construct(
        public readonly string $orderId,
        public readonly int $amountCents,
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

The JSON converter creates the object without its constructor. A constructor parameter default is therefore not applied to an old payload: the property stays uninitialized, and the first read throws an `Error`, which retries the Workflow Task forever. Add a new field as a non-promoted property with a property default (`public ?string $couponCode = null;`). A `readonly` property cannot have a default, so use `readonly` only for fields that exist since the first version.

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

Since SDK 2.20, a payload converter can know which Workflow or Activity it serializes data for. Use it to select an encryption key or to sign payloads per Workflow. Implement `SerializationContextAwareInterface`. The `DataConverter` gives the context to each converter that implements it.

The example signs each `SignedValue` payload with its Workflow and rejects a payload decoded for another Workflow:

```php
use Temporal\Api\Common\V1\Payload;
use Temporal\DataConverter\HasWorkflowSerializationContext;
use Temporal\DataConverter\PayloadConverterInterface;
use Temporal\DataConverter\SerializationContext;
use Temporal\DataConverter\SerializationContextAwareInterface;
use Temporal\DataConverter\Type;

final class SignedValue
{
    public function __construct(public mixed $value) {}
}

final class SigningConverter implements PayloadConverterInterface, SerializationContextAwareInterface
{
    private const ENCODING = 'json/signed';
    private const METADATA_KEY = 'ctx-signature';

    private ?SerializationContext $context = null;
    private string $signature = 'none';

    public function getEncodingType(): string
    {
        return self::ENCODING;
    }

    public function getSerializationContext(): ?SerializationContext
    {
        return $this->context;
    }

    public function withSerializationContext(?SerializationContext $context): static
    {
        $clone = clone $this;
        $clone->context = $context;
        $clone->signature = $context instanceof HasWorkflowSerializationContext
            ? $context->getNamespace() . '|' . ($context->getWorkflowId() ?? '')
            : 'none';
        return $clone;
    }

    public function toPayload($value): ?Payload
    {
        if (!$value instanceof SignedValue) {
            return null;
        }

        return (new Payload())
            ->setData(json_encode($value->value, \JSON_THROW_ON_ERROR))
            ->setMetadata(['encoding' => self::ENCODING, self::METADATA_KEY => $this->signature]);
    }

    public function fromPayload(Payload $payload, Type $type): SignedValue
    {
        $signature = $payload->getMetadata()[self::METADATA_KEY] ?? '';
        if ($signature !== $this->signature) {
            throw new \RuntimeException("Payload signed for \"{$signature}\", decoded for \"{$this->signature}\"");
        }

        return new SignedValue(json_decode($payload->getData(), true, 512, \JSON_THROW_ON_ERROR));
    }
}
```

Register it on the client and the worker, before `JsonConverter`:

```php
$converter = new DataConverter(
    new SigningConverter(),
    new NullConverter(),
    new BinaryConverter(),
    new ProtoJsonConverter(),
    new ProtoConverter(),
    new JsonConverter(),
);
```

Context types:

- `WorkflowSerializationContext` - `namespace`, `workflowId`
- `ActivitySerializationContext` - `namespace`, `activityType`, `taskQueue`, `workflowId`, `workflowType`, `isLocal`

Both implement `HasWorkflowSerializationContext`. The SDK applies the context on the client and the worker to Workflow and Activity inputs and results, Signals, Queries, Updates, Memo, child Workflows, Continue-As-New, external Signals and failures. `ActivityCompletionClient` applies no context by default: call `withContext(ActivitySerializationContext $context)` on it to set one.

## Payload Encryption

The PHP SDK has no `PayloadCodec` interface and no codec chain. To encrypt payloads, decorate the `DataConverter`: encrypt the payload that the inner converter makes, and mark it with its own `encoding`.

```php
use Temporal\Api\Common\V1\Payload;
use Temporal\DataConverter\DataConverterInterface;
use Temporal\DataConverter\HasWorkflowSerializationContext;
use Temporal\DataConverter\SerializationContext;
use Temporal\DataConverter\SerializationContextAwareInterface;

final class EncryptingConverter implements DataConverterInterface, SerializationContextAwareInterface
{
    private const ENCODING = 'binary/encrypted';

    private ?SerializationContext $context = null;

    public function __construct(
        private DataConverterInterface $inner,
        private readonly KeyStore $keys,
    ) {}

    public function getSerializationContext(): ?SerializationContext
    {
        return $this->context;
    }

    public function withSerializationContext(?SerializationContext $context): static
    {
        $clone = clone $this;
        $clone->context = $context;
        if ($this->inner instanceof SerializationContextAwareInterface) {
            $clone->inner = $this->inner->withSerializationContext($context);
        }
        return $clone;
    }

    public function toPayload($value): Payload
    {
        $keyId = $this->keyId();
        $plain = $this->inner->toPayload($value)->serializeToString();

        return (new Payload())
            ->setData($this->keys->encrypt($keyId, $plain))
            ->setMetadata(['encoding' => self::ENCODING, 'key-id' => $keyId]);
    }

    public function fromPayload(Payload $payload, $type)
    {
        if (($payload->getMetadata()['encoding'] ?? '') !== self::ENCODING) {
            return $this->inner->fromPayload($payload, $type);
        }

        $plain = new Payload();
        $plain->mergeFromString($this->keys->decrypt($payload->getMetadata()['key-id'], $payload->getData()));

        return $this->inner->fromPayload($plain, $type);
    }

    private function keyId(): string
    {
        return $this->context instanceof HasWorkflowSerializationContext ? $this->context->getNamespace() : 'default';
    }
}

$converter = new EncryptingConverter(DataConverter::createDefault(), $keyStore);
```

- Implement `SerializationContextAwareInterface` on the decorator. Otherwise the SDK does not give it the context, and it does not pass the context to the inner converter.
- Use the same converter on the client, the worker and the replayer. Keep old keys to decrypt old histories.
- Failure messages and stack traces are not encrypted. Search Attributes and Memo keys are not encrypted.
- To see decrypted payloads in the Web UI and CLI, run a separate codec server.

## Payload Size Limits

Since SDK 2.20, the client logs a `[TMPRL1103]` warning when a request carries a payload above 512 KiB or a Memo above 2 KiB. The limits are configurable (experimental API):

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

1. Use typed DTOs for inputs and results.
2. Register the same converter on clients, workers and replayers.
3. Keep payloads small. Store large data externally and pass references.
4. Do not put secrets or personal data in Search Attributes or Memo.
5. Add new DTO fields as properties with property defaults, not as constructor parameters.
