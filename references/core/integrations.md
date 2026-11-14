# Third-Party Integrations Catalog

Temporal ships and supports a growing set of integrations with third-party frameworks and SDKs — typically as plugins, contrib modules, or starter libraries. This file is the catalog. The catalog also lists community packages, marked as such. The catalog includes integrations listed in Temporal's SDK indexes or maintained AI integration repository. Use a local reference when available; otherwise follow the upstream guide. Model-provider examples are labeled as sample patterns rather than SDK plugins.

## How to use this catalog

1. Find the row matching the framework, SDK, or library the user is working with.
2. Confirm the language column matches what the user is building in.
3. Read the linked local reference or upstream guide for setup, APIs, release stage, and version requirements.
4. Cross-check the **Related** column — for AI/LLM integrations, also read [Temporal AI integration patterns](ai-patterns.md) and the language's `ai-patterns.md`; for Spring-based integrations, read [Spring Boot Java integration guide](../java/integrations/spring-boot.md) first.

Temporal-maintained Python AI integrations ship as standalone `temporalio-*` packages with `temporalio.<integration>` imports. For integrations migrated out of the SDK, former `temporalio.contrib.*` paths and SDK extras are compatibility shims. Register Python plugins on the Client; Workers created from that Client inherit plugins implementing the Worker protocol.

