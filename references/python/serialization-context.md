> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

[Cross-SDK concept file](references/core/serialization-context.md).

The Python SDK delivers a **serialization context** — `StorageDriverStoreContext` on the way in and `StorageDriverRetrieveContext` on the way out — to every custom External Storage driver. The context's `target` attribute is a discriminated union (`StorageDriverWorkflowInfo` or `StorageDriverActivityInfo`) that carries namespace and execution-identity metadata, including the Standalone-Activity case.

## Prerequisites

- A Temporal Python SDK version that exposes the External Storage `StorageDriver` abstract class. External Storage is in Public Preview; consult the Python SDK release notes for the minimum supported version.
- An existing custom storage driver, or willingness to write one — see `references/python/data-handling.md` for the broader Data Converter setup that External Storage plugs into.

## Storage driver context

A custom Python storage driver subclasses `StorageDriver` and implements async `store` and `retrieve` methods. The second argument to each is the context object:

```python
class MyDriver(StorageDriver):
    async def store(
        self,
        context: StorageDriverStoreContext,
        payloads: Sequence[Payload],
    ) -> list[StorageDriverClaim]:
        ...

    async def retrieve(
        self,
        context: StorageDriverRetrieveContext,
        claims: Sequence[StorageDriverClaim],
    ) -> list[Payload]:
        ...
```

Both context types expose a `target` attribute that identifies the owning execution.

## Reading workflow vs activity metadata

`context.target` is one of two concrete classes. Use `isinstance` to extract identity fields:

```python
target = context.target
if isinstance(target, StorageDriverWorkflowInfo) and target.id:
    # Workflow-scoped operation, including Activities started by a Workflow.
    # Attributes: target.namespace, target.id  (Workflow ID)
    prefix = os.path.join(base_dir, target.namespace, target.id)
elif isinstance(target, StorageDriverActivityInfo):
    # StorageDriverActivityInfo only fires for standalone (non-workflow-bound)
    # activities. Activities started by a workflow use StorageDriverWorkflowInfo.
    ...
```

Key facts:

- The `StorageDriverActivityInfo` branch fires **only for [Standalone Activities](references/core/standalone-activities.md)** — Activities started directly from a Client without a Workflow.
- An Activity scheduled by a Workflow is reported on `StorageDriverWorkflowInfo`, with the orchestrating Workflow's ID.
- The docs describe the identity attributes as "namespace, Workflow ID, or Activity ID" depending on the operation.
- The transcribed snippet uses `target.id` for the Workflow ID and `target.namespace` for the namespace on the `StorageDriverWorkflowInfo` branch.

## Driver selection

When more than one driver is registered, you must pass a `driver_selector` callable to `ExternalStorage`. The selector receives the same `StorageDriverStoreContext` plus the payload and returns the driver to use — or `None` to keep the payload inline in Event History:

```python
ExternalStorage(
    drivers=[preferred_driver, legacy_driver],
    driver_selector=lambda context, payload: preferred_driver,
)
```

Branch inside the selector on `context.target` the same way the driver does.

## Common mistakes

- **Falling through to a Workflow-only code path when `target` is `StorageDriverActivityInfo`.** Standalone Activities have no Workflow ID; check the branch explicitly.
- **Expecting a context on `EncodingPayloadConverter` or `PayloadCodec`.** The Python SDK's serialization-context object is only passed to the `StorageDriver` (and the `driver_selector` callable). To key behavior off Workflow/Activity identity, do it in the storage driver, not in a custom Payload Converter.
- **Changing a driver's `name()` after payloads have been written.** The SDK records the name on each claim; renaming breaks retrieval.

## Resources

- External Storage encyclopedia page: <https://docs.temporal.io/external-storage>
- Python SDK External Storage guide: <https://docs.temporal.io/develop/python/data-handling/external-storage>
- Cross-SDK concept file: `references/core/serialization-context.md`.
- Standalone Activities (Python): `references/python/standalone-activities.md`.
