# Continue-As-New Backoff — .NET

Use Continue-As-New with a start delay so the next run begins after a fixed interval. The delay is server-side backoff; no Workflow code runs until it expires. See core: references/core/continue-as-new-backoff.md.

Example (VERIFY property names):
- Throw CreateContinueAsNewException with ContinueAsNewOptions { StartDelay = TimeSpan.From... } (VERIFY StartDelay on ContinueAsNewOptions).
- Core call: docs/develop/dotnet/workflows/continue-as-new.mdx

Semantics: docs/design-patterns/delayed-start.mdx; docs/encyclopedia/retry-policies.mdx; docs/references/events.mdx
