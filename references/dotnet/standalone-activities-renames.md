# Standalone Activities — API Renames (.NET)

Use this page when updating .NET code that starts or manages Standalone Activities.

## What the docs show today

- The .NET Standalone Activities Feature Guide is the source of truth for API shape and concepts. Title present: .
- CLI supports `--static-summary` / `--static-details` for Activities; these ground current metadata terms. `--static-details`  `--static-summary` .
- The Web UI displays static Summary/Details and dynamic Current Details.

## Migration guidance

- Prefer non-`static` naming when .NET SDK surfaces Standalone Activity metadata fields (e.g., `Summary`, `Details`).
- If your current .NET SDK exposes only `static`-prefixed names for Standalone Activity metadata, keep using them until the SDK version adds the non-`static` forms. Do not invent properties.
- Do not copy Workflow-start-only parameters (e.g., Workflow `static_summary`/`static_details` from Python docs) into Standalone Activity APIs. Concepts align, tokens may differ.

## Do not

- Do not assume method/property names from Java/Go apply to .NET; verify in .NET docs or intellisense.
- Do not set CLI-only flags in SDK code; those flags exist only for CLI usage. `--static-summary` / `--static-details`

