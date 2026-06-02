> [!NOTE]
> External Storage and its serialization-context object are in Public Preview in the SDKs that ship it. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

## Overview

[Cross-SDK concept file](references/core/serialization-context.md).

The Temporal **.NET SDK documentation currently has no published surface for a serialization-context object** delivered to Data Converter components. The encyclopedia External Storage page lists SDK-specific guides for the Go SDK and Python SDK only; there is no .NET SDK guide.

What the .NET docs **do** describe is the existing Data Converter and Codec surface in `Temporalio.Converters`. `IPayloadCodec` exposes `EncodeAsync(IReadOnlyCollection<Payload>)` and `DecodeAsync(IReadOnlyCollection<Payload>)` — neither overload receives a context parameter.

Treat this page as a placeholder. If a user asks how to access Workflow/Activity identity inside a .NET custom converter or codec today, the supported answer is "the .NET SDK does not document one."

## Prerequisites

## Storage driver context

## Reading workflow vs activity metadata

## Driver selection

## Common mistakes

- **Assuming the .NET SDK has the same `SerializationContext` / `StorageDriver` API as Go or Python.** It does not, as of the current published documentation. Don't generate .NET code that imports `Temporalio.Converters.StorageDriverStoreContext` or similar based on the Go/Python names.
- **Reaching for a context parameter on `IPayloadCodec.EncodeAsync` / `DecodeAsync`.** Neither method receives a context argument in the documented .NET API.

## Resources

- .NET Data Converters and encryption: <https://docs.temporal.io/develop/dotnet/data-handling> (see "Converters and encryption").
- External Storage encyclopedia page (Go and Python only, today): <https://docs.temporal.io/external-storage>
- Cross-SDK concept file: `references/core/serialization-context.md`.
