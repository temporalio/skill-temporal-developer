# Temporal LangGraph Plugin (Python)

## Overview

The Temporal Python SDK ships an experimental plugin, `LangGraphPlugin`, that runs [LangGraph](https://www.langchain.com/langgraph) nodes and tasks as Temporal Activities — giving graph-driven AI workflows durable execution, automatic retries, and timeouts. <!-- sdk-python: temporalio/contrib/langgraph/__init__.py -->

The plugin supports both LangGraph APIs:

- **Graph API** — `StateGraph` with `add_node(...)`. Activity options travel on the node's `metadata` dict.
- **Functional API** — `@entrypoint` / `@task` decorators. Activity options travel on a separate `activity_options={"task_name": {...}}` dict passed to the plugin constructor. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

**Experimental status.** The README and the package docstring both warn the API may change; use with caution in production. <!-- sdk-python: temporalio/contrib/langgraph/README.md, __init__.py -->

**Python 3.11+ required for full async support.** Older Python emits `warnings.warn(...)` at plugin construction; the Functional API (`@task` / `@entrypoint`) and `interrupt()` will not work below 3.11 because LangGraph relies on `contextvars` propagation through `asyncio.create_task()` that only exists on 3.11+. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

The plugin is built on Temporal's general Plugin system (it extends `SimplePlugin`); see `docs/develop/plugins-guide.mdx` for the underlying mechanics. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

## Installation

```sh
uv add temporalio[langgraph]
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md -->

## Public API

Exported from `temporalio.contrib.langgraph`: <!-- sdk-python: temporalio/contrib/langgraph/__init__.py -->

- `LangGraphPlugin` — the plugin class. Pass to `Client.connect(..., plugins=[...])` and `Worker(..., plugins=[...])`.
- `graph(name, cache=None)` — workflow-side helper to retrieve a registered graph by the name it was registered under.
- `entrypoint(name, cache=None)` — workflow-side helper to retrieve a registered entrypoint.
- `cache()` — return the current task result cache as a plain dict, suitable to pass back through `workflow.continue_as_new()`.

`graph()` and `entrypoint()` raise `RuntimeError` if called outside a workflow running under `LangGraphPlugin`. They raise `KeyError` if the requested name is not registered. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

## Plugin Initialization

`LangGraphPlugin.__init__` accepts: <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

```python
LangGraphPlugin(
    graphs: dict[str, StateGraph] | None = None,
    entrypoints: dict[str, Pregel] | None = None,
    tasks: list | None = None,
    activity_options: dict[str, dict[str, Any]] | None = None,
    default_activity_options: dict[str, Any] | None = None,
)
```

The plugin registers itself with the underlying `SimplePlugin` under the name `"langchain.LangGraphPlugin"`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

### Graph API initialization

```python
from langgraph.graph import StateGraph
from temporalio.contrib.langgraph import LangGraphPlugin

g = StateGraph(State)
g.add_node("my_node", my_node, metadata={"execute_in": "activity"})

plugin = LangGraphPlugin(graphs={"my-graph": g})
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md -->

### Functional API initialization

```python
from temporalio.contrib.langgraph import LangGraphPlugin

plugin = LangGraphPlugin(
    entrypoints={"my_entrypoint": my_entrypoint},
    tasks=[my_task],
    activity_options={"my_task": {"execute_in": "activity"}},
)
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md -->

## The `execute_in` Requirement

Every node (Graph API) and every task (Functional API) **must** be labeled with `execute_in`, set to one of two values: `"activity"` or `"workflow"`. <!-- sdk-python: temporalio/contrib/langgraph/README.md, _plugin.py -->

- `"activity"` — the node/task runs as a Temporal Activity. Durable, retryable, timed out by Temporal.
- `"workflow"` — the node/task runs inline in the Workflow code. Must be deterministic; no I/O.

**`execute_in` cannot be set in `default_activity_options`.** The plugin constructor raises `ValueError("execute_in cannot be set in default_activity_options. Set it on each node's metadata (Graph API) or in activity_options[task_name] (Functional API).")` if you try. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

If you forget to set `execute_in` on a node:

```
ValueError: Node {graph_name}.{node_name} is missing required 'execute_in' in metadata.
Set it to 'activity' or 'workflow'.
```

If you forget to set it on a task:

```
ValueError: Task {name} is missing required 'execute_in' in activity_options[{name!r}].
Set it to 'activity' or 'workflow'.
```
<!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

## Activity Options

Options pass through to `workflow.execute_activity()`, which accepts the standard kwargs (`start_to_close_timeout`, `retry_policy`, `schedule_to_close_timeout`, `heartbeat_timeout`, and so on). <!-- sdk-python: temporalio/contrib/langgraph/README.md, _plugin.py -->

### Graph API — options on `metadata`

```python
from datetime import timedelta
from temporalio.common import RetryPolicy

g = StateGraph(State)
g.add_node("my_node", my_node, metadata={
    "execute_in": "activity",
    "start_to_close_timeout": timedelta(seconds=30),
    "retry_policy": RetryPolicy(maximum_attempts=3),
})
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md -->

### Functional API — options on the plugin constructor

```python
from datetime import timedelta
from temporalio.common import RetryPolicy
from temporalio.contrib.langgraph import LangGraphPlugin

plugin = LangGraphPlugin(
    entrypoints={"my_entrypoint": my_entrypoint},
    tasks=[my_task],
    activity_options={
        "my_task": {
            "execute_in": "activity",
            "start_to_close_timeout": timedelta(seconds=30),
            "retry_policy": RetryPolicy(maximum_attempts=3),
        },
    },
)
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md -->

`default_activity_options` (passed to the plugin constructor) supplies shared options for every node/task, with the per-node `metadata` (Graph API) or per-task entry in `activity_options` (Functional API) overlaying on top. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

### LangGraph's own `retry_policy` is not supported

Setting LangGraph's `retry_policy` on a node or `@task` raises ValueError; use Temporal's retry policy via the activity options instead: <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

```
ValueError: Node {graph_name}.{node_name} has a LangGraph retry_policy set. Use Temporal
activity options instead, e.g. pass retry_policy=RetryPolicy(...) via default_activity_options
or in the node's metadata dict.
```

## Workflow-Side Usage

Inside the workflow, retrieve the registered graph or entrypoint by name and invoke it normally:

```python
from temporalio import workflow
from temporalio.contrib.langgraph import graph

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, state_in) -> Any:
        g = graph("my-graph").compile()
        return await g.ainvoke(state_in)
