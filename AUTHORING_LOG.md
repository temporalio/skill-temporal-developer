# Standalone Activities — Authoring Log

## Current scope

The PR extends the existing Standalone Activities guides with a CLI reference and concrete SDK conflict/reuse-policy examples. It preserves the current core and SDK guidance from `main`, including TypeScript and Ruby coverage.

The original authoring and validation plans describe the earlier Public Preview snapshot. Their assumptions about missing TypeScript documentation and unsupported pause/reset/update operations have been superseded.

## Resolved SDK policy gaps

Each example uses a stable Activity ID, attaches to an already-running execution with `USE_EXISTING`, and rejects reuse after closure with `REJECT_DUPLICATE`. The exact enum name is singular; `REJECT_DUPLICATES` was an error in the original gap description.

| SDK | Policy parameters | Policy values | Verified source |
|---|---|---|---|
| Python v1.23.0 | `id_conflict_policy`, `id_reuse_policy` | `ActivityIDConflictPolicy.USE_EXISTING`, `ActivityIDReusePolicy.REJECT_DUPLICATE` | [Client](https://github.com/temporalio/sdk-python/blob/1.23.0/temporalio/client.py), [enums](https://github.com/temporalio/sdk-python/blob/1.23.0/temporalio/common.py) |
| Go v1.41.0 | `StartActivityOptions.ActivityIDConflictPolicy`, `ActivityIDReusePolicy` | `enumspb.ACTIVITY_ID_CONFLICT_POLICY_USE_EXISTING`, `enumspb.ACTIVITY_ID_REUSE_POLICY_REJECT_DUPLICATE` | [Options](https://github.com/temporalio/sdk-go/blob/v1.41.0/internal/internal_activity_client.go) |
| Java v1.35.0 | `setIdConflictPolicy`, `setIdReusePolicy` | `ActivityIdConflictPolicy.ACTIVITY_ID_CONFLICT_POLICY_USE_EXISTING`, `ActivityIdReusePolicy.ACTIVITY_ID_REUSE_POLICY_REJECT_DUPLICATE` | [Builder](https://github.com/temporalio/sdk-java/blob/v1.35.0/temporal-sdk/src/main/java/io/temporal/client/StartActivityOptions.java) |
| .NET v1.12.0 | `StartActivityOptions.IdConflictPolicy`, `IdReusePolicy` | `ActivityIdConflictPolicy.UseExisting`, `ActivityIdReusePolicy.RejectDuplicate` | [Options](https://github.com/temporalio/sdk-dotnet/blob/1.12.0/src/Temporalio/Client/StartActivityOptions.cs), [enums](https://github.com/temporalio/sdk-dotnet/blob/1.12.0/src/Temporalio/Api/Enums/V1/Activity.cs) |
| TypeScript v1.17.0 | `idConflictPolicy`, `idReusePolicy` | `ActivityIdConflictPolicy.USE_EXISTING`, `ActivityIdReusePolicy.REJECT_DUPLICATE` | [Options](https://github.com/temporalio/sdk-typescript/blob/v1.17.0/packages/client/src/activity-client.ts), [enums](https://github.com/temporalio/sdk-typescript/blob/v1.17.0/packages/client/src/types.ts) |

The [core policy section](references/core/standalone-activities.md#activity-id-conflict-and-reuse-policies) explains running versus closed executions, defaults, supported policies, retention, and Activity retry/idempotency considerations. `TerminateExisting` and `TerminateIfRunning` remain unsupported Activity policies.

## Resolved TypeScript coverage gap

The [TypeScript reference](references/typescript/standalone-activities.md) covers Worker registration, typed and untyped Client calls, start, handle lookup, result retrieval, list, count, and policies. The [upstream TypeScript feature guide](https://docs.temporal.io/develop/typescript/activities/standalone-activities) is available and linked from the reference. Coverage is no longer upstream-pending.

## Validation

See the [current validation report](STANDALONE_ACTIVITIES_VALIDATION_REPORT.md) for executed checks and their limits. The original SDK policy gaps and Python server-version sourcing gap are resolved; the core guide states the shared server requirement.
