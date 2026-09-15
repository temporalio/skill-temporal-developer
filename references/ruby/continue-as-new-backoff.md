# Continue-As-New Backoff — Ruby

Raise Temporalio::Workflow::ContinueAsNewError with start_delay so the next run starts after a delay. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY option name and units):
- Raise Temporalio::Workflow::ContinueAsNewError.new(..., start_delay: seconds) (VERIFY support on Continue-As-New).
- Core call: docs/develop/ruby/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
