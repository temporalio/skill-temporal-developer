# Versioned Continue-as-New (Java SDK)

This file covers the Java SDK surface for the "upgrade on Continue-as-New" feature. For the concept-level
explanation (handshake, Target Version, why this exists), see `references/core/versioned-continue-as-new.md`.
For a worked code example, see `references/go/versioned-continue-as-new.md` — the local docs clone contains
only a Go example for this feature.

## Public Preview status

This feature is in Public Preview as an experimental SDK-level option.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:541-545 -->

Treat APIs related to upgrade-on-Continue-as-New as experimental: names, signatures, and defaults may
change before General Availability.

## Minimum SDK version

Upgrade-on-Continue-as-New is layered on top of Worker Versioning. The minimum Java SDK version listed
for Worker Versioning is **Java SDK v1.29**.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:68 -->

The specific Java SDK release that adds the upgrade-on-Continue-as-New option is not stated in the local
docs.
<!-- VERIFY: which Java SDK release first ships the upgrade-on-Continue-as-New option? The Worker Versioning minimum is v1.29, but the upgrade-on-CaN option may have shipped in a later 1.29.x or 1.30.x release. Check the io.temporal:temporal-sdk release notes. -->

## Status of the Java example

The Temporal docs source consulted for this reference contains a Go example only.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:561-605 -->

There is **no Java code example** for the upgrade-on-Continue-as-New option in the local docs. The
concept-level behavior in `references/core/versioned-continue-as-new.md` applies to Java, and the
Java SDK is expected to expose an equivalent API surface, but the exact Java identifiers are not
verifiable from the docs in this skill's clone.
<!-- VERIFY: what is the Java SDK API name for "target worker deployment version changed"? Check io.temporal.workflow.WorkflowInfo for a method analogous to Go's GetTargetWorkerDeploymentVersionChanged in the Java SDK release notes for 1.29+. -->
<!-- VERIFY: what is the Java SDK API for setting "initial versioning behavior = AutoUpgrade" on a Continue-as-New call? Check io.temporal.workflow.ContinueAsNewOptions (and any Continue-as-New helper) in the Java SDK release notes for 1.29+. -->

## Continue-as-New in Java (background)

Inside a Workflow method, you trigger Continue-as-New by calling `Workflow.continueAsNew(...)` with the
next run's input. This stops the current run and starts a new run with the same Workflow Id, a new
Run Id, and a fresh Event History.
<!-- cite: docs/develop/java/workflows/continue-as-new.mdx:58-70 -->

Temporal can also tell you when it's a good time to Continue-as-New based on Event History size:
`Workflow.getInfo().isContinueAsNewSuggested()`.
<!-- cite: docs/develop/java/workflows/continue-as-new.mdx:82 -->
<!-- cite: docs/develop/java/workflows/continue-as-new.mdx:101 -->

Do not call Continue-as-New from Update or Signal handlers — wait for handlers to finish in the main
Workflow method, then call `continueAsNew`.
<!-- cite: docs/develop/java/workflows/continue-as-new.mdx:72-75 -->

## Declaring Versioning Behavior in Java

A Workflow implementation declares its Versioning Behavior with the
`@WorkflowVersioningBehavior(VersioningBehavior.PINNED)` annotation on the `@WorkflowMethod` override
(use `VersioningBehavior.AUTO_UPGRADE` for the other option).
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:380-394 -->

By default, Pinned Workflows stay on their original Worker Deployment Version even when they
Continue-as-New. Pinned Workflows are **not** automatically moved to a new version at the
Continue-as-New boundary — the upgrade is opt-in by the Workflow code on a per-Continue-as-New basis.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:549-554 -->

## The handshake (prose)

The mechanism the docs describe (in terms of Go names) is:

1. The Temporal Server tracks the Target Version for the Workflow's Task Queue / Deployment Series.
2. A flag on the in-Workflow `Info` object indicates whether a new Target Version has appeared since
   this run started. The flag is refreshed when a Workflow Task completes.
3. When the Workflow chooses to Continue-as-New, it can pass an option that sets the **initial
   versioning behavior of the new run to Auto-Upgrade**. The new run then starts on the Deployment's
   current Target Version.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:547-554 -->
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:570-595 -->

Note carefully: the option makes the *new run* start with **Auto-Upgrade** behavior, using the Target
Version of its Worker Deployment. It does **not** pin the new run to the new version.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:586-590 -->

In Java terms the moving parts are (a) something analogous to "is target worker deployment version
changed" on `Workflow.getInfo()`, and (b) something on a Continue-as-New options builder that sets
the new run's initial versioning behavior. The exact Java identifiers are not in the local docs.
<!-- VERIFY: confirm the Java equivalents for (a) WorkflowInfo.getTargetWorkerDeploymentVersionChanged-style flag and (b) ContinueAsNewOptions initial-versioning-behavior setter. Cross-check the Java SDK changelog around v1.29.0+. -->

## Lazy moving — not automatic for sleeping Workflows

Workflows must execute a Workflow Task in order to learn that a new Target Version exists. Sleeping
Workflows are **not** proactively notified. If you have idle Workflows you want to wake up to check
for a version change, send them a Signal.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:611-613 -->

## Interface compatibility

When you Continue-as-New across versions, the input passed by the previous run must be compatible
with the new version's Workflow definition. If it isn't, the new run can fail on its first Workflow
Task.
<!-- cite: docs/production-deployment/worker-deployments/worker-versioning.mdx:614-616 -->

## See also

- `references/core/versioned-continue-as-new.md` — concept-level walkthrough of the handshake.
- `references/go/versioned-continue-as-new.md` — the only in-docs worked example for this feature.
- `references/java/versioning.md` — general Java versioning (patching, GetVersion, Worker Versioning overview).
