# Temporal LangGraph Plugin (Python)

## Overview

`temporalio.contrib.langgraph` runs LangGraph nodes (Graph API: `StateGraph`) and tasks (Functional API: `@entrypoint` / `@task`) as Temporal Activities, giving an existing LangGraph application durable execution, automatic retries, and configurable timeouts. <!-- sdk-python: temporalio/contrib/langgraph/README.md:5 -->

> **Experimental.** The package is currently at an experimental release stage and may change. <!-- sdk-python: temporalio/contrib/langgraph/README.md:3 -->

The plugin requires Python 3.11+ for full async support; on older versions the Functional API (`@task` / `@entrypoint`) and `interrupt()` will not work because LangGraph relies on `contextvars` propagation through `asyncio.create_task()`, which is 3.11+. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:63-72 -->

## Installation

```sh
uv add temporalio[langgraph]
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md:9-11 -->

The `langgraph` extra pulls in LangGraph and the LangChain dependencies the plugin imports.

## Public API

The package exports four names: <!-- sdk-python: temporalio/contrib/langgraph/__init__.py:13-22 -->

- `LangGraphPlugin` — the plugin class. Subclass of `temporalio.plugin.SimplePlugin`, which implements both `temporalio.client.Plugin` and `temporalio.worker.Plugin`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:38 --> <!-- sdk-python: temporalio/plugin.py:35-38 -->
- `graph(name, cache=None)` — fetch a registered graph from inside the workflow. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:209-211 -->
- `entrypoint(name, cache=None)` — fetch a registered Functional API entrypoint from inside the workflow. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:231-233 -->
- `cache()` — return the task result cache as a serializable dict (or `None` if empty), suitable for passing through `continue_as_new`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:255-262 -->

## Wiring the plugin

Construct `LangGraphPlugin` once at process start and pass it to either the Client or the Worker. **Do not pass it to both** — a plugin that implements `temporalio.worker.Plugin` is automatically forwarded from Client to Worker. <!-- sdk-python: temporalio/client.py:158-165 --> <!-- sdk-python: temporalio/worker/_worker.py:189-192 -->

Samples wire it to the Worker:

```python
from temporalio.client import Client
from temporalio.contrib.langgraph import LangGraphPlugin
from temporalio.worker import Worker

client = await Client.connect("localhost:7233")
plugin = LangGraphPlugin(graphs={"hello-world": make_hello_graph()})

worker = Worker(
    client,
    task_queue="langgraph-hello-world",
    workflows=[HelloWorldWorkflow],
    plugins=[plugin],
)
await worker.run()
```
<!-- samples-python: langgraph_plugin/graph_api/hello_world/run_worker.py:1-31 -->

The plugin contributes:

- Activities — one per registered node/task whose `execute_in == "activity"`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:199-202 -->
- A workflow interceptor (`LangGraphInterceptor`) that scopes the registered graphs/entrypoints to each workflow run via the run ID. <!-- sdk-python: temporalio/contrib/langgraph/_interceptor.py:26-49 -->
- A workflow-runner wrapper that adds `langchain`, `langchain_core`, `langgraph`, `langsmith`, and `numpy` to the sandbox passthrough list when the sandboxed runner is in use. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:166-180 -->

## `LangGraphPlugin` constructor

```python
LangGraphPlugin(
    graphs: dict[str, StateGraph] | None = None,
    entrypoints: dict[str, Pregel] | None = None,
    tasks: list | None = None,
    activity_options: dict[str, dict[str, Any]] | None = None,
    default_activity_options: dict[str, Any] | None = None,
)
```
<!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:51-61 -->

- `graphs` — Graph API. Map of graph-name → compiled-uncompiled `StateGraph`. The plugin walks each graph's nodes and replaces their underlying callable with an activity-dispatching wrapper.
- `entrypoints` — Functional API. Map of entrypoint-name → `Pregel` (the object returned by `@entrypoint()`).
- `tasks` — Functional API. List of `@task`-decorated callables. The plugin replaces each task's `func` with an activity-dispatching wrapper. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:140-164 -->
- `activity_options` — Functional API only. Per-task dict keyed by task function name, holding kwargs for `workflow.execute_activity` plus the required `execute_in`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:150-160 -->
- `default_activity_options` — defaults merged under each node/task's per-call options. **Must not contain `execute_in`** — the plugin raises `ValueError` if it does. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:74-79 -->

## The `execute_in` requirement

Every node (Graph API) and every task (Functional API) must be labeled with `execute_in`, set to either `"activity"` or `"workflow"`. This is required per node/task; it cannot be set in `default_activity_options`. <!-- sdk-python: temporalio/contrib/langgraph/README.md:64 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:74-79 -->

| `execute_in` | Behavior |
|---|---|
| `"activity"` | The node/task runs as a Temporal Activity. Activity options apply (timeouts, retry policy, etc.). <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:199-202 --> |
| `"workflow"` | The node/task runs inline inside the Workflow. Use only for code that is deterministic and side-effect-free. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:203-204 --> |

Missing `execute_in` raises `ValueError` at plugin construction:

- Graph API: `"Node {graph_name}.{node_name} is missing required 'execute_in' in metadata. Set it to 'activity' or 'workflow'."` <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:124-129 -->
- Functional API: `"Task {name} is missing required 'execute_in' in activity_options[{name!r}]. Set it to 'activity' or 'workflow'."` <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:151-156 -->

## Graph API

Define a `StateGraph` and label each node's `metadata` with `execute_in` (plus any Activity options). Register it with the plugin under a name you'll use from the workflow:

```python
from datetime import timedelta
from langgraph.graph import START, StateGraph
from temporalio import workflow
from temporalio.contrib.langgraph import graph as temporal_graph
from typing_extensions import TypedDict


