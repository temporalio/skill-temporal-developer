# Temporal Spring AI Integration

## Overview

`temporal-spring-ai` runs Spring AI agents — chat model calls, tools, vector stores, embeddings, and MCP clients — durably through Temporal. <!-- docs/develop/java/integrations/spring-ai.mdx:22, 24 --> Model calls execute as Temporal Activities, so responses are recorded in Workflow history and retried per your Activity options. Tools are dispatched per their type so each kind lands in the right place in Workflow execution. <!-- docs/develop/java/integrations/spring-ai.mdx:24 -->

The integration is built on the Temporal Java SDK's Plugin system and ships alongside the existing Spring Boot integration. <!-- docs/develop/java/integrations/spring-ai.mdx:26 --> It is currently in **Public Preview**. <!-- docs/develop/java/integrations/spring-ai.mdx:28–33 -->

Companion reference: `references/java/integrations/spring-boot.md` (required — `temporal-spring-ai` does not auto-configure without the Spring Boot starter on the classpath).

## Prerequisites

The plugin will not auto-configure if any of these is missing or below the minimum. <!-- docs/develop/java/integrations/spring-ai.mdx:37 -->

| Dependency        | Minimum version |
| ----------------- | --------------- |
| Java              | 17              |
| Spring Boot       | 3.x             |
| Spring AI         | 1.1.0           |
| Temporal Java SDK | 1.35.0          |

<!-- docs/develop/java/integrations/spring-ai.mdx:39–44 -->

You also need `temporal-spring-boot-starter` and a Spring AI model starter (for example, `spring-ai-starter-model-openai`). `temporal-spring-ai` does not pull in a model provider on its own. <!-- docs/develop/java/integrations/spring-ai.mdx:46 -->

## Add the dependency

Maven:

```xml
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-spring-ai</artifactId>
    <version>${temporal-sdk.version}</version>
</dependency>
```

Gradle (Groovy DSL):

```groovy
implementation "io.temporal:temporal-spring-ai:${temporalSdkVersion}"
```

<!-- docs/develop/java/integrations/spring-ai.mdx:55–66 -->

## Auto-registered Activities

When `temporal-spring-ai` is on the classpath, the `SpringAiPlugin` auto-registers `ChatModelActivity` with all Temporal Workers created by the Spring Boot integration. <!-- docs/develop/java/integrations/spring-ai.mdx:68 --> Optional Activities are auto-configured when their dependencies are present: <!-- docs/develop/java/integrations/spring-ai.mdx:69 -->

| Feature      | Dependency      | Registered Activity      |
| ------------ | --------------- | ------------------------ |
| Vector store | `spring-ai-rag` | `VectorStoreActivity`    |
| Embeddings   | `spring-ai-rag` | `EmbeddingModelActivity` |
| MCP          | `spring-ai-mcp` | `McpClientActivity`      |

<!-- docs/develop/java/integrations/spring-ai.mdx:71–74 -->

If you don't want auto-configuration, register the plugin classes explicitly instead: `VectorStorePlugin(vectorStore)`, `EmbeddingModelPlugin(embeddingModel)`, `McpPlugin()`. <!-- docs/develop/java/integrations/spring-ai.mdx:389–395 -->

## Calling a chat model from a Workflow

Use `ActivityChatModel` as the Spring AI `ChatModel` inside a Workflow — every call goes through a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:76, 78 --> Wrap it in a `TemporalChatClient` to build prompts and register tools. <!-- docs/develop/java/integrations/spring-ai.mdx:81 -->

