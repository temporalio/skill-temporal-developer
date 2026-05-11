# Python LangGraph Plugin

## Status

The Temporal Python SDK reportedly ships a LangGraph plugin built on the SDK's
[Plugin system](/develop/plugins-guide), but **the canonical Temporal documentation does not yet cover it**. As of the
docs snapshot this reference was authored against, the documented Python AI-framework integrations are:

| Framework         | Tags            |
| ----------------- | --------------- |
| Braintrust        | Observability   |
| Google ADK        | Agent framework |
| OpenAI Agents SDK | Agent framework |
| Pydantic AI       | Agent framework |
| Tenuo             | Governance      |

<!-- docs/develop/python/integrations/index.mdx:23-29 -->

LangGraph is not on that list. Until it is, treat the sections below as *the plugin pattern that LangGraph integration
follows*, not as transcribed LangGraph API. Every LangGraph-specific token (class name, import path, install string,
constructor option, semantics) is marked `<!-- VERIFY -->` and should be confirmed against the upstream
`temporalio/sdk-python` repository or the integration's own README before being relied on.

## What a Temporal Plugin is

A Plugin is an abstraction that allows you to customize any aspect of your Temporal Worker setup, including registering
Workflow and Activity definitions and modifying worker and client options. <!-- docs/develop/plugins-guide.mdx:20-22 -->
A Plugin bundles multiple extensibility primitives — interceptors, context propagators, data converters, and built-in
Workflow/Activity/Nexus definitions — into a single reusable package. <!-- docs/encyclopedia/plugins.mdx:15 -->

AI Agent SDKs are a documented use case for plugins. <!-- docs/develop/plugins-guide.mdx:29 --> The encyclopedia
explicitly names OpenAI Agents and Pydantic AI as examples. <!-- docs/encyclopedia/plugins.mdx:19 -->

The recommended starting point for authoring a plugin is `SimplePlugin`.
<!-- docs/develop/plugins-guide.mdx:36-37 --> Temporal's Python SDK ships an OpenAI Agents SDK plugin at
`temporalio/contrib/openai_agents`. <!-- docs/develop/plugins-guide.mdx:44 -->

## What the LangGraph plugin gives you (pattern, unverified specifics)

By analogy with the **Braintrust** integration (the closest sibling pattern documented today), a Python integration
plugin generally:

1. Provides a `Plugin` class added to the `plugins=[...]` list when constructing the Worker and/or Client. The
   Braintrust analogue is:

   ```python
   from braintrust.contrib.temporal import BraintrustPlugin  # docs/develop/python/integrations/braintrust.mdx:80
   # plugins=[BraintrustPlugin()] on Worker/Client  # docs/develop/python/integrations/braintrust.mdx:88
   ```

   The LangGraph equivalent class name and import path are <!-- VERIFY: confirm exact class and module against
   temporalio/sdk-python -->.

2. Ships under a `pip install "<package>[temporal]"`-shaped extra, e.g. `uv pip install "braintrust[temporal]"`.
   <!-- docs/develop/python/integrations/braintrust.mdx:63 --> Whether the LangGraph plugin uses
   `pip install "langgraph[temporal]"`, `pip install "temporalio[langgraph]"`, or some other install string is
   <!-- VERIFY: confirm install command against package metadata --> — do not infer the name from the Braintrust shape.

3. Registers any required Activities, Workflows, Data Converters, Interceptors, or Workflow runner overrides through
   `SimplePlugin` so that adding the plugin to the Worker is sufficient to make the integration work.
   <!-- docs/develop/plugins-guide.mdx:55-60 -->

The Plugin guide lists what a plugin can register: built-in Activities, Workflow-friendly libraries, built-in
Workflows, built-in Nexus Operations, custom Data Converters, Interceptors, and Context Propagators.
<!-- docs/develop/plugins-guide.mdx:54-60 --> Which of those primitives the LangGraph plugin actually contributes is
<!-- VERIFY: enumerate against the plugin's source -->.

## Workflow-friendly library rules (apply to LangGraph code in a Workflow)

If you call LangGraph from Workflow code via the plugin's library surface, the Plugin guide's workflow-friendly
library rules apply verbatim:

