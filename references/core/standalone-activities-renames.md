# Standalone Activities — API Renames (Summary/Details)

One-sentence description: Standalone Activity APIs rename static summary/details and related fields/methods and remove some deprecated properties.

## Grounding: What exists today

- CLI supports static metadata for Activities via `--static-summary` and `--static-details`. `--static-details` and `--static-summary` appear in the Activity command options. `--static-details`  `--static-summary`  and also in a later options table: `--static-details`  `--static-summary` .
- The Web UI displays "static Workflow Summary and Details" and dynamic "Current Details" in Metadata.
- Python docs show Workflow start parameters `static_summary` and `static_details`, and `summary` on Activities/timers in Workflow context. `static_summary` / `static_details`  `summary` on Activity .
- Standalone Activities are documented per SDK (Feature Guides) but do not currently enumerate metadata fields on start/execute options (cite per language pages as context). Go Feature Guide title ; Java Feature Guide title ; .NET Feature Guide title ; Python Feature Guide title ; Ruby Feature Guide title .

## Migration intent (do not fabricate tokens)

- When SDKs surface Standalone Activity metadata fields for UI labeling, prefer "summary" (single-line) and "details" (multi-line Markdown, where supported), matching UI semantics and CLI terminology.
- If a given SDK still exposes `static_*` names for Standalone Activities, continue to use those names. When releases add `summary`/`details`, migrate to the new names.
- Do not assume parity across SDKs. Verify per language. If docs are silent, add a `` note in per-language sections and avoid naming fields/methods.

## Related removals

- Deprecated or experimental properties related to prior naming may be removed during this transition. Do not rely on deprecated tokens; prefer currently documented fields and methods per SDK docs.

## Per-language pages

- .NET: `references/dotnet/standalone-activities-renames.md`
- Go: `references/go/standalone-activities-renames.md`
- Java: `references/java/standalone-activities-renames.md`
- Python: `references/python/standalone-activities-renames.md`
- Ruby: `references/ruby/standalone-activities-renames.md`

