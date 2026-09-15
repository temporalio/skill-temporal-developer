# Child Workflow Defaults (Java)

## Overview

Java lets you set default `ChildWorkflowOptions` for a workflow implementation via `WorkflowImplementationOptions`. This removes repetitive option wiring when a parent starts many children.

## Prerequisites

- Temporal Java SDK v1.39.0 or higher (adds ChildWorkflowOptions support to `WorkflowImplementationOptions`).

## Where defaults live

Defaults are configured on a `WorkflowImplementationOptions` instance and applied when you register workflow implementations on a `Worker` using those options. They affect child workflows spawned by those implementations.

Example (conceptual): create a `WorkflowImplementationOptions` with `setDefaultChildWorkflowOptions(ChildWorkflowOptions.Builder...)`, then pass it to `worker.registerWorkflowImplementationTypes(options, ...)` when registering the parent workflow implementation.

Notes:
- Parent Close Policy default is Terminate. Change it on defaults (or per call) when children must outlive the parent. See `docs/encyclopedia/child-workflows/parent-close-policy.mdx`.
- If you don’t set a Task Queue in `ChildWorkflowOptions`, a child inherits the parent’s Task Queue. See `docs/encyclopedia/workers/task-queues.mdx`.

## Use the defaults in workflow code

When you create a child stub without passing options (e.g., `Workflow.newChildWorkflowStub(GreetingChild.class)`), the defaults apply automatically. To ensure the child has started before the parent closes, get the `Promise<WorkflowExecution>` via `Workflow.getWorkflowExecution(child)` and call `get()`.

## Per-child-type overrides

Provide a per-type map to customize defaults by child workflow type name (string) using `setChildWorkflowOptions(Map<String, ChildWorkflowOptions>)`. Workflow type names in Java come from `@WorkflowMethod(name = ...)` or the interface short name when not set.

## Related defaults and concepts

- Parent Close Policy values and default: `docs/encyclopedia/child-workflows/parent-close-policy.mdx` (default = Terminate).
- Child inherits Task Queue if none set: `docs/encyclopedia/workers/task-queues.mdx`.
- Java child workflow APIs and examples: `docs/develop/java/workflows/child-workflows.mdx`.

## Common pitfalls

- Forgetting to wait for child start when parent may complete immediately. Use `Workflow.getWorkflowExecution(child).get()` to ensure the child has started before the parent closes (see Java child workflow docs, Parent Close Policy section).
- Assuming defaults are global. They apply only to workflow implementations registered with the `WorkflowImplementationOptions` you pass to `Worker`.
- Using class names as map keys unintentionally. The per-type defaults map keys are workflow type names (strings). Ensure they match your child workflow type names.