- Code in the Workflow context must be [deterministic](/workflow-definition#deterministic-constraints) — it must
  produce the same commands and results when replayed. Don't call system time APIs, generate random values, or perform
  direct network or file I/O from Workflow-context code; move that work to Activities or Nexus Operations.
  <!-- docs/develop/plugins-guide.mdx:192-195 -->
- Put other side effects inside Activities or [Local Activities](/local-activity).
  <!-- docs/develop/plugins-guide.mdx:198-200 -->
- Workflow-context code should run quickly, since it may be replayed many times during a long Workflow execution. More
  expensive code belongs in Activities or Nexus Operations.
  <!-- docs/develop/plugins-guide.mdx:202-203 -->

Concretely: LLM API calls, tool calls that hit the network or disk, and any other non-deterministic operations a
LangGraph node performs must run inside Activities, not directly in the Workflow. Whether the plugin auto-dispatches
LangGraph node execution to Activities, or whether the developer is responsible for that decomposition, is
<!-- VERIFY: confirm dispatch model against the LangGraph plugin's design -->.

## Python sandbox interaction

Python Workflows can be run in a sandbox to help prevent non-determinism errors.
<!-- docs/develop/plugins-guide.mdx:842-844 --> A plugin that needs to work for users running the sandbox should
specify the Workflow runner it uses by passing `workflow_runner=...` to `SimplePlugin`, typically wrapping the
sandboxed runner with `with_passthrough_modules(...)` for any modules that must pass through the sandbox.
<!-- docs/develop/plugins-guide.mdx:846-863 -->

Whether the LangGraph plugin adds the `langgraph` (and adjacent) packages to the sandbox passthrough list, and which
exact modules it passes through, is <!-- VERIFY: read the plugin's `workflow_runner` argument or equivalent -->.

## Data converter

The Plugin guide notes that a custom Data Converter can be supplied via `data_converter=` on `SimplePlugin`, and that
existing converters such as `PydanticPayloadConverter` can be reused.
<!-- docs/develop/plugins-guide.mdx:529, 536-545 --> Many AI integrations need Pydantic-compatible serialization to
handle complex types (see `references/python/ai-patterns.md` for the manual Pydantic setup pattern).

Whether the LangGraph plugin installs `pydantic_data_converter`, a different converter, or none at all is
<!-- VERIFY: confirm against the plugin's `data_converter` argument -->. If it does not, applications should follow
the manual setup in `references/python/ai-patterns.md`.

## Testing

The Plugin guide's general testing guidance applies:

- **Replay testing.** When you make changes to your plugin after it has already shipped, set up replay testing on each
  important change to make sure you're not introducing non-determinism errors for users.
  <!-- docs/develop/plugins-guide.mdx:899-901 --> The Temporal Python SDK has an example for the OpenAI Agents plugin
  at `tests/contrib/openai_agents/test_openai_replay.py`. <!-- docs/develop/plugins-guide.mdx:229 -->
- **Side effects.** Turn the Workflow cache off (`max_cached_workflows=0` on the Worker) so the Workflow replays from
  the top each progress step, then assert that side effects don't duplicate.
  <!-- docs/develop/plugins-guide.mdx:909-916 -->

## When to use the LangGraph plugin vs. building manually

The Plugin guide notes that a plugin allows users to decompose Workflows into Activities, Child Workflows, and Nexus
Calls; this gives granular retries and timeouts, Temporal UI debuggability, operability with resets/pauses/cancels,
memoization, and scalability via task queues and Workers. <!-- docs/develop/plugins-guide.mdx:205-208 --> If the
LangGraph plugin already provides that decomposition out of the box, prefer it over hand-rolling activities for each
node. If it does not, fall back to the manual patterns in `references/python/ai-patterns.md` (in particular the
generic `call_llm` activity and the tool-calling agent workflow patterns).

The decision criteria for *whether* the LangGraph plugin's decomposition matches your needs require knowing what it
actually registers, which is <!-- VERIFY -->.

## Verification checklist

Before relying on this page for code generation, confirm the following against the upstream
[`temporalio/sdk-python`](https://github.com/temporalio/sdk-python) source (the only currently-authoritative source —
the Temporal docs are silent on LangGraph as of this writing):

- [ ] The plugin's exact class name (don't infer from `BraintrustPlugin` / `OpenAIAgentsPlugin`).
- [ ] The plugin's import path (don't assume `temporalio.contrib.langgraph` — `temporalio.contrib.openai_agents` and
      `temporalio.contrib.pydantic` are the documented `contrib` shapes).
- [ ] The install string (extras name, package name).
- [ ] The constructor option surface (model, tools, runner overrides, data converter, interceptors).
- [ ] Whether the plugin auto-dispatches LangGraph nodes to Activities, or expects the user to decompose.
- [ ] The exact sandbox passthrough module list, if any.
- [ ] Any replay test fixtures shipped under `tests/contrib/`.

Once these are confirmed, the `<!-- VERIFY -->` markers above can be replaced with grounded prose and the documented
integrations table at the top of this file should be updated to add LangGraph.

## See also

- `references/python/ai-patterns.md` — language-specific AI/LLM patterns (Pydantic data converter, generic LLM
  activity, tool-calling agent, multi-agent pipeline). The manual fallback if the plugin doesn't fit.
- `references/core/ai-patterns.md` — conceptual AI patterns (activities-wrap-LLM-calls, deterministic tools in
  workflows, non-deterministic tools in activities).
- `docs/develop/plugins-guide.mdx` (in the docs clone) — the canonical Plugin guide. The authoritative source for any
  generic plugin question this file doesn't answer.
- `docs/develop/python/integrations/index.mdx` — the canonical list of documented Python AI-framework integrations.
  Check here first to see whether LangGraph has since been added.
