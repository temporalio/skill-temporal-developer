# Continue-As-New Backoff — Go

Return a Continue-As-New with a start delay so the new run is created now but starts after the delay. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY options API):
- Return workflow.NewContinueAsNewError; if an options type exists (e.g., ContinueAsNewOptions with StartDelay), use it. (VERIFY exact API names in Go SDK).
- Core call: docs/develop/go/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
