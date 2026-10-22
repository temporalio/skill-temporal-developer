# Standalone Activities — Validation Report

This report covers the current PR after merging `main` and resolving the SDK gaps. It supersedes the original citation counts and Public Preview assumptions in the historical validation plan.

## SDK policy checks

The policy code blocks were extracted directly from each language reference. Test harnesses supplied the connected Client, Activity definition, or enclosing function as needed, without changing the documented policy parameters.

| SDK | Validation | Result |
|---|---|---|
| Python v1.23.0 | Ran the extracted snippet against an isolated Temporal CLI v1.9.1 / Server v1.32.0 dev server. Submitted the same ID twice, terminated it, then submitted it again. | Both running submissions returned the same Run ID; the closed duplicate raised `ActivityAlreadyStartedError`. |
| Go v1.41.0 | Compiled the extracted snippet with `go build ./...` against the pinned SDK and its dependencies. | Passed. |
| Java v1.35.0 | Compiled the extracted snippet with `javac` against the pinned SDK and service-client JARs. | Passed. |
| TypeScript v1.17.0 | Type-checked the extracted snippet with TypeScript v5.8.3 using strict mode and `--noEmit`. | Passed. |
| .NET v1.12.0 | Checked `IdConflictPolicy`, `IdReusePolicy`, enum imports, `UseExisting`, and `RejectDuplicate` against the tagged SDK source. | Confirmed. Compilation was not run because the .NET SDK is not installed. |

Compile checks confirm API names, imports, and types; they do not test server behavior. The Python check exercises both policy branches against the local server without a Worker. The dev server and test harnesses are temporary and outside the repository.

## Source verification

The [authoring log](AUTHORING_LOG.md#resolved-sdk-policy-gaps) links each SDK's tagged source. All five examples use Activity policies rather than Workflow policies. The [Activity API definitions](https://github.com/temporalio/api/blob/main/temporal/api/enums/v1/activity.proto) confirm the supported values and distinguish running-ID conflicts from closed-ID reuse.

- The reuse enum is `REJECT_DUPLICATE`, singular.
- `USE_EXISTING` attaches to the running execution; it does not start a second execution.
- `REJECT_DUPLICATE` rejects another execution using a retained closed execution's ID. It does not disable retries of the original execution.
- `TerminateExisting` and `TerminateIfRunning` remain unsupported Activity policies.
- The Python server requirement is sourced from the shared core guide rather than left as an unresolved per-language caveat.

## TypeScript coverage

The [upstream TypeScript feature guide](https://docs.temporal.io/develop/typescript/activities/standalone-activities) exists. The [local TypeScript reference](references/typescript/standalone-activities.md) already covers the lifecycle APIs and now includes a verified policy example and a link to that upstream guide. The original upstream-pending gap is resolved.

## Repository checks

- Markdown formatting: `rumdl fmt --check .`.
- Relative links and heading fragments: `rumdl check .`.
- Skill metadata and structure: `skills-ref validate` against a temporary copy named `temporal-developer`, matching CI's checkout path.
- Skill-creator validation: `quick_validate.py`.
- Patch whitespace: `git diff --check`.

These checks passed for the updated documentation. No unresolved `VERIFY` comments remain in the active Standalone Activities references.