```
<!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

`graph()` and `entrypoint()` look up the workflow's run via `workflow.info().run_id` and return only graphs/entrypoints registered for that run; they cannot be called from non-workflow code. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py, _interceptor.py -->

### Continue-as-new and the task cache

The plugin maintains a per-run task result cache keyed by `(module.qualname, args, kwargs)` so completed tasks survive `workflow.continue_as_new()`. Use the `cache()` helper to snapshot it and pass it back in via `graph(name, cache=...)` or `entrypoint(name, cache=...)`: <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py, _task_cache.py -->

```python
from temporalio import workflow
from temporalio.contrib.langgraph import entrypoint, cache

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, state_in, prior_cache=None):
        ep = entrypoint("my_entrypoint", cache=prior_cache)
        # ... drive the entrypoint ...
        if should_continue_as_new():
            workflow.continue_as_new(args=[new_state, cache()])
```

`task_id()` — the function used to key the cache — **requires module-level definitions**. It raises ValueError for: <!-- sdk-python: temporalio/contrib/langgraph/_task_cache.py -->

- Tasks defined in `__main__` (`"Cannot identify task {qualname}: defined in __main__. Tasks must be importable from a named module."`).
- Lambdas or local/closure functions (`"<locals>"` in `__qualname__` → `"closures/local functions are not supported."`).
- Functions missing `__module__` or `__qualname__`.

## Checkpointer

If your LangGraph code requires a checkpointer (for example, when you use interrupts), use `langgraph.checkpoint.memory.InMemorySaver`. Temporal already handles durability, so third-party checkpointers (Postgres, Redis, etc.) are **not** needed. <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

```python
import langgraph.checkpoint.memory
from temporalio import workflow
from temporalio.contrib.langgraph import graph

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, input: str):
        g = graph("my-graph").compile(
            checkpointer=langgraph.checkpoint.memory.InMemorySaver(),
        )
        ...