Stages below follow the [maintained AI integrations repository](https://github.com/temporalio/ai-integrations) and linked guides; verify them when upgrading.

## AI integration plugins

Plugins maintained in the Temporal AI integrations repository. Use the linked local reference or upstream guide.

| Integration | Language | What it does | Reference | Related |
| -- | -- | -- | -- | -- |
| Claude Agent SDK (`temporalio-claude-agent-sdk`) | Python | Durable Claude agents; Pre-release | [Temporal guide](https://docs.temporal.io/develop/python/integrations/claude-agent-sdk) | — |
| Deep Agents (`temporalio-deepagents`) | Python | Durable LangChain agents; Pre-release | [Temporal guide](https://docs.temporal.io/develop/python/integrations/deepagents) | — |
| Google ADK (`go.temporal.io/googleadk`) | Go | Durable agents; Public Preview | [Temporal guide](https://docs.temporal.io/develop/go/integrations/google-adk) | — |
| Google ADK (`io.temporal:google-adk`) | Java | Durable agents; Public Preview | [Package guide](https://github.com/temporalio/ai-integrations/tree/main/java/google-adk) | — |
| Google ADK (`temporalio-google-adk`, Pre-release) | Python | Durable Google ADK agents: model calls run through `TemporalModel`-wrapped Activities, tools via `activity_as_tool`, MCP toolsets via `TemporalMcpToolSet` | [Google ADK Python integration guide](../python/integrations/google-adk.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| Google ADK (`@temporalio/google-adk`) | TypeScript | Durable agents; Public Preview | [Temporal guide](https://docs.temporal.io/develop/typescript/integrations/google-adk-agents) | — |
| Google GenAI (`temporalio-google-genai`) | Python | Durable Gemini calls; GA ([package metadata](https://github.com/temporalio/ai-integrations/blob/main/python/google_genai/plugin.toml)) | [Temporal guide](https://docs.temporal.io/develop/python/integrations/google-genai) | — |
| LangGraph (`temporalio-langgraph`, Public Preview) | Python | Runs LangGraph Graph-API and Functional-API code as Temporal Workflows - nodes/tasks can execute as either in-workflow or as Activities | [LangGraph Python integration guide](../python/integrations/langgraph.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| LangSmith (`temporalio-langsmith`, Public Preview) | Python | Temporal Plugin that propagates LangSmith trace context across Worker boundaries; lets `@traceable` run inside Workflows and Activities | [LangSmith Python integration guide](../python/integrations/langsmith.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| LangSmith (`@temporalio/langsmith`) | TypeScript | Trace propagation; Public Preview | [Temporal guide](https://docs.temporal.io/develop/typescript/integrations/langsmith) | — |
| MCP (`temporalio-mcp`) | Python | Tools, prompts, and resources as Activities; Pre-release | [Temporal guide](https://docs.temporal.io/develop/python/integrations/mcp) | — |
| OpenAI Agents SDK (`temporalio-openai-agents`, GA) | Python | Durable OpenAI Agents SDK agents: model calls run as Activities via `OpenAIAgentsPlugin`; tools are Activities (`activity_as_tool`) or workflow-resident `@function_tool`s; stateless/stateful MCP, sandbox backends, streaming, and OpenTelemetry export are supported | [OpenAI Agents SDK Python integration guide](../python/integrations/openai-agents-sdk.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| OpenAI Agents SDK (`@temporalio/openai-agents`) | TypeScript | Durable agent execution; GA ([package metadata](https://github.com/temporalio/ai-integrations/blob/main/typescript/openai-agents/plugin.toml)) | [Temporal guide](https://docs.temporal.io/develop/typescript/integrations/openai-agents) | — |
| OpenAI Codex (`temporalio-openai-codex`) | Python | Durable Codex agents; Pre-release | [Package guide](https://github.com/temporalio/ai-integrations/tree/main/python/openai_codex) | — |
| Spring AI (`io.temporal:spring-ai`, Public Preview; legacy `temporal-spring-ai`) | Java | Durable Spring AI agents: chat-model calls run as Activities; tools dispatched per type (Activity stub, Nexus stub, `@SideEffectTool`, plain); vector stores, embeddings, and MCP clients auto-registered | [Spring AI Java integration guide](../java/integrations/spring-ai.md) | [Spring Boot Java integration guide](../java/integrations/spring-boot.md), [Temporal AI integration patterns](ai-patterns.md) |
| Strands Agents (`temporalio-strands-agents`) | Python | Durable Strands agents; Public Preview | [Temporal guide](https://docs.temporal.io/develop/python/integrations/strands-agents) | — |
| Strands Agents (`@temporalio/strands-agents`) | TypeScript | Durable Strands agents; Pre-release | [Temporal guide](https://docs.temporal.io/develop/typescript/integrations/strands-agents) | — |
| TypeSafe (`temporalio-typesafe`) | Python | Durable decision calls as Activities, with confidence routing in Workflow code; Pre-release | [Package guide](https://github.com/temporalio/ai-integrations/tree/main/python/typesafe) | — |
| Vercel AI SDK (`@temporalio/vercel-ai-sdk`, GA) | TypeScript | Durable Vercel AI SDK agents: `AiSdkPlugin` wraps `generateText` and other AI SDK calls as Activities; `temporalProvider.languageModel()` provides the workflow-safe model; tools dispatch via `proxyActivities`; stateless MCP servers register through `mcpClientFactories` and are used in-workflow via `TemporalMCPClient` | [Vercel AI SDK TypeScript integration guide](../typescript/integrations/vercel-ai-sdk.md) | [Temporal AI integration patterns](ai-patterns.md) |

## Additional integrations and sample patterns

Framework integrations, observability packages, community integrations, and sample patterns. Use the linked local reference or upstream guide.

| Integration | Language | What it does | Reference | Related |
| -- | -- | -- | -- | -- |
| Arize | Python | OpenInference tracing through Temporal's existing OpenTelemetry plugin; Public Preview | [Temporal guide](https://docs.temporal.io/develop/python/integrations/arize) | — |
| Baseten | Python | Model-provider sample patterns using OpenAI Agents | [Temporal guide](https://docs.temporal.io/develop/python/integrations/baseten) | — |
| Braintrust (`github.com/braintrustdata/braintrust-sdk-go`) | Go | Workflow and Activity tracing through Temporal's OpenTelemetry interceptor and Braintrust's tracer provider | [Provider guide](https://docs.braintrust.dev/integrations/sdk-integrations/temporal) | — |
| Braintrust (`braintrust[temporal]`, Public Preview) | Python | LLM observability + prompt management: `BraintrustPlugin` traces every Workflow/Activity, `wrap_openai` captures LLM calls, `start_span` adds custom context, `load_prompt` fetches Braintrust-managed prompts | [Braintrust Python integration guide](../python/integrations/braintrust.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| Braintrust (`@braintrust/temporal`) | TypeScript | LLM observability: `BraintrustTemporalPlugin` registers on Client + Worker to trace Workflow/Activity spans; canonical guide hosted by Braintrust | [Braintrust TypeScript integration guide](../typescript/integrations/braintrust.md) | [Temporal AI integration patterns](ai-patterns.md) |
| Fireworks AI | Python | Model-provider sample patterns using OpenAI Agents | [Temporal guide](https://docs.temporal.io/develop/python/integrations/fireworks-ai) | — |
| Future AGI | Go | Workflow and Activity tracing through Temporal's OpenTelemetry integrations; model/tool tracing through library instrumentation | [Go guide](https://docs.futureagi.com/docs/integrations/frameworks/temporal-go/) | — |
| Future AGI | Python | Workflow and Activity tracing through Temporal's OpenTelemetry integrations; model/tool tracing through library instrumentation | [Python guide](https://docs.futureagi.com/docs/integrations/frameworks/temporal/) | — |
| Future AGI | TypeScript | Workflow and Activity tracing through Temporal's OpenTelemetry integrations; model/tool tracing through library instrumentation | [TypeScript guide](https://docs.futureagi.com/docs/integrations/frameworks/temporal-typescript/) | — |
| Laminar | Python | Workflow, Activity, and LLM tracing | [Provider guide](https://laminar.sh/docs/integrations/temporal) | — |
| Laminar | TypeScript | Workflow, Activity, and LLM tracing | [Provider guide](https://laminar.sh/docs/integrations/temporal) | — |
| Langfuse | Python | LLM tracing | [Provider guide](https://langfuse.com/integrations/frameworks/temporal) | — |
| Laravel Temporal (`keepsuit/laravel-temporal`, community) | PHP | Laravel discovery of Workflows and Activities, artisan worker commands, workflow builders, Eloquent/Laravel Data serialization, dispatch fakes and test traits | [Laravel PHP integration guide](../php/integrations/laravel-temporal.md) | [PHP SDK guide](../php/php.md) |
| Mastra (`@mastra/temporal`, Experimental) | TypeScript | Build-time transform of Mastra `createWorkflow`/`createStep` definitions into Temporal Workflows and Activities; `MastraPlugin` auto-registers Activities on the Worker | [Mastra TypeScript integration guide](../typescript/integrations/mastra.md) | [TypeScript SDK guide](../typescript/typescript.md), [Temporal AI integration patterns](ai-patterns.md) |
| OpenBox | Python | Governance and observability | [Provider guide](https://docs.openbox.ai/getting-started/temporal) | — |
| OpenRouter | Python | Model-gateway sample patterns in Activities | [Python guide](https://docs.temporal.io/develop/python/integrations/openrouter) | — |
| OpenRouter | TypeScript | Model-gateway sample patterns in Activities | [TypeScript sample](https://github.com/temporalio/samples-typescript/tree/main/openrouter) | — |
| OpenTelemetry (`temporalio[opentelemetry]`) | Python | Distributed tracing for Temporal apps with OpenTelemetry | [OpenTelemetry Python integration guide](../python/integrations/opentelemetry.md) | [Python observability guide](../python/observability.md) |
| OpenTelemetry (`@temporalio/interceptors-opentelemetry`) | TypeScript | Distributed tracing for Temporal apps using OpenTelemetry JS 1.x | [OpenTelemetry TypeScript integration guide](../typescript/integrations/opentelemetry.md) | [TypeScript observability guide](../typescript/observability.md) |
| OpenTelemetry v2 (`go.temporal.io/sdk/contrib/opentelemetry-v2`) | Go | Context propagation, replay-safe tracing, and optional SDK metrics; Pre-release | [Temporal guide](https://docs.temporal.io/develop/go/integrations/opentelemetry-v2) | — |
| OpenTelemetry v2 (`@temporalio/interceptors-opentelemetry-v2`) | TypeScript | Workflow and Activity tracing using OpenTelemetry JS 2.x; Experimental | [Package guide](https://github.com/temporalio/sdk-typescript/tree/main/contrib/interceptors-opentelemetry-v2) | — |
| Parseable | Java | Execution-event observability | [Java guide](https://github.com/parseablehq/temporal-plugin-java/blob/main/INTEGRATION.md) | — |
| Parseable | Python | Execution-event observability | [Python guide](https://github.com/parseablehq/temporal-plugin-python/blob/main/INTEGRATION.MD) | — |
| Parseable | TypeScript | Execution-event observability | [TypeScript guide](https://github.com/parseablehq/temporal-plugin/blob/main/INTEGRATION.md) | — |
| Pydantic AI (`pydantic-ai[temporal]`) | Python | Durable agents through the `TemporalDurability` capability, with model requests, tool calls, and MCP communication executed as Temporal Activities | [Pydantic AI Python integration guide](../python/integrations/pydantic-ai.md) | [Python AI integration patterns](../python/ai-patterns.md), [Temporal AI integration patterns](ai-patterns.md) |
| Rails | Ruby | Rails setup guidance and sample, including model serialization and eager loading | [Temporal guide](https://docs.temporal.io/develop/ruby/integrations/rails-integration) | — |
| Spring Boot (`temporal-spring-boot-starter`) | Java | Auto-configuration of `WorkflowClient`, worker factories, workflow/activity bean registration, lifecycle, testing | [Spring Boot Java integration guide](../java/integrations/spring-boot.md) | [Java SDK guide](../java/java.md) |
| Tenuo | Python | Governance and compliance | [Provider guide](https://tenuo.ai/temporal) | — |
| Together AI | Python | Model-provider sample patterns using OpenAI Agents | [Temporal guide](https://docs.temporal.io/develop/python/integrations/together-ai) | — |
| xMemory | Python | Memory across Workflow Executions | [Provider guide](https://xmemory.ai/temporal/) | — |
| xMemory | TypeScript | Memory across Workflow Executions | [Provider guide](https://xmemory.ai/temporal/) | — |
