# Standalone Activities — API Renames (Ruby)

Use this page when updating Ruby code that starts or manages Standalone Activities.

## What the docs show today

- The Ruby Standalone Activities Feature Guide documents the surface and concepts. Title present: .
- CLI supports `--static-summary` / `--static-details` for Activities; these ground current metadata terms. `--static-details`  `--static-summary` .
- The Web UI displays static Summary/Details and dynamic Current Details.

## Migration guidance

- Prefer non-`static` naming when Ruby SDK exposes Standalone Activity metadata fields (e.g., `summary`, `details`).
- If only `static`-prefixed names exist in your current Ruby SDK for Standalone Activity metadata, continue using them until non-`static` forms exist. Do not invent parameters.

## Do not

- Do not assume names from other SDKs (Go/Java/.NET/Python) apply to Ruby; verify in Ruby docs/yard.
- Do not use CLI flag names in SDK code; those are CLI-only. `--static-summary` / `--static-details`

