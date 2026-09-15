# Standalone Activities — API Renames (Java)

Use this page when updating Java code that starts or manages Standalone Activities.

## What the docs show today

- The Java Standalone Activities Feature Guide documents the surface and concepts. Title present: .
- CLI supports `--static-summary` / `--static-details` for Activities. `--static-details`  `--static-summary` .
- The Web UI displays static Summary/Details and dynamic Current Details.
- Secondary (SDK API docs): `StartActivityOptions.Builder` exposes `setStaticSummary(...)` and `setStaticDetails(...)` in current releases.

## Migration guidance

- When available in your Java SDK version, prefer `setSummary(...)` and `setDetails(...)` on Standalone Activity start options to align with UI semantics.
- If your version only exposes `setStaticSummary(...)` / `setStaticDetails(...)`, continue to use them until the non-`static` forms exist. Do not substitute names from other SDKs.

## Do not

- Do not copy `ActivityOptions.Builder#setSummary(...)` (used for Workflow Activities) as evidence that `StartActivityOptions.Builder` already supports the same method names. Verify on the correct type.
- Do not conflate CLI flag names with SDK API names.