```java
@WorkflowInit
public ChatWorkflowImpl(String systemPrompt) {
  // Default model: resolves to the default Spring AI ChatModel bean.
  ActivityChatModel activityChatModel = ActivityChatModel.forDefault();

  // Tools (see "Tool dispatch" below). Each kind dispatches differently.
  WeatherActivity weatherTool =
      Workflow.newActivityStub(
          WeatherActivity.class,
          ActivityOptions.newBuilder()
              .setStartToCloseTimeout(Duration.ofSeconds(30))
              .setRetryOptions(RetryOptions.newBuilder().setMaximumAttempts(3).build())
              .build());
  StringTools stringTools = new StringTools();        // plain — runs on workflow thread
  TimestampTools timestampTools = new TimestampTools(); // @SideEffectTool

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

<!-- docs/develop/java/integrations/spring-ai.mdx:85–125 -->

`ActivityChatModel.forDefault()` resolves to the default Spring AI `ChatModel` bean. To target a specific model in a multi-model application, pass its bean name to `ActivityChatModel.forModel("openai")`. <!-- docs/develop/java/integrations/spring-ai.mdx:130 -->

> **Streaming responses are not currently supported.** <!-- docs/develop/java/integrations/spring-ai.mdx:134 -->

## Tool dispatch — the four cases

In Spring AI, tools are methods the model can choose to call. <!-- docs/develop/java/integrations/spring-ai.mdx:139 --> The Temporal integration inspects each registered tool's *type* and dispatches it to the matching Temporal primitive, so you can mix durable and in-Workflow tools in the same chat client. <!-- docs/develop/java/integrations/spring-ai.mdx:141 -->

### 1. Activity stubs — durable external calls

An interface annotated with **both** `@ActivityInterface` and Spring AI `@Tool` methods is auto-detected and executed as a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:145 --> Use this for external calls that need retries and timeouts. <!-- docs/develop/java/integrations/spring-ai.mdx:145 -->

```java
@ActivityInterface
public interface WeatherActivity {
  @Tool(description = "Get the current weather for a city...")
  @ActivityMethod
  String getWeather(@ToolParam(description = "The name of the city") String city);
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:150–168 -->

### 2. Nexus service stubs — cross-Namespace calls

Nexus service stubs with `@Tool` methods are auto-detected and invoked as Nexus operations, enabling cross-Namespace tool calls. <!-- docs/develop/java/integrations/spring-ai.mdx:187 -->

### 3. `@SideEffectTool` — cheap non-deterministic operations

Classes annotated with `@SideEffectTool` have each `@Tool` method wrapped in `Workflow.sideEffect()`. The result is recorded in history on first execution and replayed from history afterward. Use this for cheap, non-deterministic operations such as timestamps or UUIDs. <!-- docs/develop/java/integrations/spring-ai.mdx:191 -->

```java
@SideEffectTool
public class TimestampTools {
  @Tool(description = "Get the current date and time")
  public String getCurrentDateTime() {
    return FORMATTER.format(Instant.now());
  }
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:196–213 -->

Note the dispatch shape: `@SideEffectTool` is a **class-level** annotation; `@Tool` is **method-level**. <!-- docs/develop/java/integrations/spring-ai.mdx:196, 210 -->

### 4. Plain tools — inherently deterministic / orchestration

Any class with `@Tool` methods that isn't an Activity stub, Nexus stub, or `@SideEffectTool` runs directly on the Workflow thread. <!-- docs/develop/java/integrations/spring-ai.mdx:260 --> Use this for inherently deterministic tools (such as updating in-memory agent state), or for orchestration of durable primitives — calling multiple Activities, child Workflows, wait conditions, or other Temporal durable primitives. <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->

```java
public class StringTools {
  @Tool(description = "Reverse a string, returning the characters in opposite order")
  public String reverse(@ToolParam(description = "The string to reverse") String input) {
    return new StringBuilder(input).reverse().toString();
  }
}
```

<!-- docs/develop/java/integrations/spring-ai.mdx:265–273 -->

Plain tools carry **no Temporal annotation** — they're plain Spring AI tool classes.

### Choosing the right dispatch type

| When the tool…                                                | Use                        |
| ------------------------------------------------------------- | -------------------------- |
| Makes external calls, needs retries/timeouts                  | `@ActivityInterface` + `@Tool` (Activity stub) |
| Needs to invoke a service in another Namespace                | Nexus service stub with `@Tool` |
| Is cheap and non-deterministic (timestamp, UUID, randomness)  | `@SideEffectTool` class with `@Tool` methods |
| Is inherently deterministic, or orchestrates durable primitives | Plain class with `@Tool` methods |

<!-- docs/develop/java/integrations/spring-ai.mdx:143–260 -->

## Activity options and retry behavior

`ActivityChatModel.forDefault()` and `forModel(name)` build the chat Activity stub with these defaults: **2-minute start-to-close timeout**, **3 attempts**, and **`org.springframework.ai.retry.NonTransientAiException`** and **`java.lang.IllegalArgumentException`** classified as non-retryable so a bad API key or invalid prompt fails fast. <!-- docs/develop/java/integrations/spring-ai.mdx:314 -->

Pass an `ActivityOptions` directly when you need finer control — a specific Task Queue, heartbeats, priority, or a custom `RetryOptions`: <!-- docs/develop/java/integrations/spring-ai.mdx:316 -->

```java
ActivityChatModel chatModel = ActivityChatModel.forDefault(
        ActivityOptions.newBuilder(ActivityChatModel.defaultActivityOptions())
                .setTaskQueue("chat-heavy")
                .build());
```

<!-- docs/develop/java/integrations/spring-ai.mdx:318–323 -->

### Per-model overrides via `ChatModelActivityOptions`

For configuration-driven per-model overrides, declare a `ChatModelActivityOptions` bean. The plugin consults it whenever `forDefault()` or `forModel(name)` runs in a Workflow. <!-- docs/develop/java/integrations/spring-ai.mdx:325 --> Map keys are `ChatModel` bean names. The literal string `"default"` (constant `ChatModelTypes.DEFAULT_MODEL_NAME`) is a global catch-all that applies to any model not explicitly listed — including models contributed by third-party starters. <!-- docs/develop/java/integrations/spring-ai.mdx:325 -->

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

<!-- docs/develop/java/integrations/spring-ai.mdx:331–339 -->

Keys that neither match a registered `ChatModel` bean nor equal `"default"` cause **plugin construction to fail**, so a typo surfaces at startup rather than at first call. <!-- docs/develop/java/integrations/spring-ai.mdx:343 -->

### MCP activity options

`ActivityMcpClient.create()` and `create(ActivityOptions)` work the same way for MCP tool calls, with a **30-second default timeout**. <!-- docs/develop/java/integrations/spring-ai.mdx:345 -->

## Provider-specific `ChatOptions`

Provider-specific `ChatOptions` subclasses — for example, `AnthropicChatOptions` (extended thinking) or `OpenAiChatOptions` (`reasoning_effort`) — pass through the Activity boundary unchanged. Attach them via `ChatClient.defaultOptions(...)` and the plugin re-applies them on the Activity side before calling the underlying model. <!-- docs/develop/java/integrations/spring-ai.mdx:349 -->

```java
AnthropicChatOptions thinkingOptions =
    AnthropicChatOptions.builder()
        .thinking(AnthropicApi.ThinkingType.ENABLED, 1024)
        .temperature(1.0)
        .maxTokens(4096)
        .build();

TemporalChatClient.builder(anthropicModel)
    .defaultSystem("...")
    .defaultOptions(thinkingOptions)
    .build();
```

<!-- docs/develop/java/integrations/spring-ai.mdx:354–368 -->

The pass-through relies on the `ChatOptions` subclass overriding `copy()` to return its own type — every provider class shipped with Spring AI does. <!-- docs/develop/java/integrations/spring-ai.mdx:372 -->

## Media in messages

Prefer **URI-based** media when attaching images, audio, or other binary content to chat messages. Raw `byte[]` media gets serialized into every chat Activity's input and result payload, which end up inside Workflow history events. Server-side history events have a fixed **2 MiB size limit**; to leave headroom for messages, tool definitions, and options, the plugin enforces a **1 MiB default cap on inline bytes** and fails fast with a **non-retryable `ApplicationFailure`** pointing at the URI alternative. <!-- docs/develop/java/integrations/spring-ai.mdx:376 -->

```java
// Preferred — only the URL crosses the Activity boundary.
Media image = new Media(MimeTypeUtils.IMAGE_PNG, URI.create("https://cdn.example.com/pic.png"));
```

<!-- docs/develop/java/integrations/spring-ai.mdx:378–381 -->

Override the cap by setting the system property `io.temporal.springai.maxMediaBytes` before your worker starts (positive integer; `0` disables the check). For anything larger than a small thumbnail, route the bytes to a binary store from an Activity and pass only the URL across the conversation. <!-- docs/develop/java/integrations/spring-ai.mdx:383 -->

## Vector stores, embeddings, and MCP

When the corresponding Spring AI modules are on the classpath, the integration registers Activities for vector stores, embeddings, and MCP tool calls (see auto-registered Activities above). Inject the matching Spring AI types into your Activities or Workflows and use them as you would in any Spring AI application — each operation is executed through a Temporal Activity. <!-- docs/develop/java/integrations/spring-ai.mdx:387 -->

Explicit registration (skip auto-configuration): <!-- docs/develop/java/integrations/spring-ai.mdx:389 -->

```java
new VectorStorePlugin(vectorStore);
new EmbeddingModelPlugin(embeddingModel);
new McpPlugin();
```

<!-- docs/develop/java/integrations/spring-ai.mdx:391–395 -->

`ActivityMcpClient` wraps a Spring AI MCP client so that remote MCP tool calls become durable Activity executions. <!-- docs/develop/java/integrations/spring-ai.mdx:397 -->

## Common mistakes

**Mistaking class names.** The chat *model* type is `ActivityChatModel`; the *client* type is `TemporalChatClient`. They are not interchangeable, and there is no `TemporalChatModel` or `ActivityChatClient`. <!-- docs/develop/java/integrations/spring-ai.mdx:119, 120 -->

**Inventing a plain-tool annotation.** Plain tools have no Temporal annotation. The dispatcher classifies anything with `@Tool` methods that is *not* an `@ActivityInterface`, Nexus stub, or `@SideEffectTool` as a plain tool. <!-- docs/develop/java/integrations/spring-ai.mdx:260 -->

**Putting `@SideEffectTool` on a method.** `@SideEffectTool` is **class-level**. `@Tool` is the method-level annotation. <!-- docs/develop/java/integrations/spring-ai.mdx:196 -->

**Mis-typing the media system property.** It is `io.temporal.springai.maxMediaBytes` — a JVM system property, not an `application.properties` key. <!-- docs/develop/java/integrations/spring-ai.mdx:383 -->

**Inventing per-model property keys.** `ChatModelActivityOptions` is a Spring `@Bean` containing a `Map` keyed by `ChatModel` bean names; the special key for "everything else" is the literal string `"default"` (constant `ChatModelTypes.DEFAULT_MODEL_NAME`). It is not configured via `application.properties`. <!-- docs/develop/java/integrations/spring-ai.mdx:325, 343 -->

**Assuming streaming works.** Streaming responses are not currently supported. <!-- docs/develop/java/integrations/spring-ai.mdx:134 -->

**Confusing default timeouts.** Chat Activities default to a **2-minute** start-to-close timeout with **3 attempts**; `ActivityMcpClient` defaults to **30 seconds**. Don't apply one to the other. <!-- docs/develop/java/integrations/spring-ai.mdx:314, 345 -->

**Skipping `temporal-spring-boot-starter`.** The auto-configuration registers Activities with workers created by the Spring Boot integration; without it, no auto-registration happens. <!-- docs/develop/java/integrations/spring-ai.mdx:46, 68 -->

## Related references

- `references/java/integrations/spring-boot.md` — companion Spring Boot integration (required).
- `references/java/java.md` — base Java SDK reference (workflow/activity definition, worker setup, determinism).

## Resources

- `temporal-spring-ai` README in `temporalio/sdk-java` — full module reference. <!-- docs/develop/java/integrations/spring-ai.mdx:401 -->
- Temporal plugins guide — how integrations are registered with Workers and Clients. <!-- docs/develop/java/integrations/spring-ai.mdx:403 -->
