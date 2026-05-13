# Temporal LangGraph Plugin (Python)

> **Experimental.** The `temporalio.contrib.langgraph` package is marked experimental in its module docstring and `README` and may change in future releases. Treat the API as unstable.

## Overview

`LangGraphPlugin` (from `temporalio.contrib.langgraph`) runs LangGraph nodes and tasks as Temporal Activities so they inherit durable execution, automatic retries, and timeouts. It supports both LangGraph APIs:

- **Graph API** — `StateGraph`, with per-node `metadata={"execute_in": ...}` controlling Activity vs. workflow execution.
- **Functional API** — `@entrypoint` / `@task`, with options passed via the plugin constructor.

The plugin is one instance of the general Temporal Plugin pattern, which can register Activities, Workflows, Nexus Operations, Data Converters, Interceptors, and Context Propagators.

## Installation

```sh
uv add temporalio[langgraph]
```

## Public API

Importable from `temporalio.contrib.langgraph`:

- `LangGraphPlugin` — the plugin class registered with the Temporal `Client` / `Worker`.
- `graph(name, cache=None)` — workflow-side accessor that retrieves the compiled `StateGraph` registered under `name`.
- `entrypoint(name, cache=None)` — workflow-side accessor for a Functional API entrypoint registered under `name`.
- `cache()` — helper returning the plugin's per-workflow task cache.

`LangGraphPlugin.__init__` signature:

```python
LangGraphPlugin(
    graphs: dict[str, StateGraph] | None = None,
    entrypoints: dict[str, Pregel] | None = None,
    tasks: list | None = None,
    activity_options: dict[str, dict] | None = None,
    default_activity_options: dict | None = None,
)
```

## Plugin Initialization

### Graph API

```python
from langgraph.graph import StateGraph
from temporalio.contrib.langgraph import LangGraphPlugin

g = StateGraph(State)
g.add_node("my_node", my_node, metadata={"execute_in": "activity"})

plugin = LangGraphPlugin(graphs={"my-graph": g})
```

### Functional API

```python
from temporalio.contrib.langgraph import LangGraphPlugin

plugin = LangGraphPlugin(
    entrypoints={"my_entrypoint": my_entrypoint},
    tasks=[my_task],
    activity_options={"my_task": {"execute_in": "activity"}},
)
```

Pass the resulting `plugin` to your `Client` and `Worker` like any other Temporal plugin.

## Execution Location: `execute_in` is Required Per Node/Task

Every node (Graph API) and every task (Functional API) **must** be labeled with `execute_in`, set to either `"activity"` or `"workflow"`. This setting is required per node/task and **cannot** be set in `default_activity_options`.

```python
# Graph API
graph.add_node("my_node", my_node, metadata={"execute_in": "activity"})
graph.add_node("tool_node", tool_node, metadata={"execute_in": "workflow"})

# Functional API
plugin = LangGraphPlugin(
    tasks=[my_task, tool_task],
    activity_options={
        "my_task": {"execute_in": "activity"},
        "tool_task": {"execute_in": "workflow"},
    },
)
```

Use `"activity"` for any node that performs non-deterministic or heavy work (LLM calls, HTTP requests, file I/O). Use `"workflow"` for deterministic state-mutation nodes that need to run inline (consistent with `references/core/ai-patterns.md` Pattern 3).

## Activity Options

Options on a node/task are passed through to `workflow.execute_activity()`, which supports parameters including `start_to_close_timeout`, `retry_policy`, `schedule_to_close_timeout`, and `heartbeat_timeout`.

### Graph API: options as node `metadata`

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

### Functional API: options keyed by task function name

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

`default_activity_options=` on the plugin constructor sets defaults that apply across nodes/tasks. The one option this default mechanism does **not** cover is `execute_in` — see the warning above.

## Using the Registered Graph or Entrypoint Inside a Workflow

