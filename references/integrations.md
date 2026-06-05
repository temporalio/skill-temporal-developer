# Third-Party Integrations Catalog

Temporal ships and supports a growing set of integrations with third-party frameworks and SDKs — typically as plugins, contrib modules, or starter libraries. This file is the catalog. Each integration has a dedicated reference under `references/{language}/integrations/`.

## How to use this catalog

1. Find the row matching the framework, SDK, or library the user is working with.
2. Confirm the language column matches what the user is building in.
3. Read the linked reference file for setup, APIs, and pitfalls.
4. Cross-check the **Related** column — for AI/LLM integrations, also read `references/core/ai-patterns.md` and the language's `ai-patterns.md`; for Spring-based integrations, read `references/java/integrations/spring-boot.md` first.

## Catalog

| Integration | Language(s) | What it does | Reference | Related |
|---|---|---|---|---|
| Spring Boot (`temporal-spring-boot-starter`) | Java | Auto-configuration of `WorkflowClient`, worker factories, workflow/activity bean registration, lifecycle, testing | `references/java/integrations/spring-boot.md` | `references/java/java.md` |
| Spring AI (`temporal-spring-ai`) | Java | Durable Spring AI agents: chat-model calls run as Activities; tools dispatched per type (Activity stub, Nexus stub, `@SideEffectTool`, plain); vector stores, embeddings, and MCP clients auto-registered | `references/java/integrations/spring-ai.md` | `references/java/integrations/spring-boot.md`, `references/core/ai-patterns.md` |
| OpenAI Agents SDK (`temporalio.contrib.openai_agents`) | Python | Durable OpenAI Agents SDK agents: model calls run as Activities via `OpenAIAgentsPlugin`; tools are Activities (`activity_as_tool`) or workflow-resident `@function_tool`s; stateless/stateful MCP, sandbox backends, streaming, and OpenTelemetry export are supported | `references/python/integrations/openai-agents-sdk.md` | `references/python/ai-patterns.md`, `references/core/ai-patterns.md` |
| LangSmith tracing (`temporalio.contrib.langsmith`) | Python | Experimental Temporal Plugin that propagates LangSmith trace context across Worker boundaries; lets `@traceable` run inside Workflows and Activities | `references/python/integrations/langsmith.md` | `references/python/ai-patterns.md`, `references/core/ai-patterns.md` |
| LangGraph (`temporalio.contrib.langgraph`, Pre-release) | Python | Runs LangGraph Graph-API and Functional-API code as Temporal Workflows - nodes/tasks can execute as either in-workflow or as Activities | `references/python/integrations/langgraph.md` | `references/python/ai-patterns.md`, `references/core/ai-patterns.md` |
| Google ADK (`temporalio[google-adk]`) | Python | Durable Google ADK agents: model calls run through `TemporalModel`-wrapped Activities, tools via `activity_tool`, MCP toolsets via `TemporalMcpToolSet` | `references/python/integrations/google-adk.md` | `references/python/ai-patterns.md`, `references/core/ai-patterns.md` |
| OpenTelemetry (`temporalio[opentelemetry]`) | Python | Distributed tracing for Temporal apps with OpenTelemetry | `references/python/observability.md` (Distributed Tracing section) | |
