# Standalone Activities — API Renames (Go)

Use this page when updating Go code that starts or manages Standalone Activities.

## What the docs show today

- The Go Standalone Activities Feature Guide documents the surface and concepts. Title present:  and describes using `client.ExecuteActivity()` for Standalone Activities.
- CLI supports `--static-summary` / `--static-details` for Activities (flags for UI-facing metadata). `--static-details`  `--static-summary` .
- The Web UI displays static Summary/Details and dynamic Current Details.

## Migration guidance

- Prefer non-`static` naming when the Go SDK exposes Standalone Activity metadata fields for UI labeling (e.g., `Summary`, `Details`).
- If your current Go SDK only exposes `StaticDetails` for Standalone Activity metadata, continue to use it until the non-`static` form is available. Do not invent fields.

## Do not

- Do not assume Workflow Activity options map 1:1 to Standalone Activity options; verify in docs/sources.
- Do not use CLI flag names in SDK code; those are CLI-only. `--static-summary` / `--static-details`

