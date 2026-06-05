# Temporal Braintrust Integration (TypeScript)

## Overview

[Braintrust](https://braintrust.dev) is an LLM observability and prompt-management platform. The Temporal TypeScript integration is delivered as the `@braintrust/temporal` package, which exposes a `BraintrustTemporalPlugin` that registers on both the Temporal Client and the Worker. Once registered, the plugin produces Braintrust spans for Workflow and Activity executions and propagates trace context across the Worker boundary.

The Temporal TypeScript documentation lists Braintrust as a supported integration and points to the Braintrust-hosted guide as the canonical reference.

> Canonical TypeScript guide: <https://www.braintrust.dev/docs/integrations/sdk-integrations/temporal#typescript>. Treat the Braintrust-hosted page as authoritative for TypeScript-specific API surface; this reference file captures only what is independently verifiable from Temporal's documentation and the canonical guide.

For conceptual LLM patterns shared across SDKs read `references/core/ai-patterns.md`.

## Prerequisites

- An existing Temporal TypeScript development environment as described in `references/typescript/typescript.md`.
- A Braintrust account.

## Install

```bash
npm install @braintrust/temporal braintrust @temporalio/client @temporalio/worker @temporalio/workflow @temporalio/activity @temporalio/common
```

The integration package is `@braintrust/temporal`; it sits alongside the standard `braintrust` SDK and the relevant `@temporalio/*` packages.

## Initialize the Braintrust logger

Initialize the Braintrust logger before constructing the Temporal Client and Worker so spans connect to the active project.

```typescript
import * as braintrust from "braintrust";

braintrust.initLogger({ projectName: "my-project" });
```

## Register `BraintrustTemporalPlugin` on the Client and the Worker

Create one `BraintrustTemporalPlugin` instance and pass it to **both** the Client and the Worker via `plugins`.

```typescript
import { Client, Connection } from "@temporalio/client";
import { Worker } from "@temporalio/worker";
import { BraintrustTemporalPlugin } from "@braintrust/temporal";

const plugin = new BraintrustTemporalPlugin();

const client = new Client({
  connection: await Connection.connect(),
  plugins: [plugin],
});

const worker = await Worker.create({
  taskQueue: "my-task-queue",
  workflowsPath: require.resolve("./workflows"),
  activities,
  plugins: [plugin],
});
```

The Client registration links client-initiated spans to the Workflow Executions they start. The Worker registration produces the Workflow and Activity spans inside Braintrust.

## API credentials

The Worker process needs the `BRAINTRUST_API_KEY` environment variable available so the plugin can post spans to Braintrust. The Client process that starts Workflow Executions does not call Braintrust directly.

## Tracing LLM calls, custom spans, and prompt management

Braintrust's standard TypeScript SDK provides:

- `wrapTraced` / wrapped client helpers to capture LLM calls as spans.
- `startSpan` to add application-level context (user query, final output) around `client.workflow.start` / `client.workflow.execute`.
- `loadPrompt` to fetch prompts managed in the Braintrust UI so prompt edits ship without redeploying code.

These helpers are not Temporal-specific; consult the canonical Braintrust TypeScript SDK documentation and the Temporal-specific guide at <https://www.braintrust.dev/docs/integrations/sdk-integrations/temporal#typescript> for current API surface before using them inside Activities or client code.

## Common mistakes

- **Initializing the Braintrust logger after constructing the Client or Worker.** Call `braintrust.initLogger({ projectName: ... })` first so the Worker process attaches spans to the correct project.
- **Registering `BraintrustTemporalPlugin` on only one side.** Register on both the Client and the Worker so client-side spans link to the Workflows they start.
- **Calling LLM-tracing or prompt-loading APIs from inside a Workflow.** Workflows must be deterministic; place LLM calls and `loadPrompt` invocations inside Activities, matching the pattern documented for the Python integration in `references/python/integrations/braintrust.md`.

## Additional Resources

- Canonical TypeScript guide: <https://www.braintrust.dev/docs/integrations/sdk-integrations/temporal#typescript>.
- `references/python/integrations/braintrust.md` — the Python integration is the closest documented analogue; the high-level patterns (Plugin on Client + Worker, LLM calls in Activities, prompts loaded from Braintrust) carry over conceptually.
- `references/core/ai-patterns.md` — conceptual LLM patterns shared across SDKs.
