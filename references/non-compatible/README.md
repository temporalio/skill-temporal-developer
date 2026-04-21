# Non-Compatible Temporal Content

This repository was originally derived from a Temporal-oriented skill. It now targets official Cadence scope only.

## Supported Here

- Core Cadence concepts
- Cadence Go SDK
- Cadence Java SDK

## Temporal Material Intentionally Removed Or Replaced

### Temporal Cloud

This skill does not document Temporal Cloud. Use Cadence self-hosted or your Cadence provider's operational guidance.

### Updates

Temporal-style workflow Updates are not part of the official Cadence scope documented here.

Cadence replacement pattern:

- Signal to request mutation
- Query to observe resulting state

### Worker Versioning / Build IDs

Temporal Worker Versioning guidance does not apply here.

Cadence replacement:

- `GetVersion` / `Workflow.getVersion`
- new workflow type for large incompatible changes
- operational recovery such as reset flows when required

### Schedule APIs

Temporal Schedule APIs are not documented here.

Cadence-compatible direction:

- distributed cron where supported by Cadence docs and SDKs

### Temporal TypeScript SDK Runtime Features

Removed examples included Temporal TypeScript-specific features such as:

- `@temporalio/*` packages
- workflow sandbox behavior
- `proxyActivities`
- `TestWorkflowEnvironment` from Temporal TypeScript
- Temporal Schedule APIs for TypeScript

They are not represented as Cadence guidance in this repository.

### Non-Official SDK Surfaces In This Repo

The previous repository also contained Temporal-derived Python, TypeScript, and .NET reference trees. Those are now replaced with compatibility READMEs instead of partial or misleading Cadence conversions.

## Terminology Mapping

Common replacements while working with Cadence:

- Temporal Namespace -> Cadence Domain
- Temporal Task Queue -> Cadence Task List
- Temporal Workflow Task -> Cadence Decision Task
- `temporal` CLI -> `cadence` CLI

## Reason For The Narrower Scope

The goal of this repository is accuracy over surface-area parity. Keeping unsupported Temporal content would make the Cadence skill misleading.
