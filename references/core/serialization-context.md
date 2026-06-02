> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

# Serialization Context (Concepts)

For language-specific implementation, see `references/{your_language}/serialization-context.md`.

## What "serialization context" means in Temporal today

When the SDK serializes a Payload on the way out of your application, the **Data Conversion pipeline** runs Payload Converters first, then Payload Codecs, then — if configured — hands the encoded bytes to an **External Storage driver** that offloads large payloads to a backing store like Amazon S3.

The External Storage **storage driver** is the one stage of that pipeline that receives a context object alongside the payloads. This context carries identity information about the operation that triggered the serialization — namespace plus the owning Workflow or, for [Standalone Activities](references/core/standalone-activities.md), the owning Activity.

The current Public Preview surface only exposes this context to **storage drivers** (and to the driver-selection callback when multiple drivers are registered). Payload Converters and Payload Codecs do not currently receive a serialization-context argument in Temporal's documented SDK APIs.

## The context object and its `Target`

Two parallel context types exist, one per direction of the pipeline:

- A **store** context delivered to the driver's store/upload entry point.
- A **retrieve** context delivered to the driver's retrieve/download entry point.

Each context carries a `Target` (Go) / `target` (Python) field that is a **discriminated union** over two concrete types:

- A **WorkflowInfo** branch, present whenever the operation is associated with a Workflow Execution. Activities **started by a Workflow** are reported through this branch too.
- An **ActivityInfo** branch, present **only for Standalone Activities** (Activities started directly from a Temporal Client, not orchestrated by a Workflow).

This is the headline rule: if your driver branches on the target type, the `ActivityInfo` arm is the **Standalone-Activity-only** path. For Workflow-bound activities, you still receive `WorkflowInfo`.

## What's on each branch

The exact field names differ across SDKs — see the per-language reference for the verbatim API:

- **WorkflowInfo** carries the namespace and the Workflow ID.
- **ActivityInfo** carries the namespace and the Activity ID (no Workflow ID, because there is no Workflow).

Driver authors typically:

1. Switch / `isinstance` on the target type.
2. Build a storage key prefix from the namespace plus the workflow-or-activity ID.
3. Write payloads under that prefix so storage is naturally partitioned by execution.

## Where this context shows up

- The driver's **store** method (Go: `Store(ctx, payloads)`; Python: `async def store(self, context, payloads)`).
- The driver's **retrieve** method (Go: `Retrieve(ctx, claims)`; Python: `async def retrieve(self, context, claims)`).
- The **driver-selector** callback used when more than one storage driver is registered. The selector receives the store context plus the payload and returns the driver to use (or `nil` / `None` to keep the payload inline).

## SDK coverage

Documented SDK guides for External Storage and its context object exist for:

- **Go SDK** — see `references/go/serialization-context.md`.
- **Python SDK** — see `references/python/serialization-context.md`.

The encyclopedia External Storage page lists only those two SDKs. The Temporal **.NET SDK** documentation is currently silent on a serialization-context object; treat `references/dotnet/serialization-context.md` as a placeholder until .NET docs add coverage.

## Common mistakes

- **Assuming `ActivityInfo` covers Workflow-bound activities.** It does not. An Activity scheduled by a Workflow surfaces as `WorkflowInfo` (Workflow ID is the orchestrator's ID). Only [Standalone Activities](references/core/standalone-activities.md) produce `ActivityInfo`.
- **Reaching for workflow info from inside a custom Payload Converter or Payload Codec.** No documented SDK API exposes a context to those stages today; only the StorageDriver does. If you need the owning Workflow ID at serialization time, implement a custom storage driver (or driver selector) rather than smuggling state into a converter.
- **Treating `Target` as a struct with a `Kind` enum.** It is a discriminated union — a Go interface satisfied by either concrete type, or a Python target whose runtime type you check with `isinstance`. Use a type switch / `isinstance`.

## Resources

- External Storage encyclopedia page: <https://docs.temporal.io/external-storage>
- Standalone Activities concept page: see `references/core/standalone-activities.md`.
