# Continue-As-New Backoff — TypeScript

Use wf.makeContinueAsNewFunc with options to pass a startDelay, or an equivalent overload, so the next run starts after the delay. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY field name):
- Use wf.makeContinueAsNewFunc with options { startDelay: ... } then invoke with args. (VERIFY startDelay option on Continue-As-New path).
- Core call: docs/develop/typescript/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
