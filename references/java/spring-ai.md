# Spring AI integration (Java)

## Overview

The `temporal-spring-ai` module makes Spring AI agents durable by routing model calls through Temporal Activities and dispatching each registered tool to the appropriate Temporal primitive. <!-- docs/develop/java/integrations/spring-ai.mdx:22-24 --> Model responses are recorded in Workflow history, agents retry on failure, and replay stays deterministic without changing how you write Spring AI code. <!-- docs/develop/java/integrations/spring-ai.mdx:24 -->

The integration is built on the Temporal Java SDK's Plugin system and is distributed as the `io.temporal:temporal-spring-ai` Maven module alongside the existing Spring Boot integration. <!-- docs/develop/java/integrations/spring-ai.mdx:26 -->

> **Public Preview.** The Spring AI Integration is in Public Preview. <!-- docs/develop/java/integrations/spring-ai.mdx:28-33 -->

> **Streaming is not supported.** Streaming responses are not currently supported. <!-- docs/develop/java/integrations/spring-ai.mdx:132-135 -->

## Prerequisites

The plugin will not auto-configure unless every entry on this table is on the classpath at or above the listed minimum. <!-- docs/develop/java/integrations/spring-ai.mdx:37 -->

| Dependency        | Minimum version |
| ----------------- | --------------- |
| Java              | 17              |
| Spring Boot       | 3.x             |
| Spring AI         | 1.1.0           |
| Temporal Java SDK | 1.35.0          |

<!-- docs/develop/java/integrations/spring-ai.mdx:39-44 -->

You also need `temporal-spring-boot-starter` and a Spring AI model starter (for example, `spring-ai-starter-model-openai`); `temporal-spring-ai` does not pull in a model provider on its own. <!-- docs/develop/java/integrations/spring-ai.mdx:46 -->

## Add the dependency

Add `temporal-spring-ai` alongside `temporal-spring-boot-starter` and a Spring AI model starter. <!-- docs/develop/java/integrations/spring-ai.mdx:50 -->

**Maven:** <!-- docs/develop/java/integrations/spring-ai.mdx:52-60 -->

```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-ai</artifactId>
    <version>${temporal-sdk.version}</version>
</dependency>
```

**Gradle:** <!-- docs/develop/java/integrations/spring-ai.mdx:62-66 -->

```groovy
implementation "io.temporal:temporal-spring-ai:${temporalSdkVersion}"
```

When `temporal-spring-ai` is on the classpath, `SpringAiPlugin` auto-registers `ChatModelActivity` with all Temporal Workers created by the Spring Boot integration. <!-- docs/develop/java/integrations/spring-ai.mdx:68 --> Optional Activities are auto-configured when their dependencies are present: <!-- docs/develop/java/integrations/spring-ai.mdx:68 -->

| Feature      | Dependency      | Registered Activity      |
| ------------ | --------------- | ------------------------ |
| Vector store | `spring-ai-rag` | `VectorStoreActivity`    |
| Embeddings   | `spring-ai-rag` | `EmbeddingModelActivity` |
| MCP          | `spring-ai-mcp` | `McpClientActivity`      |

<!-- docs/develop/java/integrations/spring-ai.mdx:70-74 -->

## Call a chat model from a Workflow

Use `ActivityChatModel` as a Spring AI `ChatModel` inside a Workflow — every call goes through a Temporal Activity, so model responses are durable and retried per your Activity options. <!-- docs/develop/java/integrations/spring-ai.mdx:78 --> Wrap it in a `TemporalChatClient` to build prompts and register tools. <!-- docs/develop/java/integrations/spring-ai.mdx:80 -->

```java
ActivityChatModel activityChatModel = ActivityChatModel.forDefault();

ChatMemory chatMemory =
    MessageWindowChatMemory.builder()
        .chatMemoryRepository(new InMemoryChatMemoryRepository())
        .maxMessages(20)
        .build();

this.chatClient =
    TemporalChatClient.builder(activityChatModel)
        .defaultSystem(systemPrompt)
        .defaultTools(weatherTool, stringTools, timestampTools)
        .defaultAdvisors(PromptChatMemoryAdvisor.builder(chatMemory).build())
        .build();
```

<!-- docs/develop/java/integrations/spring-ai.mdx:89-124 -->

- `ActivityChatModel.forDefault()` resolves to the default Spring AI `ChatModel` bean. <!-- docs/develop/java/integrations/spring-ai.mdx:130 -->
- `ActivityChatModel.forModel("openai")` targets a specific model in a multi-model application by Spring bean name. <!-- docs/develop/java/integrations/spring-ai.mdx:130 -->

Reminder: streaming responses are not currently supported. <!-- docs/develop/java/integrations/spring-ai.mdx:132-135 -->

## Tool dispatch — four categories

