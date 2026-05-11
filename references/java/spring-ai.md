# Temporal Spring AI Integration (Java)

## Overview

`temporal-spring-ai` makes [Spring AI](https://docs.spring.io/spring-ai/reference/) agents durable: model calls run through Temporal Activities recorded in Workflow history, and tools are dispatched per their type so each kind lands in the right place in Workflow execution. <!-- docs/develop/java/integrations/spring-ai.mdx:24 -->

The integration is built on the Java SDK's [Plugin system](/develop/plugins-guide) and is distributed as the `io.temporal:temporal-spring-ai` module alongside the existing [`temporal-spring-boot-starter`](/develop/java/integrations/spring-boot-integration). <!-- docs/develop/java/integrations/spring-ai.mdx:26 -->

The integration is in **Public Preview**. <!-- docs/develop/java/integrations/spring-ai.mdx:30 -->

For Spring Boot wiring fundamentals (`@WorkflowImpl`, `@ActivityImpl`, `WorkflowClient` injection, auto-discovery, worker lifecycle), see `references/java/spring-boot.md`. This reference assumes that file's setup is already in place.

## Prerequisites

All four of these must be on the classpath at the listed minimum versions, or the plugin will not auto-configure: <!-- docs/develop/java/integrations/spring-ai.mdx:37–38 -->

| Dependency        | Minimum version |
| ----------------- | --------------- |
| Java              | 17              |
| Spring Boot       | 3.x             |
| Spring AI         | 1.1.0           |
| Temporal Java SDK | 1.35.0          |

<!-- Sources: docs/develop/java/integrations/spring-ai.mdx:39–44 -->

You also need `temporal-spring-boot-starter` and a Spring AI model starter (for example, `spring-ai-starter-model-openai`). The `temporal-spring-ai` module does not pull in a model provider on its own. <!-- docs/develop/java/integrations/spring-ai.mdx:46 -->

## Add the dependency

Maven: <!-- docs/develop/java/integrations/spring-ai.mdx:52–60 -->

```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-ai</artifactId>
    <version>${temporal-sdk.version}</version>
</dependency>
```

Gradle: <!-- docs/develop/java/integrations/spring-ai.mdx:62–66 -->

```groovy
implementation "io.temporal:temporal-spring-ai:${temporalSdkVersion}"
```

When `temporal-spring-ai` is on the classpath, `SpringAiPlugin` auto-registers `ChatModelActivity` with every Temporal Worker created by the Spring Boot integration. <!-- docs/develop/java/integrations/spring-ai.mdx:68 -->

Optional Activities auto-register when their gating dependency is present: <!-- docs/develop/java/integrations/spring-ai.mdx:68 -->

| Feature      | Dependency      | Registered Activity      |
| ------------ | --------------- | ------------------------ |
| Vector store | `spring-ai-rag` | `VectorStoreActivity`    |
| Embeddings   | `spring-ai-rag` | `EmbeddingModelActivity` |
| MCP          | `spring-ai-mcp` | `McpClientActivity`      |

<!-- Sources: docs/develop/java/integrations/spring-ai.mdx:70–74 -->

## Call a chat model from a Workflow

Use `ActivityChatModel` as a Spring AI `ChatModel` inside a Workflow. Every call goes through a Temporal Activity, so model responses are durable and retried per your Activity options. Wrap `ActivityChatModel` in a `TemporalChatClient` to build prompts and register tools. <!-- docs/develop/java/integrations/spring-ai.mdx:78–80 -->

```java
@WorkflowInit
public ChatWorkflowImpl(String systemPrompt) {
    ActivityChatModel activityChatModel = ActivityChatModel.forDefault();

    WeatherActivity weatherTool =
        Workflow.newActivityStub(
            WeatherActivity.class,
            ActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofSeconds(30))
                .setRetryOptions(RetryOptions.newBuilder().setMaximumAttempts(3).build())
                .build());

    StringTools stringTools = new StringTools();
    TimestampTools timestampTools = new TimestampTools();

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
}
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:85–125 (samples-java/springai/basic ChatWorkflowImpl.java) -->

Resolving the model bean: <!-- docs/develop/java/integrations/spring-ai.mdx:130 -->

- `ActivityChatModel.forDefault()` — resolves to the default Spring AI `ChatModel` bean.
- `ActivityChatModel.forModel("openai")` — targets a specific bean by name in a multi-model app.

**Streaming responses are not currently supported.** <!-- docs/develop/java/integrations/spring-ai.mdx:134 -->

## Register tools

Spring AI [tools](https://docs.spring.io/spring-ai/reference/api/tools.html) are methods the model can choose to call; you make them available via `ChatClient.defaultTools(...)` or per-prompt `tools(...)`. The Temporal integration inspects the type of each tool you register and dispatches it to the appropriate Temporal primitive, so you can mix durable and in-Workflow tools in the same chat client. <!-- docs/develop/java/integrations/spring-ai.mdx:139–141 -->

There are **four** dispatch paths. Choose by tool class shape:

| Tool class shape                                    | Dispatched as                  | When to use |
| --------------------------------------------------- | ------------------------------ | ----------- |
| `@ActivityInterface` + `@Tool` methods              | Temporal Activity              | External calls that need retries and timeouts. <!-- docs/develop/java/integrations/spring-ai.mdx:145 --> |
| Nexus service stub + `@Tool` methods                | Nexus operation                | Cross-Namespace tool calls. <!-- docs/develop/java/integrations/spring-ai.mdx:187 --> |
| `@SideEffectTool` class with `@Tool` methods        | `Workflow.sideEffect()` wrap   | Cheap, non-deterministic operations such as timestamps or UUIDs. <!-- docs/develop/java/integrations/spring-ai.mdx:191 --> |
| Plain class with `@Tool` methods (none of the above) | Runs on the Workflow thread    | Inherently deterministic helpers, or orchestration of durable primitives (Activities, child Workflows, wait conditions). <!-- docs/develop/java/integrations/spring-ai.mdx:260 --> |

### Activity-stub tools

An interface annotated with both `@ActivityInterface` and Spring AI `@Tool` methods is auto-detected and executed as a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:145 -->

```java
@ActivityInterface
public interface WeatherActivity {

    @Tool(
        description =
            "Get the current weather for a city. Returns temperature, conditions, and humidity.")
    @ActivityMethod
    String getWeather(
        @ToolParam(description = "The name of the city (e.g., 'Seattle', 'New York')")
            String city);
}
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:150–181 (samples-java/springai/basic WeatherActivity.java) -->

Pass the Activity stub (produced by `Workflow.newActivityStub`) into `defaultTools(...)`; the integration runs invocations as durable Activity executions.

### Nexus-stub tools

Nexus service stubs with `@Tool` methods are auto-detected and invoked as [Nexus operations](/develop/java/nexus), enabling cross-Namespace tool calls. <!-- docs/develop/java/integrations/spring-ai.mdx:187 -->

### `@SideEffectTool`

Classes annotated with `@SideEffectTool` have each `@Tool` method wrapped in `Workflow.sideEffect()`. The result is recorded in history on first execution and replayed from history afterward. <!-- docs/develop/java/integrations/spring-ai.mdx:191 -->

```java
@SideEffectTool
public class TimestampTools {

    @Tool(description = "Get the current date and time")
    public String getCurrentDateTime() {
        return FORMATTER.format(Instant.now());
    }

    @Tool(description = "Generate a random UUID")
    public String generateUuid() {
        return UUID.randomUUID().toString();
    }
}
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:196–254 (samples-java/springai/basic TimestampTools.java) -->

### Plain tools

Any class with `@Tool` methods that isn't an Activity stub, Nexus stub, or `@SideEffectTool` runs directly on the Workflow thread. Use this for deterministic helpers, or to orchestrate durable primitives (Activities, child Workflows, wait conditions). <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->

```java
public class StringTools {

    @Tool(description = "Reverse a string, returning the characters in opposite order")
    public String reverse(@ToolParam(description = "The string to reverse") String input) {
        return new StringBuilder(input).reverse().toString();
    }

    @Tool(description = "Count the number of words in a text")
    public int countWords(@ToolParam(description = "The text to count words in") String text) {
        return text.trim().split("\\s+").length;
    }
}
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:265–308 (samples-java/springai/basic StringTools.java) -->

## Activity options and retry behavior

`ActivityChatModel.forDefault()` and `forModel(name)` build the chat Activity stub with the following defaults: <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->

- **Start-to-close timeout:** 2 minutes
- **Attempts:** 3
- **Non-retryable exception types:** `org.springframework.ai.retry.NonTransientAiException`, `java.lang.IllegalArgumentException`

A bad API key or invalid prompt therefore fails fast rather than retrying.

To override for one chat model instance, pass an `ActivityOptions` directly. Start from `ActivityChatModel.defaultActivityOptions()` to inherit the non-retryable classifications: <!-- docs/develop/java/integrations/spring-ai.mdx:316–323 -->

```java
ActivityChatModel chatModel = ActivityChatModel.forDefault(
        ActivityOptions.newBuilder(ActivityChatModel.defaultActivityOptions())
                .setTaskQueue("chat-heavy")
                .build());
```

For configuration-driven per-model overrides, declare a `ChatModelActivityOptions` bean. The plugin consults it whenever `forDefault()` or `forModel(name)` runs in a Workflow. <!-- docs/develop/java/integrations/spring-ai.mdx:325 -->

Use the special key `ChatModelTypes.DEFAULT_MODEL_NAME` (the literal string `"default"`) as a global catch-all that applies to any model not explicitly listed — including models contributed by third-party starters: <!-- docs/develop/java/integrations/spring-ai.mdx:325 -->

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

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:330–339 (samples-java/springai/multimodel ChatModelConfig.java) -->

Keys that neither match a registered `ChatModel` bean nor equal `"default"` cause plugin construction to fail, so a typo surfaces at startup rather than at first call. <!-- docs/develop/java/integrations/spring-ai.mdx:343 -->

`ActivityMcpClient.create()` and `ActivityMcpClient.create(ActivityOptions)` work the same way for MCP tool calls, with a **30-second default timeout**. <!-- docs/develop/java/integrations/spring-ai.mdx:345 -->

For Temporal-side concepts referenced above (heartbeats, priority, retry options, custom Activity options), see the canonical Java SDK docs at `/develop/java/activities/execution` and `references/java/error-handling.md`.

## Provider-specific chat options

Provider-specific `ChatOptions` subclasses — for example, `AnthropicChatOptions` (extended thinking) or `OpenAiChatOptions` (`reasoning_effort`) — pass through the Activity boundary unchanged. Attach them with `ChatClient.defaultOptions(...)` and the plugin re-applies them on the Activity side before calling the underlying model: <!-- docs/develop/java/integrations/spring-ai.mdx:349 -->

```java
AnthropicChatOptions thinkingOptions =
    AnthropicChatOptions.builder()
        .thinking(AnthropicApi.ThinkingType.ENABLED, 1024)
        .temperature(1.0)
        .maxTokens(4096)
        .build();

chatClients.put(
    "think",
    TemporalChatClient.builder(anthropicModel)
        .defaultSystem(
            "You are a helpful assistant powered by Anthropic with extended thinking. ...")
        .defaultOptions(thinkingOptions)
        .build());
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:354–368 (samples-java/springai/multimodel MultiModelWorkflowImpl.java) -->

The pass-through relies on the `ChatOptions` subclass overriding `copy()` to return its own type — every provider class shipped with Spring AI does. <!-- docs/develop/java/integrations/spring-ai.mdx:372 -->

## Media in messages

Prefer URI-based media when attaching images, audio, or other binary content to chat messages. Raw `byte[]` media gets serialized into every chat Activity's input and result payload, which end up inside Temporal Workflow history events. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->

Server-side history events have a fixed **2 MiB** size limit. To leave headroom for messages, tool definitions, and options, the plugin enforces a **1 MiB default cap** on inline bytes and fails fast with a non-retryable `ApplicationFailure` pointing at the URI alternative. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->

```java
// Preferred — only the URL crosses the Activity boundary.
Media image = new Media(MimeTypeUtils.IMAGE_PNG, URI.create("https://cdn.example.com/pic.png"));
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:378–381 -->

Override the cap with the system property `io.temporal.springai.maxMediaBytes`, set before the worker starts. Positive integers raise the cap; `0` disables the check. For anything larger than a small thumbnail, route the bytes to a binary store from an Activity and pass only the URL across the conversation. <!-- docs/develop/java/integrations/spring-ai.mdx:383 -->

## Vector stores, embeddings, and MCP

When the matching Spring AI module is on the classpath, the integration registers an Activity for each surface — `VectorStoreActivity`, `EmbeddingModelActivity`, `McpClientActivity` — and you use the corresponding Spring AI types as you would in any Spring AI application. Each operation executes through a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:387 -->

To skip auto-configuration and register the plugins explicitly: <!-- docs/develop/java/integrations/spring-ai.mdx:389 -->

```java
new VectorStorePlugin(vectorStore);
new EmbeddingModelPlugin(embeddingModel);
new McpPlugin();
```

<!-- Source: docs/develop/java/integrations/spring-ai.mdx:391–395 -->

`ActivityMcpClient` wraps a Spring AI MCP client so that remote MCP tool calls become durable Activity executions. <!-- docs/develop/java/integrations/spring-ai.mdx:397 -->

## Resources

- [`temporal-spring-ai` README](https://github.com/temporalio/sdk-java/blob/master/temporal-spring-ai/README.md) — full reference for the module. <!-- docs/develop/java/integrations/spring-ai.mdx:401 -->
- `references/java/spring-boot.md` — required companion integration; covers `@WorkflowImpl`, `@ActivityImpl`, auto-discovery, and `WorkflowClient` injection.
- [Plugin system](/develop/plugins-guide) — how Temporal integrations register with Workers and Clients. <!-- docs/develop/java/integrations/spring-ai.mdx:403 -->
