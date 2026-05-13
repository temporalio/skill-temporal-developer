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
| Jackson 3 (`tools.jackson.core:jackson-databind:3.x`) | Java | Opt-in `JacksonJsonPayloadConverter.setDefaultAsJackson3(...)` swap of the default JSON payload converter to Jackson 3; wire-compatible (`json/plain`) with Jackson 2 | `references/java/integrations/jackson-3.md` | `references/java/data-handling.md`, `references/java/integrations/spring-boot.md` |