In Spring AI, tools are methods the model can choose to call; you register them on the chat client via `ChatClient.defaultTools(...)` or per-prompt `tools(...)`. <!-- docs/develop/java/integrations/spring-ai.mdx:139 --> The Temporal integration inspects the type of each registered tool and dispatches it to the appropriate Temporal primitive, so durable and in-Workflow tools can be mixed in the same chat client. <!-- docs/develop/java/integrations/spring-ai.mdx:141 -->

### 1. Activity stubs

- **When to use:** external calls that need retries and timeouts. <!-- docs/develop/java/integrations/spring-ai.mdx:145 -->
- **What Temporal does:** an interface annotated with both `@ActivityInterface` and Spring AI `@Tool` methods is auto-detected and executed as a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:145 -->
- **Key annotations:** `@ActivityInterface` on the interface plus `@Tool` (and typically `@ActivityMethod`) on each method, with parameters annotated `@ToolParam`. <!-- docs/develop/java/integrations/spring-ai.mdx:150-181 -->
- **Determinism note:** because the tool runs in an Activity, its result is recorded in Workflow history and replays deterministically. <!-- docs/develop/java/integrations/spring-ai.mdx:78 -->

```java
@ActivityInterface
public interface WeatherActivity {
  @Tool(description = "Get the current weather for a city. ...")
  @ActivityMethod
  String getWeather(@ToolParam(description = "The name of the city ...") String city);
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:150-167 -->

### 2. Nexus service stubs

- **When to use:** cross-Namespace tool calls. <!-- docs/develop/java/integrations/spring-ai.mdx:187 -->
- **What Temporal does:** Nexus service stubs with `@Tool` methods are auto-detected and invoked as Nexus operations. <!-- docs/develop/java/integrations/spring-ai.mdx:187 -->
- **Determinism note:** Nexus operations are durable Temporal primitives, so the result is recorded and deterministic on replay. <!-- docs/develop/java/integrations/spring-ai.mdx:187 -->

### 3. `@SideEffectTool`

- **When to use:** cheap, non-deterministic operations such as timestamps or UUIDs. <!-- docs/develop/java/integrations/spring-ai.mdx:191 -->
- **What Temporal does:** classes annotated with `@SideEffectTool` have each `@Tool` method wrapped in `Workflow.sideEffect()`; the result is recorded in history on first execution and replayed from history afterward. <!-- docs/develop/java/integrations/spring-ai.mdx:191 -->
- **Key annotation:** `@SideEffectTool` on the class (each method still uses Spring AI `@Tool`). <!-- docs/develop/java/integrations/spring-ai.mdx:196-210 -->
- **Determinism note:** the `Workflow.sideEffect()` wrapper records the value, so replay is safe even though the underlying call is non-deterministic. <!-- docs/develop/java/integrations/spring-ai.mdx:191 -->

```java
@SideEffectTool
public class TimestampTools {
  @Tool(description = "Get the current date and time")
  public String getCurrentDateTime() { /* ... */ }
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:196-213 -->

### 4. Plain tools

- **When to use:** inherently deterministic tools (such as updating in-memory agent state), or orchestration of durable primitives like calling multiple Activities, child Workflows, wait conditions, or other Temporal durable primitives. <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->
- **What Temporal does:** any class with `@Tool` methods that isn't an Activity stub, Nexus stub, or `@SideEffectTool` runs directly on the Workflow thread. <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->
- **Key annotation:** Spring AI `@Tool` only (no Temporal-specific annotation). <!-- docs/develop/java/integrations/spring-ai.mdx:265-308 -->
- **Determinism note:** because plain tools execute inside the Workflow, the author is responsible for keeping them deterministic. <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->

## Activity options and retry defaults

`ActivityChatModel.forDefault()` and `forModel(name)` build the chat Activity stub with: <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->

- 2-minute start-to-close timeout, <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->
- 3 attempts, <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->
- `org.springframework.ai.retry.NonTransientAiException` and `java.lang.IllegalArgumentException` classified as non-retryable, so a bad API key or invalid prompt fails fast. <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->

Pass an `ActivityOptions` directly when you need finer control — for example a specific Task Queue, heartbeats, priority, or a custom `RetryOptions`: <!-- docs/develop/java/integrations/spring-ai.mdx:316 -->

```java
ActivityChatModel chatModel = ActivityChatModel.forDefault(
    ActivityOptions.newBuilder(ActivityChatModel.defaultActivityOptions())
        .setTaskQueue("chat-heavy")
        .build());
```

<!-- docs/develop/java/integrations/spring-ai.mdx:318-323 -->

For configuration-driven per-model overrides, declare a `ChatModelActivityOptions` bean. The plugin consults it whenever `forDefault()` or `forModel(name)` runs in a Workflow. <!-- docs/develop/java/integrations/spring-ai.mdx:325 --> Use the special key `ChatModelTypes.DEFAULT_MODEL_NAME` (literal value `"default"`) as a global catch-all that applies to any model not explicitly listed — including models contributed by third-party starters. <!-- docs/develop/java/integrations/spring-ai.mdx:325 -->

```java
@Bean
public ChatModelActivityOptions chatModelActivityOptions() {
  return new ChatModelActivityOptions(
      Map.of(
          "anthropicChatModel",
          ActivityOptions.newBuilder(ActivityChatModel.defaultActivityOptions())
              .setStartToCloseTimeout(Duration.ofMinutes(5))
              .setScheduleToCloseTimeout(Duration.ofMinutes(15))
              .build()));
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:330-339 -->

Keys that neither match a registered `ChatModel` bean nor equal `"default"` cause plugin construction to fail, so a typo surfaces at startup rather than at first call. <!-- docs/develop/java/integrations/spring-ai.mdx:343 -->

`ActivityMcpClient.create()` and `create(ActivityOptions)` work the same way for MCP tool calls, with a 30-second default timeout. <!-- docs/develop/java/integrations/spring-ai.mdx:345 -->

## Provider-specific `ChatOptions` pass-through

Provider-specific `ChatOptions` subclasses — for example, `AnthropicChatOptions` to enable extended thinking, or `OpenAiChatOptions` to set `reasoning_effort` — pass through the Activity boundary unchanged. <!-- docs/develop/java/integrations/spring-ai.mdx:349 --> Attach them via `ChatClient.defaultOptions(...)` and the plugin re-applies them on the Activity side before calling the underlying model. <!-- docs/develop/java/integrations/spring-ai.mdx:349 -->

```java
AnthropicChatOptions thinkingOptions =
    AnthropicChatOptions.builder()
        .thinking(AnthropicApi.ThinkingType.ENABLED, 1024)
        .temperature(1.0)
        .maxTokens(4096)
        .build();

TemporalChatClient.builder(anthropicModel)
    .defaultSystem("You are a helpful assistant ...")
    .defaultOptions(thinkingOptions)
    .build();
```

<!-- docs/develop/java/integrations/spring-ai.mdx:354-368 -->

The pass-through relies on the `ChatOptions` subclass overriding `copy()` to return its own type — every provider class shipped with Spring AI does. <!-- docs/develop/java/integrations/spring-ai.mdx:372 -->

## Media in messages

Prefer URI-based media when attaching images, audio, or other binary content to chat messages. <!-- docs/develop/java/integrations/spring-ai.mdx:376 --> Raw `byte[]` media gets serialized into every chat Activity's input and result payload, which end up inside Temporal Workflow history events. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->

- Server-side history events have a fixed 2 MiB size limit. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->
- The plugin enforces a **1 MiB default cap** on inline bytes and fails fast with a non-retryable `ApplicationFailure` pointing at the URI alternative. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->
- Override the cap by setting the system property `io.temporal.springai.maxMediaBytes` before your Worker starts (positive integer; `0` disables the check). <!-- docs/develop/java/integrations/spring-ai.mdx:383 -->
- For anything larger than a small thumbnail, route the bytes to a binary store from an Activity and pass only the URL across the conversation. <!-- docs/develop/java/integrations/spring-ai.mdx:383 -->

```java
// Preferred — only the URL crosses the Activity boundary.
Media image = new Media(MimeTypeUtils.IMAGE_PNG, URI.create("https://cdn.example.com/pic.png"));
```

<!-- docs/develop/java/integrations/spring-ai.mdx:378-381 -->

## Vector stores, embeddings, and MCP

When the corresponding Spring AI modules are on the classpath, the integration registers Activities for vector stores, embeddings, and MCP tool calls. <!-- docs/develop/java/integrations/spring-ai.mdx:387 --> Inject the matching Spring AI types into your Activities or Workflows and use them as you would in any Spring AI application — each operation is executed through a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:387 -->

You can also register these plugins explicitly, without relying on auto-configuration: <!-- docs/develop/java/integrations/spring-ai.mdx:389 -->

```java
new VectorStorePlugin(vectorStore);
new EmbeddingModelPlugin(embeddingModel);
new McpPlugin();
```

<!-- docs/develop/java/integrations/spring-ai.mdx:391-395 -->

`ActivityMcpClient` wraps a Spring AI MCP client so that remote MCP tool calls become durable Activity executions. <!-- docs/develop/java/integrations/spring-ai.mdx:397 --> Build it with `ActivityMcpClient.create()` or `ActivityMcpClient.create(ActivityOptions)`; the default timeout is 30 seconds. <!-- docs/develop/java/integrations/spring-ai.mdx:345 -->

## Related

- Companion module: `temporal-spring-boot-starter` — see `references/java/spring-boot.md` for the underlying Worker/Client wiring. <!-- docs/develop/java/integrations/spring-ai.mdx:26 -->
- Plugin mechanism: see `references/core/ai-patterns.md` for the broader durable-agent context, and the Temporal docs `develop/plugins-guide` page for how integrations register with Workers and Clients. <!-- docs/develop/java/integrations/spring-ai.mdx:26,403 -->
- Source docs: `documentation/docs/develop/java/integrations/spring-ai.mdx`.
