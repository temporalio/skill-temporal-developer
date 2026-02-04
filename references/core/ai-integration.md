# AI/LLM Integration with Temporal

## Overview

Temporal provides durable execution for AI/LLM applications, handling retries, rate limits, and long-running operations automatically. These patterns apply across languages, with Python being the most mature for AI integration.

For Python-specific implementation details and code examples, see `references/python/ai-patterns.md`.

## Why Temporal for AI?

| Challenge | Temporal Solution |
|-----------|-------------------|
| LLM API timeouts | Automatic retries with backoff |
| Rate limiting | Activity retry policies handle 429s |
| Long-running agents | Durable state survives crashes |
| Multi-step pipelines | Workflow orchestration |
| Cost tracking | Activity-level visibility |
| Debugging | Full execution history |

## Core Patterns

### Pattern 1: Generic LLM Activity

Create flexible, reusable activities for LLM calls:

```
Activity: call_llm_generic(
    model: string,
    system_instructions: string,
    user_input: string,
    tools?: list,
    response_format?: schema
) -> response
```

**Benefits**:
- Single activity handles multiple use cases
- Consistent retry handling
- Centralized configuration

### Pattern 2: Activity-Based Separation

Isolate each operation in its own activity:

```
Workflow:
  ├── Activity: call_llm (get tool selection)
  ├── Activity: execute_tool (run selected tool)
  └── Activity: call_llm (interpret results)
```

**Benefits**:
- Independent retry for each step
- Clear audit trail in history
- Easier testing and mocking
- Failure isolation

### Pattern 3: Centralized Retry Management

**Critical**: Disable retries in LLM client libraries, let Temporal handle retries.

```
LLM Client Config:
  max_retries = 0  ← Disable client retries

Activity Retry Policy:
  initial_interval = 1s
  backoff_coefficient = 2.0
  maximum_attempts = 5
  maximum_interval = 60s
```

**Why**:
- Temporal retries are durable (survive crashes)
- Single retry configuration point
- Better visibility into retry attempts
- Consistent backoff behavior

### Pattern 4: Tool-Calling Agent

Three-phase workflow for LLM agents with tools:

```
┌─────────────────────────────────────────────┐
│ Phase 1: Tool Selection                      │
│   Activity: Present tools to LLM             │
│   LLM returns: tool_name, arguments          │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│ Phase 2: Tool Execution                      │
│   Activity: Execute selected tool            │
│   (Separate activity per tool type)          │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│ Phase 3: Result Interpretation               │
│   Activity: Send results back to LLM         │
│   LLM returns: final response or next tool   │
└─────────────────────────────────────────────┘
                    │
                    ▼
        Loop until LLM returns final answer
```

### Pattern 5: Multi-Agent Orchestration

Complex pipelines with multiple specialized agents:

```
Deep Research Example:
  │
  ├── Planning Agent (Activity)
  │   └── Output: subtopics to research
  │
  ├── Query Generation Agent (Activity)
  │   └── Output: search queries per subtopic
  │
  ├── Parallel Web Search (Multiple Activities)
  │   └── Output: search results (resilient to partial failures)
  │
  └── Synthesis Agent (Activity)
      └── Output: final report
```

**Key Pattern**: Use parallel execution with `return_exceptions=True` to continue with partial results when some searches fail.

### Pattern 6: Structured Outputs

Define schemas for LLM responses:

```
Input: Raw LLM prompt
Schema: { action: string, confidence: float, reasoning: string }
Output: Validated, typed response
```

**Benefits**:
- Type safety
- Automatic validation
- Easier downstream processing

## Timeout Recommendations

| Operation Type | Recommended Timeout |
|----------------|---------------------|
| Simple LLM calls (GPT-4, Claude-3) | 30 seconds |
| Reasoning models (o1, o3, extended thinking) | 300 seconds (5 min) |
| Web searches | 300 seconds (5 min) |
| Simple tool execution | 30-60 seconds |
| Image generation | 120 seconds |
| Document processing | 60-120 seconds |

**Rationale**:
- Reasoning models need time for complex computation
- Web searches may hit rate limits requiring backoff
- Fast timeouts catch stuck operations
- Longer timeouts prevent premature failures for expensive operations

## Rate Limit Handling

### From HTTP Headers

Parse rate limit info from API responses:

```
Response Headers:
  Retry-After: 30
  X-RateLimit-Remaining: 0

Activity:
  If rate limited:
    Raise retryable error with retry_after hint
    Temporal handles the delay
```

### Retry Policy Configuration

```
Retry Policy:
  initial_interval: 1s (or from Retry-After header)
  backoff_coefficient: 2.0
  maximum_interval: 60s
  maximum_attempts: 10
  non_retryable_errors: [InvalidAPIKey, InvalidInput]
```

## Error Handling

### Retryable Errors
- Rate limits (429)
- Timeouts
- Temporary server errors (500, 502, 503)
- Network errors

### Non-Retryable Errors
- Invalid API key (401)
- Invalid input/prompt
- Content policy violations
- Model not found

## Best Practices

1. **Disable client retries** - Let Temporal handle all retries
2. **Set appropriate timeouts** - Based on operation type
3. **Separate activities** - One per logical operation
4. **Use structured outputs** - For type safety and validation
5. **Handle partial failures** - Continue with available results
6. **Monitor costs** - Track LLM calls at activity level
7. **Version prompts** - Track prompt changes in code
8. **Test with mocks** - Mock LLM responses in tests

## Observability

- **Activity duration**: Track LLM latency
- **Retry counts**: Monitor rate limiting
- **Token usage**: Log in activity output
- **Cost attribution**: Tag workflows with cost centers

## Language-Specific Resources

### Python
See `references/python/ai-patterns.md` for:
- Pydantic data converter setup
- OpenAI client configuration
- LiteLLM multi-model support
- OpenAI Agents SDK integration
- Complete code examples
- Testing patterns

### TypeScript
AI integration patterns in TypeScript follow the same concepts:
- Use `proxyActivities` for LLM activities
- Configure timeouts per activity type
- Handle errors with `ApplicationFailure`