class State(TypedDict):
    value: str


async def process_query(state: State) -> dict[str, str]:
    return {"value": f"Processed: {state['value']}"}


def make_hello_graph() -> StateGraph:
    g = StateGraph(State)
    g.add_node(
        "process_query",
        process_query,
        metadata={
            "execute_in": "activity",
            "start_to_close_timeout": timedelta(seconds=10),
        },
    )
    g.add_edge(START, "process_query")
    return g


@workflow.defn
class HelloWorldWorkflow:
    @workflow.run
    async def run(self, query: str) -> str:
        result = await temporal_graph("hello-world").compile().ainvoke({"value": query})
        return result["value"]
```
<!-- samples-python: langgraph_plugin/graph_api/hello_world/workflow.py:1-42 -->

Inside the workflow, call `temporal_graph(name)` to retrieve the run-scoped graph, then `.compile()` and `.ainvoke()` as you would normally. Calling it outside a workflow raises `RuntimeError`. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:222-228 -->

## Functional API

Pass the `@entrypoint()` Pregel object via `entrypoints=` and the list of `@task` callables via `tasks=`. Per-task options (including the required `execute_in`) go in `activity_options=`, keyed by the task function name:

```python
from datetime import timedelta
from langgraph.func import entrypoint, task
from temporalio import workflow
from temporalio.contrib.langgraph import entrypoint as temporal_entrypoint


@task
def process_query(query: str) -> str:
    return f"Processed: {query}"


@entrypoint()
async def hello_entrypoint(query: str) -> dict:
    result = await process_query(query)
    return {"result": result}


all_tasks = [process_query]

activity_options = {
    "process_query": {
        "execute_in": "activity",
        "start_to_close_timeout": timedelta(seconds=10),
    },
}


@workflow.defn
class HelloWorldFunctionalWorkflow:
    @workflow.run
    async def run(self, query: str) -> dict:
        return await temporal_entrypoint("hello-world").ainvoke(query)
```
<!-- samples-python: langgraph_plugin/functional_api/hello_world/workflow.py:1-41 -->

Worker wiring:

```python
plugin = LangGraphPlugin(
    entrypoints={"hello-world": hello_entrypoint},
    tasks=all_tasks,
    activity_options=activity_options,
)
```
<!-- samples-python: langgraph_plugin/functional_api/hello_world/run_worker.py:20-24 -->

Tasks must be defined at module level. The plugin builds a stable task identity from `module.qualname` and raises `ValueError` for: <!-- sdk-python: temporalio/contrib/langgraph/_task_cache.py:30-54 -->

- functions defined in `__main__`,
- closures / nested functions (anything whose qualname contains `<locals>`),
- functions without `__module__` / `__qualname__`.

## Activity options

`activity_options` and `default_activity_options` are forwarded as kwargs to `workflow.execute_activity()` — anything that function accepts is valid (e.g. `start_to_close_timeout`, `schedule_to_close_timeout`, `retry_policy`, `heartbeat_timeout`). <!-- sdk-python: temporalio/contrib/langgraph/README.md:81-83 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:33-35 -->

**Graph API** — pass options as node `metadata`. Activity-option keys are split out and forwarded; non-option keys stay on `node.metadata` and remain visible to the node function via `config["metadata"]`: <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:115-123 -->

```python
from datetime import timedelta
from temporalio.common import RetryPolicy

