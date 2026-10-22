# PHP Batches and Concurrent Branches

Read for large imports, per-item pipelines, or first-useful-result searches. See [worker capacity](workers.md) separately: workflow fan-out and Activity execution capacity are different limits.

## Bounded fan-out and fan-in

Use a batch ID plus a durable cursor, not 100,000 input records. An Activity reads a bounded page of IDs from a stable snapshot/keyset. Launch one coroutine per item in that page. Keep its dependent steps sequential with `yield`; give each external step its own idempotency key. Store large results externally and retain only counters/references in workflow state.

A page-level fragment, inside a generator workflow with configured `$activities`:

```php
use Temporal\Exception\Failure\ActivityFailure;
use Temporal\Exception\Failure\CanceledFailure;
use Temporal\Promise;
use Temporal\Workflow;

// Application contract: ids has at most 50 entries; nextCursor is durable.
$page = yield $activities->readPage($batchId, $cursor, 50);
$promises = [];
foreach ($page['ids'] as $itemId) {
    $promises[] = Workflow::async(function () use ($activities, $batchId, $itemId) {
        try {
            yield $activities->markStarted($batchId, $itemId);
            $resultRef = yield $activities->process($batchId, $itemId);
            yield $activities->markCompleted($batchId, $itemId, $resultRef);
            return ['ok' => true];
        } catch (CanceledFailure $cancelled) {
            throw $cancelled;
        } catch (ActivityFailure $failure) {
            if ($failure->getPrevious() instanceof CanceledFailure) {
                throw $failure;
            }
            // Best-effort batch policy, after that Activity's retries end.
            // Persist failures too; a reporting failure must not become success.
            yield $activities->markFailed($batchId, $itemId, $failure->getMessage());
            return ['ok' => false];
        }
    });
}
$outcomes = yield Promise::all($promises); // Join AFTER launching this page.
```

After the join, update cumulative counts and advance the cursor. Release per-page arrays. Either process a bounded number of pages per run or Continue-As-New after each page; carry batch ID, cursor, policy and summary forward. Make that handoff explicit and terminal in the main generator with `return yield Workflow::continueAsNew(...)`; drain message handlers first and preserve pending input. Finish the batch only when no page remains and all intended work has settled. An empty page must either terminate or advance the cursor, never create a busy loop.

`Promise::all()` rejects when a constituent rejects; it does not automatically cancel or join remaining branches on failure. Choose fail-fast with explicit cancellation/draining, or turn expected terminal per-item failures into outcomes as above. Do not swallow workflow programming failures or cancellation as “one failed row.” For progress visible before the slowest item completes, update bounded counters in each completing coroutine or in `then()` callbacks, rather than awaiting results only in input order.

Activities retry their own steps. If `process()` fails, successful `markStarted()` is already in history; a normal Activity retry does not rerun the whole chain. Restarting the workflow or re-reading a page after a failed run can repeat steps, so business-level deduplication is still required. For a multi-step item with its own lifecycle, use bounded child workflows; huge child fan-out also grows the parent's history.

Sources: [AsyncClosure](https://github.com/temporalio/samples-php/tree/bb3e9d3d1dee9f035359bea68fa7cd7c6e3153d4/app/src/AsyncClosure), [PHP Promise implementation](https://github.com/temporalio/sdk-php/blob/v2.18/src/Promise.php), [Continue-As-New](https://docs.temporal.io/develop/php/workflows/continue-as-new).

## First useful result

Courier search from the course illustrates a different policy: return the first **non-empty** successful result, or stop when every provider finishes or the deadline expires. `Promise::race()` means first settled; `Promise::any()` means first fulfilled, which may be an empty list. Neither implies “first acceptable business result.”

Maintain attempt-local winner and completion count. Handle rejected provider calls and increment completion in `finally`. When a winner or timeout occurs, cancel and drain losing scopes when safe, or guard late callbacks with an attempt token so results from an old search cannot mutate the next attempt. Cancellation requests cannot undo an external reservation; release losing reservations idempotently. Validate acceptance Signals against offered IDs and the current search round, not just “no courier assigned yet.”

## Article assessment

[Thierry Feuzeu's batch article](https://medium.com/@thierry.feuzeu/parallel-batch-processing-with-temporal-b10ae89e7269) contributes per-item sequential chains, concurrent items, queryable progress and explicit success/failure outcomes. Its intermediate snippet puts the join inside the launch loop; the full example places it after the loop. Use the latter shape. `always()` reflects an older promise API; verify the installed implementation before using `finally()`/callbacks. Its Schedule-To-Start and workflow timeout values are demonstration choices, not required batch settings. The bounded design above adds explicit memory/history budgets and cancellation handling based on SDK primitives.
