# Versioned Continue-as-New (.NET)

This page is the .NET-specific reference for the upgrade-on-Continue-as-New
option of Worker Versioning. For the cross-language concept overview and
behavior model, see `references/core/versioned-continue-as-new.md`. For general
.NET versioning guidance, see `references/dotnet/versioning.md`.

## Public Preview

This feature is in Public Preview as an experimental SDK-level option.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 541-545 -->

## Minimum SDK Version

The Temporal .NET SDK minimum version for Worker Versioning is v1.7.0.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx line 70 -->

The local docs do not separately state whether the upgrade-on-Continue-as-New
option requires a newer .NET SDK release than v1.7.0.
<!-- VERIFY: which exact .NET SDK release first exposes the upgrade-on-Continue-as-New option? Check Temporalio.Workflows / Temporalio.Common in the .NET SDK release notes for 1.7.0+ -->

## Status of the .NET Example in Local Docs

The only in-docs code example for upgrading on Continue-as-New is written in
Go. The local docs clone does not contain a .NET code example for this
option.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 561-605 (Go-only example) -->

For the canonical example pattern, refer to
`references/go/versioned-continue-as-new.md`. The concept-level behavior
documented in `references/core/versioned-continue-as-new.md` applies to .NET;
the .NET SDK is expected to expose an equivalent API surface, but the exact
.NET API identifiers for this option are not present in the local docs.
<!-- VERIFY: which Temporalio.Workflows APIs in the .NET SDK correspond to Go's workflow.GetInfo().GetTargetWorkerDeploymentVersionChanged and workflow.NewContinueAsNewErrorWithOptions(... InitialVersioningBehavior: ContinueAsNewVersioningBehaviorAutoUpgrade ...)? Check the .NET SDK release notes for 1.7.0+ -->

## Behavior (Concept-Level)

By default, Pinned Workflows stay on their original Worker Deployment Version
even when they Continue-as-New. The upgrade option is opt-in: a Pinned
Workflow must explicitly choose to Continue-as-New onto the current Target
Version, and the new run starts with Auto-Upgrade behavior on that Target
Version. Pinned Workflows do not automatically upgrade on Continue-as-New.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 547-554, 586-590 -->

The Temporal Server tells the Workflow when a new Target Version becomes
available; Workflow code observes this signal on Workflow Task completion and
decides whether to Continue-as-New with the upgrade option set.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 552-554, 570-583 -->

When the upgrade option is used, the new run starts with Auto-Upgrade
behavior and uses the Target Version of its Worker Deployment. The new run is
not Pinned to the new version.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 587-590 -->

## Continue-as-New in .NET (General)

In the .NET SDK, Continue-as-New is initiated by throwing the exception
returned from `Workflow.CreateContinueAsNewException`. This stops the current
run immediately and starts a new run in the same Workflow chain with a fresh
Event History.
<!-- Source: docs/develop/dotnet/workflows/continue-as-new.mdx lines 60-75 -->

```csharp
throw Workflow.CreateContinueAsNewException((ClusterManagerWorkflow wf) => wf.RunAsync(new()
{
    State = CurrentState,
    TestContinueAsNew = input.TestContinueAsNew,
}));
```
<!-- Source: docs/develop/dotnet/workflows/continue-as-new.mdx lines 69-75 -->

The local .NET docs for Continue-as-New do not describe an options parameter
on `CreateContinueAsNewException` that selects an initial versioning behavior
for the new run.
<!-- VERIFY: how does the .NET SDK pass an initial versioning behavior (Auto-Upgrade) when creating the Continue-as-New exception? Is there an overload of Workflow.CreateContinueAsNewException that accepts options analogous to Go's workflow.ContinueAsNewErrorOptions{ InitialVersioningBehavior: ... }? Check Temporalio.Workflows.ContinueAsNewException and related options types in the .NET SDK release notes for 1.7.0+ -->

## Declaring Versioning Behavior in .NET

The .NET SDK declares the Workflow-level versioning behavior with the
`VersioningBehavior` property on the `[Workflow]` attribute. Pinned is the
versioning behavior that benefits from the upgrade-on-Continue-as-New option
(unpinned Auto-Upgrade Workflows already follow Current/Ramping versions
without Continue-as-New).
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 419-429 -->

```csharp
[Workflow(VersioningBehavior = VersioningBehavior.Pinned)]
public class HelloWorld
{
    [WorkflowRun]
    public async Task<string> RunAsync()
    {
        return "hello world!";
    }
}
```
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 419-429 -->

The Worker is configured with a Deployment Version and a default versioning
behavior via `TemporalWorkerOptions.DeploymentOptions`.
<!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 222-233 -->

## Handshake Pattern (Prose)

The pattern in the Go example translates conceptually to .NET as follows.

1. Run as a Pinned Workflow so each individual run stays on a single
   Deployment Version.
2. Periodically perform a Workflow Task (any non-sleep step, or wake via a
   Signal) so the Workflow has the chance to observe whether the Target
   Version has changed since the run started. This is the only way an idle
   run learns of a new Target Version.
   <!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 611-613 -->
3. When the run observes that the Target Version has changed, throw the .NET
   Continue-as-New exception configured so that the new run starts with
   Auto-Upgrade behavior on the Target Version. The exact .NET API for that
   configuration is not present in the local docs.
   <!-- VERIFY: what is the .NET equivalent of Go's workflow.ContinueAsNewErrorOptions{ InitialVersioningBehavior: workflow.ContinueAsNewVersioningBehaviorAutoUpgrade } and the .NET equivalent of Workflow.Info().GetTargetWorkerDeploymentVersionChanged()? Check Temporalio.Workflows / Temporalio.Common in the .NET SDK release notes for 1.7.0+ -->
4. The new run is not Pinned to the new version; it runs with Auto-Upgrade
   behavior on the Target Version of its Worker Deployment.
   <!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 587-590 -->

## Limitations

- Lazy moving only. Sleeping Workflows are not proactively notified when a
  new Target Version becomes available; they only see the change when they
  next run a Workflow Task. To wake an idle Workflow so it can check, send it
  a Signal.
  <!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 611-613 -->
- Interface compatibility. When continuing onto a different version, the
  Workflow input produced by the previous version must be compatible with
  the new version's Workflow Definition, or the new run may fail on its first
  Workflow Task.
  <!-- Source: docs/production-deployment/worker-deployments/worker-versioning.mdx lines 614-616 -->

## Cross-References

- `references/core/versioned-continue-as-new.md` for concept overview.
- `references/go/versioned-continue-as-new.md` for the canonical code example.
- `references/dotnet/versioning.md` for general .NET versioning and patching.
