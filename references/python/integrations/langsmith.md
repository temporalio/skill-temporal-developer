# LangSmith Tracing (Python)

> **Experimental.** The `temporalio.contrib.langsmith` package is currently at an experimental release stage. <!-- sdk-python: contrib/langsmith/README.md top banner -->

## What it does

`LangSmithPlugin` lets [LangSmith](https://smith.langchain.com/) traces work inside Temporal Workflows. It propagates trace context across Worker boundaries — Client → Workflow → Activity → Child Workflow → Nexus — so that `@traceable` calls, LLM invocations, and (optionally) Temporal operations appear in a single connected trace tree, and it ensures Workflow replays do not generate duplicate traces. <!-- sdk-python: contrib/langsmith/README.md intro + "Context Propagation" -->

The plugin's only public exports are `LangSmithPlugin` and `LangSmithInterceptor`. <!-- sdk-python: contrib/langsmith/__init__.py __all__ -->

## Install

```bash
uv add temporalio[langsmith]
```
<!-- sdk-python: contrib/langsmith/README.md "Quick Start" -->

The auto-created `langsmith.Client` reads `LANGSMITH_API_KEY` from the environment. Pass an explicit `client=langsmith.Client(...)` to the plugin if you need to override that. <!-- sdk-python: contrib/langsmith/_plugin.py LangSmithPlugin.__init__ docstring -->

## Register the plugin

Register `LangSmithPlugin` on **both** the Client and the Worker. Strictly speaking, only the sides that produce traces require it, but registering on both avoids surprises with context propagation; the Client and Worker do not need to share the same configuration (e.g., they can use different `add_temporal_runs` settings). <!-- sdk-python: contrib/langsmith/README.md "API Reference" -->

```python
from temporalio.client import Client
from temporalio.contrib.langsmith import LangSmithPlugin

client = await Client.connect(
    "localhost:7233",
    plugins=[LangSmithPlugin(project_name="my-project")],
)
```
<!-- sdk-python: contrib/langsmith/README.md "Quick Start" -->

```python
from temporalio.worker import Worker
from temporalio.contrib.langsmith import LangSmithPlugin

worker = Worker(
    client,
    task_queue="chatbot",
    workflows=[ChatbotWorkflow],
    activities=[call_openai],
    plugins=[LangSmithPlugin(project_name="chatbot")],
)
await worker.run()
```
<!-- sdk-python: contrib/langsmith/README.md "Worker" -->

## API reference — `LangSmithPlugin`

All arguments are keyword-only. <!-- sdk-python: contrib/langsmith/_plugin.py LangSmithPlugin.__init__ signature uses `*,` -->

| Parameter | Default | Meaning |
|---|---|---|
| `client` | `None` | A `langsmith.Client` instance. If `None`, one is created automatically using the `LANGSMITH_API_KEY` env var. |
| `project_name` | `None` | LangSmith project name for traces. |
| `add_temporal_runs` | `False` | When `True`, also emits LangSmith runs for Temporal operations (StartWorkflow / RunWorkflow / StartActivity / RunActivity, etc.). |
| `default_metadata` | `None` | Dict attached as metadata to all runs produced by this plugin. |
| `default_tags` | `None` | List of tags attached to all runs produced by this plugin. |
<!-- sdk-python: contrib/langsmith/_plugin.py LangSmithPlugin.__init__ -->

The plugin registers under the identifier string `"langchain.LangSmithPlugin"` internally — relevant if filtering or debugging plugin lists. <!-- sdk-python: contrib/langsmith/_plugin.py super().__init__("langchain.LangSmithPlugin", ...) -->

## Where `@traceable` works

The plugin makes `@traceable` (from the `langsmith` package) work inside Temporal's deterministic Workflow sandbox, where it normally can't run. <!-- sdk-python: contrib/langsmith/README.md "Where @traceable Works" -->

| Location | Works? | Notes |
|---|---|---|
| Inside Workflow methods | Yes | Traces called from inside `@workflow.run`, `@workflow.signal`, etc.; can trace sync and async methods |
| Inside Activity methods | Yes | Traces called from inside `@activity.defn`; can trace sync and async methods |
| On `@activity.defn` functions | Yes | Must stack `@traceable` **on top of** `@activity.defn` for correct functionality. This trace fires on every retry — see *Wrapping retriable steps* below |
| On `@workflow.defn` classes | **No** | Use `@traceable` **inside** `@workflow.run` instead. Decorating the workflow class or the `@workflow.run` function is not supported. |
<!-- sdk-python: contrib/langsmith/README.md "Where @traceable Works" table -->

### Stacking order on activities

`@traceable` must appear **above** `@activity.defn`: <!-- sdk-python: contrib/langsmith/README.md "Activity (Wraps the LLM Call)" -->

```python
from langsmith import traceable
from temporalio import activity

@traceable(name="Call OpenAI", run_type="chain")
@activity.defn
async def call_openai(request: OpenAIRequest) -> Response:
    ...
```

### Tracing inside a Workflow

Use `@traceable` on local async functions or via `traceable(...)(method)` inside `@workflow.run`: <!-- sdk-python: contrib/langsmith/README.md "Workflow (Orchestrates the Conversation)" -->

```python
from langsmith import traceable
from temporalio import workflow

@workflow.defn
class ChatbotWorkflow:
    @workflow.run
    async def run(self) -> str:
        now = workflow.now().strftime("%b %d %H:%M")
        return await traceable(
            name=f"Session {now}", run_type="chain",
        )(self._run_with_trace)()
```

## `add_temporal_runs` — Temporal operation visibility

Default (`add_temporal_runs=False`): only your `@traceable` application logic appears in traces. <!-- sdk-python: contrib/langsmith/README.md "add_temporal_runs — Temporal Operation Visibility" -->

```
Session Apr 03 14:30
  Query: "What's the weather in NYC?"
    Call OpenAI
      openai.responses.create  (auto-traced by wrap_openai)
```

Opt in to see Temporal orchestration nodes alongside your application logic:

```python
plugins=[LangSmithPlugin(project_name="my-project", add_temporal_runs=True)]
```
<!-- sdk-python: contrib/langsmith/README.md "add_temporal_runs — Temporal Operation Visibility" -->

With `add_temporal_runs=True`, and when the caller wraps `start_workflow` in a `@traceable` function, the trace becomes:

```
Ask Chatbot                      # @traceable wrapper around client.start_workflow
  StartWorkflow:ChatbotWorkflow
  RunWorkflow:ChatbotWorkflow
    Session Apr 03 14:30
      Query: "What's the weather in NYC?"
        StartActivity:call_openai
        RunActivity:call_openai
          Call OpenAI
            openai.responses.create
```
<!-- sdk-python: contrib/langsmith/README.md "add_temporal_runs — Temporal Operation Visibility" -->

`StartFoo` and `RunFoo` appear as siblings: the start is the short-lived outbound RPC that enqueues work on a Task Queue and completes immediately; the run is the actual execution, which may be delayed and may take much longer. <!-- sdk-python: contrib/langsmith/README.md "add_temporal_runs — Temporal Operation Visibility" -->

## Replay safety

Temporal Workflows are deterministic and get replayed from event history on recovery. The plugin handles this mechanically: <!-- sdk-python: contrib/langsmith/README.md "Replay Safety" -->

- **No duplicate traces on replay.** Run IDs are derived deterministically from the Workflow's random seed, so replayed operations produce the same IDs and LangSmith deduplicates them.
- **No non-deterministic calls.** The plugin injects metadata using `workflow.now()` for timestamps and `workflow.random()` for UUIDs instead of `datetime.now()` and `uuid4()`.
- **Background I/O stays outside the sandbox.** LangSmith HTTP calls are submitted to a background thread pool that does not interfere with deterministic Workflow execution.
<!-- sdk-python: contrib/langsmith/README.md "Replay Safety" -->

You do not need to do anything special for this. `@traceable` functions behave the same whether it's a fresh execution or a replay. <!-- sdk-python: contrib/langsmith/README.md "Replay Safety" -->

### Crash example

```
1. Workflow starts, executes Activity A          -> trace appears in LangSmith
2. Worker crashes during Activity B
3. New Worker picks up the Workflow
4. Workflow replays Activity A (skips execution) -> NO duplicate trace
5. Workflow executes Activity B (new work)       -> new trace appears
```
<!-- sdk-python: contrib/langsmith/README.md "Example: Worker Crash Mid-Workflow" -->

## Context propagation

The plugin propagates trace context across process boundaries via Temporal headers. No manual passing is required. <!-- sdk-python: contrib/langsmith/README.md "Context Propagation" -->

```
Client Process              Worker Process (Workflow)        Worker Process (Activity)
─────────────              ──────────────────────────       ─────────────────────────
@traceable("my workflow")
  start_workflow ──headers──> RunWorkflow
                               @traceable("session")
                                 execute_activity ──headers──> RunActivity
                                                                @traceable("Call OpenAI")
                                                                  openai.create(...)
```
<!-- sdk-python: contrib/langsmith/README.md "Context Propagation" -->

## Recipe: wrap retriable steps in a single trace

Because Temporal retries failed Activities, an outer `@traceable` groups the attempts together under one logical step: <!-- sdk-python: contrib/langsmith/README.md "Example: Wrapping Retriable Steps in a Trace" -->

```python
from langsmith import traceable
from temporalio import activity, workflow

@traceable(name="Call OpenAI", run_type="llm")
@activity.defn
async def call_openai(...):
    ...

@traceable(name="my_step", run_type="chain")
async def my_step(message: str) -> str:
    return await workflow.execute_activity(
        call_openai,
        ...
    )
```

Resulting trace shape, with one outer step grouping the retries: <!-- sdk-python: contrib/langsmith/README.md "Example: Wrapping Retriable Steps in a Trace" -->

```
my_step
  Call OpenAI           # first attempt
    openai.responses.create
  Call OpenAI           # retry
    openai.responses.create
```

## Common mistakes

- **Putting `@traceable` below `@activity.defn`.** The decorator order must be `@traceable` *above* `@activity.defn`. <!-- sdk-python: contrib/langsmith/README.md "Where @traceable Works" -->
- **Decorating `@workflow.defn` or `@workflow.run` with `@traceable`.** Not supported. Use `@traceable` inside the body of `@workflow.run` instead. <!-- sdk-python: contrib/langsmith/README.md "Where @traceable Works" -->
- **Registering only on the Worker (or only on the Client).** Register on both for predictable context propagation. <!-- sdk-python: contrib/langsmith/README.md "API Reference" -->
- **Assuming `add_temporal_runs` defaults to `True`.** It defaults to `False`; you only see Temporal operation nodes when you opt in. <!-- sdk-python: contrib/langsmith/_plugin.py LangSmithPlugin.__init__ -->
- **Forgetting that activity-level `@traceable` fires on every retry.** Wrap the activity call in an outer `@traceable` (see the recipe above) when you want one logical run that contains all attempts. <!-- sdk-python: contrib/langsmith/README.md "Where @traceable Works" -->

## Related

- `references/python/ai-patterns.md` — general Python AI/LLM patterns (Pydantic data converter, OpenAI client config, retries).
- `references/python/observability.md` — non-LangSmith observability (metrics, logs).
- `references/integrations.md` — full third-party integrations catalog.
