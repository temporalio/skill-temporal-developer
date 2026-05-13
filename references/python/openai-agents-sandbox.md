# OpenAI Agents SDK + Python Workflow Sandbox

## Scope

This reference covers two grounded topics and how they interact:

1. The **OpenAI Agents SDK** integration with the Temporal Python SDK, which ships as a Plugin in `temporalio.contrib.openai_agents`. <!-- docs/develop/plugins-guide.mdx:44 -->
2. The **Python Workflow Sandbox** (`SandboxedWorkflowRunner`) — the default Worker-side environment that workflow code runs in. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:100 -->

The OpenAI Agents SDK plugin is the documented mechanism for wiring `openai-agents-python` into a Temporal Worker. The integration guide for it lives in the upstream `temporalio/sdk-python` repository's `temporalio/contrib/openai_agents/README.md`. <!-- docs/develop/python/integrations/index.mdx:27 -->

> **Note on terminology.** Some ticket descriptions and AI-generated content refer to a "SandboxAgent" symbol. That name does **not** appear in Temporal's documentation. The sandbox-related symbols are `SandboxedWorkflowRunner`, `UnsandboxedWorkflowRunner`, `SandboxRestrictions`, `SandboxMatcher`, and `SandboxImportNotificationPolicy`. The OpenAI Agents plugin's class is referred to as `OpenAIAgentsPlugin` in the Plugins guide. <!-- docs/develop/plugins-guide.mdx:228 -->

## Where the integration lives

| Item | Source |
|---|---|
| Plugin location | `temporalio.contrib.openai_agents` (Python SDK contrib) <!-- docs/develop/plugins-guide.mdx:44 --> |
| Plugin class name (as named in docs) | `OpenAIAgentsPlugin` <!-- docs/develop/plugins-guide.mdx:228 --> |
| Integration guide | `temporalio/sdk-python` → `temporalio/contrib/openai_agents/README.md` <!-- docs/develop/python/integrations/index.mdx:27 --> |
| Replay-test example | `temporalio/sdk-python` → `tests/contrib/openai_agents/test_openai_replay.py` <!-- docs/develop/plugins-guide.mdx:229 --> |
| Conceptual framing | AI Agent SDKs are a documented Plugin use case. <!-- docs/encyclopedia/plugins.mdx:19 --> |

<!-- VERIFY: Specific OpenAIAgentsPlugin constructor arguments, model-routing options, and the exact set of activities it registers are not in the local Temporal documentation. Consult the upstream README for current API shape rather than inferring from this file. -->

## How the Python Workflow Sandbox interacts with a plugin

A Worker's `workflow_runner` defaults to `SandboxedWorkflowRunner()`. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:100 --> `SandboxedWorkflowRunner` accepts a `restrictions` keyword argument typed as `SandboxRestrictions`, an immutable dataclass with three notable fields: <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:101–107 -->

- `passthrough_modules`
- `invalid_module_members`
- `import_notification_policy`

A Plugin that adds new modules to the workflow environment should specialize the runner so its modules are passed through correctly. The documented pattern looks like this: <!-- docs/develop/plugins-guide.mdx:849–863 -->

```python
import dataclasses
from temporalio.worker import WorkflowRunner
from temporalio.worker.workflow_sandbox import SandboxedWorkflowRunner

def workflow_runner(runner: WorkflowRunner | None) -> WorkflowRunner:
    if not runner:
        raise ValueError("No WorkflowRunner provided to the plugin.")
    # If in sandbox, add additional passthrough.
    if isinstance(runner, SandboxedWorkflowRunner):
        return dataclasses.replace(
            runner,
            restrictions=runner.restrictions.with_passthrough_modules("module"),
        )
    return runner
```

Key points (all from the canonical snippet):

- The plugin receives the existing `runner` and returns a (possibly modified) runner — it does not construct one from scratch.
- It only modifies the runner when `isinstance(runner, SandboxedWorkflowRunner)`. If the user has chosen `UnsandboxedWorkflowRunner` or a custom runner, the plugin leaves it alone.
- `dataclasses.replace(runner, restrictions=…)` is used because `SandboxRestrictions` is immutable. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:103 -->
- `runner.restrictions.with_passthrough_modules("module")` returns a new `SandboxRestrictions` with the named module added to passthrough. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:142–146 -->

## What "passthrough" means and why it matters here

Passing a module through means the sandbox imports it from outside rather than reloading it on every Workflow run. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:111 --> The docs are explicit: only pass through modules known to be **side-effect-free and deterministic** — repeated use in a single workflow run must not produce different results. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:113–115 -->

For the OpenAI Agents integration this matters because:

