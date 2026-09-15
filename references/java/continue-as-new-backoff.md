# Continue-As-New Backoff — Java

Use Workflow.continueAsNew with ContinueAsNewOptions to delay the next run. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY method availability):
- Workflow.continueAsNew with ContinueAsNewOptions.newBuilder().setStartDelay(Duration...) (VERIFY setStartDelay on ContinueAsNewOptions).
- Core call: docs/develop/java/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