g.add_node("my_node", my_node, metadata={
    "execute_in": "activity",
    "start_to_close_timeout": timedelta(seconds=30),
    "retry_policy": RetryPolicy(maximum_attempts=3),
})
```
<!-- sdk-python: temporalio/contrib/langgraph/README.md:90-98 -->

**Functional API** — pass options in the `LangGraphPlugin` constructor, keyed by task function name:

```python
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
<!-- sdk-python: temporalio/contrib/langgraph/README.md:108-121 -->

### Do not set LangGraph's `retry_policy`

The plugin rejects nodes and tasks that carry LangGraph's own `retry_policy`, since retries are owned by Temporal. Use Temporal's `retry_policy=RetryPolicy(...)` via `default_activity_options` or per-node/per-task options instead. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:87-94 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:143-149 -->

## Runtime context

LangGraph's run-scoped context (`context_schema`) is serialized across the activity boundary and reconstructed on the activity side, so nodes and tasks can read from and write to `runtime.context`: <!-- sdk-python: temporalio/contrib/langgraph/README.md:123-144 -->

```python
from langgraph.runtime import Runtime
from typing_extensions import TypedDict
from temporalio.contrib.langgraph import graph as temporal_graph


class Context(TypedDict):
    user_id: str


async def my_node(state: State, runtime: Runtime[Context]) -> dict:
    return {"user": runtime.context["user_id"]}


# In the workflow:
g = temporal_graph("my-graph").compile()
await g.ainvoke({...}, context=Context(user_id="alice"))
```

The `context` object must be serializable by the configured Temporal payload converter, since it crosses the activity boundary. <!-- sdk-python: temporalio/contrib/langgraph/README.md:144 -->

## Checkpointer

If your LangGraph code requires a checkpointer (for example, when using `interrupt()`), use `langgraph.checkpoint.memory.InMemorySaver`. Temporal handles durability, so third-party checkpointers (PostgreSQL, Redis, etc.) are not needed and not recommended: <!-- sdk-python: temporalio/contrib/langgraph/README.md:39-60 -->

```python
import langgraph.checkpoint.memory
from temporalio import workflow
from temporalio.contrib.langgraph import graph as temporal_graph

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, input: str):
        g = temporal_graph("my-graph").compile(
            checkpointer=langgraph.checkpoint.memory.InMemorySaver(),
        )
        ...
```

## Human-in-the-loop via `interrupt()`

LangGraph's `interrupt()` pauses the graph; combine it with a Temporal signal to receive human input asynchronously. The plugin propagates `GraphInterrupt` raised inside the activity back to the workflow, so the v2 invocation surface (`result.interrupts`, `Command(resume=...)`) behaves as it would outside Temporal: <!-- sdk-python: temporalio/contrib/langgraph/_activity.py:74-76 --> <!-- sdk-python: temporalio/contrib/langgraph/_activity.py:133-134 -->

```python
from langchain_core.runnables import RunnableConfig
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command, interrupt
from temporalio import workflow
from temporalio.contrib.langgraph import graph as temporal_graph


async def human_review(state):
    feedback = interrupt(state["value"])
    if feedback == "approve":
        return {"value": state["value"]}
    return {"value": f"[Revised] {state['value']} (feedback: {feedback})"}


@workflow.defn
class ChatbotWorkflow:
    def __init__(self) -> None:
        self._human_input: str | None = None

    @workflow.signal
    async def provide_feedback(self, feedback: str) -> None:
        self._human_input = feedback

    @workflow.run
    async def run(self, user_message: str) -> str:
        app = temporal_graph("chatbot").compile(checkpointer=InMemorySaver())
        config = RunnableConfig(
            {"configurable": {"thread_id": workflow.info().workflow_id}}
        )

        result = await app.ainvoke({"value": user_message}, config, version="v2")
        await workflow.wait_condition(lambda: self._human_input is not None)

        resumed = await app.ainvoke(
            Command(resume=self._human_input), config, version="v2"
        )
        return resumed.value["value"]
```
<!-- samples-python: langgraph_plugin/graph_api/human_in_the_loop/workflow.py:32-89 -->

Notes:

- Use `InMemorySaver` for the checkpointer.
- Use `version="v2"` on `ainvoke` so interrupts surface on the returned object (`result.interrupts`).
- Use a `workflow.signal` to deliver the human's response, then `workflow.wait_condition` until it arrives.

## Continue-as-new with task result caching

The plugin caches each activity's result by a content-addressed key derived from the task's fully-qualified name plus its `(args, kwargs, langgraph_config['context'])`. The cache is held in a contextvar and survives `continue_as_new` only if you carry it explicitly via `cache()` → plugin's `graph()` / `entrypoint()` `cache=` parameter. <!-- sdk-python: temporalio/contrib/langgraph/_task_cache.py:1-68 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:255-262 -->