```

## Runtime Context

LangGraph's run-scoped context (`context_schema`) is reconstructed on the Activity side, so nodes and tasks can read from and write to `runtime.context`: <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

```python
from langgraph.runtime import Runtime
from typing_extensions import TypedDict
from temporalio.contrib.langgraph import graph

class Context(TypedDict):
    user_id: str

async def my_node(state: State, runtime: Runtime[Context]) -> dict:
    return {"user": runtime.context["user_id"]}

# In the Workflow:
g = graph("my-graph").compile()
await g.ainvoke({...}, context=Context(user_id="alice"))
```

The `context` object must be serializable by the configured Temporal payload converter, since it crosses the Activity boundary. <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

For Pydantic models in the context, configure `pydantic_data_converter` on the client — see `references/python/ai-patterns.md` for the standard setup.

## Sandboxing

The plugin adds `langchain`, `langchain_core`, `langgraph`, `langsmith`, and `numpy` to the workflow sandbox's passthrough modules automatically when a `SandboxedWorkflowRunner` is in use. Do not configure these passthroughs yourself; the plugin's `workflow_runner` callback handles it. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

See `docs/develop/plugins-guide.mdx` (Python section) for the broader Plugin sandbox-passthrough pattern.

## What's Not Supported

### `Store` is not accessible inside Activity-wrapped nodes

LangGraph's `Store` (e.g. `InMemoryStore` passed via `graph.compile(store=...)` or `@entrypoint(store=...)`) holds live state that can't cross the Activity boundary. Activities may run on a different worker than the workflow. If you pass a store, the plugin logs a warning on first use and `runtime.store` is `None` inside nodes. <!-- sdk-python: temporalio/contrib/langgraph/README.md, _activity.py -->

Use workflow state for per-run memory, or an external database (Postgres, Redis, etc.) configured on each worker if you need shared memory across runs. <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

### LangGraph's `retry_policy` on nodes/tasks

As above — setting `retry_policy` on the LangGraph side raises ValueError. Use Temporal's `RetryPolicy` via activity options. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py -->

## Tracing

For tracing, the README recommends the Temporal LangSmith Plugin shipped at `temporalio.contrib.langsmith` in the same Python SDK repository. The LangGraph plugin does not provide its own tracing configuration. <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

## Testing

The upstream plugin's tests live in `tests/contrib/langgraph` in the `temporalio/sdk-python` repository and start a local Temporal dev server automatically — no external server needed. <!-- sdk-python: temporalio/contrib/langgraph/README.md -->

For general Temporal Python testing patterns (replay tests, `WorkflowEnvironment`, time-skipping), see `references/python/testing.md`.

## Cross-References

- General LLM activity patterns (data converter, OpenAI client config, generic LLM activity, error mapping): `references/python/ai-patterns.md`.
- Plugin system fundamentals (`SimplePlugin`, sandbox passthrough, per-language nuances): `docs/develop/plugins-guide.mdx`.
- Other AI/agent integrations (OpenAI Agents, Google ADK, Pydantic AI, Braintrust): `references/integrations.md`.

## Common Mistakes

- **Forgetting `execute_in`.** Every node and every task must set it; there is no default. Putting it in `default_activity_options` is explicitly rejected.
- **Using `metadata=` for Functional API tasks.** Tasks don't carry their own metadata; activity options for tasks must come through the plugin's `activity_options={"task_name": {...}}` kwarg.
- **Recommending PostgreSQL/Redis checkpointers.** Temporal already handles durability — only `InMemorySaver` is needed for LangGraph interrupts.
- **Calling `graph()` or `entrypoint()` outside a workflow.** They raise `RuntimeError` because they look up state in `workflow.info().run_id`.
- **Defining `@task` functions in `__main__` or as closures.** `task_id()` rejects these; tasks must be importable from a named module at module level.
- **Passing a `Store` and expecting it to work inside an Activity-wrapped node.** The plugin warns; `runtime.store` is `None`. Use workflow state or an external DB.
- **Setting LangGraph's own `retry_policy` on a node or `@task`.** Raises ValueError. Use Temporal's `RetryPolicy` via activity options.
- **Treating the plugin as GA.** It is explicitly experimental; the API may change.
