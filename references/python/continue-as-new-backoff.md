# Continue-As-New Backoff — Python

Call workflow.continue_as_new with a start_delay to defer the first task of the next run. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY parameter name):
- workflow.continue_as_new(..., start_delay=timedelta(...)) (VERIFY start_delay keyword parameter).
- Core call: docs/develop/python/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
