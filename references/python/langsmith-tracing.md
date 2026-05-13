# Python LangSmith Tracing Plugin

> ⚠️ The `LangSmithPlugin` is **experimental**. APIs and behavior may change. <!-- sdk-python: temporalio/contrib/langsmith/README.md (banner); temporalio/contrib/langsmith/__init__.py (module docstring) -->

## What it does

`LangSmithPlugin` connects LangSmith tracing to Temporal Workflows and Activities so that `@traceable` functions, LLM calls auto-traced by `wrap_openai`, and (optionally) Temporal operations appear in a single connected trace tree — even across Worker boundaries — and replays do not produce duplicate traces. <!-- sdk-python: temporalio/contrib/langsmith/README.md -->

The plugin is built on Temporal's Python [plugin system](../../../documentation/docs/develop/plugins-guide.mdx); it wires an interceptor and a sandbox passthrough into the Client and Worker for you.

## Install

```bash
uv add temporalio[langsmith]
```

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Quick Start) -->

Authentication: when no explicit `client=` is passed, the plugin auto-creates a `langsmith.Client` that reads `LANGSMITH_API_KEY` from the environment. <!-- sdk-python: temporalio/contrib/langsmith/_plugin.py (`__init__` docstring) -->

## Register the plugin

Register on **both** the Client (starter) and the Worker. Strictly only the side that emits traces needs it, but registering on both avoids surprises with context propagation. Client and Worker do not have to share configuration — for example, they can use different `add_temporal_runs` values. <!-- sdk-python: temporalio/contrib/langsmith/README.md (API Reference) -->

```python
from temporalio.client import Client
from temporalio.contrib.langsmith import LangSmithPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[LangSmithPlugin(project_name="my-project")],
)
```

```python
from temporalio.worker import Worker

worker = Worker(
    client,
    task_queue="chatbot",
    workflows=[ChatbotWorkflow],
    activities=[call_openai],
)
```

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Example: AI Chatbot — Worker) -->

When the plugin's `run_context` exits, the LangSmith client's `flush()` is invoked so in-flight runs are uploaded before shutdown. <!-- sdk-python: temporalio/contrib/langsmith/_plugin.py -->

## Where `@traceable` is supported

| Location | Supported? | Notes |
|---|---|---|
| Inside `@workflow.run`, `@workflow.signal`, etc. | Yes | Sync or async; replay-safe. |
| Inside `@activity.defn` bodies | Yes | Sync or async. |
| Stacked **on top of** `@activity.defn` | Yes | Order matters — see below. Fires on every retry. |
| Decorating an `@workflow.defn` class or the `@workflow.run` method | **No** | Use `@traceable` inside the method body instead. |

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Where @traceable Works) -->

Decorator order on Activities (`@traceable` outermost):

```python
from langsmith import traceable
from temporalio import activity

@traceable(name="Call OpenAI", run_type="chain")
@activity.defn
async def call_openai(request: OpenAIRequest) -> Response:
    client = wrap_openai(AsyncOpenAI())  # auto-traced by langsmith
    return await client.responses.create(
        model=request.model,
        input=request.input,
        instructions=request.instructions,
    )
```

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Activity (Wraps the LLM Call)) -->

Inside a Workflow, wrap inner functions with `@traceable` rather than decorating the class:

```python
@workflow.defn
class ChatbotWorkflow:
    @workflow.run
    async def run(self) -> str:
        now = workflow.now().strftime("%b %d %H:%M")
        return await traceable(
            name=f"Session {now}", run_type="chain",
        )(self._run_with_trace)()
```

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Workflow (Orchestrates the Conversation)) -->

## `add_temporal_runs` — what shows up in the trace tree

Default `False`: only your own `@traceable` runs appear. <!-- sdk-python: temporalio/contrib/langsmith/_plugin.py (`__init__` default) -->

```
Session Apr 03 14:30
  Query: "What's the weather in NYC?"
    Call OpenAI
      openai.responses.create
```

Set `True` to also surface Temporal operations (`StartWorkflow`, `RunWorkflow`, `StartActivity`, `RunActivity`, …) as siblings/children in the tree:

```python
plugins=[LangSmithPlugin(project_name="my-project", add_temporal_runs=True)]
```

```
Ask Chatbot
  StartWorkflow:ChatbotWorkflow
  RunWorkflow:ChatbotWorkflow
    Session Apr 03 14:30
      Query: "What's the weather in NYC?"
        StartActivity:call_openai
        RunActivity:call_openai
          Call OpenAI
            openai.responses.create
```

`StartFoo` and `RunFoo` appear as siblings: the start is the short-lived outbound RPC that enqueues work on a Task Queue and completes immediately; the run is the actual execution, which may be delayed and may take much longer. <!-- sdk-python: temporalio/contrib/langsmith/README.md (add_temporal_runs section) -->

