# Temporal Nexus (GA)

One-sentence: Nexus Operations are GA for calling from Workflows and for Workflow‑backed Operation handlers, with stabilized APIs.

## What To Use Nexus For

- Cross‑Namespace calls with durability, observability, and security via a Nexus Endpoint.
- Two operation modes:
  - Synchronous: must finish within the 10‑second handler deadline.
  - Asynchronous: can run up to 60 days in Temporal Cloud.
- Prefer synchronous only when the full path is highly reliable and well under 10s; otherwise choose asynchronous.

## Endpoints and Registry

- Endpoint is a managed reverse proxy; callers use an Endpoint name, which routes to a target Namespace and Task Queue.
- Each Endpoint targets a single Nexus Service (single Namespace + Task Queue).
- Runtime access uses an allowlist of caller Namespaces; no callers are allowed by default.
- In Temporal Cloud, Registry is account‑wide; Endpoint resource is project‑scoped for management.

## Execution Semantics and Timeouts

- At‑least‑once execution with automatic retries handled by Nexus Machinery.
- Timeouts set by the caller:
  - Schedule‑to‑Close (overall operation; Cloud max 60 days).
  - Schedule‑to‑Start (wait to be started or completed if sync).
  - Start‑to‑Close (async only).

## Circuit Breaking

- Trips per caller‑Namespace/Endpoint pair after 5 consecutive retryable errors; pauses requests, probes after 60s.
- Repeated sync handler failures/timeouts can contribute to trips; ensure handler availability.

## CLI Entry Points

- Self‑hosted operations from CLI:
  - `temporal nexus operation start|execute|result|cancel|terminate` with `--endpoint --service --operation --operation-id` and optional timeouts/inputs.
- Cloud endpoint management:
  - `temporal cloud nexus endpoint create|update|get|list` and manage `allowed-namespace`.

## Language Pages

- TypeScript: see `references/typescript/nexus.md`.
- .NET: see `references/dotnet/nexus.md`.

## Don’t / Do

- Don’t use a sync Operation if the work risks exceeding 10s; do use an async Operation backed by a Workflow.
- Don’t assume Endpoint callers are permitted by default; do add allowed Namespaces.
- Don’t register partial handlers on a Task Queue; do ensure Workers on a Queue register all Workflows/Activities/Nexus Operations they serve.
