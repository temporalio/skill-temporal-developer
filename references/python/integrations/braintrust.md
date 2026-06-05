# Temporal Braintrust Integration (Python)

## Overview

[Braintrust](https://braintrust.dev) is an LLM observability and prompt-management platform. The Temporal Python SDK integrates with it through `braintrust.contrib.temporal.BraintrustPlugin`, which traces every Workflow and Activity as a span in Braintrust, links client-initiated spans to the Workflows they start, and pairs with Braintrust's existing helpers (`wrap_openai`, `start_span`, `load_prompt`) to capture LLM calls, custom context, and managed prompts. <!-- docs/develop/python/integrations/braintrust.mdx:21-29 -->

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.

<!-- Public Preview source: docs/develop/python/integrations/braintrust.mdx:31-37 -->

For Python AI patterns (Pydantic data converter, disabling client-side LLM retries, generic LLM Activity shape) read `references/python/ai-patterns.md`. For conceptual LLM patterns shared across SDKs read `references/core/ai-patterns.md`.

## Prerequisites

- An existing Temporal Python development environment as described in `references/python/python.md`. <!-- docs/develop/python/integrations/braintrust.mdx:49-51 -->
- A Braintrust account; familiarity with Braintrust concepts (projects, spans, prompts). <!-- docs/develop/python/integrations/braintrust.mdx:45-46 -->

## Install

```bash
uv pip install "braintrust[temporal]"
```
<!-- docs/develop/python/integrations/braintrust.mdx:62-64 -->

## Initialize the logger before the Client or Worker

The Braintrust logger must be initialized **before** the Temporal Client and Worker are constructed so that spans connect correctly. <!-- docs/develop/python/integrations/braintrust.mdx:66-68 -->

```python
import os
from braintrust import init_logger

init_logger(project=os.environ.get("BRAINTRUST_PROJECT", "my-project"))
```
<!-- docs/develop/python/integrations/braintrust.mdx:69-75 -->

`init_logger` takes a `project` argument that names the Braintrust project traces are written to. <!-- docs/develop/python/integrations/braintrust.mdx:74 -->

## Register `BraintrustPlugin` on the Client and the Worker

Register `BraintrustPlugin` on **both** the Client and every Worker. The Worker registration produces Workflow/Activity spans; the Client registration propagates span context so client-side spans link to the Workflow they start. <!-- docs/develop/python/integrations/braintrust.mdx:77-103 -->

Client:

```python
from temporalio.client import Client
from braintrust.contrib.temporal import BraintrustPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[BraintrustPlugin()],
)
```
<!-- docs/develop/python/integrations/braintrust.mdx:95-103 -->

Worker:

```python
from braintrust.contrib.temporal import BraintrustPlugin
from temporalio.worker import Worker

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    plugins=[BraintrustPlugin()],
)
```
<!-- docs/develop/python/integrations/braintrust.mdx:80-90 -->

## API credentials

The Worker process needs `BRAINTRUST_API_KEY` in its environment. The Client process that starts Workflow Executions does **not** need the Braintrust API key. <!-- docs/develop/python/integrations/braintrust.mdx:105-118 -->

```bash
export BRAINTRUST_API_KEY="your-api-key"
python worker.py
```
<!-- docs/develop/python/integrations/braintrust.mdx:108-111 -->

## Trace LLM calls with `wrap_openai`

Wrap the OpenAI client with `braintrust.wrap_openai` so every chat/completion call is captured as a span with inputs, outputs, token counts, and latency. Pass `max_retries=0` so Temporal — not the OpenAI client — owns retries. <!-- docs/develop/python/integrations/braintrust.mdx:120-132 -->

```python
from braintrust import wrap_openai
from openai import AsyncOpenAI
from temporalio import activity

@activity.defn
async def invoke_model(prompt: str) -> str:
    client = wrap_openai(AsyncOpenAI(max_retries=0))

    response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt},
        ],
    )

    return response.choices[0].message.content
```
<!-- docs/develop/python/integrations/braintrust.mdx:136-152 -->

The resulting trace nests the OpenAI span under the Activity span, which sits under the Workflow span, which sits under the client-side span: <!-- docs/develop/python/integrations/braintrust.mdx:154-161 -->

```
my-workflow-request (client span)
└── temporal.workflow.MyWorkflow
    └── temporal.activity.invoke_model
        └── Chat Completion (gpt-4o)
```

## Add custom spans with `start_span`

Use `braintrust.start_span` from client code to capture application-level context (the user query, the final result) alongside the Workflow/Activity spans the plugin produces. <!-- docs/develop/python/integrations/braintrust.mdx:163-165 -->

```python
from braintrust import start_span

async def run_research(query: str):
    with start_span(name="research-request", type="task") as span:
        span.log(input={"query": query})

        result = await client.execute_workflow(
            ResearchWorkflow.run,
            query,
            id=f"research-{uuid.uuid4()}",
            task_queue="research-task-queue",
        )

        span.log(output={"result": result})
        return result
```
<!-- docs/develop/python/integrations/braintrust.mdx:167-183 -->

## Manage prompts with `load_prompt`

`braintrust.load_prompt(project=..., slug=...)` fetches a prompt managed in the Braintrust UI, so prompt edits go live without redeploying Workflow or Activity code. Call it from an Activity (model calls live in Activities), then call `prompt.build()` to get the prompt configuration; extract the message you need before invoking the LLM. <!-- docs/develop/python/integrations/braintrust.mdx:185-230 -->

```python
import os
import braintrust
from braintrust import wrap_openai
from openai import AsyncOpenAI
from temporalio import activity

@activity.defn
async def invoke_model(prompt_slug: str, user_input: str) -> str:
    prompt = braintrust.load_prompt(
        project=os.environ.get("BRAINTRUST_PROJECT", "my-project"),
        slug=prompt_slug,
    )

    built = prompt.build()

    system_content = None
    for msg in built.get("messages", []):
        if msg.get("role") == "system":
            system_content = msg["content"]
            break

    client = wrap_openai(AsyncOpenAI(max_retries=0))

    response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": system_content},
            {"role": "user", "content": user_input},
        ],
    )

    return response.choices[0].message.content
```
<!-- docs/develop/python/integrations/braintrust.mdx:197-229 -->

### Fallback prompt for resilience

Wrap `load_prompt` in a `try`/`except` and fall back to a hardcoded prompt so the Activity still runs if Braintrust is unreachable. <!-- docs/develop/python/integrations/braintrust.mdx:232-248 -->

```python
DEFAULT_SYSTEM_PROMPT = "You are a helpful assistant."

try:
    prompt = braintrust.load_prompt(project="my-project", slug="my-prompt")
    system_content = extract_system_message(prompt.build())
except Exception as e:
    activity.logger.warning(f"Failed to load prompt: {e}. Using fallback.")
    system_content = DEFAULT_SYSTEM_PROMPT
```
<!-- docs/develop/python/integrations/braintrust.mdx:237-245 -->

## Common mistakes

- **Initializing the Braintrust logger after constructing the Client or Worker.** Call `init_logger(...)` first; otherwise spans don't connect to the Worker process. <!-- docs/develop/python/integrations/braintrust.mdx:66-75 -->
- **Registering `BraintrustPlugin` on only the Worker (or only the Client).** Register on both — the Client registration is what links client-side spans to Workflow executions. <!-- docs/develop/python/integrations/braintrust.mdx:92-103 -->
- **Forgetting `max_retries=0` on the wrapped OpenAI client.** Temporal owns retries; leaving the OpenAI client's built-in retries on duplicates work and obscures retry counts in traces. <!-- docs/develop/python/integrations/braintrust.mdx:131 -->
- **Calling `load_prompt` from inside a Workflow.** Prompt loading is an external I/O call; keep it in an Activity. <!-- docs/develop/python/integrations/braintrust.mdx:197-205 -->
- **Setting `BRAINTRUST_API_KEY` only on the Client process.** The Worker is what calls Braintrust; the Client doesn't need the key. <!-- docs/develop/python/integrations/braintrust.mdx:113-118 -->

## Additional Resources

- `references/python/ai-patterns.md` — Python LLM patterns (Pydantic, retry discipline, generic LLM Activity shape).
- `references/core/ai-patterns.md` — Conceptual LLM patterns shared across SDKs.
- [Deep research sample](https://github.com/braintrustdata/braintrust-cookbook/blob/main/examples/TemporalDeepResearch/TemporalDeepResearch.mdx) — end-to-end agent showing `BraintrustPlugin`, `wrap_openai`, `start_span`, and `load_prompt`. <!-- docs/develop/python/integrations/braintrust.mdx:39-41 -->
