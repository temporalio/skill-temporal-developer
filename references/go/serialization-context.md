> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

[Cross-SDK concept file](references/core/serialization-context.md).

The Go SDK delivers a **serialization context** — `converter.StorageDriverStoreContext` on the way in and `converter.StorageDriverRetrieveContext` on the way out — to every custom External Storage driver. The context's `Target` field is a discriminated union (`converter.StorageDriverWorkflowInfo` or `converter.StorageDriverActivityInfo`) that carries namespace and execution-identity metadata, including the Standalone-Activity case.

## Prerequisites

- A Temporal Go SDK version that supports External Storage and the `converter.StorageDriver` interface. External Storage is in Public Preview; consult the Go SDK release notes for the minimum supported version.
- An existing custom storage driver, or willingness to write one — see the `references/go/data-handling.md` file for the broader Data Converter setup that External Storage plugs into.

## Storage driver context

A `converter.StorageDriver` exposes `Store` and `Retrieve` methods. The first argument to each is the context object:

```go
func (d *MyDriver) Store(
    ctx converter.StorageDriverStoreContext,
    payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) { ... }

func (d *MyDriver) Retrieve(
    ctx converter.StorageDriverRetrieveContext,
    claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) { ... }
```

Both context types carry a `Target` field that identifies the owning execution.

## Reading workflow vs activity metadata

`ctx.Target` is an interface satisfied by one of two concrete types. Use a Go type switch to extract identity fields:

```go
switch info := ctx.Target.(type) {
case converter.StorageDriverWorkflowInfo:
    // Workflow-scoped operation, including Activities started by a Workflow.
    // Fields: info.Namespace, info.WorkflowID
    if info.WorkflowID != "" {
        // build key from info.Namespace + info.WorkflowID
    }
case converter.StorageDriverActivityInfo:
    // StorageDriverActivityInfo is only used for standalone (non-workflow-bound)
    // activities. Activities started by a workflow use StorageDriverWorkflowInfo.
    // Fields: info.Namespace, info.ActivityID
    if info.ActivityID != "" {
        // build key from info.Namespace + info.ActivityID
    }
}
```

Key facts:

- The `StorageDriverActivityInfo` arm fires **only for [Standalone Activities](references/core/standalone-activities.md)** — Activities started directly from a Client without a Workflow.
- An Activity scheduled by a Workflow is reported on the `StorageDriverWorkflowInfo` arm, with the orchestrating Workflow's ID.
- The docs describe the identity fields as "namespace, Workflow ID" depending on the operation; use the type switch to access the concrete values.

## Driver selection

When more than one driver is registered, a `StorageDriverSelector` decides which driver stores a given payload. Its `SelectDriver` method receives the same `StorageDriverStoreContext`, so the selection logic can branch on namespace, Workflow ID, or whether the operation is a Standalone Activity:

```go
func (s *PreferredSelector) SelectDriver(
    ctx converter.StorageDriverStoreContext,
    payload *commonpb.Payload,
) (converter.StorageDriver, error) {
    // Inspect ctx.Target the same way Store does.
    return s.preferred, nil
}
```

Return `nil` for the driver to keep a payload inline in Event History instead of offloading.

## Common mistakes

- **Switching on `Target` with a default-case fallthrough that assumes Workflow identity.** A driver that runs against Standalone Activities will land in `StorageDriverActivityInfo` and have no `WorkflowID`. Branch explicitly.
- **Reading `info.WorkflowID` on `StorageDriverActivityInfo`.** The activity branch carries `info.Namespace` and `info.ActivityID` only.
- **Expecting a context on `PayloadConverter` or `PayloadCodec`.** The Go SDK's serialization-context object is only passed to the `StorageDriver` interface (and the `StorageDriverSelector`). To key behavior off Workflow/Activity identity, do it in the storage driver, not in a custom Payload Converter.
- **Changing a driver's `Name()` after payloads have been written.** The SDK records the name on each claim; renaming breaks retrieval.

## Resources

- External Storage encyclopedia page: <https://docs.temporal.io/external-storage>
- Go SDK External Storage guide: <https://docs.temporal.io/develop/go/data-handling/external-storage>
- Cross-SDK concept file: `references/core/serialization-context.md`.
- Standalone Activities (Go): see the language-specific reference under `references/{your_language}/standalone-activities.md`.