## Replay safety

The plugin keeps tracing deterministic across Workflow replays so that surviving a Worker crash or replay does not produce duplicate runs in LangSmith:

- Run IDs are derived from the Workflow's deterministic random seed (`workflow.new_random()`), so a replayed operation produces the same ID and LangSmith deduplicates it. <!-- sdk-python: temporalio/contrib/langsmith/_interceptor.py (`_get_workflow_random`, `_uuid_from_random`) -->
- Timestamps come from `workflow.now()` and UUIDs from the workflow-seeded RNG rather than `datetime.now()` / `uuid4()`. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Replay Safety) -->
- During replay, `post()`/`end()`/`patch()` on the wrapped `RunTree` are no-ops so no I/O is repeated, while `create_child()` still runs to maintain parent-child linkage. <!-- sdk-python: temporalio/contrib/langsmith/_interceptor.py (`_ReplaySafeRunTree`) -->
- HTTP submission to the LangSmith server happens on a background thread pool so it does not interact with the Workflow event loop. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Replay Safety) -->

You do not need to call any of this yourself.

## Grouping retried Activities under one parent

Because Temporal retries failed Activities, an outer `@traceable` around the call wraps all attempts in one parent run:

```python
@traceable(name="Call OpenAI", run_type="llm")
@activity.defn
async def call_openai(...): ...

@traceable(name="my_step", run_type="chain")
async def my_step(message: str) -> str:
    return await workflow.execute_activity(call_openai, ...)
```

Produces:

```
my_step
  Call OpenAI           # attempt 1
    openai.responses.create
  Call OpenAI           # retry
    openai.responses.create
```

<!-- sdk-python: temporalio/contrib/langsmith/README.md (Example: Wrapping Retriable Steps in a Trace) -->

## Context propagation

Trace context is carried across Client → Workflow → Activity → Child Workflow → Nexus boundaries via a Temporal header. No manual passing required. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Context Propagation) -->

Internals (informational): the header key is `_temporal-langsmith-context` and the plugin marks `langsmith` and `langchain_core` as workflow-sandbox passthrough modules so they can be imported inside Workflows. <!-- sdk-python: temporalio/contrib/langsmith/_interceptor.py (`HEADER_KEY`); temporalio/contrib/langsmith/_plugin.py (`with_passthrough_modules`) -->

The plugin registers under the name `langchain.LangSmithPlugin`. <!-- sdk-python: temporalio/contrib/langsmith/_plugin.py -->

## API Reference

```python
LangSmithPlugin(
    client=None,              # langsmith.Client; auto-created from LANGSMITH_API_KEY if None
    project_name=None,        # LangSmith project name
    add_temporal_runs=False,  # If True, also emit runs for Temporal operations
    default_metadata=None,    # dict[str, Any] attached to all runs
    default_tags=None,        # list[str] attached to all runs
)
```

<!-- sdk-python: temporalio/contrib/langsmith/_plugin.py (`LangSmithPlugin.__init__` signature and docstring) -->

All arguments are keyword-only.

## Gotchas

- **Status is experimental.** Treat it as Pre-release per the [release-stages guide](../../../documentation/docs/evaluate/development-production-features/release-stages.mdx#pre-release): API may change; no SLA. <!-- sdk-python: temporalio/contrib/langsmith/README.md (banner) ; docs/evaluate/development-production-features/release-stages.mdx -->
- **Activity-level `@traceable` fires on every retry.** If you want one parent run across attempts, wrap the `execute_activity` call in an outer `@traceable`. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Where @traceable Works; Wrapping Retriable Steps) -->
- **Decorator order on Activities is `@traceable` then `@activity.defn`.** Reversing the order is unsupported. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Where @traceable Works table) -->
- **Do not decorate the `@workflow.defn` class or the `@workflow.run` method with `@traceable`.** Apply `@traceable` to a function defined inside `run` instead. <!-- sdk-python: temporalio/contrib/langsmith/README.md (Where @traceable Works table) -->
- **Register on both Client and Workers.** Trace context is propagated through Temporal headers; missing the plugin on the starter side prevents parent-child linkage from the Client into the Workflow. <!-- sdk-python: temporalio/contrib/langsmith/README.md (API Reference) -->

## See also

- `references/python/observability.md` — workflow/activity loggers and SDK metrics; complementary to LangSmith application-level tracing.
- `references/python/ai-patterns.md` — Pydantic data converter, OpenAI client config (`max_retries=0`), LLM activity patterns.
- `references/core/ai-patterns.md` — conceptual AI/LLM patterns shared across SDKs.
- Sibling plugin pattern: `../../../documentation/docs/develop/python/integrations/braintrust.mdx` — similar observability plugin shape (Braintrust).
- Plugin authoring concepts: `../../../documentation/docs/develop/plugins-guide.mdx`.
