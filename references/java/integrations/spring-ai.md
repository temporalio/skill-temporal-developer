# Temporal Spring AI Integration

<!-- Source for this entire file: docs/develop/java/integrations/spring-ai.mdx
     Every named class, annotation, default value, and property below is transcribed
     verbatim from that file. Inline comments call out the source line. -->

## Overview

`io.temporal:temporal-spring-ai` makes [Spring AI](https://docs.spring.io/spring-ai/reference/) agents durable on Temporal. Model calls run as Activities recorded in Workflow history, and tools are dispatched per their type so each kind lands in the right place in Workflow execution — Activity stubs and Nexus stubs as durable operations, `@SideEffectTool` classes wrapped in `Workflow.sideEffect`, and plain tools running directly in Workflow code.

The module is built on the Java SDK's [Plugin system](/develop/plugins-guide) and is distributed alongside the existing Spring Boot integration.

> **Public Preview.** The Spring AI integration is in Public Preview. See the Temporal product release stages guide for what that means for support and stability.

For Spring Boot wiring (`@WorkflowImpl`, `@ActivityImpl`, auto-discovery, `WorkflowClient` bean), see `references/java/integrations/spring-boot.md` — it is a required companion.

## Prerequisites

All of the following must be on the application's classpath. The plugin **won't auto-configure** if any is missing or below the listed minimum:

| Dependency        | Minimum version |
| ----------------- | --------------- |
| Java              | 17              |
| Spring Boot       | 3.x             |
| Spring AI         | 1.1.0           |
| Temporal Java SDK | 1.35.0          |

You also need [`temporal-spring-boot-starter`](https://central.sonatype.com/artifact/io.temporal/temporal-spring-boot-starter) and a Spring AI model starter (for example, `spring-ai-starter-model-openai`) — `temporal-spring-ai` does not pull in a model provider on its own.

## Dependency setup

**Maven:**

```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-ai</artifactId>
    <version>${temporal-sdk.version}</version>
</dependency>
```

**Gradle (Groovy DSL):**

```groovy
implementation "io.temporal:temporal-spring-ai:${temporalSdkVersion}"
```

When `temporal-spring-ai` is on the classpath, `SpringAiPlugin` auto-registers `ChatModelActivity` with all Workers created by the Spring Boot integration.

Three more Activities auto-register when their gating Spring AI artifacts are also present:

| Feature      | Required artifact | Auto-registered Activity |
| ------------ | ----------------- | ------------------------ |
| Vector store | `spring-ai-rag`   | `VectorStoreActivity`    |
| Embeddings   | `spring-ai-rag`   | `EmbeddingModelActivity` |
| MCP          | `spring-ai-mcp`   | `McpClientActivity`      |

You can also register the corresponding plugins explicitly, without relying on auto-configuration:

```java
new VectorStorePlugin(vectorStore);
new EmbeddingModelPlugin(embeddingModel);
new McpPlugin();
```

## Calling a chat model from a Workflow

`ActivityChatModel` is a Spring AI `ChatModel` you can use inside a Workflow. Every call goes through a Temporal Activity, so model responses are durable and retried per your Activity options.

Wrap it in `TemporalChatClient` to build prompts and register tools:

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

  StringTools stringTools = new StringTools();        // plain tool — runs in Workflow
  TimestampTools timestampTools = new TimestampTools(); // @SideEffectTool — wrapped in sideEffect()

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

`ActivityChatModel.forDefault()` resolves to the default `ChatModel` bean. To target a specific model in a multi-model application, pass its bean name: `ActivityChatModel.forModel("openai")`.

> **Streaming responses are not currently supported.**

## Tool dispatch — four categories

In Spring AI, [tools](https://docs.spring.io/spring-ai/reference/api/tools.html) are methods the model may choose to call. You register them with the chat client via `defaultTools(...)` or per-prompt `tools(...)`, and the framework runs the chosen method and feeds the result back into the conversation.

The Temporal integration inspects the **type** of each registered tool and dispatches it to the matching Temporal primitive. Four categories:

| Tool object                                                    | Where it runs                        | Use for                                                                                                       |
| -------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| Interface with `@ActivityInterface` + `@Tool` methods          | As a Temporal Activity               | External calls that need retries and timeouts                                                                 |
| Nexus service stub with `@Tool` methods                        | As a [Nexus operation](/develop/java/nexus) | Cross-Namespace tool calls                                                                              |
| Class annotated `@SideEffectTool`                              | Wrapped in `Workflow.sideEffect()`   | Cheap, non-deterministic operations (timestamps, UUIDs) — result is recorded in history on first execution    |
| Plain class with `@Tool` methods (none of the above)           | Directly on the Workflow thread      | Inherently deterministic tools (e.g., in-memory state updates) or orchestration over other Temporal primitives |

### Activity-stub tool

```java
@ActivityInterface
public interface WeatherActivity {

  @Tool(
      description =
          "Get the current weather for a city. Returns temperature, conditions, and humidity.")
  @ActivityMethod
  String getWeather(
      @ToolParam(description = "The name of the city (e.g., 'Seattle', 'New York')") String city);

  @Tool(description = "Get the weather forecast for a city for the specified number of days.")
  @ActivityMethod
  String getForecast(
      @ToolParam(description = "The name of the city") String city,
      @ToolParam(description = "Number of days to forecast (1-7)") int days);
}
```

### Nexus-stub tool

Nexus service stubs with `@Tool` methods are auto-detected and invoked as Nexus operations, enabling cross-Namespace tool calls.

### `@SideEffectTool`

Each `@Tool` method on a `@SideEffectTool` class is wrapped in `Workflow.sideEffect()`. The result is recorded in history on first execution and replayed from history afterward.

```java
@SideEffectTool
public class TimestampTools {

  @Tool(description = "Get the current date and time")
  public String getCurrentDateTime() {
    return FORMATTER.format(Instant.now());
  }

  @Tool(description = "Get the current Unix timestamp in milliseconds")
  public long getCurrentTimestamp() {
    return System.currentTimeMillis();
  }

  @Tool(description = "Generate a random UUID")
  public String generateUuid() {
    return UUID.randomUUID().toString();
  }
}
```

### Plain Workflow-thread tool

```java
public class StringTools {

  @Tool(description = "Reverse a string, returning the characters in opposite order")
  public String reverse(@ToolParam(description = "The string to reverse") String input) {
    return new StringBuilder(input).reverse().toString();
  }

  @Tool(description = "Convert text to all uppercase letters")
  public String toUpperCase(@ToolParam(description = "The text to convert") String text) {
    return text.toUpperCase(java.util.Locale.ROOT);
  }
}
```

## Activity options and retry behavior

`ActivityChatModel.forDefault()` and `forModel(name)` build the chat Activity stub with these defaults:

- **Start-to-close timeout:** 2 minutes
- **Maximum attempts:** 3
- **Non-retryable:** `org.springframework.ai.retry.NonTransientAiException` and `java.lang.IllegalArgumentException` — so a bad API key or invalid prompt fails fast

Pass `ActivityOptions` directly when you need a specific Task Queue, [heartbeats](/develop/java/activities/execution#heartbeattimeout), [priority](/develop/task-queue-priority-fairness), or a custom `RetryOptions`:

```java
ActivityChatModel chatModel = ActivityChatModel.forDefault(
        ActivityOptions.newBuilder(ActivityChatModel.defaultActivityOptions())
                .setTaskQueue("chat-heavy")
                .build());
```

### Per-model overrides via `ChatModelActivityOptions`

Declare a `ChatModelActivityOptions` bean and the plugin consults it whenever `forDefault()` or `forModel(name)` runs in a Workflow. The map is keyed by `ChatModel` bean name, plus a special key — `ChatModelTypes.DEFAULT_MODEL_NAME` (the literal `"default"`) — that acts as a global catch-all for any model not explicitly listed (including ones contributed by third-party starters):

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

Keys that neither match a registered `ChatModel` bean nor equal `"default"` cause **plugin construction to fail**, so a typo surfaces at startup rather than at first call.

### MCP equivalent

`ActivityMcpClient.create()` and `create(ActivityOptions)` work the same way for MCP tool calls, with a **30-second default timeout**.

## Provider-specific `ChatOptions`

Provider-specific `ChatOptions` subclasses — for example, `AnthropicChatOptions` to enable extended thinking, or `OpenAiChatOptions` to set `reasoning_effort` — pass through the Activity boundary unchanged. Attach them via `ChatClient.defaultOptions(...)` and the plugin re-applies them on the Activity side before calling the underlying model:

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
            "You are a helpful assistant powered by Anthropic with extended thinking. "
                + "Use the thinking budget to reason carefully, then give a crisp answer "
                + "that reflects the reasoning you did.")
        .defaultOptions(thinkingOptions)
        .build());
```

The pass-through relies on the `ChatOptions` subclass overriding `copy()` to return its own type — every provider class shipped with Spring AI does.

## Media in messages — prefer URI

Prefer URI-based media when attaching images, audio, or other binary content to chat messages. Raw `byte[]` media gets serialized into every chat Activity's input and result payload, which end up inside Workflow history events. Server-side history events have a fixed 2 MiB size limit; to leave headroom for messages, tool definitions, and options, the plugin enforces a **1 MiB default cap** on inline bytes and fails fast with a non-retryable `ApplicationFailure` pointing at the URI alternative.

```java
// Preferred — only the URL crosses the Activity boundary.
Media image = new Media(MimeTypeUtils.IMAGE_PNG, URI.create("https://cdn.example.com/pic.png"));
```

Override the cap by setting the system property `io.temporal.springai.maxMediaBytes` before your Worker starts (positive integer; `0` disables the check). For anything larger than a small thumbnail, route the bytes to a binary store from an Activity and pass only the URL across the conversation.

## Vector stores, embeddings, and MCP

When the matching Spring AI module is on the classpath, the integration registers Activities for vector stores, embeddings, and MCP tool calls (see the table in [Dependency setup](#dependency-setup)). Inject the corresponding Spring AI types into your Activities or Workflows and use them as you would in any Spring AI application — each operation is executed through a Temporal Activity.

`ActivityMcpClient` wraps a Spring AI MCP client so that remote MCP tool calls become durable Activity executions.

## Common mistakes

- **Forgetting the model starter.** `temporal-spring-ai` does not pull in a model provider — you still need a Spring AI model starter (e.g., `spring-ai-starter-model-openai`) on the classpath.
- **Wrong category for the tool.** The dispatch table above is exhaustive. A `@SideEffectTool` does **not** run as an Activity, and a plain `@Tool` class does **not** get wrapped in `sideEffect()`. Choose the category that matches the tool's actual behavior.
- **Expecting streaming.** Streaming responses are not currently supported.
- **Mis-typed `ChatModelActivityOptions` keys.** Keys must equal a registered `ChatModel` bean name or the sentinel `"default"`. Anything else fails at plugin construction (startup).
- **Wrong gating artifact for optional Activities.** `VectorStoreActivity` and `EmbeddingModelActivity` are gated on `spring-ai-rag` — not `spring-ai-vectorstore` or `spring-ai-embedding`. `McpClientActivity` is gated on `spring-ai-mcp`.
- **Large inline media.** Inline `byte[]` over the 1 MiB default cap triggers a non-retryable `ApplicationFailure`. Use URI-based `Media` or route the bytes to a binary store and pass the URL.
- **Confusing the system property with a Spring property.** The cap is overridden via the JVM system property `io.temporal.springai.maxMediaBytes` — there is no corresponding `spring.temporal.*` key for it.
- **Below-floor versions.** If Java < 17, Spring Boot < 3.x, Spring AI < 1.1.0, or Temporal SDK < 1.35.0, the plugin won't auto-configure — silently. Verify versions before debugging missing-Activity errors.

## Related

- `references/java/integrations/spring-boot.md` — required companion module; `@WorkflowImpl`, `@ActivityImpl`, auto-discovery, `WorkflowClient` injection.
- `references/core/ai-patterns.md` — language-agnostic AI/LLM patterns on Temporal.
- [`temporal-spring-ai` README](https://github.com/temporalio/sdk-java/blob/master/temporal-spring-ai/README.md) — full reference for the module.
- [Plugin system](/develop/plugins-guide) — how integrations are registered with Workers and Clients.