```python
from dataclasses import dataclass
from typing import Any
from temporalio import workflow
from temporalio.contrib.langgraph import cache
from temporalio.contrib.langgraph import graph as temporal_graph


@dataclass
class PipelineInput:
    data: int
    cache: dict[str, Any] | None = None
    phase: int = 1


@workflow.defn
class PipelineWorkflow:
    @workflow.run
    async def run(self, input_data: PipelineInput) -> int:
        app = temporal_graph("pipeline", cache=input_data.cache).compile()
        result = await app.ainvoke({"value": input_data.data})

        if input_data.phase < 3:
            workflow.continue_as_new(
                PipelineInput(
                    data=input_data.data,
                    cache=cache(),
                    phase=input_data.phase + 1,
                )
            )
        return result["value"]
```
<!-- samples-python: langgraph_plugin/graph_api/continue_as_new/workflow.py:53-86 -->

The cache key includes the task's `module.qualname`, so renaming or moving a `@task` function invalidates prior cache entries. Tasks defined in `__main__`, closures, and unnamed functions cannot be cached and raise `ValueError` at plugin construction. <!-- sdk-python: temporalio/contrib/langgraph/_task_cache.py:30-54 -->

## Sandbox passthrough modules

When the workflow uses the sandboxed runner, the plugin rewrites its `restrictions` to pass through `langchain`, `langchain_core`, `langgraph`, `langsmith`, and `numpy`. You do not need to add these manually. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:166-180 -->

## Tracing

For workflow + activity tracing alongside LangGraph, use the Temporal LangSmith plugin (`temporalio.contrib.langsmith`). The LangGraph plugin's README explicitly recommends it for tracing LangGraph workflows. <!-- sdk-python: temporalio/contrib/langgraph/README.md:146-148 -->

## What is **not** supported

### LangGraph `Store`

`Store` (e.g. `InMemoryStore` passed via `graph.compile(store=...)` or `@entrypoint(store=...)`) is not accessible inside activity-wrapped nodes. The Store object isn't serializable across the activity boundary, and activities may run on a different worker than the workflow. The plugin logs a warning on first use per run, and `runtime.store` is `None` inside nodes. <!-- sdk-python: temporalio/contrib/langgraph/README.md:150-154 --> <!-- sdk-python: temporalio/contrib/langgraph/_activity.py:99-112 -->

Use workflow state for per-run memory, or a backend-backed store (Postgres/Redis/etc.) configured on each worker if you need shared memory across runs. <!-- sdk-python: temporalio/contrib/langgraph/README.md:154 -->

### Stripped fields of `RunnableConfig`

The plugin serializes only a small, primitive subset of LangGraph's `RunnableConfig` across the activity boundary: `tags`, `metadata`, `run_name`, `run_id`, `recursion_limit`, and a fixed subset of `configurable` (`CHECKPOINT_NS`, `CHECKPOINT_ID`, `CHECKPOINT_MAP`, `THREAD_ID`, `TASK_ID`, `RESUMING`, `DURABILITY`). Callbacks, the checkpointer/store/cache handles, and Pregel's send/read callables are dropped. <!-- sdk-python: temporalio/contrib/langgraph/_langgraph_config.py:27-65 -->

### Live `Runtime` fields

`stream_writer`, `store`, and other non-serializable parts of `Runtime` are not propagated. The `Runtime` object inside an activity is reconstructed from `context`, `previous`, and `execution_info`; `stream_writer` is a no-op lambda and `store` is `None`. <!-- sdk-python: temporalio/contrib/langgraph/_langgraph_config.py:96-120 -->

## Gotchas and constraints

- **Plugin scope per Worker.** `LangGraphInterceptor` keys graphs/entrypoints by workflow run ID and clears them when the workflow exits. The same plugin instance can serve many concurrent runs on a Worker. <!-- sdk-python: temporalio/contrib/langgraph/_interceptor.py:22-58 -->
- **`graph(...)` / `entrypoint(...)` must be called from inside a running workflow.** They look up the run ID from `workflow.info()` and raise `RuntimeError` otherwise. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:222-225 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:244-247 -->
- **Unknown name → `KeyError`.** Asking for a graph or entrypoint name not in the plugin's map raises `KeyError` listing the available names. <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:226-228 --> <!-- sdk-python: temporalio/contrib/langgraph/_plugin.py:248-251 -->
- **Workflow code is still deterministic.** Marking a node `execute_in="workflow"` makes it run inside the workflow runner — apply the usual workflow restrictions (no time/IO/random). For anything non-deterministic, use `execute_in="activity"`.
