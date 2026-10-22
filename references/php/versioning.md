# PHP SDK Versioning

See [core versioning](../core/versioning.md) for strategy. Sources: [PHP versioning guide](https://docs.temporal.io/develop/php/workflows/versioning), [SDK deployment options](https://github.com/temporalio/sdk-php/blob/v2.18/src/Worker/WorkerDeploymentOptions.php).

## Patching workflow commands

PHP uses `yield Workflow::getVersion()`, not another SDK's `patched()`:

```php
$version = yield \Temporal\Workflow::getVersion(
    'notification-channel',
    \Temporal\Workflow::DEFAULT_VERSION,
    2,
);
if ($version === 1) {
    yield $activities->sendSms($orderId);
} elseif ($version === 2) {
    yield $activities->sendPush($orderId);
}
// DEFAULT_VERSION preserves the original history with neither notification.
```

A new execution records the maximum supported version; an execution replaying a history from before the marker uses `DEFAULT_VERSION` (-1). Keep each historical branch needed by retained executions. Adding a new `sideEffect()`, UUID generation, timer or Activity elsewhere in the workflow can still break replay even if the notification itself is versioned. Review the entire command sequence.

Once old versions are no longer needed, remove their branches but retain a `getVersion()` call with narrowed supported bounds. Remove the marker only after verifying the SDK's removal rules and every history you still need to replay/reset. “No open workflows” alone does not cover retained closed histories, reset points or rollback needs. Use actual visibility/history evidence and replay fixtures, not an assumed deployment date.

When querying `TemporalChangeVersion`, inspect the emitted values; the value includes change ID **and version**, such as `notification-channel-2`, not just `notification-channel`. Absence alone is not a reliable classification of every old code path. Preserve a unique change ID for each logical patch.

## New Workflow Types

For a substantially incompatible contract, register a new name (for example `OrderV2`), route new starts to it and keep the old implementation available for existing executions. Rename PHP classes independently from registered type names only when their attributes preserve the contract. Check routing on every worker polling the affected Task Queue.

## Worker Deployment Versioning

Verify SDK, RoadRunner and server compatibility together. The deployment types below exist in SDK 2.16+ and were experimental in 2.16. Do not infer feature maturity or server support from class existence. Avoid copying historical preview/removal dates as current facts.

```php
use Temporal\Common\Versioning\VersioningBehavior;
use Temporal\Common\Versioning\WorkerDeploymentVersion;
use Temporal\Worker\WorkerDeploymentOptions;
use Temporal\Worker\WorkerOptions;

$options = WorkerOptions::new()->withDeploymentOptions(
    WorkerDeploymentOptions::new()
        ->withUseVersioning(true)
        ->withVersion(WorkerDeploymentVersion::new('orders', 'build-abc123'))
        ->withDefaultVersioningBehavior(VersioningBehavior::Pinned),
);
$worker = $factory->newWorker('orders', $options);
```

Deployment options belong inside `WorkerOptions`; `newWorker()` has no `deploymentOptions:` argument. The canonical version string is `deploymentName.buildId`, not `deploymentName:buildId`.

- `Pinned` keeps a workflow on its assigned deployment version. Retain capacity/code for that version until it is safe to retire. Moving a pinned workflow deliberately still requires compatibility review.
- `AutoUpgrade` allows movement to the current deployment version; incompatible command changes still require patching.

Use the installed CLI's `temporal worker deployment --help` and subcommand help before performing a rollout. Setting the current deployment version affects routing; it is not a local code-only operation. Verify drained executions, visibility, replay and rollback requirements before removing workers or historical branches.
