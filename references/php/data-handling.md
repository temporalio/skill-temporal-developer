# PHP SDK Data Handling

Sources: [SDK converters](https://github.com/temporalio/sdk-php/tree/v2.18/src/DataConverter), [typed Search Attributes](https://github.com/temporalio/sdk-php/blob/v2.18/src/Common/TypedSearchAttributes.php), [Laravel integration](integrations/laravel-temporal.md).

## Contracts and payloads

The default `DataConverter` tries `NullConverter`, `BinaryConverter`, `ProtoJsonConverter`, `ProtoConverter`, then `JsonConverter`. Use small explicit inputs: business IDs, immutable DTO snapshots, cursors and external result references. Do not serialize service/container objects or rely on a hydrated ORM model to stay current. Loading a lazy relation in a workflow is still DB I/O.

For a generator workflow, its PHP return declaration describes the coroutine, not the serialized result:

```php
use Temporal\Workflow\ReturnType;
use Temporal\Workflow\WorkflowInterface;
use Temporal\Workflow\WorkflowMethod;

#[WorkflowInterface]
interface OrderWorkflowInterface
{
    #[WorkflowMethod(name: 'Order')]
    #[ReturnType(OrderResult::class)]
    public function run(OrderInput $input): \Generator;
}
```

`#[ReturnType]` supplies the result type for typed client/child calls; untyped clients can specify a result type explicitly. Use a compatible declared return type for synchronous methods. Test nested DTOs, enums, UUIDs, dates, collections and nullable fields through the actual converter on both sides. Adding a required constructor field can break old payloads; preserve backward-compatible decoding and fixtures.

## Custom conversion and encryption

Implement `Temporal\DataConverter\PayloadConverterInterface` when specializing one payload type. Its decode signature is `fromPayload(Payload $payload, Temporal\DataConverter\Type $type)`, not `ReflectionType`. Return `null` from `toPayload()` for unsupported values. Put specialized converters before the catch-all `JsonConverter` and preserve support for other encodings that the application uses.

Register the same converter for the client and worker:

```php
$client = \Temporal\Client\WorkflowClient::create(
    \Temporal\Client\GRPC\ServiceClient::create('127.0.0.1:7233'),
    converter: $converter,
);
$factory = \Temporal\WorkerFactory::create(converter: $converter);
```

Also align Schedule clients, replay workers, and test invocation caches. The named parameter is `converter`, not `dataConverter`.

Payload encryption/compression needs an implementation compatible with PHP's converter contracts, for example a `DataConverterInterface` decorator around the normal serialization pipeline. Verify encode/decode, encoding metadata, key rotation and old-history replay; use a reviewed encryption library. SDK v2.18 has no `DataConverter::withCodec()` or `Temporal\DataConverter\PayloadCodecInterface`; do not copy those APIs from other SDKs. A codec server is an optional UI/CLI decoding service, not worker-side encryption by itself. Search Attributes remain queryable metadata and must not contain secrets.

## Search Attributes and Memo

Register custom Search Attribute names/types in the target namespace before using them. Set values at workflow start:

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
    )
    ->withMemo(['source' => 'checkout']);
```

Within a workflow:

```php
\Temporal\Workflow::upsertTypedSearchAttributes(
    \Temporal\Common\SearchAttributes\SearchAttributeKey::forKeyword('OrderStatus')
        ->valueSet('completed'),
);
\Temporal\Workflow::upsertMemo(['phase' => 'fulfilled']);
```

These upserts are synchronous SDK calls. Memo is non-indexed metadata; Search Attributes support visibility filtering. Queries read one workflow's current state and require a worker; visibility is indexed and can lag. Use a DB projection for application reporting when appropriate, with Activities updating it idempotently.

```php
foreach ($client->listWorkflowExecutions('OrderStatus = "pending"') as $info) {
    echo $info->execution->getID(), PHP_EOL; // Client-side code only.
}
```

Avoid placing customer names/phones/addresses in Memo, Search Attributes or logs merely to make demos convenient. Payload size, retained workflow state and event-history growth are separate budgets; see [bounded batch design](batch-processing.md).