- Lightweight, deterministic helpers from the agent framework (type definitions, dataclass-style models, prompt-shaping utilities that don't call out) are reasonable passthrough candidates.
- The `openai` client and any HTTP library are **not** passthrough candidates. Network calls are non-deterministic; they belong in activities, which is precisely what the plugin arranges. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:30, 41–47 -->

Which specific modules the `OpenAIAgentsPlugin` passes through is determined by the upstream plugin code, not by Temporal documentation. If you build your own plugin or extend behavior, follow the snippet above.

## Authoring your own plugin that uses the sandbox

This is the generic pattern from the Plugins guide, with the Python sandbox specialization included.

```python
import dataclasses
from temporalio.contrib.pydantic import pydantic_data_converter
from temporalio.worker import WorkflowRunner
from temporalio.worker.workflow_sandbox import SandboxedWorkflowRunner
from temporalio import workflow

# Plugin's own workflow code, defined in a separate file in production,
# would import its helpers under imports_passed_through() in that file.
```

The `workflow_runner` callable above plugs into a `SimplePlugin`: <!-- docs/develop/plugins-guide.mdx:862 -->

```python
plugin = SimplePlugin("organization.PluginName", workflow_runner=workflow_runner)
```

`SimplePlugin` is Temporal's general-purpose plugin abstraction; it can also register workflows, activities, Nexus services, custom data converters, and interceptors. <!-- docs/develop/plugins-guide.mdx:36–37 -->

## Skipping or scoping the sandbox

The sandbox can be skipped in three documented ways. None of these are usually needed when using the OpenAI Agents plugin — list them so users know the surface area, not because they should reach for them.

- **Per-block, inside a workflow:** `with workflow.unsafe.sandbox_unrestricted():` skips runtime restrictions for the block. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:78–83 -->
- **Per-workflow:** `@workflow.defn(sandboxed=False)` runs the entire workflow without sandbox restrictions. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:87–92 -->
- **Per-worker:** set `workflow_runner=UnsandboxedWorkflowRunner()` on the `Worker` init. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:96 -->

The docs note that skipping sandboxing "results in a lack of determinism checks." <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:74 -->

## Import-notification policy (debugging passthrough issues)

When wiring a new plugin or a new third-party library into workflows, the import notification policy is the fastest way to discover modules that you forgot to pass through. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:198–209 -->

- `WARN_ON_DYNAMIC_IMPORT` — default; warns when modules are imported after initial workflow load. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:202 -->
- `WARN_ON_UNINTENTIONAL_PASSTHROUGH` — off by default; warns when a module not in the passthrough list is imported into the sandbox. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:205 -->
- `RAISE_ON_UNINTENTIONAL_PASSTHROUGH` — off by default; raises instead of warning. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:207 -->

Override per-import inside a workflow file via `workflow.unsafe.sandbox_import_notification_policy(...)`. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:209 -->

## Testing changes to your plugin

When a plugin evolves, its workflow-side behavior must remain deterministic for in-flight workflows. The documented approach is **replay testing** for substantive changes, plus turning Workflow caching off to surface side-effect bugs. <!-- docs/develop/plugins-guide.mdx:900–916 --> The upstream OpenAI Agents replay test is the canonical example. <!-- docs/develop/plugins-guide.mdx:229 -->

For non-deterministic code changes within a plugin, use [patching](/patching). <!-- docs/develop/plugins-guide.mdx:223–224 -->

## Common mistakes to avoid

- **Don't pass through `openai`, `httpx`, or other network libraries.** Network and other I/O are activity-only. The sandbox is not a security boundary; it's a Python-level reload + restriction layer. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:30, 42–48, 113–115 -->
- **Don't confuse `sandboxed=False` (per-workflow decorator) with `UnsandboxedWorkflowRunner` (per-worker runner).** They sit at different levels. <!-- docs/develop/python/best-practices/python-sdk-sandbox.mdx:87, 96 -->
- **Don't construct a new runner inside your plugin.** Take the runner you're handed, check `isinstance(runner, SandboxedWorkflowRunner)`, and `dataclasses.replace` it. Constructing a fresh runner discards any earlier plugin's customizations. <!-- docs/develop/plugins-guide.mdx:849–859 -->
- **Don't assume the plugin replaces your sandbox.** The plugin coexists with `SandboxedWorkflowRunner`; it adds passthrough modules so its imports work inside the sandbox.
- **Don't conflate "OpenAI Agents plugin" with a generic OpenAI client.** The plugin wraps the OpenAI Agents SDK (`openai-agents-python`), which is an agent framework. Plain `openai.AsyncOpenAI` use in activities is unrelated. <!-- docs/develop/python/integrations/index.mdx:27 -->

## See also

- `references/python/determinism-protection.md` — fuller Python Workflow Sandbox reference.
- `references/python/ai-patterns.md` — broader Python AI/LLM patterns. (Its "OpenAI Agents SDK Integration" snippet predates this reference and uses an import path that does not match what's in `docs/develop/plugins-guide.mdx`; treat that snippet's API names as illustrative pending an update.)
- [Plugins guide](/develop/plugins-guide) and [encyclopedia/plugins](/encyclopedia/plugins) for cross-language plugin concepts.

<!-- Sources: docs/develop/plugins-guide.mdx; docs/develop/python/best-practices/python-sdk-sandbox.mdx; docs/develop/python/integrations/index.mdx; docs/encyclopedia/plugins.mdx -->