`graph(name)` and `entrypoint(name)` are workflow-side accessors: call them from inside a `@workflow.defn` to retrieve the LangGraph object registered under that name in `LangGraphPlugin(graphs=..., entrypoints=...)`. The returned `StateGraph` is then `.compile()`-ed inside the workflow.

```python
import langgraph.checkpoint.memory
import typing

from temporalio import workflow
from temporalio.contrib.langgraph import graph

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, input: str) -> typing.Any:
        g = graph("my-graph").compile(
            checkpointer=langgraph.checkpoint.memory.InMemorySaver(),
        )
        ...
```

## Checkpointer: Use `InMemorySaver`

If your LangGraph code requires a checkpointer (for example, when using interrupts), use `langgraph.checkpoint.memory.InMemorySaver`. Temporal handles durability for the workflow, so third-party checkpointers like PostgreSQL or Redis are not needed.

Do not configure `PostgresSaver`, `SqliteSaver`, or `RedisSaver` — they duplicate work Temporal is already doing and introduce a second persistence boundary that can desynchronize from workflow history.

## Runtime Context

LangGraph's run-scoped context (the `context_schema` you pass to `.ainvoke({...}, context=...)`) is reconstructed on the Activity side, so nodes and tasks can read from `runtime.context`.

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

Your `context` object must be serializable by the configured Temporal payload converter, since it crosses the Activity boundary.  For applications that already use Pydantic types in workflow signatures, configure `pydantic_data_converter` on the `Client` (see `references/python/ai-patterns.md`).

## Tracing

Use the Temporal LangSmith Plugin (`temporalio.contrib.langsmith`) to trace LangGraph workflows and the activities they spawn.

## Stores are Not Supported

LangGraph's `Store` (e.g. `InMemoryStore` passed via `graph.compile(store=...)` or `@entrypoint(store=...)`) is **not** accessible inside Activity-wrapped nodes. The Store holds live in-process state that cannot cross the Activity boundary, and Activities may run on a different worker than the workflow. If you pass a store, the plugin logs a warning on first use and `runtime.store` is `None` inside nodes.

Documented workarounds:

- **Per-run memory** → use workflow state (instance variables on the `@workflow.defn` class).
- **Shared memory across runs** → an external database (PostgreSQL, Redis, etc.) configured on each worker, accessed from inside Activities.

## Common Mistakes

- **Setting `execute_in` in `default_activity_options`.** It must be set per node (Graph API `metadata={...}`) or per task (Functional API `activity_options={task_name: {...}}`).
- **Putting Functional-API options under `metadata={...}`.** `metadata` is the Graph-API channel. The Functional API uses the plugin's `activity_options=` constructor argument, keyed by task function name.
- **Recommending `PostgresSaver` / `RedisSaver`.** Use `InMemorySaver`; Temporal handles durability.
- **Calling `graph(name)` or `entrypoint(name)` outside a workflow.** They are workflow-side accessors meant for `@workflow.defn` code.
- **Treating the plugin as GA.** It is experimental; pin the `temporalio` version and re-test on upgrade.
- **Passing a `Store` and expecting it to work on the Activity side.** It will not; switch to workflow state or an external DB.

## Testing

The upstream contrib test suite uses a local Temporal dev server started automatically — no external server required.

```sh
uv sync --all-extras
uv run pytest tests/contrib/langgraph
```

For your own LangGraph plugin tests, follow `references/python/testing.md` patterns — register `LangGraphPlugin` on both the test `Client` and the test `Worker`, then drive workflows the same way as any other Temporal test.

## Related References

- `references/core/ai-patterns.md` — language-agnostic AI/LLM patterns (activities wrap LLM calls, disable client retries, centralized retry management).
- `references/python/ai-patterns.md` — Python AI/LLM implementation details (Pydantic data converter, generic LLM activity).
- `references/python/python.md` — Python SDK overview, client/worker setup.
- `../documentation/docs/develop/plugins-guide.mdx` — general Temporal plugin guide (concepts, what a plugin can register, Python sandbox notes).
