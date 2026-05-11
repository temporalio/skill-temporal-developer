# Google ADK Integration (Python)

## Overview

The Temporal Python SDK ships a Google ADK integration that lets you run Google ADK agents inside Temporal Workflows, gaining durable execution (automatic retries, state persistence, recovery) for agent runs. <!-- docs/develop/python/integrations/index.mdx:21-26 -->

Google ADK is listed in the Python integrations table as an **Agent framework**. <!-- docs/develop/python/integrations/index.mdx:26 -->

## Authoritative setup guide

The Temporal documentation does **not** host the setup steps for this integration. The canonical, authoritative guide is on the Google ADK site:

- **Integration guide:** <https://adk.dev/integrations/temporal/> <!-- docs/develop/python/integrations/index.mdx:26 -->
- **Google ADK SDK docs:** <https://adk.dev/> <!-- docs/develop/python/integrations/index.mdx:26 -->

Read the integration guide above for the current package name, plugin/class names, import paths, and end-to-end setup. Do not guess these from memory — they are not present in the Temporal documentation repository.

## How it fits with Temporal

This integration is built on the Temporal Python SDK's [Plugin system](https://docs.temporal.io/develop/plugins-guide), the same substrate used by other Python AI/agent integrations (Braintrust, OpenAI Agents SDK, Pydantic AI). <!-- docs/develop/python/integrations/index.mdx:31-32 -->

Plugins are the recommended way to:

- Register Workflow and Activity definitions for the integration. <!-- docs/develop/plugins-guide.mdx:20-22 -->
- Modify Worker and Client options.  <!-- docs/develop/plugins-guide.mdx:20-22 -->

The Plugins guide lists **AI Agent SDKs** as a primary use case for the Plugin system. <!-- docs/develop/plugins-guide.mdx:27-32 -->

A user normally provides the integration's plugin to both their Temporal Client and Worker, following the same shape used by other Python integrations (see `references/python/ai-patterns.md` for the general AI integration patterns and `docs/develop/python/integrations/braintrust.mdx` for a worked example of plugin-on-Client-and-Worker setup). For Google ADK specifically, follow the steps in the adk.dev integration guide linked above.

## When to use this integration

Use it when:

- You are writing Python.
- You are already using (or planning to use) the Google ADK agent framework.
- You want Temporal's durable execution guarantees — retries, state persistence across worker restarts, and visibility — around your ADK agent runs.

If you are not committed to Google ADK, see the integrations table in `docs/develop/python/integrations/index.mdx` for sibling agent-framework options (OpenAI Agents SDK, Pydantic AI) and the general AI patterns guidance in `references/python/ai-patterns.md` and `references/core/ai-patterns.md`.

## What this skill does not document

Specific setup tokens — pip install command, import paths, plugin class names, code shape — live on the external `adk.dev` integration guide and are not duplicated here. Follow that guide for the current authoritative setup.
