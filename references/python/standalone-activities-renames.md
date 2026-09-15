# Standalone Activities — API Renames (Python)

Use this page when updating Python code that starts or manages Standalone Activities.

## What the docs show today

- The Python Standalone Activities Feature Guide documents the surface and concepts. Title present: .
- UI/CLI grounding:
  - CLI supports `--static-summary` / `--static-details` for Activities. `--static-details`  `--static-summary` .
  - The Web UI displays static Summary/Details and dynamic Current Details.
- Python UI-enrichment docs show `static_summary` / `static_details` at Workflow start and `summary` for Activities/timers within a Workflow. `static_summary` / `static_details`  `summary` on Activity .

## Migration guidance

- For Standalone Activities started via `Client.execute_activity()` / `Client.start_activity()`, use the SDK-documented parameter names for metadata when present. Prefer non-`static` (`summary`, `details`) if and when these are exposed for Standalone Activity calls.
- Do not copy Workflow-start-only parameters (e.g., `static_summary`, `static_details`) into Standalone Activity APIs unless explicitly documented for those client methods.

## Do not

- Do not assume parity with Workflow Activity `workflow.execute_activity(..., summary=...)` params for Standalone Activity client calls; verify per method.
- Do not use CLI flag names in SDK code; those are CLI-only. `--static-summary` / `--static-details`

